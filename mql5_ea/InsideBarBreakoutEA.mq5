#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input int ATRPeriod = 14;
input double BreakoutBufferPips = 1.0;
input double ATR_SL_Mult = 1.0;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 3;
input ulong MagicNumber = 220004;
