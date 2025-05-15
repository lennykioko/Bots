//+------------------------------------------------------------------+
//|                                     SessionOpenRangeFVGStrategy.mq5 |
//|                                  Copyright 2023, Your Company Name. |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Company Name."
#property link      "https://www.example.com"
#property version   "1.00"
#property strict

// Include helper modules
#include <Helpers/GetRange.mqh>
#include <Helpers/GetSwingHighLows.mqh>
#include <Helpers/GetFVGs.mqh>
#include <Helpers/RiskManagement.mqh>
#include <Helpers/OrderManagement.mqh>
#include <Helpers/GetIndicators.mqh>
#include <Helpers/TextDisplay.mqh>

// Enumerations
enum TRADE_STATE {
   STATE_NO_TRADE,      // No trade conditions met
   STATE_WAIT_BUY,      // Waiting for a bearish candle to buy
   STATE_WAIT_SELL,     // Waiting for a bullish candle to sell
   STATE_IN_TRADE,      // Already in a trade
   STATE_MAX_TRADES,    // Maximum trades reached
   STATE_MAX_LOSS       // Maximum loss reached
};

//+------------------------------------------------------------------+
//| Strategy state structure                                          |
//+------------------------------------------------------------------+
class StrategyState {
public:
   // Market structure
   TimeRange       openingRange;     // 16:30 to 17:00 range
   FVG             firstBullFVG;     // First bullish FVG
   FVG             firstBearFVG;     // First bearish FVG
   FVG             firstFVG;         // First FVG (either bullish or bearish)
   bool            isFirstFVGBullish; // Whether the first FVG is bullish (true) or bearish (false)
   SwingPoint      swingHighs[];     // Swing highs past 17:00
   SwingPoint      swingLows[];      // Swing lows past 17:00

   // Strategy state
   TRADE_STATE     currentState;     // Current trading state
   bool            fvgFound;         // Whether the FVG has been found
   datetime        sessionStartTime; // Start of trading session (17:00)
   datetime        sessionEndTime;   // End of trading session (19:00)
   datetime        lastCheck;        // Time of last check
   int             dayOfYear;        // Current day of year for daily resets

   // Risk management
   int             tradesOpenedToday; // Number of trades opened today
   datetime        tradeTimeLog[];    // Log of trade times
   double          dayProfit;         // Cumulative profit/loss for the day
   double          maxLossAmount;     // Maximum loss amount per day
   double          dayStartBalance;   // Account balance at start of day

   // Constructor
   StrategyState() {
      currentState = STATE_NO_TRADE;
      fvgFound = false;
      lastCheck = 0;
      tradesOpenedToday = 0;
      dayProfit = 0.0;
      maxLossAmount = 0.0;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      isFirstFVGBullish = true; // Default
      dayOfYear = 0;
   }
};

// Global variables
StrategyState State;

// Input parameters
// Time settings
input string TimeSettings = "===== Time Settings ====="; // Time Settings
input string OpenRangeStartTime = "16:30";             // Opening Range Start
input string OpenRangeEndTime = "17:00";               // Opening Range End
input string SessionStartTime = "17:00";               // Trading Session Start
input string SessionEndTime = "19:00";                 // Trading Session End

// Trade settings
input string TradeSettings = "===== Trade Settings ====="; // Trade Settings
input double RiskPerTrade = 77.0;                     // Risk Per Trade (in dollars)
input double RewardRiskRatio = 3.0;                    // Reward:Risk Ratio
input int    MaxTradesPerDay = 3;                      // Maximum Trades Per Day
input int    MaxTradesPerHour = 2;                     // Maximum Trades Per Hour
input double MaxLossPerDay = 3.0;                      // Max Loss Per Day (multiple of Risk)

// FVG settings
input string FVGSettings = "===== FVG Settings ====="; // FVG Settings
input bool   IncludeFirstCandleFVG = false;            // Include FVGs on first candle of range
input int    MinFVGSearchBars = 200;                   // Minimum bars to search for FVGs

// Indicators
input string IndicatorSettings = "===== Indicator Settings ====="; // Indicator Settings
input int MADuration = 20;                            // Moving Average Period (5 min timeframe)

// Visualization
input string VisualSettings = "===== Visual Settings ====="; // Visualization Settings
input bool   ShowFVGs = true;                         // Show FVGs on chart
input bool   ShowSwingPoints = true;                  // Show Swing Points on chart
input bool   ShowOpeningRange = true;                 // Show Opening Range
input color  BullFVGColor = clrGreenYellow;           // Bullish FVG color
input color  BearFVGColor = clrDeepPink;              // Bearish FVG color
input color  SwingHighColor = clrDodgerBlue;          // Swing High color
input color  SwingLowColor = clrCrimson;              // Swing Low color
input color  OpenRangeColor = clrGoldenrod;           // Opening Range color

