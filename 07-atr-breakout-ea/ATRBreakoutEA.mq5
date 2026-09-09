//+------------------------------------------------------------------+
//|                                              ATR_Breakout_EA.mq5 |
//|                    ATR + Donchian Style Breakout Strategy         |
//|                    Research / Optimization Version               |
//+------------------------------------------------------------------+
#property copyright "Research EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;


//====================================================================
// ENUMS
//====================================================================

enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,
   LOT_RISK_PERCENT = 1
};

enum ENUM_SL_MODE
{
   SL_FIXED = 0,
   SL_ATR = 1,
   SL_BREAKOUT = 2
};

enum ENUM_TP_MODE
{
   TP_FIXED = 0,
   TP_ATR = 1,
   TP_RR = 2
};


//====================================================================
// GENERAL SETTINGS
//====================================================================

input ulong MagicNumber = 20260911;

input bool AllowBuy  = true;
input bool AllowSell = true;

input bool OnePositionOnly = true;

input bool UseNewBarOnly = true;


//====================================================================
// BREAKOUT SETTINGS
//====================================================================

// Number of completed candles used to determine breakout range
input int BreakoutLookback = 20;

// Additional breakout buffer in points
input int BreakoutBufferPoints = 10;

// Use candle close for confirmation
// true  = previous candle must close beyond breakout
// false = high/low penetration is enough
input bool RequireCloseBreakout = true;


//====================================================================
// ATR SETTINGS
//====================================================================

input int ATRPeriod = 14;

// ATR used as minimum volatility filter
input bool UseATRVolatilityFilter = false;

// Current ATR must be greater than
// Average ATR * multiplier
input double ATRFilterMultiplier = 1.0;

input int ATRAveragePeriod = 20;


//====================================================================
// STOP LOSS
//====================================================================

input ENUM_SL_MODE StopLossMode = SL_ATR;

input int FixedStopLossPoints = 1500;

input double ATR_SL_Multiplier = 2.0;


//====================================================================
// TAKE PROFIT
//====================================================================

input ENUM_TP_MODE TakeProfitMode = TP_RR;

input int FixedTakeProfitPoints = 3000;

input double ATR_TP_Multiplier = 3.0;

input double RiskRewardRatio = 2.0;


//====================================================================
// POSITION SIZING
//====================================================================

input ENUM_LOT_MODE LotMode = LOT_FIXED;

input double FixedLot = 0.10;

input double RiskPercent = 1.0;


//====================================================================
// TRAILING STOP
//====================================================================

input bool UseTrailingStop = false;

input double ATR_TrailingMultiplier = 2.0;

input int FixedTrailingPoints = 1000;

input bool TrailingUseATR = true;


//====================================================================
// SPREAD FILTER
//====================================================================

input bool UseSpreadFilter = true;

input int MaxSpreadPoints = 100;


//====================================================================
// TRADING SESSION
//====================================================================

input bool UseTradingSession = false;

input int StartHour = 8;

input int StartMinute = 0;

input int EndHour = 20;

input int EndMinute = 0;


//====================================================================
// GLOBAL VARIABLES
//====================================================================

int atrHandle = INVALID_HANDLE;

datetime lastBarTime = 0;


//====================================================================
// INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   trade.SetDeviationInPoints(20);


   //==============================================================
   // ATR
   //==============================================================

   atrHandle = iATR(
      _Symbol,
      _Period,
      ATRPeriod
   );


   if(atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle.");
      return INIT_FAILED;
   }


   Print("==========================================");
   Print("ATR Breakout EA initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Breakout Lookback: ", BreakoutLookback);
   Print("ATR Period: ", ATRPeriod);
   Print("==========================================");


   return INIT_SUCCEEDED;
}


//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}


//====================================================================
// ON TICK
//====================================================================

