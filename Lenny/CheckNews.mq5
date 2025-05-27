//+------------------------------------------------------------------+
//|                                                  CheckNews.mq5   |
//|                                                  Copyright 2025  |
//|                                     https://www.yourwebsite.com  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

input int InpCheckIntervalMinutes = 30;    // Check interval in minutes
input int InpHoursAhead = 24;              // Hours ahead to check for news

#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayString.mqh>
#include <Helpers\TextDisplay.mqh>

MqlCalendarCountry countries[];
MqlCalendarValue newsValues[];
MqlCalendarEvent newsEvents[];
ulong eventIds[];
datetime lastCheck = 0;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    EventSetTimer(5);
    clearTextDisplay();
    LoadCountriesData();
    CheckHighImpactNews();
    Print("CheckNews initialized successfully");
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

    if(TimeCurrent() - lastCheck >= InpCheckIntervalMinutes * 60) {
        CheckHighImpactNews();
        lastCheck = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Functions to check for news events                               |
//+------------------------------------------------------------------+
bool LoadCountriesData() {
    int total = CalendarCountries(countries);
    if(total <= 0) {
        Print("Failed to load calendar countries");
        return false;
    }

    Print("Loaded ", total, " countries");
    return true;
}

ulong GetUSCountryId() {
    for(int i = 0; i < ArraySize(countries); i++) {
        if(countries[i].code == "US" || countries[i].code == "USD") {
            return countries[i].id;
        }
    }
    return 0;
}

void CheckHighImpactNews() {
    datetime timeFrom = TimeCurrent();
    datetime timeTo = timeFrom + InpHoursAhead * 3600; // Check next 24 hours

    ulong countryId = GetUSCountryId();
    if(countryId == 0) {
        Print("US country not found in calendar");
        return;
    }

    int totalValues = CalendarValueHistory(newsValues, timeFrom, timeTo, countryId);
    if(totalValues <= 0) {
        Print("No news events found for the next 24 hours");
        return;
    }

    ArrayResize(eventIds, totalValues);

    for(int i = 0; i < totalValues; i++) {
        eventIds[i] = newsValues[i].event_id;
    }

    // Remove duplicates
    int uniqueCount = RemoveDuplicateIds(eventIds);
    ArrayResize(eventIds, uniqueCount);

    int totalEvents = CalendarEventById(newsEvents, eventIds);
    if(totalEvents <= 0) {
        Print("Failed to get event details");
        return;
    }

    ProcessHighImpactEvents(newsEvents, newsValues);
}

int RemoveDuplicateIds(ulong &ids[]) {
    int size = ArraySize(ids);
    if(size <= 1) return size;

    ulong temp[];
    ArrayResize(temp, size);
    int count = 0;

    for(int i = 0; i < size; i++) {
        bool found = false;
        for(int j = 0; j < count; j++) {
            if(temp[j] == ids[i]) {
                found = true;
                break;
            }
        }
        if(!found) {
            temp[count] = ids[i];
            count++;
        }
    }

    ArrayResize(ids, count);
    for(int i = 0; i < count; i++) {
        ids[i] = temp[i];
    }

    return count;
}

void ProcessHighImpactEvents(const MqlCalendarEvent &events[], const MqlCalendarValue &values[]) {
    int highImpactCount = 0;

    for(int i = 0; i < ArraySize(events); i++) {
        if(events[i].importance == CALENDAR_IMPORTANCE_HIGH) {
            highImpactCount++;

            MqlCalendarValue eventValue;
            bool foundValue = false;

            for(int j = 0; j < ArraySize(values); j++) {
                if(values[j].event_id == events[i].id) {
                    eventValue = values[j];
                    foundValue = true;
                    break;
                }
            }

            if(foundValue) {
                ProcessSingleHighImpactEvent(events[i], eventValue);
            }
        }
    }

    if(highImpactCount == 0) {
        Print("No high impact US news events found for the next 24 hours");
    } else {
        Print("Found ", highImpactCount, " high impact US news events");
    }
}

void ProcessSingleHighImpactEvent(const MqlCalendarEvent &event, const MqlCalendarValue &value) {
    string eventTime = TimeToString(value.time, TIME_DATE|TIME_MINUTES);
    string message = StringFormat("HIGH IMPACT NEWS: %s at %s", event.name, eventTime);

    Print(message);
    Print("  Event ID: ", event.id);
    Print("  Sector: ", EnumToString(event.sector));
    Print("  Frequency: ", EnumToString(event.frequency));
    Print("  Time until event: ", (value.time - TimeCurrent()) / 60, " minutes");

    // Here you can add your trading logic
    HandleHighImpactNews(event, value);
}

void HandleHighImpactNews(const MqlCalendarEvent &event, const MqlCalendarValue &value) {
    // Calculate time until news event
    long secondsUntilNews = value.time - TimeCurrent();
    long minutesUntilNews = secondsUntilNews / 60;

    // Example logic: warn if news is within next 30 minutes
    if(minutesUntilNews <= 30 && minutesUntilNews > 0) {
        string warning = StringFormat("WARNING: High impact news '%s' in %d minutes!",
                                    event.name, minutesUntilNews);
        Print(warning);

        // Add your specific actions here:
        // - Close open positions
        // - Cancel pending orders
        // - Set trading pause flag
        // - Send notifications
    }

    // Example: if news is happening now (within 5 minutes)
    if(MathAbs(minutesUntilNews) <= 5) {
        string alert = StringFormat("NEWS ALERT: '%s' is happening NOW!", event.name);
        Print(alert);

        // Add immediate actions here:
        // - Pause all trading
        // - Emergency position management
    }
}

//+------------------------------------------------------------------+
