//+------------------------------------------------------------------+
//|                                             TurnaroundTuesdayEA.mq5 |
//|                         Turnaround Tuesday Research EA - MT5       |
//|                         Educational / Backtest Version            |
//+------------------------------------------------------------------+
#property copyright "Research EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUT PARAMETERS
//====================================================================

//--- General
input ulong   MagicNumber              = 20260908;
input bool    AllowBuy                 = true;
input bool    AllowSell                = false;

//--- Position sizing
enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,
   LOT_RISK_PERCENT = 1
};

input ENUM_LOT_MODE LotMode             = LOT_FIXED;
input double        FixedLot            = 0.10;
input double        RiskPercent         = 1.0;

//--- Turnaround Tuesday setup
input double MondayDropPercent         = 0.30;
input bool   UseMondayRangeFilter      = false;
input double MinimumMondayRangePercent = 0.50;

//--- Entry time
input int EntryHour                    = 9;
input int EntryMinute                  = 0;

//--- Exit time
input bool UseTimeExit                 = true;
input int ExitHour                     = 16;
input int ExitMinute                   = 0;

//--- EMA filter
input bool UseEMAFilter                = false;
input int  EMAPeriod                   = 50;

//--- ATR stop/target
input bool   UseATRStops               = true;
input int    ATRPeriod                 = 14;
input double ATR_SL_Multiplier         = 1.50;
input double ATR_TP_Multiplier         = 2.00;

//--- Fixed SL/TP
input int FixedStopLossPoints          = 1000;
input int FixedTakeProfitPoints        = 2000;

//--- Trading filters
input int MaxSpreadPoints              = 100;
input bool OneTradePerTuesday          = true;

//--- Optional Friday/Monday gap filter
input bool UseGapFilter                = false;
input double MaxMondayGapPercent       = 2.0;


//====================================================================
// GLOBAL VARIABLES
//====================================================================

int      emaHandle = INVALID_HANDLE;
int      atrHandle = INVALID_HANDLE;

datetime lastProcessedTuesday = 0;


//====================================================================
// INITIALIZATION
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   //--- EMA
   if(UseEMAFilter)
   {
      emaHandle = iMA(
         _Symbol,
         PERIOD_D1,
         EMAPeriod,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

      if(emaHandle == INVALID_HANDLE)
      {
         Print("Failed to create EMA handle");
         return INIT_FAILED;
      }
   }

   //--- ATR
   if(UseATRStops)
   {
      atrHandle = iATR(
         _Symbol,
         PERIOD_D1,
         ATRPeriod
      );

      if(atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle");
         return INIT_FAILED;
      }
   }

   Print("Turnaround Tuesday EA initialized.");
   Print("Symbol: ", _Symbol);
   Print("Magic Number: ", MagicNumber);

   return INIT_SUCCEEDED;
}


//====================================================================
// DEINITIALIZATION
//====================================================================

void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);

   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}


//====================================================================
// MAIN TICK
//====================================================================

void OnTick()
{
   datetime currentTime = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(currentTime, dt);

   //--- Manage existing position
   ManageOpenPosition();

   //--- Only Tuesday
   //   MQL5:
   //   Sunday = 0
   //   Monday = 1
   //   Tuesday = 2
   if(dt.day_of_week != 2)
      return;

   //--- Check entry time
   if(dt.hour != EntryHour || dt.min != EntryMinute)
      return;

   //--- Prevent multiple execution during same minute
   datetime todayStart = StringToTime(
      StringFormat(
         "%04d.%02d.%02d 00:00",
         dt.year,
         dt.mon,
         dt.day
      )
   );

   if(lastProcessedTuesday == todayStart)
      return;

   lastProcessedTuesday = todayStart;

   //--- Spread filter
   if(!CheckSpread())
   {
      Print("Spread too high. Entry skipped.");
      return;
   }

   //--- Existing position?
   if(HasOpenPosition())
   {
      Print("Existing position found. No new trade.");
      return;
   }

   //--- One trade per Tuesday
   if(OneTradePerTuesday && HasTradedThisTuesday())
   {
      Print("Already traded this Tuesday.");
      return;
   }

   //--- Check strategy
   if(!CheckTurnaroundTuesday())
   {
      Print("Turnaround Tuesday conditions not satisfied.");
      return;
   }

   //--- BUY
   if(AllowBuy)
   {
      OpenBuy();
   }
}


