#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input ENUM_TIMEFRAMES HigherTF = PERIOD_H1;
input ENUM_TIMEFRAMES LowerTF = PERIOD_M15;
input int HTFTrendMAPeriod = 50;
input int BreakoutPeriod = 20;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.5;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 440007;

datetime lastBarTime = 0;
datetime lastSignalBar = 0;
int tradesToday = 0;
int lastTradeDay = -1;

bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol, LowerTF, 0);
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
   int handle = iATR(_Symbol, LowerTF, ATRPeriod);
   if(handle == INVALID_HANDLE) return 0.0;
   double atr[];
   if(CopyBuffer(handle, 0, 1, 1, atr) <= 0) return 0.0;
   return atr[0];
}

string GetHTFTrend()
{
   int maHandle = iMA(_Symbol, HigherTF, HTFTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE) return "NONE";
   double maBuf[];
   if(CopyBuffer(maHandle, 0, 1, 1, maBuf) <= 0) return "NONE";

   double close1 = iClose(_Symbol, HigherTF, 1);
   if(close1 > maBuf[0]) return "BULL";
   if(close1 < maBuf[0]) return "BEAR";
   return "NONE";
}

double HighestHigh(int period)
{
   int shift = iHighest(_Symbol, LowerTF, MODE_HIGH, period, 1);
   return iHigh(_Symbol, LowerTF, shift);
}

double LowestLow(int period)
{
   int shift = iLowest(_Symbol, LowerTF, MODE_LOW, period, 1);
   return iLow(_Symbol, LowerTF, shift);
}

void CheckForSignal()
{
   if(!IsNewBar()) return;
   ResetDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return;
   if(HasOpenPosition()) return;

   datetime currentBar = iTime(_Symbol, LowerTF, 1);
   if(lastSignalBar == currentBar) return;

   string trend = GetHTFTrend();
   if(trend == "NONE") return;

   double close1 = iClose(_Symbol, LowerTF, 1);
   double close2 = iClose(_Symbol, LowerTF, 2);
   double breakoutHigh = HighestHigh(BreakoutPeriod);
   double breakoutLow = LowestLow(BreakoutPeriod);
   double atr = GetATR();
   if(atr <= 0) return;

   bool buySignal = (trend == "BULL" && close2 <= breakoutHigh && close1 > breakoutHigh);
   bool sellSignal = (trend == "BEAR" && close2 >= breakoutLow && close1 < breakoutLow);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      double sl = NormalizeDouble(ask - atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "MTF Breakout BUY"))
      {
         tradesToday++;
         lastSignalBar = currentBar;
      }
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(bid + atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(bid - atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "MTF Breakout SELL"))
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
