#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int ATRPeriod=14;
input double ATRSLMult=1.4;
input double RR=2.5;
input int MaxTradesPerDay=2;
input ulong Magic=620003;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
bool Levels(double &r1,double &s1){ MqlRates rates[]; ArraySetAsSeries(rates,true); if(CopyRates(_Symbol,PERIOD_D1,1,2,rates)<2) return false; double p=(rates[1].high+rates[1].low+rates[1].close)/3.0; r1=2*p-rates[1].low; s1=2*p-rates[1].high; return true; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(), r1,s1; if(atr<=0 || !Levels(r1,s1)) return; double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(c2<=r1 && c1>r1){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"PivotBreakoutBuy")) tradesToday++; }
 else if(c2>=s1 && c1<s1){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"PivotBreakoutSell")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
