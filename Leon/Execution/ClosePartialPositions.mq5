//+------------------------------------------------------------------+
//|                                           ClosePartialPositions.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Trade/Trade.mqh>

// Input parameters
input double CloseRatio = 0.5;        // Ratio to close (1.0 = full position)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    CTrade trade;

    // Check if ratio is valid
    if(CloseRatio <= 0 || CloseRatio > 1) {
        MessageBox("Close ratio must be between 0 and 1", "Invalid Input");
        return;
    }

    // Iterate through all positions
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);

        if(ticket <= 0) continue;

        // Only process positions for current symbol
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        // Get position volume
        double positionVolume = PositionGetDouble(POSITION_VOLUME);

        // Calculate volume to close based on ratio
        double volumeToClose = NormalizeDouble(positionVolume * CloseRatio, 2);

        // If closing full position or remaining would be too small, close everything
        if(CloseRatio >= 1.0 || (positionVolume - volumeToClose) < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
            if(trade.PositionClose(ticket)) {
                Print("Closed full position ", ticket, " (", positionVolume, " lots)");
            } else {
                Print("Failed to close position ", ticket, ". Error: ", GetLastError());
            }
        }
        // Close partial position
        else if(volumeToClose > 0) {
            if(trade.PositionClosePartial(ticket, volumeToClose)) {
                Print("Closed partial position ", ticket, " (", volumeToClose, " of ", positionVolume, " lots)");
            } else {
                Print("Failed to close partial position ", ticket, ". Error: ", GetLastError());
            }
        }
    }
}
//+------------------------------------------------------------------+