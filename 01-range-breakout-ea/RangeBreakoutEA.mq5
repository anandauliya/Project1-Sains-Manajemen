#include <Trade/Trade.mqh>

input double RiskMoney       = 50;
input int    RangeStartHour  = 3;
input int    RangeStartMin   = 0;
input int    RangeEndHour    = 6;
input int    RangeEndMin     = 0;
input int    TradingEndHour  = 18;
input int    TradingEndMin   = 0;
input int    Magic           = 123;

//--- filter baru
input double MinRangePips    = 10;    // range breakout minimum (pip), skip hari kalau lebih kecil dari ini
input double MaxRangePips    = 60;    // range breakout maksimum (pip), skip hari kalau lebih besar dari ini
input ENUM_TIMEFRAMES ConfirmTF = PERIOD_M15;  // timeframe buat candle close confirmation
input bool   UseCandleConfirm = true; // true = pakai konfirmasi candle close, false = pakai tick touch (perilaku lama)

datetime rangeTimeStart;
datetime rangeTimeEnd;
datetime tradingTimeEnd;
double   rangeHigh;
double   rangeLow;
CTrade   trade;
bool     isTrade;
bool     rangeValid;      // apakah range hari ini lolos filter min/max
datetime lastConfirmedBar; // buat mencegah cek candle yang sama berulang kali

int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   calcTimes();

   if(TimeCurrent() >= rangeTimeEnd && (rangeHigh == 0 || rangeLow == 0))
     {
      calcRange();
      validateRange();
     }

   if(TimeCurrent() > rangeTimeEnd && TimeCurrent() < tradingTimeEnd)
     {
      if(!isTrade && rangeValid)
        {
         if(UseCandleConfirm)
            checkEntryByCandleClose();
         else
            checkEntryByTickTouch();
        }
     }
   else if(TimeCurrent() >= tradingTimeEnd)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         CPositionInfo pos;
         if(pos.SelectByIndex(i))
           {
            if(pos.Magic() == Magic && pos.Symbol() == _Symbol)
              {
               trade.PositionClose(pos.Ticket());
              }
           }
        }
     }
}

//--- entry lama: begitu tick nyentuh level (dipertahankan sebagai opsi, buat A/B test)
void checkEntryByTickTouch()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(rangeHigh > 0 && rangeLow > 0)
     {
      if(bid > rangeHigh)
        {
         double lots = calcLots();
         if(lots > 0) trade.Buy(lots, _Symbol, 0, rangeLow);
         isTrade = true;
        }
      else if(bid < rangeLow)
        {
         double lots = calcLots();
         if(lots > 0) trade.Sell(lots, _Symbol, 0, rangeHigh);
         isTrade = true;
        }
     }
}

//--- entry baru: nunggu candle ConfirmTF close di luar range
void checkEntryByCandleClose()
{
   datetime barTime = iTime(_Symbol, ConfirmTF, 0);
   if(barTime == lastConfirmedBar) return; // candle yang sama, sudah dicek

   // pastikan candle sebelumnya (index 1) sudah closed dan kita belum proses dia
   datetime closedBarTime = iTime(_Symbol, ConfirmTF, 1);
   if(closedBarTime <= rangeTimeStart) return; // candle belum dari sesi breakout

   double closePrice = iClose(_Symbol, ConfirmTF, 1);
   if(closePrice == 0) return;

   if(closedBarTime == lastConfirmedBar) return;

   if(rangeHigh > 0 && rangeLow > 0)
     {
      if(closePrice > rangeHigh)
        {
         double lots = calcLots();
         if(lots > 0) trade.Buy(lots, _Symbol, 0, rangeLow);
         isTrade = true;
        }
      else if(closePrice < rangeLow)
        {
         double lots = calcLots();
         if(lots > 0) trade.Sell(lots, _Symbol, 0, rangeHigh);
         isTrade = true;
        }
      lastConfirmedBar = closedBarTime;
     }
}

//--- cek apakah range hari ini masuk rentang MinRangePips - MaxRangePips
void validateRange()
{
   rangeValid = false;
   if(rangeHigh <= 0 || rangeLow <= 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;

   double rangePips = (rangeHigh - rangeLow) / pipSize;

   if(rangePips >= MinRangePips && rangePips <= MaxRangePips)
      rangeValid = true;
}

void calcTimes()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.sec = 0;

   dt.hour = RangeStartHour;
   dt.min  = RangeStartMin;

   if(rangeTimeStart != StructToTime(dt))
     {
      isTrade    = false;
      rangeHigh  = 0;
      rangeLow   = 0;
      rangeValid = false;
     }

   rangeTimeStart = StructToTime(dt);

   dt.hour = RangeEndHour;
   dt.min  = RangeEndMin;
   rangeTimeEnd = StructToTime(dt);

   dt.hour = TradingEndHour;
   dt.min  = TradingEndMin;
   tradingTimeEnd = StructToTime(dt);
}

void calcRange()
{
   double highs[];
   double lows[];

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(CopyHigh(_Symbol, PERIOD_M1, rangeTimeStart, rangeTimeEnd, highs) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_M1, rangeTimeStart, rangeTimeEnd, lows) <= 0) return;

   int indexHighest = ArrayMaximum(highs);
   int indexLowest  = ArrayMinimum(lows);

   rangeHigh = highs[indexHighest];
   rangeLow  = lows[indexLowest];

   if(!MQLInfoInteger(MQL_TESTER))
     {
      string objName = "Range " + TimeToString(rangeTimeStart, TIME_DATE);
      if(ObjectFind(0, objName) < 0)
        {
         ObjectCreate(0, objName, OBJ_RECTANGLE, 0, rangeTimeStart, rangeLow, rangeTimeEnd, rangeHigh);
         ObjectSetInteger(0, objName, OBJPROP_FILL, true);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, clrYellow);
        }
      else
        {
         ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, rangeLow);
         ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, rangeHigh);
        }
     }
}

double calcLots()
{
   double ticksize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(ticksize == 0 || tickvalue == 0) return 0.01;

   double rangeSize  = rangeHigh - rangeLow;
   if(rangeSize <= 0) return 0.01;

   double riskPerLot = rangeSize / ticksize * tickvalue;
   if(riskPerLot <= 0) return 0.01;

   double lots = RiskMoney / riskPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}