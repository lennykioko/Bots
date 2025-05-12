//+------------------------------------------------------------------+
//|                                                NY-Strategy-1.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Smart Breakout Strategy with Opening Range and FVG confirmation"
#property strict

//--- Include necessary helpers
#include <Helpers\GetRange.mqh>
#include <Helpers\GetSwingHighLows.mqh>
#include <Helpers\GetFVGs.mqh>
#include <Helpers\RiskManagement.mqh>
#include <Helpers\OrderManagement.mqh>
#include <Helpers\GetIndicators.mqh>
#include <Helpers\TextDisplay.mqh>
#include <Trade\Trade.mqh>

//--- Enumerations
enum TRADE_DIRECTION {
   NO_DIRECTION,   // No direction
   LONG,           // Bullish
   SHORT           // Bearish
};

//--- Structures
struct StrategyState {
   // Market structure
   TimeRange        asianRanges[];         // Opening range
   TimeRange        londonRanges[];        // London range
   FVG              bullishFVGs[];    // Bullish fair value gaps
   FVG              bearishFVGs[];    // Bearish fair value gaps
   SwingPoint       swingHighs[];     // Swing high points
   SwingPoint       swingLows[];      // Swing low points
   string           biasDirection;    // Current bias direction
   int              lastRangeBarIndex;// Index of last range bar
   double           prevDayHigh;     // Previous day high
   double           prevDayLow;      // Previous day low

   // Position management
   double           entryPrice;       // Entry price for position
   double           stopLoss;         // Stop loss price
   double           beRRR;            // Breakeven risk-reward ratio
   double           partialRRR;       // Partial take-profit risk-reward ratio
   bool             partialClosed;    // Partial position closed flag

   // Session management
   double           startDayBalance;  // Balance at start of trading day
   datetime         lastReset;        // Last reset datetime
   datetime         lastDisplayUpdate;  // Last display update time

   // Constructor with default values
   void StrategyState() {
      biasDirection = "";
      lastRangeBarIndex = 0;
      entryPrice = 0.0;
      stopLoss = 0.0;
      beRRR = 1.0;
      partialRRR = 1.0;
      partialClosed = false;
      startDayBalance = 0.0;
      lastReset = 0;
      lastDisplayUpdate = 0;
   }
};

//--- Global variables
StrategyState state;  // Main strategy state

//--- Input parameters
// Opening Range parameters
input string     AsianStartTime = "18:00";       // 1800 NY = 0100 KE no DST (HH:MM)
input string     AsianEndTime = "00:00";         // 0000 NY = 0700 KE no DST (HH:MM)
input string     LondonStartTime = "00:00";       // 0000 NY = 0700 KE no DST (HH:MM)
input string     LondonEndTime = "06:00";         // 0600 NY = 1300 KE no DST (HH:MM)
input int        startTradingHour = 07;       // 0700 NY = 1400 KE no DST (24H)
input int        endTradingHour = 12;         // 1200 NY = 1900 KE no DST (24H)

// Market structure parameters
input bool       DrawOnChart = true;          // Draw ranges on chart
input int        MaxSwingPoints = 10;         // Number of swing points to identify
input int        MinFVGSearchRange = 10;      // Minimum bars to search for FVGs
input int        FVGLookBackBars = 2;         // FVG lookback bars
input int        SMA_Period = 20;             // SMA period for trend confirmation
input double     BufferPips = 1.0;            // Buffer in pips for stop loss

// Money management parameters
input double     RiskDollars = 100.0;         // Risk in dollars per trade
input double     MinRRR = 5.0;                // Minimum risk to reward ratio
input double     MaxDailyLoss = 300;          // Maximum daily loss in account currency
input double     DailyTarget = 300;           // Daily target in account currency

// Position management parameters
input bool       UseBreakeven = true;         // Move to breakeven
input double     BeRRR = 0.1;                 // Risk-reward ratio for breakeven
input bool       UsePartialProfit = true;     // Take partial profit
input double     PartialRRR = 0.1;            // Risk-reward ratio for partial profit
input double     PartialPercent = 1.0;        // Percentage to close on partial

