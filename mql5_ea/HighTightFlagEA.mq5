#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int PoleBars=30;
input int FlagBars=15;
input int ATRPeriod=14;
input double ATRSLMult=1.5;
input double RR=3.0;
input int MaxTradesPerDay=1;
input ulong Magic=620009;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double start=iOpen(_Symbol,_Period,PoleBars+FlagBars), end=iClose(_Symbol,_Period,FlagBars+1); if(start<=0) return; double gain=(end-start)/start; if(gain<0.08) return; double flagHigh=-DBL_MAX, flagLow=DBL_MAX; for(int i=2;i<FlagBars+2;i++){ flagHigh=MathMax(flagHigh,iHigh(_Symbol,_Period,i)); flagLow=MathMin(flagLow,iLow(_Symbol,_Period,i)); }
 if(flagLow<end*0.9) return; double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(c2<=flagHigh && c1>flagHigh){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"HighTightFlag")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