// Additional input parameters for trade management
input string TradeManagementSettings = "===== Trade Management Settings ====="; // Trade Management
input double BE_RRR_Level = 1.5;           // Move to Breakeven at R multiple
input double PARTIAL_PROFIT_PERCENT = 0.4; // Take partial profit percentage at BE level
input double PARTIAL_LOSS_RRR = 0.8;       // Take partial loss at R multiple
input double PARTIAL_LOSS_PERCENT = 0.5;   // Partial loss percentage

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Clear chart objects
   ObjectsDeleteAll(ChartID(), "");

   // Calculate maximum loss amount
   State.maxLossAmount = -(RiskPerTrade * MaxLossPerDay);

   // Set up timer for main processing - adjust for optimization in backtesting
   if (IsTesting() && !IsVisualMode()) {
      // Use longer timer interval for non-visual backtesting (5 seconds instead of 1)
      EventSetTimer(5);
   } else {
      // Standard 1-second timer for visual mode and live trading
      EventSetTimer(1);
   }

   // Set up session times
   SetupSessionTimes();

   // Initialize text display
   clearTextDisplay();

   // Initialize day of year
   MqlDateTime dt;
   datetime now = TimeCurrent();
   TimeToStruct(now, dt);
   State.dayOfYear = dt.day_of_year;

   // Reset trading state
   State.tradesOpenedToday = 0;
   State.currentState = STATE_NO_TRADE;
   State.fvgFound = false;
   State.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("EA initialized on day ", State.dayOfYear,
         ". Max loss amount: ", State.maxLossAmount,
         ", Trades opened today: ", State.tradesOpenedToday);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Clean up resources
   ObjectsDeleteAll(ChartID(), "");
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer() {
   // Always check for day reset first
   CheckDayReset();

   // Quick check if within trading hours - exit immediately if not
   if (!IsWithinTradingHours()) {
      // Only update display if visible on chart (optimization for backtesting)
      if (IsTesting() && !IsVisualMode()) {
         // In non-visual backtesting, skip any display updates for speed
         return;
      }

      // Update display only in visual mode or live trading
      clearTextDisplay();
      addTextOnScreen("Outside trading hours", clrRed);
      addTextOnScreen("Current time: " + TimeToString(TimeCurrent()), clrWhite);
      addTextOnScreen("Session start: " + TimeToString(State.sessionStartTime), clrWhite);
      addTextOnScreen("Session end: " + TimeToString(State.sessionEndTime), clrWhite);

      // Additional debug information about trade state
      string stateStr = "";
      switch (State.currentState) {
         case STATE_NO_TRADE:  stateStr = "No Trade Signal"; break;
         case STATE_WAIT_BUY:  stateStr = "Waiting for Bearish Candle to BUY"; break;
         case STATE_WAIT_SELL: stateStr = "Waiting for Bullish Candle to SELL"; break;
         case STATE_IN_TRADE:  stateStr = "In Trade"; break;
         case STATE_MAX_TRADES: stateStr = "Maximum Trades Reached"; break;
         case STATE_MAX_LOSS:  stateStr = "Maximum Loss Reached"; break;
      }
      addTextOnScreen("Current state: " + stateStr, clrYellow);
      addTextOnScreen("Trades opened today: " + IntegerToString(State.tradesOpenedToday), clrYellow);
      addTextOnScreen("Day of Year: " + IntegerToString(State.dayOfYear), clrYellow);
      return;
   }

   // Continue with regular processing - we're in trading hours

   // Clear display
   clearTextDisplay();

   // Update daily performance
   UpdateDailyPerformance();

   // Update market structure
   UpdateMarketStructure();

   // Manage existing trades
   ManageExistingTrades();

   // Process trading logic
   ProcessTradingLogic();

   // Display current status
   DisplayStatus();
}

//+------------------------------------------------------------------+
//| Set up session time variables                                    |
//+------------------------------------------------------------------+
void SetupSessionTimes() {
   // Today's date at midnight
   datetime today = TimeCurrent();
   today = today - (today % 86400); // Round down to midnight (00:00:00)

   // Simple string to hour/minute conversion
   int orStartHour = (int)StringToInteger(StringSubstr(OpenRangeStartTime, 0, 2));
   int orStartMin = (int)StringToInteger(StringSubstr(OpenRangeStartTime, 3, 2));

   int orEndHour = (int)StringToInteger(StringSubstr(OpenRangeEndTime, 0, 2));
   int orEndMin = (int)StringToInteger(StringSubstr(OpenRangeEndTime, 3, 2));

   int sessionStartHour = (int)StringToInteger(StringSubstr(SessionStartTime, 0, 2));
   int sessionStartMin = (int)StringToInteger(StringSubstr(SessionStartTime, 3, 2));

   int sessionEndHour = (int)StringToInteger(StringSubstr(SessionEndTime, 0, 2));
   int sessionEndMin = (int)StringToInteger(StringSubstr(SessionEndTime, 3, 2));

   // Convert to seconds and add to today's midnight
   State.sessionStartTime = today + (sessionStartHour * 3600) + (sessionStartMin * 60);
   State.sessionEndTime = today + (sessionEndHour * 3600) + (sessionEndMin * 60);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours() {
   datetime now = TimeCurrent();

   // Get today's session times
   datetime today = now - (now % 86400);  // Today at midnight
   datetime todayStart = today + (State.sessionStartTime % 86400);  // Get just the time portion
   datetime todayEnd = today + (State.sessionEndTime % 86400);  // Get just the time portion

   return (now >= todayStart && now <= todayEnd);
}

//+------------------------------------------------------------------+
//| Update market structure: OR, FVGs, and Swing points               |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
   // Update opening range (if not already updated)
   if (!State.openingRange.valid) {
      UpdateOpeningRange();
   }

   // Update swing points since trading session start
   UpdateSwingPoints();

   // Update FVGs (if not already found)
   if (!State.fvgFound) {
      UpdateFVGs();
   }
}

