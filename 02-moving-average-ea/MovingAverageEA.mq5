//+------------------------------------------------------------------+
//|                                   MA_Crossover_Template_EA.mq5   |
//|         Template dasar Expert Advisor - Moving Average Crossover |
//|         Dibuat sebagai starting point project kelompok EA MT5    |
//+------------------------------------------------------------------+
#property copyright "Project Sains Manajemen 261"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters (silakan sesuaikan dengan strategi channel referensi kalian)
input int      FastMA_Period   = 30;         // Periode MA cepat
input int      SlowMA_Period   = 100;         // Periode MA lambat
input ENUM_MA_METHOD MA_Method = MODE_EMA;   // Metode MA (SMA/EMA/SMMA/LWMA)
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // Harga acuan MA

input double   LotSize         = 0.10;       // Lot size tetap
input int      StopLoss_Points = 450;        // Stop Loss (dalam points)
input int      TakeProfit_Points = 200;      // Take Profit (dalam points)
input int      MagicNumber     = 20261001;   // Magic number unik per EA
input string   TradeComment    = "MA_Cross_EA"; // Komentar order

//--- Handle indikator
int fastMA_handle;
int slowMA_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, FastMA_Period, 0, MA_Method, MA_Price);
   slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, SlowMA_Period, 0, MA_Method, MA_Price);

   if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE)
   {
      Print("Error creating MA indicator handles");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastMA_handle);
   IndicatorRelease(slowMA_handle);
}

//+------------------------------------------------------------------+
//| Ambil nilai MA dari buffer                                       |
//+------------------------------------------------------------------+
bool GetMAValues(double &fastCurr, double &fastPrev, double &slowCurr, double &slowPrev)
{
   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf, true);
   ArraySetAsSeries(slowBuf, true);

   if(CopyBuffer(fastMA_handle, 0, 0, 3, fastBuf) < 3) return false;
   if(CopyBuffer(slowMA_handle, 0, 0, 3, slowBuf) < 3) return false;

   fastCurr = fastBuf[1]; // candle terakhir yang sudah close
   fastPrev = fastBuf[2];
   slowCurr = slowBuf[1];
   slowPrev = slowBuf[2];
   return true;
}

//+------------------------------------------------------------------+
//| Cek apakah sudah ada posisi terbuka dari EA ini                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Hanya evaluasi sinyal di awal candle baru
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   double fastCurr, fastPrev, slowCurr, slowPrev;
   if(!GetMAValues(fastCurr, fastPrev, slowCurr, slowPrev)) return;

   if(HasOpenPosition()) return; // sudah ada posisi, tunggu close dulu (bisa dikembangkan multi-posisi)

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Golden Cross -> BUY
   if(fastPrev <= slowPrev && fastCurr > slowCurr)
   {
      double sl = NormalizeDouble(ask - StopLoss_Points * point, digits);
      double tp = NormalizeDouble(ask + TakeProfit_Points * point, digits);
      trade.Buy(LotSize, _Symbol, ask, sl, tp, TradeComment);
   }
   // Death Cross -> SELL
   else if(fastPrev >= slowPrev && fastCurr < slowCurr)
   {
      double sl = NormalizeDouble(bid + StopLoss_Points * point, digits);
      double tp = NormalizeDouble(bid - TakeProfit_Points * point, digits);
      trade.Sell(LotSize, _Symbol, bid, sl, tp, TradeComment);
   }
}
//+------------------------------------------------------------------+