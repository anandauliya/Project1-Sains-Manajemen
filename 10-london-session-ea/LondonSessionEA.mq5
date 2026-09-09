//+------------------------------------------------------------------+
//| 09-london-session-ea.mq5                                         |
//| Strategi: ukur range sesi Asia, pasang pending stop order di     |
//| kedua sisi pas London session open (OCO), auto cancel & flat     |
//| di akhir sesi London. Beda dari Range Breakout EA (01) yang      |
//| pakai candle-close confirmation & market order — ini pakai       |
//| pending order dari awal, jadi lebih sensitif ke breakout cepat.  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

input double RiskMoney        = 50;
input int    AsianStartHour   = 0;    // jam mulai sesi Asia (waktu broker/server)
input int    AsianEndHour     = 7;    // jam sesi Asia selesai = jam London session open
input int    LondonEndHour    = 16;   // jam sesi London dianggap selesai, posisi/pending ditutup
input double MinRangePips     = 8;    // skip hari kalau range Asia lebih kecil dari ini
input double MaxRangePips     = 50;   // skip hari kalau range Asia lebih besar dari ini
input double PendingBufferPips= 2;    // jarak pending order dari batas range Asia
input double SL_BufferPips    = 3;    // buffer tambahan SL di luar sisi range yang berlawanan
input double RR_Ratio         = 1.5;  // TP = SL_distance * RR_Ratio
input int    Magic            = 109;

datetime asianStart, asianEnd, londonEnd;
double   asianHigh, asianLow;
bool     rangeValid;
bool     ordersPlacedToday;
datetime lastProcessedDay;
CTrade   trade;

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
   calcSessionTimes();

   datetime now = TimeCurrent();

   // hari baru -> reset state
   MqlDateTime dtNow;
   TimeToStruct(now, dtNow);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dtNow.year, dtNow.mon, dtNow.day));
   if(today != lastProcessedDay)
     {
      lastProcessedDay  = today;
      asianHigh = 0; asianLow = 0;
      rangeValid = false;
      ordersPlacedToday = false;
      cancelPendingOrders(); // buang sisa pending kemarin kalau ada
     }

   // begitu sesi Asia selesai (= London open), hitung range & pasang pending order sekali
   if(now >= asianEnd && !ordersPlacedToday)
     {
      if(calcAsianRange())
        {
         validateRange();
         if(rangeValid)
            placeBreakoutOrders();
        }
      ordersPlacedToday = true; // sekali coba per hari, sukses atau nggak
     }

   // kalau salah satu pending sudah jadi posisi, cancel sisi satunya (OCO)
   if(positionExists())
      cancelPendingOrders();

   // akhir sesi London: tutup posisi & buang pending yang belum jadi
   if(now >= londonEnd)
     {
      closeAllPositions();
      cancelPendingOrders();
     }
}

void calcSessionTimes()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.sec = 0;

   dt.hour = AsianStartHour; dt.min = 0;
   asianStart = StructToTime(dt);

   dt.hour = AsianEndHour; dt.min = 0;
   asianEnd = StructToTime(dt);

   dt.hour = LondonEndHour; dt.min = 0;
   londonEnd = StructToTime(dt);
}

bool calcAsianRange()
{
   double highs[]; double lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(CopyHigh(_Symbol, PERIOD_M5, asianStart, asianEnd, highs) <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_M5, asianStart, asianEnd, lows) <= 0) return false;

   asianHigh = highs[ArrayMaximum(highs)];
   asianLow  = lows[ArrayMinimum(lows)];
   return true;
}

void validateRange()
{
   rangeValid = false;
   if(asianHigh <= 0 || asianLow <= 0) return;

   double pipSize = getPipSize();
   double rangePips = (asianHigh - asianLow) / pipSize;

   if(rangePips >= MinRangePips && rangePips <= MaxRangePips)
      rangeValid = true;
}

void placeBreakoutOrders()
{
   double pipSize = getPipSize();
   double buffer  = PendingBufferPips * pipSize;
   double slBuf   = SL_BufferPips * pipSize;

   double buyPrice  = asianHigh + buffer;
   double sellPrice = asianLow  - buffer;

   double buySl  = asianLow  - slBuf;
   double sellSl = asianHigh + slBuf;

   double buySlDist  = buyPrice - buySl;
   double sellSlDist = sellSl - sellPrice;

   double buyLots  = calcLots(buySlDist);
   double sellLots = calcLots(sellSlDist);

   if(buyLots > 0)
     {
      double tp = buyPrice + buySlDist * RR_Ratio;
      trade.BuyStop(buyLots, buyPrice, _Symbol, buySl, tp, ORDER_TIME_DAY);
     }
   if(sellLots > 0)
     {
      double tp = sellPrice - sellSlDist * RR_Ratio;
      trade.SellStop(sellLots, sellPrice, _Symbol, sellSl, tp, ORDER_TIME_DAY);
     }
}

double getPipSize()
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? point * 10 : point;
}

bool positionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
        }
     }
   return false;
}

void cancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetInteger(ORDER_MAGIC) == Magic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            trade.OrderDelete(ticket);
        }
     }
}

void closeAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            trade.PositionClose(ticket);
        }
     }
}

double calcLots(double slDist)
{
   double ticksize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ticksize == 0 || tickvalue == 0 || slDist <= 0) return 0;

   double riskPerLot = slDist / ticksize * tickvalue;
   if(riskPerLot <= 0) return 0;

   double lots = RiskMoney / riskPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / stepLot) * stepLot;
   if(lots < minLot) return 0;
   lots = MathMin(maxLot, lots);

   return NormalizeDouble(lots, 2);
}