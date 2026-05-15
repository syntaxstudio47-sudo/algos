#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.2;
input double RR_Multiple = 2.5;
input double BreakoutBufferPips = 1.0;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 440008;

datetime lastBarTime = 0;
datetime lastSignalBar = 0;
int tradesToday = 0;
int lastTradeDay = -1;

double PipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      return true;
   }
   return false;
}

void ResetDailyCounter()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(lastTradeDay != tm.day)
   {
      tradesToday = 0;
      lastTradeDay = tm.day;
   }
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

double GetATR()
{
   int handle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   if(handle == INVALID_HANDLE) return 0.0;
   double atr[];
   if(CopyBuffer(handle, 0, 1, 1, atr) <= 0) return 0.0;
   return atr[0];
}

bool IsNR7(double &nrHigh, double &nrLow)
{
   double ranges[7];
   for(int i = 0; i < 7; i++)
      ranges[i] = iHigh(_Symbol, PERIOD_CURRENT, i + 1) - iLow(_Symbol, PERIOD_CURRENT, i + 1);

   double latestRange = ranges[0];
   for(int i = 1; i < 7; i++)
   {
      if(latestRange >= ranges[i])
         return false;
   }

   nrHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   nrLow = iLow(_Symbol, PERIOD_CURRENT, 1);
   return true;
}

void CheckForSignal()
{
   if(!IsNewBar()) return;
   ResetDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return;
   if(HasOpenPosition()) return;

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(lastSignalBar == currentBar) return;

   double nrHigh, nrLow;
   if(!IsNR7(nrHigh, nrLow)) return;

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double atr = GetATR();
   if(atr <= 0) return;
   double buffer = BreakoutBufferPips * PipSize();

   bool buySignal = close1 > nrHigh + buffer;
   bool sellSignal = close1 < nrLow - buffer;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      double sl = NormalizeDouble(MathMax(nrLow, ask - atr * ATR_SL_Mult), _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "NR7 Breakout BUY"))
      {
         tradesToday++;
         lastSignalBar = currentBar;
      }
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(MathMin(nrHigh, bid + atr * ATR_SL_Mult), _Digits);
      double tp = NormalizeDouble(bid - atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "NR7 Breakout SELL"))
      {
         tradesToday++;
         lastSignalBar = currentBar;
      }
   }
}

void OnTick()
{
   CheckForSignal();
}
