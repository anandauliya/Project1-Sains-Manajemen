//+------------------------------------------------------------------+
//| NinjaTurtleEA.mq5                                                |
//| Classic Turtle Trading breakout EA for MetaTrader 5              |
//| Baseline version - designed for Strategy Tester optimization     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//========================= INPUTS ===================================
input group "=== Turtle Entry ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;
input int EntryPeriod = 20;              // Donchian breakout period
input int ExitPeriod  = 10;              // Donchian exit period
input bool UseCloseBreakout = true;      // Breakout confirmed by candle close
input int BreakoutBufferPoints = 0;

input group "=== Trend / Filter ==="
input bool UseATRFilter = true;
input int ATRPeriod = 20;
input double MinATRPoints = 0.0;
input bool UseEMATrendFilter = false;
input int TrendEMA = 200;

input group "=== Risk / Position Sizing ==="
input bool UseRiskPercent = true;
input double RiskPercent = 1.0;
input double FixedLot = 0.10;
input double StopATRMultiplier = 2.0;
input double RewardRisk = 2.0;

input group "=== Pyramiding ==="
input bool EnablePyramiding = true;
input int MaxEntries = 4;
input double AddOnATRMultiplier = 0.5;

input group "=== Trade Management ==="
input bool UseBreakEven = false;
input double BreakEvenR = 1.0;
input int BreakEvenLockPoints = 5;
input bool UseTrailingATR = true;
input double TrailATRMultiplier = 2.0;

input group "=== Filters ==="
input bool OnePositionOnly = false;
input int MaxSpreadPoints = 50;
input bool UseSessionFilter = false;
input int StartHour = 7;
input int EndHour = 22;

input group "=== General ==="
input ulong MagicNumber = 26090802;
input bool ShowDebug = true;

//========================= GLOBALS ==================================
int atrHandle = INVALID_HANDLE;
int emaHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

//========================= HELPERS ==================================
void Log(string msg)
{
   if(ShowDebug)
      Print("[NinjaTurtleEA] ", msg);
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t == 0) return false;

   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

double GetATR(int shift=1)
{
   if(atrHandle == INVALID_HANDLE) return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(atrHandle, 0, shift, 1, buffer) != 1)
      return 0.0;

   return buffer[0];
}

double GetEMA(int shift=1)
{
   if(emaHandle == INVALID_HANDLE) return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(emaHandle, 0, shift, 1, buffer) != 1)
      return 0.0;

   return buffer[0];
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   return ((tick.ask - tick.bid) / _Point <= MaxSpreadPoints);
}

bool SessionOK()
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(StartHour == EndHour)
      return true;

   if(StartHour < EndHour)
      return (dt.hour >= StartHour && dt.hour < EndHour);

   return (dt.hour >= StartHour || dt.hour < EndHour);
}

bool VolatilityOK()
{
   if(!UseATRFilter)
      return true;

   double atr = GetATR(1);
   if(atr <= 0.0)
      return false;

   return (atr / _Point >= MinATRPoints);
}

double DonchianHigh(int period, int startShift=2)
{
   double highest = -DBL_MAX;

   for(int i=startShift; i<startShift+period; i++)
   {
      double h = iHigh(_Symbol, InpTimeframe, i);
      if(h > highest)
         highest = h;
   }

   if(highest == -DBL_MAX)
      return 0.0;

   return highest;
}

double DonchianLow(int period, int startShift=2)
{
   double lowest = DBL_MAX;

   for(int i=startShift; i<startShift+period; i++)
   {
      double l = iLow(_Symbol, InpTimeframe, i);
      if(l < lowest)
         lowest = l;
   }

   if(lowest == DBL_MAX)
      return 0.0;

   return lowest;
}

double NormalizeVolume(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      return volume;

   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / step) * step;

   int digits = 2;
   if(step >= 1.0) digits = 0;
   else if(step >= 0.1) digits = 1;

   return NormalizeDouble(volume, digits);
}

double CalculateLot(double entry, double stop)
{
   if(!UseRiskPercent)
      return NormalizeVolume(FixedLot);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * RiskPercent / 100.0;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeVolume(FixedLot);

   double distance = MathAbs(entry - stop);
   if(distance <= 0.0)
      return NormalizeVolume(FixedLot);

   double lossPerLot = (distance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return NormalizeVolume(FixedLot);

   return NormalizeVolume(riskMoney / lossPerLot);
}

int CountOurPositions(long positionType=-1)
{
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(positionType != -1 &&
         PositionGetInteger(POSITION_TYPE) != positionType)
         continue;

      count++;
   }

   return count;
}

bool HasOurPosition()
{
   return CountOurPositions() > 0;
}

double LastEntryPrice(long positionType)
{
   double result = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != positionType)
         continue;

      double p = PositionGetDouble(POSITION_PRICE_OPEN);

      if(result == 0.0)
         result = p;
      else
      {
         if(positionType == POSITION_TYPE_BUY)
            result = MathMax(result, p);
         else
            result = MathMin(result, p);
      }
   }

   return result;
}

bool TrendOK(bool buy)
{
   if(!UseEMATrendFilter)
      return true;

   double ema = GetEMA(1);
   double close1 = iClose(_Symbol, InpTimeframe, 1);

   if(ema <= 0.0 || close1 <= 0.0)
      return false;

   if(buy)
      return close1 > ema;

   return close1 < ema;
}