void OnTick()
{
   //--- Manage existing position
   ManageTrailingStop();


   //--- New bar
   if(UseNewBarOnly)
   {
      if(!IsNewBar())
         return;
   }


   //--- Session filter
   if(UseTradingSession)
   {
      if(!IsTradingTime())
         return;
   }


   //--- Spread filter
   if(UseSpreadFilter)
   {
      if(!CheckSpread())
         return;
   }


   //--- Existing position
   if(OnePositionOnly && HasOpenPosition())
      return;


   //--- Make sure enough bars exist
   if(Bars(_Symbol, _Period) <
      BreakoutLookback + ATRAveragePeriod + 10)
   {
      return;
   }


   //==============================================================
   // GET ATR
   //==============================================================

   double atr[];

   ArraySetAsSeries(
      atr,
      true
   );


   int atrNeeded =
      ATRAveragePeriod + 5;


   if(CopyBuffer(
      atrHandle,
      0,
      0,
      atrNeeded,
      atr
   ) < atrNeeded)
   {
      return;
   }


   double currentATR =
      atr[1];


   if(currentATR <= 0)
      return;


   //==============================================================
   // ATR VOLATILITY FILTER
   //==============================================================

   if(UseATRVolatilityFilter)
   {
      double averageATR = 0.0;


      for(
         int i = 1;
         i <= ATRAveragePeriod;
         i++
      )
      {
         averageATR += atr[i];
      }


      averageATR /=
         ATRAveragePeriod;


      if(
         currentATR <
         averageATR *
         ATRFilterMultiplier
      )
      {
         Print(
            "ATR volatility filter failed. ",
            "Current ATR=",
            currentATR,
            " Average ATR=",
            averageATR
         );

         return;
      }
   }


   //==============================================================
   // FIND BREAKOUT LEVELS
   //==============================================================

   double highestHigh =
      GetHighestHigh(
         BreakoutLookback
      );


   double lowestLow =
      GetLowestLow(
         BreakoutLookback
      );


   if(
      highestHigh <= 0 ||
      lowestLow <= 0
   )
   {
      return;
   }


   double buyBreakoutLevel =
      highestHigh +
      BreakoutBufferPoints *
      _Point;


   double sellBreakoutLevel =
      lowestLow -
      BreakoutBufferPoints *
      _Point;


   //==============================================================
   // PREVIOUS CANDLE
   //==============================================================

   double previousClose =
      iClose(
         _Symbol,
         _Period,
         1
      );


   double previousHigh =
      iHigh(
         _Symbol,
         _Period,
         1
      );


   double previousLow =
      iLow(
         _Symbol,
         _Period,
         1
      );


   //==============================================================
   // BUY BREAKOUT
   //==============================================================

   bool buySignal = false;


   if(RequireCloseBreakout)
   {
      buySignal =
         previousClose >
         buyBreakoutLevel;
   }
   else
   {
      buySignal =
         previousHigh >
         buyBreakoutLevel;
   }


   //==============================================================
   // SELL BREAKOUT
   //==============================================================

   bool sellSignal = false;


   if(RequireCloseBreakout)
   {
      sellSignal =
         previousClose <
         sellBreakoutLevel;
   }
   else
   {
      sellSignal =
         previousLow <
         sellBreakoutLevel;
   }


   //==============================================================
   // EXECUTION
   //==============================================================

   if(
      buySignal &&
      AllowBuy
   )
   {
      Print(
         "BUY BREAKOUT SIGNAL | ",
         "Level=",
         buyBreakoutLevel,
         " Close=",
         previousClose,
         " ATR=",
         currentATR
      );

      OpenBuy(
         currentATR,
         lowestLow
      );
   }


   if(
      sellSignal &&
      AllowSell
   )
   {
      Print(
         "SELL BREAKOUT SIGNAL | ",
         "Level=",
         sellBreakoutLevel,
         " Close=",
         previousClose,
         " ATR=",
         currentATR
      );

      OpenSell(
         currentATR,
         highestHigh
      );
   }
}


//====================================================================
// GET HIGHEST HIGH
//====================================================================

double GetHighestHigh(int lookback)
{
   double highest = 0.0;


   for(
      int i = 2;
      i < lookback + 2;
      i++
   )
   {
      double high =
         iHigh(
            _Symbol,
            _Period,
            i
         );


      if(
         high > highest
      )
      {
         highest = high;
      }
   }


   return highest;
}


//====================================================================
// GET LOWEST LOW
//====================================================================

double GetLowestLow(int lookback)
{
   double lowest =
      DBL_MAX;


   for(
      int i = 2;
      i < lookback + 2;
      i++
   )
   {
      double low =
         iLow(
            _Symbol,
            _Period,
            i
         );


      if(
         low < lowest
      )
      {
         lowest = low;
      }
   }


   if(lowest == DBL_MAX)
      return 0;


   return lowest;
}


//====================================================================
// OPEN BUY
//====================================================================

