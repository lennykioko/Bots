//+------------------------------------------------------------------+
//|                                                  CheckNews.mq5   |
//|                                                  Copyright 2025  |
//|                                     https://www.yourwebsite.com  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

#include <Helpers\TextDisplay.mqh>


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    EventSetTimer(100);
    clearTextDisplay();
    Print("CheckNews initialized successfully");
    GetNewsByDUration();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Cleanup code if needed
    EventKillTimer();
    Print("CheckNews deinitialized.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTimer() {
    datetime currentTime = TimeCurrent();
    string timeStr = TimeToString(currentTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    Print("Current time: ", timeStr);
    clearTextDisplay();
    addTextOnScreen(timeStr, clrWhite);
    GetNewsByDUration();
}

//+------------------------------------------------------------------+
//| Functions to check for news events                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check for high-impact US news in next 24 hours                   |
//+------------------------------------------------------------------+
void GetAllNewsByCountry() {
    string code = "US";
    MqlCalendarEvent events[];
    int events_count = CalendarEventByCountry(code, events);
    if(events_count > 0) {
        Print("Total US events: " + IntegerToString(events_count));
        // ArrayPrint(events);
        for(int i = 0; i < events_count; i++) {
            if(events[i].importance == 3) {
                Print("ID: " + IntegerToString(events[i].id) +
                      " | Type: " + IntegerToString(events[i].type) +
                      " | Importance: " + IntegerToString(events[i].importance) +
                      " | Event: " + events[i].event_code);
            }
        }

    } else {
        Print("No US events found.");
    }
}

void GetNewsByDUration() {
    string code = "US";
    MqlCalendarValue values[];
    // datetime dateFrom = TimeCurrent();
    // datetime dateTo = dateFrom + 36 * 3600; // 36 hours ahead
    datetime dateFrom=D'01.05.2025';
    datetime dateTo=D'30.05.2025';

    if(CalendarValueHistory(values, dateFrom, dateTo, code)) {
        // ArrayPrint(values);
        for(int i = 0; i < ArraySize(values); i++) {
            string time = TimeToString(values[i].time, TIME_DATE|TIME_MINUTES);
            MqlCalendarEvent event;
            ulong eventId = values[i].event_id;

            if(CalendarEventById(eventId, event)) {
                // check if is CALENDAR_TYPE_HOLIDAY or CALENDAR_IMPORTANCE_HIGH
                if(event.importance == CALENDAR_IMPORTANCE_HIGH || event.type == CALENDAR_TYPE_HOLIDAY) {
                    Print("Time: " + time +
                        " | Event ID: " + IntegerToString(eventId) +
                        " | Name: " + event.name +
                        " | Importance: " + EnumToString((ENUM_CALENDAR_EVENT_IMPORTANCE)event.importance) +
                        " | Type: " + EnumToString((ENUM_CALENDAR_EVENT_TYPE)event.type));
                }
            } else {
                Print("Error retrieving event by ID: " + IntegerToString(GetLastError()));
            }
        }
    } else {
        Print("Error retrieving news values: " + IntegerToString(GetLastError()));
    }
}
bool isTradingAllowedByNews() {
    string code = "US";
    MqlCalendarValue values[];
    datetime currentTime = TimeCurrent();
    datetime tomorrow = currentTime + 24 * 3600; // Add 24 hours

    // Check events from now until tomorrow end of day
    datetime dateTo = tomorrow + 24 * 3600;

    if(CalendarValueHistory(values, currentTime, dateTo, code)) {
        for(int i = 0; i < ArraySize(values); i++) {
            MqlCalendarEvent event;
            ulong eventId = values[i].event_id;

            if(CalendarEventById(eventId, event)) {
                datetime eventTime = values[i].time;

                // Check for bank holidays today
                if(event.type == CALENDAR_TYPE_HOLIDAY &&
                   TimeToString(eventTime, TIME_DATE) == TimeToString(currentTime, TIME_DATE)) {
                    Print("Trading not allowed: Bank Holiday today");
                    return false;
                }

                // Check for NFP tomorrow
                if(event.name == "Nonfarm Payrolls" &&
                   TimeToString(eventTime, TIME_DATE) == TimeToString(tomorrow, TIME_DATE)) {
                    if(currentTime < eventTime) {
                        Print("Trading not allowed: NFP tomorrow");
                        return false;
                    }
                }

                // Check for CPI today
                if(StringFind(event.name, "CPI") >= 0 &&
                   TimeToString(eventTime, TIME_DATE) == TimeToString(currentTime, TIME_DATE)) {
                    if(currentTime < eventTime) {
                        Print("Trading not allowed: CPI today");
                        return false;
                    }
                }
            }
        }
    } else {
        Print("Error retrieving news values: " + IntegerToString(GetLastError()));
        return false; // If we can't check the news, better not to trade
    }

    return true; // No blocking news events found
}
//+------------------------------------------------------------------+
2025.05.27 13:45:41.126	CheckNews (NAS100,M5)	Time: 2025.05.02 15:30 | Event ID: 840030016 | Name: Nonfarm Payrolls | Importance: CALENDAR_IMPORTANCE_HIGH | Type: CALENDAR_TYPE_INDICATOR
2025.05.27 13:45:41.126	CheckNews (NAS100,M5)	Time: 2025.05.13 15:30 | Event ID: 840030006 | Name: Core CPI m/m | Importance: CALENDAR_IMPORTANCE_HIGH | Type: CALENDAR_TYPE_INDICATOR

