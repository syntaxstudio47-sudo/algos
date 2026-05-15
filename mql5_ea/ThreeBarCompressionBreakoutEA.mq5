#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int ATRPeriod=14;
input double CompressionATRRatio=0.9;
input double ATRSLMult=1.2;
input double RR=2.3;
input int MaxTradesPerDay=2;
input ulong Magic=620015;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double r1=iHigh(_Symbol,_Period,1)-iLow(_Symbol,_Period,1), r2=iHigh(_Symbol,_Period,2)-iLow(_Symbol,_Period,2), r3=iHigh(_Symbol,_Period,3)-iLow(_Symbol,_Period,3); if(r1>atr*CompressionATRRatio || r2>atr*CompressionATRRatio || r3>atr*CompressionATRRatio) return; double hi=MathMax(iHigh(_Symbol,_Period,2),iHigh(_Symbol,_Period,3)); hi=MathMax(hi,iHigh(_Symbol,_Period,1)); double lo=MathMin(iLow(_Symbol,_Period,2),iLow(_Symbol,_Period,3)); lo=MathMin(lo,iLow(_Symbol,_Period,1)); double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(c2<=hi && c1>hi){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"CompressionBreakoutBuy")) tradesToday++; }
 else if(c2>=lo && c1<lo){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"CompressionBreakoutSell")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
