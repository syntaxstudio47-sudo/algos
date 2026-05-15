#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int ImpulseBars=15;
input int PullbackBars=10;
input int ATRPeriod=14;
input double MinImpulseATR=2.0;
input double ATRSLMult=1.4;
input double RR=2.8;
input int MaxTradesPerDay=2;
input ulong Magic=620014;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double start=iOpen(_Symbol,_Period,ImpulseBars+PullbackBars), end=iClose(_Symbol,_Period,PullbackBars+1); double impulse=MathAbs(end-start); if(impulse<atr*MinImpulseATR) return; double hi=-DBL_MAX, lo=DBL_MAX; for(int i=2;i<PullbackBars+2;i++){ hi=MathMax(hi,iHigh(_Symbol,_Period,i)); lo=MathMin(lo,iLow(_Symbol,_Period,i)); }
 double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(end>start && c2<=hi && c1>hi){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"MeasuredMoveBuy")) tradesToday++; }
 else if(end<start && c2>=lo && c1<lo){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"MeasuredMoveSell")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