void OpenBuy(
   double atr,
   double breakoutLow
)
{
   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );


   if(ask <= 0)
      return;


   double sl = 0.0;

   double tp = 0.0;


   //==============================================================
   // STOP LOSS
   //==============================================================

   if(
      StopLossMode ==
      SL_FIXED
   )
   {
      sl =
         ask -
         FixedStopLossPoints *
         _Point;
   }


   else if(
      StopLossMode ==
      SL_ATR
   )
   {
      sl =
         ask -
         atr *
         ATR_SL_Multiplier;
   }


   else if(
      StopLossMode ==
      SL_BREAKOUT
   )
   {
      sl =
         breakoutLow -
         BreakoutBufferPoints *
         _Point;
   }


   //==============================================================
   // TAKE PROFIT
   //==============================================================

   if(
      TakeProfitMode ==
      TP_FIXED
   )
   {
      tp =
         ask +
         FixedTakeProfitPoints *
         _Point;
   }


   else if(
      TakeProfitMode ==
      TP_ATR
   )
   {
      tp =
         ask +
         atr *
         ATR_TP_Multiplier;
   }


   else if(
      TakeProfitMode ==
      TP_RR
   )
   {
      double risk =
         ask - sl;


      if(risk <= 0)
         return;


      tp =
         ask +
         risk *
         RiskRewardRatio;
   }


   sl =
      NormalizePrice(sl);


   tp =
      NormalizePrice(tp);


   //==============================================================
   // LOT SIZE
   //==============================================================

   double lot =
      CalculateLot(
         ask,
         sl
      );


   if(lot <= 0)
      return;


   //==============================================================
   // OPEN
   //==============================================================

   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "ATR Breakout BUY"
      );


   if(result)
   {
      Print(
         "BUY OPENED | ",
         "Lot=",
         lot,
         " SL=",
         sl,
         " TP=",
         tp
      );
   }
   else
   {
      Print(
         "BUY FAILED | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//====================================================================
// OPEN SELL
//====================================================================

void OpenSell(
   double atr,
   double breakoutHigh
)
{
   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );


   if(bid <= 0)
      return;


   double sl = 0.0;

   double tp = 0.0;


   //==============================================================
   // STOP LOSS
   //==============================================================

   if(
      StopLossMode ==
      SL_FIXED
   )
   {
      sl =
         bid +
         FixedStopLossPoints *
         _Point;
   }


   else if(
      StopLossMode ==
      SL_ATR
   )
   {
      sl =
         bid +
         atr *
         ATR_SL_Multiplier;
   }


   else if(
      StopLossMode ==
      SL_BREAKOUT
   )
   {
      sl =
         breakoutHigh +
         BreakoutBufferPoints *
         _Point;
   }


   //==============================================================
   // TAKE PROFIT
   //==============================================================

   if(
      TakeProfitMode ==
      TP_FIXED
   )
   {
      tp =
         bid -
         FixedTakeProfitPoints *
         _Point;
   }


   else if(
      TakeProfitMode ==
      TP_ATR
   )
   {
      tp =
         bid -
         atr *
         ATR_TP_Multiplier;
   }


   else if(
      TakeProfitMode ==
      TP_RR
   )
   {
      double risk =
         sl - bid;


      if(risk <= 0)
         return;


      tp =
         bid -
         risk *
         RiskRewardRatio;
   }


   sl =
      NormalizePrice(sl);


   tp =
      NormalizePrice(tp);


   //==============================================================
   // LOT
   //==============================================================

   double lot =
      CalculateLot(
         bid,
         sl
      );


   if(lot <= 0)
      return;


   //==============================================================
   // OPEN
   //==============================================================

   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "ATR Breakout SELL"
      );


   if(result)
   {
      Print(
         "SELL OPENED | ",
         "Lot=",
         lot,
         " SL=",
         sl,
         " TP=",
         tp
      );
   }
   else
   {
      Print(
         "SELL FAILED | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//====================================================================
// CALCULATE LOT
//====================================================================

double CalculateLot(
   double entryPrice,
   double stopLossPrice
)
{
   if(
      LotMode ==
      LOT_FIXED
   )
   {
      return NormalizeLot(
         FixedLot
      );
   }


   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );


   double riskMoney =
      balance *
      RiskPercent /
      100.0;


   double stopDistance =
      MathAbs(
         entryPrice -
         stopLossPrice
      );


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


   if(
      tickSize <= 0 ||
      tickValue <= 0
   )
   {
      return 0;
   }


   double moneyPerLot =
      (
         stopDistance /
         tickSize
      ) *
      tickValue;


   if(moneyPerLot <= 0)
      return 0;


   double lot =
      riskMoney /
      moneyPerLot;


   return NormalizeLot(
      lot
   );
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


   lot =
      MathMax(
         lot,
         minLot
      );


   lot =
      MathMin(
         lot,
         maxLot
      );


   lot =
      MathFloor(
         lot /
         step
      ) *
      step;


   return NormalizeDouble(
      lot,
      2
   );
}


//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(
   double price
)
{
   int digits =
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS
      );


   return NormalizeDouble(
      price,
      digits
   );
}


