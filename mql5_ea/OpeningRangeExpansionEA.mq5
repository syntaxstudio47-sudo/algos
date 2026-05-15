#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int SessionBars=6;
input int ATRPeriod=14;
input double RangeATRMult=0.8;
input double ATRSLMult=1.3;
input double RR=2.5;
input int MaxTradesPerDay=1;
input ulong Magic=620004;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
int BarsToday(){ MqlDateTime d0,d1; TimeToStruct(iTime(_Symbol,_Period,1),d0); int count=0; for(int i=1;i<200;i++){ datetime t=iTime(_Symbol,_Period,i); if(t==0) break; TimeToStruct(t,d1); if(d1.year==d0.year && d1.mon==d0.mon && d1.day==d0.day) count++; else break; } return count; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; int bt=BarsToday(); if(bt<SessionBars+2) return; double atr=ATR(); if(atr<=0) return; double hi=-DBL_MAX, lo=DBL_MAX; for(int i=bt;i>bt-SessionBars;i--){ hi=MathMax(hi,iHigh(_Symbol,_Period,i)); lo=MathMin(lo,iLow(_Symbol,_Period,i)); }
 if((hi-lo)<atr*RangeATRMult) return; double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(c2<=hi && c1>hi){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"OpeningRangeExpansionBuy")) tradesToday++; }
 else if(c2>=lo && c1<lo){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"OpeningRangeExpansionSell")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
