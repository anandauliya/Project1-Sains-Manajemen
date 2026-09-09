//+------------------------------------------------------------------+
//| 10-fibonacci-pullback-ea.mq5                                     |
//| Strategi: cari swing high/low, entry saat pullback ke level      |
//| Fibonacci 50%/61.8% lalu lanjut searah trend (candle confirm)    |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

input double RiskMoney         = 50;
input int    SwingLookback     = 50;   // jumlah bar buat cari swing high/low
input double FibLevelMin       = 0.5;  // batas bawah zona pullback
input double FibLevelMax       = 0.618;// batas atas zona pullback
input double RR_Ratio          = 1.5;  // TP dihitung dari jarak SL x RR_Ratio
input int    Magic             = 110;

CTrade   trade;
datetime lastBarTime;
double   swingHigh, swingLow;
bool     lastSwingWasHighFirst; // true kalau swing high terjadi lebih baru dari swing low (trend turun dari titik itu)

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
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == lastBarTime) return;
   lastBarTime = barTime;

   if(positionExists()) return;
   if(!findSwing()) return;

   double range = swingHigh - swingLow;
   if(range <= 0) return;

   double closePrev = iClose(_Symbol, PERIOD_CURRENT, 1);
   double openPrev   = iOpen(_Symbol, PERIOD_CURRENT, 1);

   // uptrend: swing low terjadi lebih baru (terbentuk setelah high) -> cari pullback dari high turun ke fib zone lalu lanjut naik
   // downtrend: swing high lebih baru -> cari pullback dari low naik ke fib zone lalu lanjut turun
   double fibMinPrice, fibMaxPrice;

   if(!lastSwingWasHighFirst) // low lebih baru = uptrend, ukur retracement dari high turun
     {
      fibMinPrice = swingHigh - range * FibLevelMax;
      fibMaxPrice = swingHigh - range * FibLevelMin;

      bool inZone = (closePrev >= fibMinPrice && closePrev <= fibMaxPrice);
      bool bullishCandle = closePrev > openPrev;

      if(inZone && bullishCandle)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl    = swingLow;
         double slDist = price - sl;
         if(slDist > 0) openTrade(ORDER_TYPE_BUY, price, sl, price + slDist * RR_Ratio, slDist);
        }
     }
   else // high lebih baru = downtrend, ukur retracement dari low naik
     {
      fibMinPrice = swingLow + range * FibLevelMin;
      fibMaxPrice = swingLow + range * FibLevelMax;

      bool inZone = (closePrev >= fibMinPrice && closePrev <= fibMaxPrice);
      bool bearishCandle = closePrev < openPrev;

      if(inZone && bearishCandle)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl    = swingHigh;
         double slDist = sl - price;
         if(slDist > 0) openTrade(ORDER_TYPE_SELL, price, sl, price - slDist * RR_Ratio, slDist);
        }
     }
}

// cari swing high & swing low dalam SwingLookback bar terakhir (tidak termasuk bar berjalan),
// lalu tentukan mana yang terbentuk lebih baru buat nentuin arah trend
bool findSwing()
{
   int highestIdx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, SwingLookback, 1);
   int lowestIdx  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, SwingLookback, 1);
   if(highestIdx < 0 || lowestIdx < 0) return false;

   swingHigh = iHigh(_Symbol, PERIOD_CURRENT, highestIdx);
   swingLow  = iLow(_Symbol, PERIOD_CURRENT, lowestIdx);

   // index lebih kecil = bar lebih baru (index 1 = bar kemarin, index SwingLookback = paling lama)
   lastSwingWasHighFirst = (highestIdx < lowestIdx);

   return true;
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

void openTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, double slDist)
{
   double lots = calcLots(slDist);
   if(lots <= 0) return;

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lots, _Symbol, price, sl, tp);
   else
      trade.Sell(lots, _Symbol, price, sl, tp);
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