//====================================================================
// TURNAROUND TUESDAY LOGIC
//====================================================================

bool CheckTurnaroundTuesday()
{
   // Monday daily candle
   double mondayOpen  = iOpen(_Symbol, PERIOD_D1, 1);
   double mondayClose = iClose(_Symbol, PERIOD_D1, 1);
   double mondayHigh  = iHigh(_Symbol, PERIOD_D1, 1);
   double mondayLow   = iLow(_Symbol, PERIOD_D1, 1);

   if(mondayOpen <= 0 || mondayClose <= 0)
      return false;

   //--- Monday return
   double mondayReturn =
      ((mondayClose - mondayOpen) / mondayOpen) * 100.0;

   Print(
      "Monday Open = ", mondayOpen,
      " | Monday Close = ", mondayClose,
      " | Monday Return = ", mondayReturn, "%"
   );

   //--- Basic turnaround condition
   // Monday must be negative
   if(mondayReturn > -MondayDropPercent)
      return false;

   //--- Optional Monday range filter
   if(UseMondayRangeFilter)
   {
      double mondayRange =
         ((mondayHigh - mondayLow) / mondayOpen) * 100.0;

      if(mondayRange < MinimumMondayRangePercent)
         return false;
   }

   //--- Optional EMA filter
   if(UseEMAFilter)
   {
      double emaBuffer[];

      ArraySetAsSeries(emaBuffer, true);

      if(CopyBuffer(
         emaHandle,
         0,
         1,
         1,
         emaBuffer
      ) <= 0)
      {
         Print("Unable to read EMA.");
         return false;
      }

      double ema = emaBuffer[0];

      if(mondayClose < ema)
      {
         Print(
            "EMA filter failed. Monday close = ",
            mondayClose,
            " EMA = ",
            ema
         );

         return false;
      }
   }

   //--- Optional gap filter
   if(UseGapFilter)
   {
      double fridayClose = iClose(_Symbol, PERIOD_D1, 2);

      if(fridayClose > 0)
      {
         double gap =
            ((mondayOpen - fridayClose) / fridayClose) * 100.0;

         if(MathAbs(gap) > MaxMondayGapPercent)
         {
            Print("Gap filter failed. Gap = ", gap, "%");
            return false;
         }
      }
   }

   return true;
}


//====================================================================
// OPEN BUY
//====================================================================

void OpenBuy()
{
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   if(ask <= 0)
      return;

   double sl = 0;
   double tp = 0;

   //--- ATR based SL / TP
   if(UseATRStops)
   {
      double atrBuffer[];

      ArraySetAsSeries(atrBuffer, true);

      if(CopyBuffer(
         atrHandle,
         0,
         1,
         1,
         atrBuffer
      ) <= 0)
      {
         Print("Unable to read ATR.");
         return;
      }

      double atr = atrBuffer[0];

      sl = ask - (atr * ATR_SL_Multiplier);
      tp = ask + (atr * ATR_TP_Multiplier);
   }
   else
   {
      sl = ask - FixedStopLossPoints * _Point;
      tp = ask + FixedTakeProfitPoints * _Point;
   }

   //--- Normalize prices
   sl = NormalizeDouble(
      sl,
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      )
   );

   tp = NormalizeDouble(
      tp,
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      )
   );

   //--- Calculate lot
   double lot = CalculateLot(sl);

   if(lot <= 0)
   {
      Print("Invalid lot size.");
      return;
   }

   //--- Open trade
   bool result = trade.Buy(
      lot,
      _Symbol,
      0,
      sl,
      tp,
      "Turnaround Tuesday BUY"
   );

   if(result)
   {
      Print(
         "BUY opened successfully. ",
         "Lot=", lot,
         " SL=", sl,
         " TP=", tp
      );
   }
   else
   {
      Print(
         "BUY failed. Retcode=",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//====================================================================
// LOT CALCULATION
//====================================================================

double CalculateLot(double stopLossPrice)
{
   if(LotMode == LOT_FIXED)
      return NormalizeLot(FixedLot);

   //--- Risk based position sizing
   double balance = AccountInfoDouble(
      ACCOUNT_BALANCE
   );

   double riskMoney =
      balance * RiskPercent / 100.0;

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double stopDistance =
      MathAbs(ask - stopLossPrice);

   if(stopDistance <= 0)
      return 0;

   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE
      );

   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE
      );

   if(tickSize <= 0 || tickValue <= 0)
      return 0;

   double moneyPerLot =
      (stopDistance / tickSize) * tickValue;

   if(moneyPerLot <= 0)
      return 0;

   double lot =
      riskMoney / moneyPerLot;

   return NormalizeLot(lot);
}


