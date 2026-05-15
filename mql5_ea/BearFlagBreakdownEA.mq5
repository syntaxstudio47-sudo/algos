#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int ImpulseBars=20;
input int FlagBars=12;
input int ATRPeriod=14;
input double ATRSLMult=1.4;
input double RR=2.8;
input int MaxTradesPerDay=2;
input ulong Magic=620007;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double impulseOpen=iOpen(_Symbol,_Period,ImpulseBars+FlagBars); double impulseClose=iClose(_Symbol,_Period,FlagBars+1); double drop=impulseOpen-impulseClose; if(drop<2.0*atr) return; double pivot=DBL_MAX;
 for(int i=2;i<FlagBars+2;i++) pivot=MathMin(pivot,iLow(_Symbol,_Period,i)); double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(c2>=pivot && c1<pivot){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"BearFlagBreakdown")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
