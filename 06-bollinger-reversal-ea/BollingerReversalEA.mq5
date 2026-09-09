//+------------------------------------------------------------------+
//|                                      BollingerReversalEA.mq5      |
//|                  Bollinger Band Mean Reversion Strategy          |
//|                  Research / Optimization Version                 |
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

enum ENUM_TP_MODE
{
   TP_FIXED_DISTANCE = 0,
   TP_MIDDLE_BAND = 1,
   TP_ATR = 2
};


//====================================================================
// GENERAL
//====================================================================

input ulong MagicNumber = 20260910;

input bool AllowBuy  = true;
input bool AllowSell = true;


//====================================================================
// BOLLINGER BAND SETTINGS
//====================================================================

input int BB_Period = 20;

input double BB_Deviation = 2.0;

input int BB_Shift = 0;

input ENUM_APPLIED_PRICE BB_Price = PRICE_CLOSE;


//====================================================================
// REVERSAL SIGNAL
//====================================================================

// 0 = previous candle closes outside band
// 1 = previous candle touches band
input bool RequireCloseOutsideBand = true;

input bool RequireCurrentCandleInsideBand = true;


//====================================================================
// RSI FILTER
//====================================================================

input bool UseRSIFilter = true;

input int RSIPeriod = 14;

input double RSI_Buy_Max = 35.0;

input double RSI_Sell_Min = 65.0;


//====================================================================
// RSI EXIT FILTER
//====================================================================

input bool UseRSIExit = false;

input double RSI_Buy_Exit = 55.0;

input double RSI_Sell_Exit = 45.0;


//====================================================================
// MOVING AVERAGE TREND FILTER
//====================================================================

input bool UseTrendFilter = false;

input int TrendMAPeriod = 200;

input ENUM_MA_METHOD TrendMAMethod = MODE_EMA;


//====================================================================
// LOT SIZE
//====================================================================

input ENUM_LOT_MODE LotMode = LOT_FIXED;

input double FixedLot = 0.10;

input double RiskPercent = 1.0;


//====================================================================
// STOP LOSS
//====================================================================

input ENUM_SLTP_MODE SLMode = SLTP_ATR;

input int FixedStopLossPoints = 1000;

input int ATRPeriod = 14;

input double ATR_SL_Multiplier = 1.5;


//====================================================================
// TAKE PROFIT
//====================================================================

input ENUM_TP_MODE TPMode = TP_MIDDLE_BAND;

input int FixedTakeProfitPoints = 1500;

input double ATR_TP_Multiplier = 2.0;


//====================================================================
// SPREAD
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
// BAR SETTINGS
//====================================================================

input bool UseNewBarOnly = true;


//====================================================================
// GLOBAL HANDLES
//====================================================================

int bbHandle = INVALID_HANDLE;

int rsiHandle = INVALID_HANDLE;

int atrHandle = INVALID_HANDLE;

int trendMAHandle = INVALID_HANDLE;

datetime lastBarTime = 0;


//====================================================================
// INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   trade.SetDeviationInPoints(20);


   //==============================================================
   // BOLLINGER BANDS
   //==============================================================

   bbHandle = iBands(
      _Symbol,
      _Period,
      BB_Period,
      BB_Shift,
      BB_Deviation,
      BB_Price
   );


   if(bbHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create Bollinger Bands handle.");
      return INIT_FAILED;
   }


   //==============================================================
   // RSI
   //==============================================================

   if(UseRSIFilter || UseRSIExit)
   {
      rsiHandle = iRSI(
         _Symbol,
         _Period,
         RSIPeriod,
         PRICE_CLOSE
      );


      if(rsiHandle == INVALID_HANDLE)
      {
         Print("ERROR: Cannot create RSI handle.");
         return INIT_FAILED;
      }
   }


   //==============================================================
   // ATR
   //==============================================================

   if(
      SLMode == SLTP_ATR ||
      TPMode == TP_ATR
   )
   {
      atrHandle = iATR(
         _Symbol,
         _Period,
         ATRPeriod
      );


      if(atrHandle == INVALID_HANDLE)
      {
         Print("ERROR: Cannot create ATR handle.");
         return INIT_FAILED;
      }
   }


   //==============================================================
   // TREND MA
   //==============================================================

   if(UseTrendFilter)
   {
      trendMAHandle = iMA(
         _Symbol,
         _Period,
         TrendMAPeriod,
         0,
         TrendMAMethod,
         PRICE_CLOSE
      );


      if(trendMAHandle == INVALID_HANDLE)
      {
         Print("ERROR: Cannot create Trend MA.");
         return INIT_FAILED;
      }
   }


   Print("======================================");
   Print("Bollinger Reversal EA initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("BB Period: ", BB_Period);
   Print("BB Deviation: ", BB_Deviation);
   Print("RSI Filter: ", UseRSIFilter);
   Print("Trend Filter: ", UseTrendFilter);
   Print("======================================");


   return INIT_SUCCEEDED;
}