//+------------------------------------------------------------------+
//| Update the opening range (16:30 to 17:00)                        |
//+------------------------------------------------------------------+
void UpdateOpeningRange() {
   TimeRange range = CalculateRangeForDay(OpenRangeStartTime, OpenRangeEndTime, 0, "OR", ShowOpeningRange, PERIOD_CURRENT);
   State.openingRange = range;

   if (ShowOpeningRange && range.valid) {
      DrawRangeLevels(range, "OR", true, PERIOD_CURRENT, OpenRangeColor, OpenRangeColor, OpenRangeColor);
   }
}

//+------------------------------------------------------------------+
//| Update swing points since trading session start                   |
//+------------------------------------------------------------------+
void UpdateSwingPoints() {
   // Calculate how many bars are between current time and session start
   int barsSinceSessionStart = 0;
   datetime now = TimeCurrent();

   MqlDateTime nowStruct;
   TimeToStruct(now, nowStruct);

   MqlDateTime todaySessionStartStruct;
   TimeToStruct(State.sessionStartTime, todaySessionStartStruct);
   todaySessionStartStruct.year = nowStruct.year;
   todaySessionStartStruct.mon = nowStruct.mon;
   todaySessionStartStruct.day = nowStruct.day;

   datetime todaySessionStart = StructToTime(todaySessionStartStruct);

   for (int i = 0; i < 500; i++) {
      datetime barTime = iTime(_Symbol, PERIOD_M1, i);
      if (barTime <= todaySessionStart) {
         barsSinceSessionStart = i;
         break;
      }
   }

   // Get swing points on M1 timeframe
   GetSwingHighs(10, State.swingHighs, PERIOD_M1, barsSinceSessionStart, ShowSwingPoints, SwingHighColor);
   GetSwingLows(10, State.swingLows, PERIOD_M1, barsSinceSessionStart, ShowSwingPoints, SwingLowColor);
}

//+------------------------------------------------------------------+
//| Update FVGs - find the first FVG after opening range                |
//+------------------------------------------------------------------+
void UpdateFVGs() {
   // Only update if we haven't found a valid FVG yet
   if (State.fvgFound)
      return;

   // Add debug info about FVG search
   addTextOnScreen("Searching for FVGs...", clrYellow);

   // Calculate the timestamp for FVG search start time
   datetime now = TimeCurrent();
   datetime today = now - (now % 86400);  // Today at midnight

   // Parse OpenRangeStartTime to get hours and minutes
   int orStartHour = (int)StringToInteger(StringSubstr(OpenRangeStartTime, 0, 2));
   int orStartMin = (int)StringToInteger(StringSubstr(OpenRangeStartTime, 3, 2));

   // FVG search will start at the opening range start
   int seconds = (orStartHour * 3600) + (orStartMin * 60);
   datetime fvgSearchTime = today + seconds;

   // If we don't want to include FVGs on the first candle, move the search time forward by 1 minute
   if (!IncludeFirstCandleFVG) {
      fvgSearchTime += 60; // Add 1 minute
      addTextOnScreen("Excluding first candle FVGs, start time: " + TimeToString(fvgSearchTime), clrYellow);
   } else {
      addTextOnScreen("Including first candle FVGs, start time: " + TimeToString(fvgSearchTime), clrYellow);
   }

   // Find bar index of FVG search time
   int barsSinceStart = 0;
   for (int i = 0; i < 500; i++) {
      datetime barTime = iTime(_Symbol, PERIOD_M1, i);
      if (barTime <= fvgSearchTime) {
         barsSinceStart = i;
         break;
      }
   }

   // Get FVGs
   FVG bullishFVGs[];
   FVG bearishFVGs[];

   GetBullishFVGs(0, barsSinceStart, bullishFVGs, MinFVGSearchBars, ShowFVGs, BullFVGColor, PERIOD_M1);
   GetBearishFVGs(0, barsSinceStart, bearishFVGs, MinFVGSearchBars, ShowFVGs, BearFVGColor, PERIOD_M1);

   // Debug information
   int bullSize = ArraySize(bullishFVGs);
   int bearSize = ArraySize(bearishFVGs);

   addTextOnScreen("Total Bullish FVGs found: " + IntegerToString(bullSize), clrWhite);
   addTextOnScreen("Total Bearish FVGs found: " + IntegerToString(bearSize), clrWhite);

   // Initialize with empty FVGs
   State.firstBullFVG.exists = false;
   State.firstBearFVG.exists = false;
   State.firstFVG.exists = false;

   // Format the time string for display
   string searchTimeStr = IncludeFirstCandleFVG ? OpenRangeStartTime : TimeToString(fvgSearchTime, TIME_MINUTES);

   // Debug the first few FVGs
   for (int i = 0; i < bullSize && i < 3; i++) {
      datetime fvgTime = bullishFVGs[i].time;
      addTextOnScreen("Bullish FVG " + IntegerToString(i) +
                     " Time: " + TimeToString(fvgTime) +
                     " After " + searchTimeStr + ": " + (fvgTime >= fvgSearchTime ? "Yes" : "No"),
                     clrLime);
   }

   for (int i = 0; i < bearSize && i < 3; i++) {
      datetime fvgTime = bearishFVGs[i].time;
      addTextOnScreen("Bearish FVG " + IntegerToString(i) +
                     " Time: " + TimeToString(fvgTime) +
                     " After " + searchTimeStr + ": " + (fvgTime >= fvgSearchTime ? "Yes" : "No"),
                     clrRed);
   }

   // Find the first (chronologically) bullish FVG after the search time
   // Search from the end of the array (oldest) to start (newest)
   datetime firstBullFVGTime = 0;
   for (int i = bullSize - 1; i >= 0; i--) {
      if (bullishFVGs[i].time >= fvgSearchTime) {
         State.firstBullFVG = bullishFVGs[i];
         firstBullFVGTime = State.firstBullFVG.time;
         addTextOnScreen("First Bull FVG after " + searchTimeStr + " - Index: " + IntegerToString(i) +
                        " Time: " + TimeToString(State.firstBullFVG.time), clrLime);
         break;
      }
   }

   // Find the first (chronologically) bearish FVG after the search time
   // Search from the end of the array (oldest) to start (newest)
   datetime firstBearFVGTime = 0;
   for (int i = bearSize - 1; i >= 0; i--) {
      if (bearishFVGs[i].time >= fvgSearchTime) {
         State.firstBearFVG = bearishFVGs[i];
         firstBearFVGTime = State.firstBearFVG.time;
         addTextOnScreen("First Bear FVG after " + searchTimeStr + " - Index: " + IntegerToString(i) +
                        " Time: " + TimeToString(State.firstBearFVG.time), clrRed);
         break;
      }
   }

   // Determine which FVG came first chronologically
   if (State.firstBullFVG.exists && State.firstBearFVG.exists) {
      // Both exist, compare times
      if (firstBullFVGTime <= firstBearFVGTime) {
         State.firstFVG = State.firstBullFVG;
         State.isFirstFVGBullish = true;
         addTextOnScreen("First FVG is BULLISH at " + TimeToString(State.firstFVG.time), clrYellow);
      } else {
         State.firstFVG = State.firstBearFVG;
         State.isFirstFVGBullish = false;
         addTextOnScreen("First FVG is BEARISH at " + TimeToString(State.firstFVG.time), clrYellow);
      }
   } else if (State.firstBullFVG.exists) {
      // Only bullish exists
      State.firstFVG = State.firstBullFVG;
      State.isFirstFVGBullish = true;
      addTextOnScreen("First FVG is BULLISH at " + TimeToString(State.firstFVG.time), clrYellow);
   } else if (State.firstBearFVG.exists) {
      // Only bearish exists
      State.firstFVG = State.firstBearFVG;
      State.isFirstFVGBullish = false;
      addTextOnScreen("First FVG is BEARISH at " + TimeToString(State.firstFVG.time), clrYellow);
   }

   // Mark as found if we have at least one FVG
   if (State.firstBullFVG.exists || State.firstBearFVG.exists) {
      State.fvgFound = true;
      addTextOnScreen("FVGs found and stored", clrYellow);
      Print("FVGs found and stored for day ", State.dayOfYear);
   } else {
      addTextOnScreen("No valid FVGs found after " + searchTimeStr, clrYellow);
   }
}