//====================================================================
// CHECK SPREAD
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


   if(
      ask <= 0 ||
      bid <= 0
   )
   {
      return false;
   }


   double spread =
      (ask - bid) /
      _Point;


   if(
      spread >
      MaxSpreadPoints
   )
   {
      Print(
         "Spread too high: ",
         spread,
         " points"
      );


      return false;
   }


   return true;
}


//====================================================================
// POSITION CHECK
//====================================================================

bool HasOpenPosition()
{
   for(
      int i = PositionsTotal() - 1;
      i >= 0;
      i--
   )
   {
      ulong ticket =
         PositionGetTicket(i);


      if(ticket == 0)
         continue;


      if(
         !PositionSelectByTicket(
            ticket
         )
      )
      {
         continue;
      }


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );


      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );


      if(
         symbol == _Symbol &&
         magic ==
         (long)MagicNumber
      )
      {
         return true;
      }
   }


   return false;
}


//====================================================================
// NEW BAR
//====================================================================

bool IsNewBar()
{
   datetime currentBar =
      iTime(
         _Symbol,
         _Period,
         0
      );


   if(
      currentBar !=
      lastBarTime
   )
   {
      lastBarTime =
         currentBar;

      return true;
   }


   return false;
}


//====================================================================
// TRADING SESSION
//====================================================================

bool IsTradingTime()
{
   MqlDateTime dt;

   TimeToStruct(
      TimeCurrent(),
      dt
   );


   int currentMinutes =
      dt.hour * 60 +
      dt.min;


   int startMinutes =
      StartHour * 60 +
      StartMinute;


   int endMinutes =
      EndHour * 60 +
      EndMinute;


   if(
      currentMinutes <
      startMinutes
   )
   {
      return false;
   }


   if(
      currentMinutes >
      endMinutes
   )
   {
      return false;
   }


   return true;
}


//====================================================================
// TRAILING STOP
//====================================================================

void ManageTrailingStop()
{
   if(!UseTrailingStop)
      return;


   if(!HasOpenPosition())
      return;


   double atrValue = 0.0;


   //==============================================================
   // GET ATR
   //==============================================================

   if(TrailingUseATR)
   {
      double atr[];

      ArraySetAsSeries(
         atr,
         true
      );


      if(
         CopyBuffer(
            atrHandle,
            0,
            0,
            2,
            atr
         ) < 2
      )
      {
         return;
      }


      atrValue =
         atr[0];
   }


   //==============================================================
   // POSITIONS
   //==============================================================

   for(
      int i = PositionsTotal() - 1;
      i >= 0;
      i--
   )
   {
      ulong ticket =
         PositionGetTicket(i);


      if(ticket == 0)
         continue;


      if(
         !PositionSelectByTicket(
            ticket
         )
      )
      {
         continue;
      }


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );


      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );


      if(
         symbol != _Symbol ||
         magic !=
         (long)MagicNumber
      )
      {
         continue;
      }


      long type =
         PositionGetInteger(
            POSITION_TYPE
         );


      double currentSL =
         PositionGetDouble(
            POSITION_SL
         );


      double currentTP =
         PositionGetDouble(
            POSITION_TP
         );


      //===========================================================
      // BUY
      //===========================================================

      if(
         type ==
         POSITION_TYPE_BUY
      )
      {
         double bid =
            SymbolInfoDouble(
               _Symbol,
               SYMBOL_BID
            );


         double distance;


         if(TrailingUseATR)
         {
            distance =
               atrValue *
               ATR_TrailingMultiplier;
         }
         else
         {
            distance =
               FixedTrailingPoints *
               _Point;
         }


         double newSL =
            bid -
            distance;


         newSL =
            NormalizePrice(
               newSL
            );


         if(
            currentSL == 0 ||
            newSL >
            currentSL
         )
         {
            if(newSL < bid)
            {
               trade.PositionModify(
                  ticket,
                  newSL,
                  currentTP
               );
            }
         }
      }


      //===========================================================
      // SELL
      //===========================================================

      if(
         type ==
         POSITION_TYPE_SELL
      )
      {
         double ask =
            SymbolInfoDouble(
               _Symbol,
               SYMBOL_ASK
            );


         double distance;


         if(TrailingUseATR)
         {
            distance =
               atrValue *
               ATR_TrailingMultiplier;
         }
         else
         {
            distance =
               FixedTrailingPoints *
               _Point;
         }


         double newSL =
            ask +
            distance;


         newSL =
            NormalizePrice(
               newSL
            );


         if(
            currentSL == 0 ||
            newSL <
            currentSL
         )
         {
            if(newSL > ask)
            {
               trade.PositionModify(
                  ticket,
                  newSL,
                  currentTP
               );
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
