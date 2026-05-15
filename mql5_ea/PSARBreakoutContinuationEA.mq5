#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input double SARStep = 0.02;
input double SARMaximum = 0.2;
input int BreakoutPeriod = 14;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.3;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 440009;

datetime lastBarTime = 0;
datetime lastSignalBar = 0;
int tradesToday = 0;
int lastTradeDay = -1;

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

bool GetSAR(double &sar1, double &sar2)
{
   int handle = iSAR(_Symbol, PERIOD_CURRENT, SARStep, SARMaximum);
   if(handle == INVALID_HANDLE) return false;
   double buf[];
   if(CopyBuffer(handle, 0, 1, 2, buf) <= 0) return false;
   sar1 = buf[0];
   sar2 = buf[1];
   return true;
}

double HighestHigh(int period)
{
   int shift = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, period, 1);
   return iHigh(_Symbol, PERIOD_CURRENT, shift);
}

double LowestLow(int period)
{
   int shift = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, period, 1);
   return iLow(_Symbol, PERIOD_CURRENT, shift);
}

void CheckForSignal()
{
   if(!IsNewBar()) return;
   ResetDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return;
   if(HasOpenPosition()) return;

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(lastSignalBar == currentBar) return;

   double sar1, sar2;
   if(!GetSAR(sar1, sar2)) return;

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double breakoutHigh = HighestHigh(BreakoutPeriod);
   double breakoutLow = LowestLow(BreakoutPeriod);
   double atr = GetATR();
   if(atr <= 0) return;

   bool bullFlip = (close2 <= sar2 && close1 > sar1);
   bool bearFlip = (close2 >= sar2 && close1 < sar1);

   bool buySignal = bullFlip && close1 > breakoutHigh;
   bool sellSignal = bearFlip && close1 < breakoutLow;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      double sl = NormalizeDouble(MathMin(sar1, ask - atr * ATR_SL_Mult), _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "PSAR Breakout BUY"))
      {
         tradesToday++;
         lastSignalBar = currentBar;
      }
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(MathMax(sar1, bid + atr * ATR_SL_Mult), _Digits);
      double tp = NormalizeDouble(bid - atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "PSAR Breakout SELL"))
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
