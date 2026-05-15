#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input int DonchianPeriod = 20;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.5;
input double RR_Multiple = 2.5;
input double BreakoutBufferPips = 1.0;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 220001;

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
         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(symbol == _Symbol && magic == (long)MagicNumber)
            return true;
      }
   }
   return false;
}
