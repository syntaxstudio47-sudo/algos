#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input int ATRPeriod = 14;
input double MinBodyATRMult = 1.2;
input double ATR_SL_Mult = 1.2;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 440010;

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

void CheckForSignal()
{
   if(!IsNewBar()) return;
   ResetDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return;
   if(HasOpenPosition()) return;

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(lastSignalBar == currentBar) return;

   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double body = MathAbs(close1 - open1);
   double atr = GetATR();
   if(atr <= 0) return;

   double ratio = body / atr;
   bool buySignal = (close1 > open1 && ratio >= MinBodyATRMult);
   bool sellSignal = (close1 < open1 && ratio >= MinBodyATRMult);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      double sl = NormalizeDouble(ask - atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "Momentum Candle BUY"))
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
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "Momentum Candle SELL"))
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
