#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double Lots = 0.10;
input double BreakoutBufferPips = 1.0;
input int ATRPeriod = 14;
input double ATR_SL_Mult = 1.2;
input double RR_Multiple = 2.5;
input int MaxTradesPerDay = 2;
input ulong MagicNumber = 220003;