//+------------------------------------------------------------------+
//| Check and handle day reset                                       |
//+------------------------------------------------------------------+
void CheckDayReset() {
   // Get current date/time
   MqlDateTime dt;
   datetime now = TimeCurrent();
   TimeToStruct(now, dt);

   // Check if it's a new day
   if (State.dayOfYear == 0 || State.dayOfYear != dt.day_of_year) {
      // It's a new day - reset everything
      Print("New day detected! Previous: ", State.dayOfYear, ", Current: ", dt.day_of_year);

      // Reset counters
      State.tradesOpenedToday = 0;
      State.dayProfit = 0.0;
      ArrayFree(State.tradeTimeLog);

      // Update balance
      State.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Reset FVG finding state
      State.fvgFound = false;
      State.firstBullFVG.exists = false;
      State.firstBearFVG.exists = false;
      State.firstFVG.exists = false;

      // Reset trade state if needed
      if (State.currentState == STATE_MAX_TRADES || State.currentState == STATE_MAX_LOSS) {
         State.currentState = STATE_NO_TRADE;
         Print("Daily limit state reset from: ", (State.currentState == STATE_MAX_TRADES ? "MAX_TRADES" : "MAX_LOSS"), " to NO_TRADE");
      }

      // Store the new day
      State.dayOfYear = dt.day_of_year;

      Print("Daily reset complete for day ", dt.day_of_year,
            ". Starting balance: ", State.dayStartBalance,
            ", FVG reset: ", !State.fvgFound);
   }
}

//+------------------------------------------------------------------+
//| Update daily performance by comparing with starting balance       |
//+------------------------------------------------------------------+
void UpdateDailyPerformance() {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   State.dayProfit = currentBalance - State.dayStartBalance;
}