//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   if(bbHandle != INVALID_HANDLE)
      IndicatorRelease(bbHandle);

   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);

   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   if(trendMAHandle != INVALID_HANDLE)
      IndicatorRelease(trendMAHandle);
}


//====================================================================
// ON TICK
//====================================================================

void OnTick()
{
   //--- Manage open trades
   ManageOpenPosition();


   //--- New bar only
   if(UseNewBarOnly)
   {
      if(!IsNewBar())
         return;
   }


   //--- Trading session
   if(UseTradingSession)
   {
      if(!IsTradingTime())
         return;
   }


   //--- Spread
   if(UseSpreadFilter)
   {
      if(!CheckSpread())
         return;
   }


   //--- Only one position
   if(HasOpenPosition())
      return;


   //--- Arrays
   double upper[];
   double middle[];
   double lower[];

   double rsi[];

   double trendMA[];


   ArraySetAsSeries(upper,true);
   ArraySetAsSeries(middle,true);
   ArraySetAsSeries(lower,true);

   ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(trendMA,true);


   //==============================================================
   // COPY BOLLINGER DATA
   //==============================================================

   if(CopyBuffer(
      bbHandle,
      1,
      0,
      3,
      upper
   ) < 3)
      return;


   if(CopyBuffer(
      bbHandle,
      0,
      0,
      3,
      middle
   ) < 3)
      return;


   if(CopyBuffer(
      bbHandle,
      2,
      0,
      3,
      lower
   ) < 3)
      return;


   //==============================================================
   // RSI
   //==============================================================

   if(UseRSIFilter)
   {
      if(CopyBuffer(
         rsiHandle,
         0,
         0,
         3,
         rsi
      ) < 3)
         return;
   }


   //==============================================================
   // TREND MA
   //==============================================================

   if(UseTrendFilter)
   {
      if(CopyBuffer(
         trendMAHandle,
         0,
         0,
         3,
         trendMA
      ) < 3)
         return;
   }


   //==============================================================
   // PRICE DATA
   //==============================================================

   double close1 =
      iClose(
         _Symbol,
         _Period,
         1
      );

   double close2 =
      iClose(
         _Symbol,
         _Period,
         2
      );

   double high1 =
      iHigh(
         _Symbol,
         _Period,
         1
      );

   double low1 =
      iLow(
         _Symbol,
         _Period,
         1
      );


   //==============================================================
   // BUY REVERSAL
   //==============================================================

   bool previousOutsideLower = false;


   if(RequireCloseOutsideBand)
   {
      previousOutsideLower =
         close2 < lower[2];
   }
   else
   {
      previousOutsideLower =
         low2TouchLower();
   }


   bool currentInsideLower =
      close1 > lower[1];


   bool buySignal =
      previousOutsideLower;


   if(RequireCurrentCandleInsideBand)
      buySignal =
         buySignal &&
         currentInsideLower;


   //--- RSI
   if(UseRSIFilter)
   {
      if(rsi[1] > RSI_Buy_Max)
         buySignal = false;
   }


   //--- Trend filter
   if(UseTrendFilter)
   {
      if(close1 < trendMA[1])
         buySignal = false;
   }


   //==============================================================
   // SELL REVERSAL
   //==============================================================

   bool previousOutsideUpper = false;


   if(RequireCloseOutsideBand)
   {
      previousOutsideUpper =
         close2 > upper[2];
   }
   else
   {
      previousOutsideUpper =
         high2TouchUpper();
   }


   bool currentInsideUpper =
      close1 < upper[1];


   bool sellSignal =
      previousOutsideUpper;


   if(RequireCurrentCandleInsideBand)
      sellSignal =
         sellSignal &&
         currentInsideUpper;


   //--- RSI
   if(UseRSIFilter)
   {
      if(rsi[1] < RSI_Sell_Min)
         sellSignal = false;
   }


   //--- Trend filter
   if(UseTrendFilter)
   {
      if(close1 > trendMA[1])
         sellSignal = false;
   }


   //==============================================================
   // EXECUTION
   //==============================================================

   if(buySignal && AllowBuy)
   {
      Print(
         "BUY SIGNAL | Close=",
         close1,
         " LowerBand=",
         lower[1],
         " RSI=",
         UseRSIFilter ? rsi[1] : 0
      );

      OpenBuy();
   }


   if(sellSignal && AllowSell)
   {
      Print(
         "SELL SIGNAL | Close=",
         close1,
         " UpperBand=",
         upper[1],
         " RSI=",
         UseRSIFilter ? rsi[1] : 0
      );

      OpenSell();
   }
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


   //==============================================================
   // STOP LOSS
   //==============================================================

   if(SLMode == SLTP_ATR)
   {
      double atr[];

      ArraySetAsSeries(
         atr,
         true
      );


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
         atr[0] *
         ATR_SL_Multiplier;
   }
   else
   {
      sl =
         ask -
         FixedStopLossPoints *
         _Point;
   }


   //==============================================================
   // TAKE PROFIT
   //==============================================================

   if(TPMode == TP_MIDDLE_BAND)
   {
      double middle[];

      ArraySetAsSeries(
         middle,
         true
      );


      if(CopyBuffer(
         bbHandle,
         0,
         1,
         1,
         middle
      ) <= 0)
         return;


      tp = middle[0];


      // Make sure TP is above entry
      if(tp <= ask)
         tp = 0;
   }


   else if(TPMode == TP_ATR)
   {
      double atr[];

      ArraySetAsSeries(
         atr,
         true
      );


      if(CopyBuffer(
         atrHandle,
         0,
         1,
         1,
         atr
      ) <= 0)
         return;


      tp =
         ask +
         atr[0] *
         ATR_TP_Multiplier;
   }


   else
   {
      tp =
         ask +
         FixedTakeProfitPoints *
         _Point;
   }


   sl = NormalizePrice(sl);

   if(tp > 0)
      tp = NormalizePrice(tp);


   //==============================================================
   // LOT
   //==============================================================

   double lot =
      CalculateLot(
         ask,
         sl
      );


   if(lot <= 0)
      return;


   //==============================================================
   // OPEN BUY
   //==============================================================

   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "Bollinger Reversal BUY"
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


   //==============================================================
   // STOP LOSS
   //==============================================================

   if(SLMode == SLTP_ATR)
   {
      double atr[];

      ArraySetAsSeries(
         atr,
         true
      );


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
         atr[0] *
         ATR_SL_Multiplier;
   }
   else
   {
      sl =
         bid +
         FixedStopLossPoints *
         _Point;
   }


   //==============================================================
   // TAKE PROFIT
   //==============================================================

   if(TPMode == TP_MIDDLE_BAND)
   {
      double middle[];

      ArraySetAsSeries(
         middle,
         true
      );


      if(CopyBuffer(
         bbHandle,
         0,
         1,
         1,
         middle
      ) <= 0)
         return;


      tp = middle[0];


      if(tp >= bid)
         tp = 0;
   }


   else if(TPMode == TP_ATR)
   {
      double atr[];

      ArraySetAsSeries(
         atr,
         true
      );


      if(CopyBuffer(
         atrHandle,
         0,
         1,
         1,
         atr
      ) <= 0)
         return;


      tp =
         bid -
         atr[0] *
         ATR_TP_Multiplier;
   }


   else
   {
      tp =
         bid -
         FixedTakeProfitPoints *
         _Point;
   }


   sl = NormalizePrice(sl);

   if(tp > 0)
      tp = NormalizePrice(tp);


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
   // OPEN SELL
   //==============================================================

   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "Bollinger Reversal SELL"
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


   if(
      tickSize <= 0 ||
      tickValue <= 0
   )
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
// SPREAD
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
      return false;


   double spread =
      (ask - bid) /
      _Point;


   if(spread >
      MaxSpreadPoints)
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
// OPEN POSITION
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
// TRADING TIME
//====================================================================

bool IsTradingTime()
{
   MqlDateTime dt;

   TimeToStruct(
      TimeCurrent(),
      dt
   );


   int current =
      dt.hour * 60 +
      dt.min;


   int start =
      StartHour * 60 +
      StartMinute;


   int end =
      EndHour * 60 +
      EndMinute;


   if(current < start)
      return false;


   if(current > end)
      return false;


   return true;
}


//====================================================================
// POSITION MANAGEMENT
//====================================================================

void ManageOpenPosition()
{
   if(!HasOpenPosition())
      return;


   //==============================================================
   // RSI EXIT
   //==============================================================

   if(!UseRSIExit)
      return;


   if(rsiHandle == INVALID_HANDLE)
      return;


   double rsi[];

   ArraySetAsSeries(
      rsi,
      true
   );


   if(CopyBuffer(
      rsiHandle,
      0,
      1,
      1,
      rsi
   ) <= 0)
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


      //--- BUY exit
      if(
         type ==
         POSITION_TYPE_BUY
      )
      {
         if(rsi[0] >=
            RSI_Buy_Exit)
         {
            trade.PositionClose(
               ticket
            );
         }
      }


      //--- SELL exit
      if(
         type ==
         POSITION_TYPE_SELL
      )
      {
         if(rsi[0] <=
            RSI_Sell_Exit)
         {
            trade.PositionClose(
               ticket
            );
         }
      }
   }
}


//====================================================================
// TOUCH LOWER BAND
//====================================================================

bool low2TouchLower()
{
   double lower[];

   ArraySetAsSeries(
      lower,
      true
   );


   if(CopyBuffer(
      bbHandle,
      2,
      0,
      3,
      lower
   ) < 3)
      return false;


   double low =
      iLow(
         _Symbol,
         _Period,
         2
      );


   return (
      low <= lower[2]
   );
}


//====================================================================
// TOUCH UPPER BAND
//====================================================================

bool high2TouchUpper()
{
   double upper[];

   ArraySetAsSeries(
      upper,
      true
   );


   if(CopyBuffer(
      bbHandle,
      1,
      0,
      3,
      upper
   ) < 3)
      return false;


   double high =
      iHigh(
         _Symbol,
         _Period,
         2
      );


   return (
      high >= upper[2]
   );
}
//+------------------------------------------------------------------+
