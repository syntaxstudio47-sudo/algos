#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input int BBPeriod = 20;
input double BBDeviation = 2.0;
input int KCPeriod = 20;
input double KCMultiplier = 1.5;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.5;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 440006;

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

double GetATR(int period)
{
   int handle = iATR(_Symbol, PERIOD_CURRENT, period);
   if(handle == INVALID_HANDLE) return 0.0;
   double atr[];
   if(CopyBuffer(handle, 0, 1, 1, atr) <= 0) return 0.0;
   return atr[0];
}

bool GetBands(double &bbUpper, double &bbLower, double &kcUpper, double &kcLower, double &close1)
{
   int bbHandle = iBands(_Symbol, PERIOD_CURRENT, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
   if(bbHandle == INVALID_HANDLE) return false;

   double upperBuf[], lowerBuf[];
   if(CopyBuffer(bbHandle, 1, 1, 1, upperBuf) <= 0) return false;
   if(CopyBuffer(bbHandle, 2, 1, 1, lowerBuf) <= 0) return false;

   double ema = iMA(_Symbol, PERIOD_CURRENT, KCPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atrKC = GetATR(KCPeriod);
   if(ema == 0 || atrKC == 0) return false;

   bbUpper = upperBuf[0];
   bbLower = lowerBuf[0];
   kcUpper = ema + atrKC * KCMultiplier;
   kcLower = ema - atrKC * KCMultiplier;
   close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
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

   double bbUpper, bbLower, kcUpper, kcLower, close1;
   if(!GetBands(bbUpper, bbLower, kcUpper, kcLower, close1)) return;

   double atr = GetATR(ATRPeriod);
   if(atr <= 0) return;

   bool squeezeReleased = (bbUpper > kcUpper || bbLower < kcLower);
   bool buySignal = squeezeReleased && close1 > bbUpper;
   bool sellSignal = squeezeReleased && close1 < bbLower;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      double sl = NormalizeDouble(ask - atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_SL_Mult * RR_Multiple, _Digits);
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "Squeeze Breakout BUY"))
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
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "Squeeze Breakout SELL"))
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