// Display parameters
input bool       ShowTextOnChart = true;      // Show strategy conditions on chart
input int        DisplayUpdateInterval = 5;   // Update display every N seconds
input color      InfoTextColor = clrWhite;    // Information text color
input color      PositiveCondColor = clrLime; // Positive condition text color
input color      NegativeCondColor = clrRed;  // Negative condition text color

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Clear chart objects and set timer
   ObjectsDeleteAll(ChartID(), "");
   EventSetTimer(60);

   // Initialize strategy state
   state.startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   state.beRRR = BeRRR;
   state.partialRRR = PartialRRR;

   // Initialize display
   if(ShowTextOnChart) {
      clearTextDisplay();
      addTextOnScreen("NY-Strategy-1 initialized", InfoTextColor);
   }

   Print("NY-Strategy-1 initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(ChartID(), "");
   EventKillTimer();
   Print("NY-Strategy-1 deinitialized");
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer() {
   if(!IsNYHour()) {
      // If not in NY hour, do not execute trading logic
      return;
   }

   // Check if trading is allowed by system
   isTradingAllowedBySystem();

   // Reset day balance on a new day
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Check if we need to reset for a new day
   MqlDateTime lastResetDT;
   if(state.lastReset > 0) {
      TimeToStruct(state.lastReset, lastResetDT);
   }

   // Reset if it's a new day or if lastReset has never been set
   if(state.lastReset == 0 || lastResetDT.day != dt.day || lastResetDT.mon != dt.mon || lastResetDT.year != dt.year) {
      state.startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      state.lastReset = now;
      state.partialClosed = false; // Reset partial flag for the new day
      Print("New day detected. Starting Day balance reset to: ", DoubleToString(state.startDayBalance, 2));
   }

   // Update market structure elements and display
   UpdateMarketStructure();

   // Update display if interval has passed
   if(ShowTextOnChart && now - state.lastDisplayUpdate >= DisplayUpdateInterval) {
      UpdateDisplayInfo();
      state.lastDisplayUpdate = now;
   }

   // Get key levels
   // Detect asian and london range
   bool asainRangeFound = GetRanges(AsianStartTime, AsianEndTime, state.asianRanges, 0, "AR", DrawOnChart, PERIOD_CURRENT);
   bool londonRangeFound = GetRanges(LondonStartTime, LondonEndTime, state.londonRanges, 0, "LR", DrawOnChart, PERIOD_CURRENT);
   if(!asainRangeFound || !londonRangeFound) return;

   state.prevDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   state.prevDayLow = iLow(_Symbol, PERIOD_D1, 1);

   // Draw horisontal lines for previous day high and low
   if(DrawOnChart) {
      DrawKeyLevel(state.prevDayHigh, "PDH", clrDodgerBlue);
      DrawKeyLevel(state.prevDayLow, "PDL", clrCrimson);
   }

   state.lastRangeBarIndex = state.londonRanges[0].endBarIndex;
   state.biasDirection = state.londonRanges[0].type;

   // Find FVGs after the london range scope
   GetBullishFVGs(FVGLookBackBars, state.londonRanges[0].endBarIndex, state.bullishFVGs, MinFVGSearchRange, DrawOnChart, clrGreenYellow, false);
   GetBearishFVGs(FVGLookBackBars, state.londonRanges[0].endBarIndex, state.bearishFVGs, MinFVGSearchRange, DrawOnChart, clrDeepPink, false);

   // Process trading logic
   if(!HasActivePositionsOrOrders()) {
      ExecuteTradeSignal(CheckForEntrySignals());
   } else {
      ManagePositions();
   }
}

void DrawKeyLevel(double price, string name, color clr) {
   if(!ObjectDelete(0, name)) {
      Print("Failed to delete line", GetLastError());
   }
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) {
      Print("Failed to create object: ", GetLastError());
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "Name: " + name + DoubleToString(price, _Digits));
}

