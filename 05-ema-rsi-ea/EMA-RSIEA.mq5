//+------------------------------------------------------------------+
//|                                             EMA_RSI_Trend_EA.mq5 |
//|                         EMA + RSI Trend Following Strategy        |
//|                         Research / Optimization Version          |
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

enum ENUM_SLTP_MODE
{
   SLTP_FIXED = 0,
   SLTP_ATR = 1
};


//====================================================================
// GENERAL SETTINGS
//====================================================================

input ulong MagicNumber = 20260909;

input bool AllowBuy  = true;
input bool AllowSell = true;


//====================================================================
// EMA SETTINGS
//====================================================================

input int FastEMAPeriod = 20;
input int SlowEMAPeriod = 50;

input ENUM_APPLIED_PRICE EMAPrice = PRICE_CLOSE;


//====================================================================
// RSI SETTINGS
//====================================================================

input int RSIPeriod = 14;

input double RSI_Buy_Level  = 50.0;
input double RSI_Sell_Level = 50.0;

input ENUM_APPLIED_PRICE RSIPrice = PRICE_CLOSE;


//====================================================================
// OPTIONAL RSI EXTREME FILTER
//====================================================================

input bool UseRSIExtremeFilter = false;

input double RSI_Max_Buy = 70.0;
input double RSI_Min_Sell = 30.0;


//====================================================================
// POSITION SIZING
//====================================================================

input ENUM_LOT_MODE LotMode = LOT_FIXED;

input double FixedLot = 0.10;

input double RiskPercent = 1.0;


//====================================================================
// STOP LOSS / TAKE PROFIT
//====================================================================

input ENUM_SLTP_MODE SLTPMode = SLTP_ATR;

//--- Fixed SL/TP
input int FixedStopLossPoints   = 1000;
input int FixedTakeProfitPoints = 2000;

//--- ATR
input int ATRPeriod = 14;

input double ATR_SL_Multiplier = 1.5;
input double ATR_TP_Multiplier = 3.0;


//====================================================================
// TRAILING STOP
//====================================================================

input bool UseTrailingStop = false;

input int TrailingStopPoints = 1000;

input int TrailingStepPoints = 100;


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
// SIGNAL SETTINGS
//====================================================================

input bool UseEMACrossEntry = false;

input bool UseNewBarOnly = true;


//====================================================================
// GLOBAL VARIABLES
//====================================================================

int fastEMAHandle = INVALID_HANDLE;
int slowEMAHandle = INVALID_HANDLE;
int rsiHandle     = INVALID_HANDLE;
int atrHandle     = INVALID_HANDLE;

datetime lastBarTime = 0;


//====================================================================
// INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   //--- Fast EMA
   fastEMAHandle = iMA(
      _Symbol,
      _Period,
      FastEMAPeriod,
      0,
      MODE_EMA,
      EMAPrice
   );

   if(fastEMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create Fast EMA.");
      return INIT_FAILED;
   }

   //--- Slow EMA
   slowEMAHandle = iMA(
      _Symbol,
      _Period,
      SlowEMAPeriod,
      0,
      MODE_EMA,
      EMAPrice
   );

   if(slowEMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create Slow EMA.");
      return INIT_FAILED;
   }

   //--- RSI
   rsiHandle = iRSI(
      _Symbol,
      _Period,
      RSIPeriod,
      RSIPrice
   );

   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Failed to create RSI.");
      return INIT_FAILED;
   }

   //--- ATR
   atrHandle = iATR(
      _Symbol,
      _Period,
      ATRPeriod
   );

   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR.");
      return INIT_FAILED;
   }

   Print("==========================================");
   Print("EMA-RSI Trend EA initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Fast EMA: ", FastEMAPeriod);
   Print("Slow EMA: ", SlowEMAPeriod);
   Print("RSI Period: ", RSIPeriod);
   Print("==========================================");

   return INIT_SUCCEEDED;
}


//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   if(fastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(fastEMAHandle);

   if(slowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(slowEMAHandle);

   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);

   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}


//====================================================================
// ON TICK
//====================================================================

void OnTick()
{
   //--- Manage trailing stop
   ManageTrailingStop();

   //--- Only evaluate on new candle
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

   //--- Only one position
   if(HasOpenPosition())
      return;

   //--- Get indicators
   double fastEMA[];
   double slowEMA[];
   double rsi[];

   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(
      fastEMAHandle,
      0,
      0,
      3,
      fastEMA
   ) < 3)
      return;

   if(CopyBuffer(
      slowEMAHandle,
      0,
      0,
      3,
      slowEMA
   ) < 3)
      return;

   if(CopyBuffer(
      rsiHandle,
      0,
      0,
      3,
      rsi
   ) < 3)
      return;


   //=================================================================
   // BUY SIGNAL
   //=================================================================

   bool bullishTrend =
      fastEMA[1] > slowEMA[1];

   bool bullishRSI =
      rsi[1] > RSI_Buy_Level;


   //--- Optional EMA crossover
   bool bullishCross =
      fastEMA[2] <= slowEMA[2] &&
      fastEMA[1] > slowEMA[1];


   bool buySignal = false;


   if(UseEMACrossEntry)
   {
      buySignal =
         bullishCross &&
         bullishRSI;
   }
   else
   {
      buySignal =
         bullishTrend &&
         bullishRSI;
   }


   //--- RSI extreme filter
   if(UseRSIExtremeFilter && buySignal)
   {
      if(rsi[1] >= RSI_Max_Buy)
         buySignal = false;
   }


   //=================================================================
   // SELL SIGNAL
   //=================================================================

   bool bearishTrend =
      fastEMA[1] < slowEMA[1];

   bool bearishRSI =
      rsi[1] < RSI_Sell_Level;


   //--- EMA cross
   bool bearishCross =
      fastEMA[2] >= slowEMA[2] &&
      fastEMA[1] < slowEMA[1];


   bool sellSignal = false;


   if(UseEMACrossEntry)
   {
      sellSignal =
         bearishCross &&
         bearishRSI;
   }
   else
   {
      sellSignal =
         bearishTrend &&
         bearishRSI;
   }


   //--- RSI extreme filter
   if(UseRSIExtremeFilter && sellSignal)
   {
      if(rsi[1] <= RSI_Min_Sell)
         sellSignal = false;
   }


   //=================================================================
   // EXECUTE
   //=================================================================

   if(buySignal && AllowBuy)
   {
      Print(
         "BUY SIGNAL | EMA Fast=",
         fastEMA[1],
         " EMA Slow=",
         slowEMA[1],
         " RSI=",
         rsi[1]
      );

      OpenBuy();
   }

   if(sellSignal && AllowSell)
   {
      Print(
         "SELL SIGNAL | EMA Fast=",
         fastEMA[1],
         " EMA Slow=",
         slowEMA[1],
         " RSI=",
         rsi[1]
      );

      OpenSell();
   }
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

   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      return true;
   }

   return false;
}