//====================================================================
// NORMALIZE LOT
//====================================================================

double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   if(step <= 0)
      return 0;

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   lot = MathFloor(lot / step) * step;

   return NormalizeDouble(lot, 2);
}


//====================================================================
// SPREAD CHECK
//====================================================================

bool CheckSpread()
{
   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   if(ask <= 0 || bid <= 0)
      return false;

   double spreadPoints =
      (ask - bid) / _Point;

   Print("Current spread = ", spreadPoints, " points");

   if(spreadPoints > MaxSpreadPoints)
      return false;

   return true;
}


//====================================================================
// CHECK OPEN POSITION
//====================================================================

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      if(symbol == _Symbol &&
         magic == (long)MagicNumber)
      {
         return true;
      }
   }

   return false;
}


//====================================================================
// TIME EXIT
//====================================================================

void ManageOpenPosition()
{
   if(!UseTimeExit)
      return;

   if(!HasOpenPosition())
      return;

   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   //--- Only close on Tuesday
   if(dt.day_of_week != 2)
      return;

   //--- Close at/after exit time
   if(dt.hour > ExitHour ||
      (dt.hour == ExitHour && dt.min >= ExitMinute))
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket =
            PositionGetTicket(i);

         if(ticket == 0)
            continue;

         if(!PositionSelectByTicket(ticket))
            continue;

         string symbol =
            PositionGetString(
               POSITION_SYMBOL
            );

         long magic =
            PositionGetInteger(
               POSITION_MAGIC
            );

         if(symbol == _Symbol &&
            magic == (long)MagicNumber)
         {
            if(trade.PositionClose(ticket))
            {
               Print(
                  "Position closed by time exit. Ticket=",
                  ticket
               );
            }
            else
            {
               Print(
                  "Failed to close position. Ticket=",
                  ticket,
                  " Error=",
                  trade.ResultRetcodeDescription()
               );
            }
         }
      }
   }
}


//====================================================================
// CHECK WHETHER ALREADY TRADED THIS TUESDAY
//====================================================================

bool HasTradedThisTuesday()
{
   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   //--- Find start of current Tuesday
   datetime dayStart =
      StringToTime(
         StringFormat(
            "%04d.%02d.%02d 00:00",
            dt.year,
            dt.mon,
            dt.day
         )
      );

   //--- History until now
   if(!HistorySelect(dayStart, now))
      return false;

   int total =
      HistoryDealsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);

      if(dealTicket == 0)
         continue;

      string symbol =
         HistoryDealGetString(
            dealTicket,
            DEAL_SYMBOL
         );

      long magic =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_MAGIC
         );

      long entry =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_ENTRY
         );

      if(symbol == _Symbol &&
         magic == (long)MagicNumber &&
         entry == DEAL_ENTRY_IN)
      {
         return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
