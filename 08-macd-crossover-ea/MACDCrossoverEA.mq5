//+------------------------------------------------------------------+
//| 08-macd-crossover-ea.mq5                                         |
//| Strategi: MACD line cross Signal line, difilter arah trend EMA   |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

input double RiskMoney      = 50;     // risk per trade dalam uang akun
input int    FastEMA        = 12;
input int    SlowEMA        = 26;
input int    SignalSMA      = 9;
input int    TrendEMAPeriod = 200;    // filter arah: hanya buy di atas EMA ini, sell di bawah
input double ATR_Multiplier = 2.0;    // SL = ATR * multiplier
input int    ATR_Period     = 14;
input double RR_Ratio       = 1.5;    // TP = SL_distance * RR_Ratio
input int    Magic          = 108;

int      hMACD, hTrendEMA, hATR;
CTrade   trade;
datetime lastBarTime;

int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   hMACD     = iMACD(_Symbol, PERIOD_CURRENT, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);
   hTrendEMA = iMA(_Symbol, PERIOD_CURRENT, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATR      = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(hMACD == INVALID_HANDLE || hTrendEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hMACD);
   IndicatorRelease(hTrendEMA);
   IndicatorRelease(hATR);
}

void OnTick()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == lastBarTime) return; // hanya evaluasi sekali per bar baru
   lastBarTime = barTime;

   if(PositionsTotal() > 0 && positionExists()) return; // sudah ada posisi kita, skip

   double macdMain[3], macdSignal[3];
   if(CopyBuffer(hMACD, 0, 1, 3, macdMain) < 3) return;
   if(CopyBuffer(hMACD, 1, 1, 3, macdSignal) < 3) return;

   double trendEma[1];
   if(CopyBuffer(hTrendEMA, 0, 1, 1, trendEma) < 1) return;

   double atr[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;

   double closePrev = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool crossUp   = (macdMain[1] <= macdSignal[1] && macdMain[2] > macdSignal[2]);
   bool crossDown = (macdMain[1] >= macdSignal[1] && macdMain[2] < macdSignal[2]);

   bool trendUp   = closePrev > trendEma[0];
   bool trendDown = closePrev < trendEma[0];

   double slDist = atr[0] * ATR_Multiplier;
   if(slDist <= 0) return;

   if(crossUp && trendUp)
      openTrade(ORDER_TYPE_BUY, slDist);
   else if(crossDown && trendDown)
      openTrade(ORDER_TYPE_SELL, slDist);
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

void openTrade(ENUM_ORDER_TYPE type, double slDist)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   double tp = (type == ORDER_TYPE_BUY) ? price + slDist * RR_Ratio : price - slDist * RR_Ratio;

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
   if(lots < minLot) return 0; // RiskMoney terlalu kecil buat lot minimum broker di stop distance ini
   lots = MathMin(maxLot, lots);

   return NormalizeDouble(lots, 2);
}