//+------------------------------------------------------------------+
//| Update the display with current strategy info                    |
//+------------------------------------------------------------------+
void UpdateDisplayInfo() {
   clearTextDisplay();

   // Show basic strategy information
   addTextOnScreen("NY-Strategy-1 Status", InfoTextColor);

   // Show trading session info
   string tradeHoursMsg = "Trading Hours: " + IntegerToString(startTradingHour) + ":00 - " + IntegerToString(endTradingHour) + ":00";
   addTextOnScreen(tradeHoursMsg, InfoTextColor);

   // Show account info
   string accountMsg = "Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   addTextOnScreen(accountMsg, InfoTextColor);

   // Show day P/L
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - state.startDayBalance;
   string dayPnLMsg = "Day P/L: $" + DoubleToString(dayPnL, 2);
   color pnlColor = (dayPnL >= 0) ? PositiveCondColor : NegativeCondColor;
   addTextOnScreen(dayPnLMsg, pnlColor);

   // Show current trading conditions
   bool inNYHour = IsNYHour();
   bool riskValid = AccountRiskValid();
   string timeCondMsg = "Trading Hour: " + (inNYHour ? "YES" : "NO");
   string riskCondMsg = "Risk Valid: " + (riskValid ? "YES" : "NO");

   addTextOnScreen(timeCondMsg, inNYHour ? PositiveCondColor : NegativeCondColor);
   addTextOnScreen(riskCondMsg, riskValid ? PositiveCondColor : NegativeCondColor);

   // Show market structure
   if(ArraySize(state.asianRanges) > 0) {
      string orMsg = "AR Type: " + state.biasDirection;
      addTextOnScreen(orMsg, InfoTextColor);

      string rangeMsg = "AR High: " + DoubleToString(state.asianRanges[0].high, _Digits) +
                        " Mid: " + DoubleToString(state.asianRanges[0].middle, _Digits) +
                        " Low: " + DoubleToString(state.asianRanges[0].low, _Digits);
      addTextOnScreen(rangeMsg, InfoTextColor);
   }

   if(ArraySize(state.londonRanges) > 0) {
      string rangeMsg2 = "LR High: " + DoubleToString(state.londonRanges[0].high, _Digits) +
                        " Mid: " + DoubleToString(state.londonRanges[0].middle, _Digits) +
                        " Low: " + DoubleToString(state.londonRanges[0].low, _Digits);
      addTextOnScreen(rangeMsg2, InfoTextColor);
   }

   // Show current price vs. MA
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool aboveSMA = CheckIsAboveSMA(prevClose, SMA_Period);
   string maCondMsg = "Price vs SMA" + IntegerToString(SMA_Period) + ": " + (aboveSMA ? "ABOVE" : "BELOW");
   addTextOnScreen(maCondMsg, aboveSMA ? PositiveCondColor : NegativeCondColor);

   // Show FVG counts
   string fvgMsg = "FVGs: " + IntegerToString(ArraySize(state.bullishFVGs)) + " Bullish, " +
                   IntegerToString(ArraySize(state.bearishFVGs)) + " Bearish";
   addTextOnScreen(fvgMsg, InfoTextColor);

   // Show position details or signal conditions
   if(HasActivePositionsOrOrders()) {
      ShowPositionDetails();
   } else {
      ShowSignalConditions();
   }
}

