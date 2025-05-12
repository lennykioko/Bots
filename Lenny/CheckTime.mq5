//+------------------------------------------------------------------+
//|                                                  CheckTime.mq5   |
//|                                                  Copyright 2025  |
//|                                     https://www.yourwebsite.com  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Cleanup code if needed
    Print("Expert deinitialized.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
    datetime currentTime = TimeCurrent();
    string timeStr = TimeToString(currentTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    Print("Current time: ", timeStr);
}