//+------------------------------------------------------------------+
//| Check if we can open more trades based on limits                 |
//+------------------------------------------------------------------+
bool CanOpenMoreTrades() {
   // Debug info - add trade count to journal if at limit
   if(State.tradesOpenedToday >= MaxTradesPerDay) {
      Print("Max daily trades reached. Current count: ", State.tradesOpenedToday, "/", MaxTradesPerDay);
      State.currentState = STATE_MAX_TRADES;
      return false;
   }

   // Check maximum loss per day
   if(State.dayProfit <= State.maxLossAmount) {
      Print("Max daily loss reached. Current P/L: ", DoubleToString(State.dayProfit, 2), ", Limit: ", DoubleToString(State.maxLossAmount, 2));
      State.currentState = STATE_MAX_LOSS;
      return false;
   }

   // Check maximum trades per hour
   datetime now = TimeCurrent();
   int tradesInLastHour = 0;

   for(int i = 0; i < ArraySize(State.tradeTimeLog); i++) {
      if(now - State.tradeTimeLog[i] < 3600) { // 3600 seconds = 1 hour
         tradesInLastHour++;
      }
   }

   if(tradesInLastHour >= MaxTradesPerHour) {
      // We don't change the state for hourly limits, just return false
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Process trading logic based on strategy rules                     |
//+------------------------------------------------------------------+
void ProcessTradingLogic() {
   // If already in a trade, manage it
   if (HasActivePositionsOrOrders()) {
      State.currentState = STATE_IN_TRADE;
      return;
   }

   // Reset state if not in a trade
   if (State.currentState == STATE_IN_TRADE) {
      State.currentState = STATE_NO_TRADE;
   }

   // Check if we've reached our trading limits
   if(!CanOpenMoreTrades()) {
      return; // State is already set by CanOpenMoreTrades
   }

   // Check for buy signal conditions
   if (State.currentState == STATE_NO_TRADE || State.currentState == STATE_WAIT_BUY) {
      if (CheckBuyConditions()) {
         State.currentState = STATE_WAIT_BUY;

         // Check if previous candle is bearish
         if (IsBearishCandle()) {
            ExecuteBuyTrade();
            State.currentState = STATE_IN_TRADE;

            // Update trade counters
            State.tradesOpenedToday++;
            ArrayResize(State.tradeTimeLog, ArraySize(State.tradeTimeLog) + 1);
            State.tradeTimeLog[ArraySize(State.tradeTimeLog) - 1] = TimeCurrent();
         }
      } else {
         State.currentState = STATE_NO_TRADE;
      }
   }

   // Check for sell signal conditions
   if (State.currentState == STATE_NO_TRADE || State.currentState == STATE_WAIT_SELL) {
      if (CheckSellConditions()) {
         State.currentState = STATE_WAIT_SELL;

         // Check if previous candle is bullish
         if (IsBullishCandle()) {
            ExecuteSellTrade();
            State.currentState = STATE_IN_TRADE;

            // Update trade counters
            State.tradesOpenedToday++;
            ArrayResize(State.tradeTimeLog, ArraySize(State.tradeTimeLog) + 1);
            State.tradeTimeLog[ArraySize(State.tradeTimeLog) - 1] = TimeCurrent();
         }
      } else {
         State.currentState = STATE_NO_TRADE;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if all buy conditions are met                               |
//+------------------------------------------------------------------+
bool CheckBuyConditions() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 1. Price is above middle of 16:30 to 17:00 range
   bool aboveMiddle = currentPrice > State.openingRange.middle;

   // 2. Price above Moving Average 20 of five minutes
   bool aboveMA = CheckIsAboveSMA(currentPrice, MADuration, PERIOD_M5);

   // 3. Previous swing high that is past 17:00 has been taken
   bool swingHighTaken = CheckSwingHighTaken();

   // 4. Price is above the high of the first presented fair value gap
   bool aboveFVGHigh = false;

   // Check based on the first FVG
   if (State.firstFVG.exists) {
      // Price should be above the high of the FVG for a buy
      aboveFVGHigh = currentPrice > State.firstFVG.high;
   }

   return aboveMiddle && aboveMA && swingHighTaken && aboveFVGHigh;
}

//+------------------------------------------------------------------+
//| Check if all sell conditions are met                              |
//+------------------------------------------------------------------+
bool CheckSellConditions() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 1. Price is below middle of 16:30 to 17:00 range
   bool belowMiddle = currentPrice < State.openingRange.middle;

   // 2. Price below Moving Average 20 of five minutes
   bool belowMA = !CheckIsAboveSMA(currentPrice, MADuration, PERIOD_M5);

   // 3. Previous swing low that is past 17:00 has been taken
   bool swingLowTaken = CheckSwingLowTaken();

   // 4. Price is below the low of the first presented fair value gap
   bool belowFVGLow = false;

   // Check based on the first FVG
   if (State.firstFVG.exists) {
      // Price should be below the low of the FVG for a sell
      belowFVGLow = currentPrice < State.firstFVG.low;
   }

   return belowMiddle && belowMA && swingLowTaken && belowFVGLow;
}

//+------------------------------------------------------------------+
//| Check if a swing low has been taken                              |
//+------------------------------------------------------------------+
bool CheckSwingLowTaken() {
   if (ArraySize(State.swingLows) == 0)
      return false;

   // Check if the most recent swing low has been taken
   bool taken = State.swingLows[0].taken;
   addTextOnScreen("Most recent swing low taken: " + (taken ? "Yes" : "No"), clrCrimson);
   return taken;
}

//+------------------------------------------------------------------+
//| Check if a swing high has been taken                             |
//+------------------------------------------------------------------+
bool CheckSwingHighTaken() {
   if (ArraySize(State.swingHighs) == 0)
      return false;

   // Check if the most recent swing high has been taken
   bool taken = State.swingHighs[0].taken;
   addTextOnScreen("Most recent swing high taken: " + (taken ? "Yes" : "No"), clrDodgerBlue);
   return taken;
}

//+------------------------------------------------------------------+
//| Check if previous candle is bearish                               |
//+------------------------------------------------------------------+
bool IsBearishCandle() {
   double open = iOpen(_Symbol, PERIOD_M1, 1);
   double close = iClose(_Symbol, PERIOD_M1, 1);

   return close < open;
}

//+------------------------------------------------------------------+
//| Check if previous candle is bullish                              |
//+------------------------------------------------------------------+
bool IsBullishCandle() {
   double open = iOpen(_Symbol, PERIOD_M1, 1);
   double close = iClose(_Symbol, PERIOD_M1, 1);

   return close > open;
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuyTrade() {
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Get the most recent swing high for stop loss
   double stopLoss = GetMostRecentSwingLow();
   if (stopLoss >= entryPrice) {
      // Invalid stop loss, use a default value
      stopLoss = entryPrice - (150 * _Point);
   }

   // Calculate take profit using the Reward:Risk Ratio
   double takeProfit = CalculateTpPrice(entryPrice, stopLoss, RewardRiskRatio);

   // Use direct risk amount in dollars
   double riskDollars = RiskPerTrade;
   double lotSize = CalculateLotSize(riskDollars, entryPrice, stopLoss);

   // Execute the order using the global trade object from OrderManagement.mqh
   trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lotSize, entryPrice, stopLoss, takeProfit, "OR FVG Strategy");
}

//+------------------------------------------------------------------+
//| Execute sell trade                                               |
//+------------------------------------------------------------------+
void ExecuteSellTrade() {
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get the most recent swing low for stop loss
   double stopLoss = GetMostRecentSwingHigh();
   if (stopLoss <= entryPrice) {
      // Invalid stop loss, use a default value
      stopLoss = entryPrice + (150 * _Point);
   }

   // Calculate take profit using the Reward:Risk Ratio
   double takeProfit = CalculateTpPrice(entryPrice, stopLoss, RewardRiskRatio);

   // Use direct risk amount in dollars
   double riskDollars = RiskPerTrade;
   double lotSize = CalculateLotSize(riskDollars, entryPrice, stopLoss);

   // Execute the order using the global trade object from OrderManagement.mqh
   trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lotSize, entryPrice, stopLoss, takeProfit, "OR FVG Strategy");
}

//+------------------------------------------------------------------+
//| Get the most recent swing high price                             |
//+------------------------------------------------------------------+
double GetMostRecentSwingHigh() {
   if (ArraySize(State.swingHighs) == 0)
      return 0;

   // The most recent swing high is at index 0
   double mostRecentPrice = State.swingHighs[0].price;

   // Debug information
   addTextOnScreen("Most recent swing high: " + DoubleToString(mostRecentPrice, _Digits) +
                  " (bar " + IntegerToString(State.swingHighs[0].bar) + ")", clrDodgerBlue);

   return mostRecentPrice;
}

//+------------------------------------------------------------------+
//| Get the most recent swing low price                              |
//+------------------------------------------------------------------+
double GetMostRecentSwingLow() {
   if (ArraySize(State.swingLows) == 0)
      return 0;

   // The most recent swing low is at index 0
   double mostRecentPrice = State.swingLows[0].price;

   // Debug information
   addTextOnScreen("Most recent swing low: " + DoubleToString(mostRecentPrice, _Digits) +
                  " (bar " + IntegerToString(State.swingLows[0].bar) + ")", clrCrimson);

   return mostRecentPrice;
}

//+------------------------------------------------------------------+
//| Display current status on chart                                  |
//+------------------------------------------------------------------+
void DisplayStatus() {
   // Skip display updates in non-visual backtesting for speed
   if (IsTesting() && !IsVisualMode()) {
      return;
   }

   // Display opening range info
   string orStatus = "Opening Range: ";
   if (State.openingRange.valid) {
      orStatus += "High: " + DoubleToString(State.openingRange.high, _Digits) +
                  ", Low: " + DoubleToString(State.openingRange.low, _Digits) +
                  ", Middle: " + DoubleToString(State.openingRange.middle, _Digits);
   } else {
      orStatus += "Not available";
   }
   addTextOnScreen(orStatus, clrWhite);

   // Display FVG info
   string bullFVGStatus = "Bullish FVG: ";
   if (State.firstBullFVG.exists) {
      // Format time with a completely explicit approach
      MqlDateTime timeStruct;
      TimeToStruct(State.firstBullFVG.time, timeStruct);

      // Ensure minutes have 2 digits
      string minuteStr = IntegerToString(timeStruct.min);
      if(timeStruct.min < 10) minuteStr = "0" + minuteStr;

      // Format full time string
      string formattedTime = IntegerToString(timeStruct.year) + "." +
                            IntegerToString(timeStruct.mon) + "." +
                            IntegerToString(timeStruct.day) + " " +
                            IntegerToString(timeStruct.hour) + ":" +
                            minuteStr;

      bullFVGStatus += "High: " + DoubleToString(State.firstBullFVG.high, _Digits) +
                      ", Low: " + DoubleToString(State.firstBullFVG.low, _Digits) +
                      ", Time: " + formattedTime;
   } else {
      bullFVGStatus += "Not found";
   }
   addTextOnScreen(bullFVGStatus, clrLime);

   string bearFVGStatus = "Bearish FVG: ";
   if (State.firstBearFVG.exists) {
      // Format time with a completely explicit approach
      MqlDateTime timeStruct;
      TimeToStruct(State.firstBearFVG.time, timeStruct);

      // Ensure minutes have 2 digits
      string minuteStr = IntegerToString(timeStruct.min);
      if(timeStruct.min < 10) minuteStr = "0" + minuteStr;

      // Format full time string
      string formattedTime = IntegerToString(timeStruct.year) + "." +
                            IntegerToString(timeStruct.mon) + "." +
                            IntegerToString(timeStruct.day) + " " +
                            IntegerToString(timeStruct.hour) + ":" +
                            minuteStr;

      bearFVGStatus += "High: " + DoubleToString(State.firstBearFVG.high, _Digits) +
                      ", Low: " + DoubleToString(State.firstBearFVG.low, _Digits) +
                      ", Time: " + formattedTime;
   } else {
      bearFVGStatus += "Not found";
   }
   addTextOnScreen(bearFVGStatus, clrRed);

   // Display First FVG info (regardless of type)
   string firstFVGStatus = "First FVG: ";
   if (State.firstFVG.exists) {
      // Format time with a completely explicit approach
      MqlDateTime timeStruct;
      TimeToStruct(State.firstFVG.time, timeStruct);

      // Ensure minutes have 2 digits
      string minuteStr = IntegerToString(timeStruct.min);
      if(timeStruct.min < 10) minuteStr = "0" + minuteStr;

      // Format full time string
      string formattedTime = IntegerToString(timeStruct.year) + "." +
                            IntegerToString(timeStruct.mon) + "." +
                            IntegerToString(timeStruct.day) + " " +
                            IntegerToString(timeStruct.hour) + ":" +
                            minuteStr;

      string fvgType = State.isFirstFVGBullish ? "BULLISH" : "BEARISH";

      firstFVGStatus += "Type: " + fvgType +
                       ", High: " + DoubleToString(State.firstFVG.high, _Digits) +
                       ", Low: " + DoubleToString(State.firstFVG.low, _Digits) +
                       ", Time: " + formattedTime;
   } else {
      firstFVGStatus += "Not found";
   }
   addTextOnScreen(firstFVGStatus, clrYellow);

   // Display trading state
   string stateStr = "State: ";
   switch (State.currentState) {
      case STATE_NO_TRADE:  stateStr += "No Trade Signal"; break;
      case STATE_WAIT_BUY:  stateStr += "Waiting for Bearish Candle to BUY"; break;
      case STATE_WAIT_SELL: stateStr += "Waiting for Bullish Candle to SELL"; break;
      case STATE_IN_TRADE:  stateStr += "In Trade"; break;
      case STATE_MAX_TRADES: stateStr += "Maximum Trades Reached"; break;
      case STATE_MAX_LOSS:  stateStr += "Maximum Loss Reached"; break;
   }
   addTextOnScreen(stateStr, clrYellow);

   // Display risk management info
   addTextOnScreen("Risk Management:", clrOrange);
   addTextOnScreen("  Risk Per Trade: $" + DoubleToString(RiskPerTrade, 2), clrWhite);
   addTextOnScreen("  Trades Today: " + IntegerToString(State.tradesOpenedToday) +
                  "/" + IntegerToString(MaxTradesPerDay),
                  State.tradesOpenedToday >= MaxTradesPerDay ? clrRed : clrGreen);

   int tradesInLastHour = 0;
   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(State.tradeTimeLog); i++) {
      if(now - State.tradeTimeLog[i] < 3600) {
         tradesInLastHour++;
      }
   }

   addTextOnScreen("  Trades Last Hour: " + IntegerToString(tradesInLastHour) +
                  "/" + IntegerToString(MaxTradesPerHour),
                  tradesInLastHour >= MaxTradesPerHour ? clrRed : clrGreen);

   addTextOnScreen("  Day P/L: " + DoubleToString(State.dayProfit, 2) +
                  " (Max Loss: " + DoubleToString(State.maxLossAmount, 2) + ")",
                  State.dayProfit < 0 ? (State.dayProfit <= State.maxLossAmount ? clrRed : clrOrange) : clrGreen);

   // Display conditions for buy setup with line breaks
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool aboveMiddle = currentPrice > State.openingRange.middle;
   bool aboveMA = CheckIsAboveSMA(currentPrice, MADuration, PERIOD_M5);
   bool swingHighTaken = CheckSwingHighTaken();
   bool aboveFVGHigh = false;

   // Check based on the first FVG
   if (State.firstFVG.exists) {
      // For buy conditions, price should be above the high
      aboveFVGHigh = currentPrice > State.firstFVG.high;
   }

   addTextOnScreen("BUY Conditions:", clrGreen);
   addTextOnScreen("  Above Middle: " + (aboveMiddle ? "Yes" : "No"), aboveMiddle ? clrGreen : clrRed);
   addTextOnScreen("  Above MA20: " + (aboveMA ? "Yes" : "No"), aboveMA ? clrGreen : clrRed);
   addTextOnScreen("  SwingHigh Taken: " + (swingHighTaken ? "Yes" : "No"), swingHighTaken ? clrGreen : clrRed);
   addTextOnScreen("  Above FVG High: " + (aboveFVGHigh ? "Yes" : "No"), aboveFVGHigh ? clrGreen : clrRed);

   // Display conditions for sell setup with line breaks
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool belowMiddle = bidPrice < State.openingRange.middle;
   bool belowMA = !CheckIsAboveSMA(bidPrice, MADuration, PERIOD_M5);
   bool swingLowTaken = CheckSwingLowTaken();
   bool belowFVGLow = false;

   // Check based on the first FVG
   if (State.firstFVG.exists) {
      // For sell conditions, price should be below the low
      belowFVGLow = bidPrice < State.firstFVG.low;
   }

   addTextOnScreen("SELL Conditions:", clrRed);
   addTextOnScreen("  Below Middle: " + (belowMiddle ? "Yes" : "No"), belowMiddle ? clrGreen : clrRed);
   addTextOnScreen("  Below MA20: " + (belowMA ? "Yes" : "No"), belowMA ? clrGreen : clrRed);
   addTextOnScreen("  SwingLow Taken: " + (swingLowTaken ? "Yes" : "No"), swingLowTaken ? clrGreen : clrRed);
   addTextOnScreen("  Below FVG Low: " + (belowFVGLow ? "Yes" : "No"), belowFVGLow ? clrGreen : clrRed);
}

//+------------------------------------------------------------------+
//| Manage existing trades based on R multiples                      |
//+------------------------------------------------------------------+
void ManageExistingTrades() {
   // Only proceed if we have active positions
   if (!HasActivePositionsOrOrders()) {
      return;
   }

   // Check if a new candle has formed since last check
   static datetime lastCandleTime = 0;
   datetime currentCandleTime = iTime(_Symbol, PERIOD_M1, 0);

   // If this is a new candle, manage trades
   if (currentCandleTime > lastCandleTime) {
      lastCandleTime = currentCandleTime;

      // Check for breakeven and partial profit targets
      CheckBreakevenAndPartialProfit();

      // Check for partial loss targets
      CheckPartialLoss();
   }
}

//+------------------------------------------------------------------+
//| Check if trades have reached breakeven and partial profit levels |
//+------------------------------------------------------------------+
void CheckBreakevenAndPartialProfit() {
   for (int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);

      // Skip positions for other symbols
      if (ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) {
         continue;
      }

      // Get position details
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLoss = PositionGetDouble(POSITION_SL);
      double takeProfit = PositionGetDouble(POSITION_TP);
      double currentPrice = posType == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Calculate initial risk (in price points)
      double initialRisk = MathAbs(entryPrice - stopLoss);

      // Calculate current profit/loss in R multiples
      double currentProfitPoints = posType == POSITION_TYPE_BUY ?
                                 currentPrice - entryPrice :
                                 entryPrice - currentPrice;
      double profitInR = currentProfitPoints / initialRisk;

      // Check if the position has reached our 2R profit target
      if (profitInR >= BE_RRR_Level) {
         // Skip if SL already at or better than breakeven
         bool slAlreadyAtBE = (posType == POSITION_TYPE_BUY && stopLoss >= entryPrice) ||
                              (posType == POSITION_TYPE_SELL && stopLoss <= entryPrice);

         if (!slAlreadyAtBE) {
            // Move stop loss to breakeven
            if (trade.PositionModify(ticket, entryPrice, takeProfit)) {
               Print("Trade reached ", DoubleToString(BE_RRR_Level, 1), "R: SL moved to breakeven");
            } else {
               Print("Failed to move SL to breakeven. Error: ", GetLastError());
            }
         }

         // Take partial profit
         TakePartialProfitByPercent(ticket, PARTIAL_PROFIT_PERCENT);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trades have reached partial loss levels                 |
//+------------------------------------------------------------------+
void CheckPartialLoss() {
   for (int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);

      // Skip positions for other symbols
      if (ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) {
         continue;
      }

      // Get position details
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLoss = PositionGetDouble(POSITION_SL);
      double currentPrice = posType == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Calculate initial risk (in price points)
      double initialRisk = MathAbs(entryPrice - stopLoss);

      // Calculate current loss in R multiples
      double currentLossPoints = posType == POSITION_TYPE_BUY ?
                              entryPrice - currentPrice :
                              currentPrice - entryPrice;
      double lossInR = currentLossPoints / initialRisk;

      // Check if the position has reached our partial loss target
      if (lossInR >= PARTIAL_LOSS_RRR) {
         // Take partial loss
         TakePartialProfitByPercent(ticket, PARTIAL_LOSS_PERCENT);
      }
   }
}

//+------------------------------------------------------------------+
//| Take partial profit/loss by percentage                           |
//+------------------------------------------------------------------+
bool TakePartialProfitByPercent(ulong ticket, double percent) {
   if (!PositionSelectByTicket(ticket)) {
      Print("Failed to select position with ticket #", ticket);
      return false;
   }

   // Get position details
   double positionVolume = PositionGetDouble(POSITION_VOLUME);

   // Calculate lot size to close
   double lotToClose = NormalizeDouble(positionVolume * percent, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Ensure we're closing valid lot size
   lotToClose = MathFloor(lotToClose / stepLot) * stepLot;
   lotToClose = MathMax(lotToClose, minLot);

   // Ensure we're not trying to close more than we have
   lotToClose = MathMin(lotToClose, positionVolume);

   // Check if there's enough volume to close
   if (lotToClose < minLot || lotToClose > positionVolume) {
      Print("Invalid lot size to close: ", lotToClose,
            " (min: ", minLot, ", position volume: ", positionVolume, ")");
      return false;
   }

   // Close the partial position
   bool success = trade.PositionClosePartial(ticket, lotToClose);
   if (success) {
      string actionType = PositionGetDouble(POSITION_PROFIT) >= 0 ? "profit" : "loss";
      Print("Partial ", actionType, " taken: Closed ",
            DoubleToString(lotToClose, 2), " lots (",
            DoubleToString(percent * 100, 0), "% of position)");
   } else {
      Print("Failed to take partial position. Error: ", GetLastError());
   }

   return success;
}