//+------------------------------------------------------------------+
//| Show details of current open position                            |
//+------------------------------------------------------------------+
void ShowPositionDetails() {
   addTextOnScreen("=== POSITION DETAILS ===", InfoTextColor);

   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (posType == POSITION_TYPE_BUY) ?
                               SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                               SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double slPrice = PositionGetDouble(POSITION_SL);
         double tpPrice = PositionGetDouble(POSITION_TP);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);

         // Position details
         string posTypeStr = (posType == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
         string posMsg = "Position: " + posTypeStr + " | Volume: " + DoubleToString(volume, 2);
         addTextOnScreen(posMsg, InfoTextColor);

         // Entry and current price
         string priceMsg = "Entry: " + DoubleToString(openPrice, _Digits) +
                           " | Current: " + DoubleToString(currentPrice, _Digits);
         addTextOnScreen(priceMsg, InfoTextColor);

         // Stop loss and take profit
         string slTpMsg = "SL: " + DoubleToString(slPrice, _Digits) +
                          " | TP: " + DoubleToString(tpPrice, _Digits);
         addTextOnScreen(slTpMsg, InfoTextColor);

         // Profit and BE condition
         string profitMsg = "Profit: $" + DoubleToString(profit, 2);
         color profitColor = (profit >= 0) ? PositiveCondColor : NegativeCondColor;
         addTextOnScreen(profitMsg, profitColor);

         // BE condition
         string beCondMsg = "";
         if(UseBreakeven && !state.partialClosed) {
            beCondMsg = "BE Status: " + (slPrice == openPrice ? "ACTIVE" : "WAITING"); // use == to allow both sell & buy
            addTextOnScreen(beCondMsg, (slPrice == openPrice) ? PositiveCondColor : InfoTextColor);
         }

         // Partial profit condition
         string partialMsg = "";
         if(UsePartialProfit) {
            partialMsg = "Partial Status: " + (state.partialClosed ? "TAKEN" : "WAITING");
            addTextOnScreen(partialMsg, state.partialClosed ? PositiveCondColor : InfoTextColor);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Show current signal conditions                                   |
//+------------------------------------------------------------------+
void ShowSignalConditions() {
   if(ArraySize(state.londonRanges) == 0) return;

   addTextOnScreen("=== SIGNAL CONDITIONS ===", InfoTextColor);

   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool inNYHour = IsNYHour();
   bool riskValid = AccountRiskValid();
   bool tradingConditionsValid = inNYHour && riskValid;

   // Long conditions
   bool aboveSMA = CheckIsAboveSMA(prevClose, SMA_Period);
   bool aboveMiddle = (prevClose > state.londonRanges[0].middle);
   bool hasBullishFVGs = (ArraySize(state.bullishFVGs) > 0);

   string longCondMsg = "LONG Signal Conditions:";
   addTextOnScreen(longCondMsg, InfoTextColor);

   string aboveSMAMsg = "- Price Above SMA" + IntegerToString(SMA_Period) + ": " + (aboveSMA ? "YES" : "NO");
   string aboveMiddleMsg = "- Price Above LR Middle: " + (aboveMiddle ? "YES" : "NO");
   string bullishFVGMsg = "- Bullish FVGs Present: " + (hasBullishFVGs ? "YES" : "NO");

   addTextOnScreen(aboveSMAMsg, aboveSMA ? PositiveCondColor : NegativeCondColor);
   addTextOnScreen(aboveMiddleMsg, aboveMiddle ? PositiveCondColor : NegativeCondColor);
   addTextOnScreen(bullishFVGMsg, hasBullishFVGs ? PositiveCondColor : NegativeCondColor);

   // Short conditions
   bool belowSMA = !aboveSMA;
   bool belowMiddle = (prevClose < state.londonRanges[0].middle);
   bool hasBearishFVGs = (ArraySize(state.bearishFVGs) > 0);

   string shortCondMsg = "SHORT Signal Conditions:";
   addTextOnScreen(shortCondMsg, InfoTextColor);

   string belowSMAMsg = "- Price Below SMA" + IntegerToString(SMA_Period) + ": " + (belowSMA ? "YES" : "NO");
   string belowMiddleMsg = "- Price Below LR Middle: " + (belowMiddle ? "YES" : "NO");
   string bearishFVGMsg = "- Bearish FVGs Present: " + (hasBearishFVGs ? "YES" : "NO");

   addTextOnScreen(belowSMAMsg, belowSMA ? PositiveCondColor : NegativeCondColor);
   addTextOnScreen(belowMiddleMsg, belowMiddle ? PositiveCondColor : NegativeCondColor);
   addTextOnScreen(bearishFVGMsg, hasBearishFVGs ? PositiveCondColor : NegativeCondColor);

   // Overall signal status
   bool longSignalValid =  aboveSMA && aboveMiddle && hasBullishFVGs && tradingConditionsValid;
   bool shortSignalValid = belowSMA && belowMiddle && hasBearishFVGs && tradingConditionsValid;

   string signalStatusMsg = "Ready to Trade: ";
   if(longSignalValid) signalStatusMsg += "LONG";
   else if(shortSignalValid) signalStatusMsg += "SHORT";
   else signalStatusMsg += "NO";

   color signalColor = (longSignalValid || shortSignalValid) ? PositiveCondColor : NegativeCondColor;
   addTextOnScreen(signalStatusMsg, signalColor);
}

//+------------------------------------------------------------------+
//| Update market structure elements                                 |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
   // Get swing points
   GetSwingLows(MaxSwingPoints, state.swingLows, PERIOD_CURRENT, 500, DrawOnChart, clrCrimson);
   GetSwingHighs(MaxSwingPoints, state.swingHighs, PERIOD_CURRENT, 500, DrawOnChart, clrDodgerBlue);

   // Get FVGs outside of opening range - for overall market context
   GetBullishFVGs(FVGLookBackBars, MinFVGSearchRange, state.bullishFVGs, MinFVGSearchRange, DrawOnChart, clrGreenYellow, false);
   GetBearishFVGs(FVGLookBackBars, MinFVGSearchRange, state.bearishFVGs, MinFVGSearchRange, DrawOnChart, clrDeepPink, false);
}

//+------------------------------------------------------------------+
//| Check if current time is within Smart Breakout trading hours     |
//+------------------------------------------------------------------+
bool IsNYHour() {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   return (dt.hour >= startTradingHour && dt.hour < endTradingHour);
}

//+------------------------------------------------------------------+
//| Check account risk conditions                                    |
//+------------------------------------------------------------------+
bool AccountRiskValid() {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayPnL = currentBalance - state.startDayBalance;

   // Check if daily loss is exceeded (negative dayPnL beyond the limit)
   bool lossExceeded = (dayPnL <= -MaxDailyLoss);

   // Check if daily target is reached (positive dayPnL reaching the target)
   bool targetReached = (dayPnL >= DailyTarget);

   // Debug output
   if(lossExceeded) Print("Daily loss limit exceeded: $", DoubleToString(dayPnL, 2));
   if(targetReached) Print("Daily profit target reached: $", DoubleToString(dayPnL, 2));

   // Return valid if neither condition is true
   return !(lossExceeded || targetReached);
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
TRADE_DIRECTION CheckForEntrySignals() {
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool aboveSMA = CheckIsAboveSMA(prevClose, SMA_Period);

   double keyLevels[];
   ArrayResize(keyLevels, 6);
   keyLevels[0] = state.prevDayHigh;
   keyLevels[1] = state.prevDayLow;
   keyLevels[2] = state.asianRanges[0].high;
   keyLevels[3] = state.asianRanges[0].low;
   keyLevels[4] = state.londonRanges[0].high;
   keyLevels[5] = state.londonRanges[0].low;

   // LONG signal
   if(ArraySize(state.swingLows) > 0 && aboveSMA && ArraySize(state.bullishFVGs) > 0) {
      if(!CheckIsAboveSMA(state.swingLows[1].price, SMA_Period) && !CheckIsAboveSMA(state.swingLows[0].price, SMA_Period)) {
         Print("Found swing lows below SMA");
         GetBullishFVGs(FVGLookBackBars, state.swingLows[0].bar, state.bullishFVGs, MinFVGSearchRange, DrawOnChart, clrGreenYellow, false);
         if(ArraySize(state.bullishFVGs) >= 1) {
            Print("Found at least 1 bullish FVGs after swing low below SMA");
            for(int i = 0; i < ArraySize(keyLevels); i++) {
               if((state.swingLows[1].price <= keyLevels[i] || state.swingLows[0].price <= keyLevels[i]) && prevClose > keyLevels[i]) {
                  Print("Reacting off key level: ", keyLevels[i]);
                  return LONG;
               }
            }
         }
      }
   }

   // SHORT signal
   if(ArraySize(state.swingHighs) > 0 && !aboveSMA &&  ArraySize(state.bearishFVGs) > 0) {
      if(CheckIsAboveSMA(state.swingHighs[1].price, SMA_Period) && CheckIsAboveSMA(state.swingHighs[0].price, SMA_Period)) {
         Print("Found swing highs above SMA");
         GetBearishFVGs(FVGLookBackBars, state.swingHighs[0].bar, state.bearishFVGs, MinFVGSearchRange, DrawOnChart, clrDeepPink, false);
         if(ArraySize(state.bearishFVGs) >= 1) {
            Print("Found at least 1 bearish FVGs after swing high above SMA");
            for(int i = 0; i < ArraySize(keyLevels); i++) {
               if((state.swingHighs[1].price >= keyLevels[i] || state.swingHighs[0].price >= keyLevels[i]) && prevClose < keyLevels[i]) {
                  Print("Reacting off key level: ", keyLevels[i]);
                  return SHORT;
               }
            }
         }
      }
   }

   return NO_DIRECTION;
}

//+------------------------------------------------------------------+
//| Execute trade based on signal                                    |
//+------------------------------------------------------------------+
void ExecuteTradeSignal(TRADE_DIRECTION signal) {
   // Check trading conditions
   if(!IsNYHour() || !AccountRiskValid() || signal == NO_DIRECTION) {
      Print("Trading conditions not met: ",
            IsNYHour() ? "In NY hour" : "Not in NY hour", ", ",
            AccountRiskValid() ? "Account risk valid" : "Account risk invalid");
      return;
   }

   double entryPrice, stopLoss, takeProfit, lotSize;

   switch(signal) {
      case LONG:
         Print("Executing LONG signal");

         // Calculate trade parameters
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         stopLoss = iLow(_Symbol, PERIOD_CURRENT, state.bullishFVGs[0].bar - 1) - (BufferPips * GetPipValue());
         // takeProfit = CalculateTpPrice(entryPrice, stopLoss, MinRRR);
         takeProfit = 0.0; // No take profit for now
         lotSize = CalculateLotSize(RiskDollars, entryPrice, stopLoss, true);

         // Store entry price for position management
         state.entryPrice = entryPrice;
         state.stopLoss = stopLoss;
         state.partialClosed = false;

         // Execute buy order
         if(!trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "NY-BUY")) {
            Print("Failed to place buy order. Error: ", GetLastError());
         } else {
            Print("Buy order placed successfully.");
         }
         break;

      case SHORT:
         Print("Executing SHORT signal");

         // Calculate trade parameters
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         stopLoss = iHigh(_Symbol, PERIOD_CURRENT, state.bearishFVGs[0].bar - 1) + (BufferPips * GetPipValue());
         // takeProfit = CalculateTpPrice(entryPrice, stopLoss, MinRRR);
         takeProfit = 0.0; // No take profit for now
         lotSize = CalculateLotSize(RiskDollars, entryPrice, stopLoss, true);

         // Store entry price for position management
         state.entryPrice = entryPrice;
         state.stopLoss = stopLoss;
         state.partialClosed = false;

         // Execute sell order
         if(!trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "NY-SELL")) {
            Print("Failed to place sell order. Error: ", GetLastError());
         } else {
            Print("Sell order placed successfully.");
         }
         break;

      case NO_DIRECTION:
         // No action needed
         break;
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions() {
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentClose = iClose(_Symbol, PERIOD_CURRENT, 0);

         // close if two candles close below SMA
         if(posType == POSITION_TYPE_BUY) {
            if(currentClose < state.swingLows[0].price || !CheckIsAboveSMA(currentClose, SMA_Period)) {
               if(UseBreakeven) MoveSymbolStopLossToBreakeven(state.beRRR);
               // Take partial profit if condition met and not already taken
               if(UsePartialProfit && !state.partialClosed) {
                  state.partialClosed = TakePartialProfit(state.partialRRR, PartialPercent);
                  if(state.partialClosed) {
                     Print("Partial profit taken");
                  }
               }
            }
         }

         // close if two candles close above SMA
         if(posType == POSITION_TYPE_SELL) {
            if(currentClose > state.swingHighs[0].price || CheckIsAboveSMA(currentClose, SMA_Period)) {
               if(UseBreakeven) MoveSymbolStopLossToBreakeven(state.beRRR);
               // Take partial profit if condition met and not already taken
               if(UsePartialProfit && !state.partialClosed) {
                  state.partialClosed = TakePartialProfit(state.partialRRR, PartialPercent);
                  if(state.partialClosed) {
                     Print("Partial profit taken");
                  }
               }
            }
         }
      }
   }
}