bool CanAddPosition(long positionType)
{
   if(!EnablePyramiding)
      return CountOurPositions(positionType) == 0;

   int count = CountOurPositions(positionType);

   if(count >= MaxEntries)
      return false;

   double atr = GetATR(1);
   if(atr <= 0.0)
      return false;

   double lastEntry = LastEntryPrice(positionType);
   if(lastEntry <= 0.0)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   if(positionType == POSITION_TYPE_BUY)
      return (tick.ask >= lastEntry + atr * AddOnATRMultiplier);

   return (tick.bid <= lastEntry - atr * AddOnATRMultiplier);
}

void OpenBuy()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   double atr = GetATR(1);
   if(atr <= 0.0) return;

   double entry = tick.ask;
   double sl = entry - atr * StopATRMultiplier;
   double tp = entry + (entry - sl) * RewardRisk;

   double lot = CalculateLot(entry, sl);
   if(lot <= 0.0) return;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   if(trade.Buy(lot, _Symbol, 0.0, sl, tp, "Turtle BUY"))
      Log("BUY opened. Lot=" + DoubleToString(lot,2));
   else
      Log("BUY failed. Retcode=" +
          IntegerToString((int)trade.ResultRetcode()));
}

void OpenSell()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   double atr = GetATR(1);
   if(atr <= 0.0) return;

   double entry = tick.bid;
   double sl = entry + atr * StopATRMultiplier;
   double tp = entry - (sl - entry) * RewardRisk;

   double lot = CalculateLot(entry, sl);
   if(lot <= 0.0) return;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   if(trade.Sell(lot, _Symbol, 0.0, sl, tp, "Turtle SELL"))
      Log("SELL opened. Lot=" + DoubleToString(lot,2));
   else
      Log("SELL failed. Retcode=" +
          IntegerToString((int)trade.ResultRetcode()));
}

void CheckEntry()
{
   double upper = DonchianHigh(EntryPeriod, 2);
   double lower = DonchianLow(EntryPeriod, 2);

   if(upper <= 0.0 || lower <= 0.0)
      return;

   double close1 = iClose(_Symbol, InpTimeframe, 1);

   double buyLevel  = upper + BreakoutBufferPoints * _Point;
   double sellLevel = lower - BreakoutBufferPoints * _Point;

   bool buySignal;
   bool sellSignal;

   if(UseCloseBreakout)
   {
      buySignal = close1 > buyLevel;
      sellSignal = close1 < sellLevel;
   }
   else
   {
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
         return;

      buySignal = tick.ask > buyLevel;
      sellSignal = tick.bid < sellLevel;
   }

   if(buySignal && TrendOK(true) && CanAddPosition(POSITION_TYPE_BUY))
      OpenBuy();

   if(sellSignal && TrendOK(false) && CanAddPosition(POSITION_TYPE_SELL))
      OpenSell();
}

void CheckExit()
{
   double exitHigh = DonchianHigh(ExitPeriod, 2);
   double exitLow  = DonchianLow(ExitPeriod, 2);

   if(exitHigh <= 0.0 || exitLow <= 0.0)
      return;

   double close1 = iClose(_Symbol, InpTimeframe, 1);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && close1 < exitLow)
      {
         if(trade.PositionClose(ticket))
            Log("BUY exited by Turtle exit channel.");
      }

      if(type == POSITION_TYPE_SELL && close1 > exitHigh)
      {
         if(trade.PositionClose(ticket))
            Log("SELL exited by Turtle exit channel.");
      }
   }
}

void ManagePositions()
{
   double atr = GetATR(1);
   if(atr <= 0.0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double current =
         (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;

      double initialRisk = MathAbs(openPrice - sl);
      if(initialRisk <= 0.0)
         continue;

      double profitDistance =
         (type == POSITION_TYPE_BUY)
         ? current - openPrice
         : openPrice - current;

      // Break-even
      if(UseBreakEven &&
         profitDistance >= initialRisk * BreakEvenR)
      {
         double newSL;

         if(type == POSITION_TYPE_BUY)
            newSL = openPrice + BreakEvenLockPoints * _Point;
         else
            newSL = openPrice - BreakEvenLockPoints * _Point;

         bool improve =
            (type == POSITION_TYPE_BUY &&
             (sl == 0.0 || newSL > sl)) ||
            (type == POSITION_TYPE_SELL &&
             (sl == 0.0 || newSL < sl));

         if(improve)
            trade.PositionModify(ticket, newSL, tp);
      }

      // ATR trailing
      if(UseTrailingATR)
      {
         double newSL;

         if(type == POSITION_TYPE_BUY)
            newSL = current - atr * TrailATRMultiplier;
         else
            newSL = current + atr * TrailATRMultiplier;

         bool improve =
            (type == POSITION_TYPE_BUY &&
             newSL > sl &&
             newSL > openPrice) ||
            (type == POSITION_TYPE_SELL &&
             newSL < sl &&
             newSL < openPrice);

         if(improve)
            trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//========================= EVENTS ===================================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   atrHandle = iATR(_Symbol, InpTimeframe, ATRPeriod);

   if(UseEMATrendFilter)
      emaHandle = iMA(_Symbol, InpTimeframe, TrendEMA, 0,
                      MODE_EMA, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle.");
      return INIT_FAILED;
   }

   if(UseEMATrendFilter && emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handle.");
      return INIT_FAILED;
   }

   Log("Ninja Turtle EA initialized.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

void OnTick()
{
   // Position management can run every tick.
   ManagePositions();

   if(!IsNewBar())
      return;

   if(!SpreadOK())
      return;

   if(!SessionOK())
      return;

   if(!VolatilityOK())
      return;

   if(OnePositionOnly && HasOurPosition())
   {
      CheckExit();
      return;
   }

   // Exit first, then evaluate new breakout.
   CheckExit();
   CheckEntry();
}
//+------------------------------------------------------------------+