//====================================================================
// BUY
//====================================================================

void OpenBuy()
{
   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   if(ask <= 0)
      return;

   double sl = 0;
   double tp = 0;


   //--- ATR SL/TP
   if(SLTPMode == SLTP_ATR)
   {
      double atr[];

      ArraySetAsSeries(atr, true);

      if(CopyBuffer(
         atrHandle,
         0,
         1,
         1,
         atr
      ) <= 0)
         return;

      sl =
         ask -
         atr[0] * ATR_SL_Multiplier;

      tp =
         ask +
         atr[0] * ATR_TP_Multiplier;
   }


   //--- Fixed SL/TP
   else
   {
      sl =
         ask -
         FixedStopLossPoints * _Point;

      tp =
         ask +
         FixedTakeProfitPoints * _Point;
   }


   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);


   double lot =
      CalculateLot(
         ask,
         sl
      );


   if(lot <= 0)
      return;


   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "EMA RSI Trend BUY"
      );


   if(result)
   {
      Print(
         "BUY opened | Lot=",
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
         "BUY failed | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//====================================================================
// SELL
//====================================================================

void OpenSell()
{
   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   if(bid <= 0)
      return;

   double sl = 0;
   double tp = 0;


   //--- ATR
   if(SLTPMode == SLTP_ATR)
   {
      double atr[];

      ArraySetAsSeries(atr, true);

      if(CopyBuffer(
         atrHandle,
         0,
         1,
         1,
         atr
      ) <= 0)
         return;

      sl =
         bid +
         atr[0] * ATR_SL_Multiplier;

      tp =
         bid -
         atr[0] * ATR_TP_Multiplier;
   }


   //--- Fixed
   else
   {
      sl =
         bid +
         FixedStopLossPoints * _Point;

      tp =
         bid -
         FixedTakeProfitPoints * _Point;
   }


   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);


   double lot =
      CalculateLot(
         bid,
         sl
      );


   if(lot <= 0)
      return;


   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "EMA RSI Trend SELL"
      );


   if(result)
   {
      Print(
         "SELL opened | Lot=",
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
         "SELL failed | ",
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
   if(LotMode == LOT_FIXED)
      return NormalizeLot(FixedLot);


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


   if(tickSize <= 0 ||
      tickValue <= 0)
      return 0;


   double moneyPerLot =
      (stopDistance / tickSize) *
      tickValue;


   if(moneyPerLot <= 0)
      return 0;


   double lot =
      riskMoney /
      moneyPerLot;


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
         lot / step
      ) * step;


   return NormalizeDouble(
      lot,
      2
   );
}


//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(double price)
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


   if(ask <= 0 ||
      bid <= 0)
      return false;


   double spread =
      (ask - bid) /
      _Point;


   if(spread >
      MaxSpreadPoints)
   {
      Print(
         "Spread too high: ",
         spread
      );

      return false;
   }


   return true;
}


//====================================================================
// CHECK POSITION
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
// TRADING TIME
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


   if(currentMinutes <
      startMinutes)
      return false;


   if(currentMinutes >
      endMinutes)
      return false;


   return true;
}


//====================================================================
// TRAILING STOP
//====================================================================

void ManageTrailingStop()
{
   if(!UseTrailingStop)
      return;


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


      if(
         symbol != _Symbol ||
         magic != (long)MagicNumber
      )
         continue;


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


      double bid =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_BID
         );


      double ask =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_ASK
         );


      //==============================================================
      // BUY TRAILING
      //==============================================================

      if(type ==
         POSITION_TYPE_BUY)
      {
         double newSL =
            bid -
            TrailingStopPoints *
            _Point;


         newSL =
            NormalizePrice(
               newSL
            );


         if(
            (currentSL == 0 ||
             newSL > currentSL +
             TrailingStepPoints *
             _Point) &&
            newSL < bid
         )
         {
            trade.PositionModify(
               ticket,
               newSL,
               currentTP
            );
         }
      }


      //==============================================================
      // SELL TRAILING
      //==============================================================

      if(type ==
         POSITION_TYPE_SELL)
      {
         double newSL =
            ask +
            TrailingStopPoints *
            _Point;


         newSL =
            NormalizePrice(
               newSL
            );


         if(
            (currentSL == 0 ||
             newSL < currentSL -
             TrailingStepPoints *
             _Point) &&
            newSL > ask
         )
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
//+------------------------------------------------------------------+
