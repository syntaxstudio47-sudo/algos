#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int Lookback=50;
input int ATRPeriod=14;
input double ATRBuffer=0.25;
input double RR=2.0;
input int MaxTradesPerDay=2;
input ulong Magic=620001;
datetime lastBar=0,lastTradeBar=0;
int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double high=-DBL_MAX, low=DBL_MAX; for(int i=2;i<Lookback+2;i++){ high=MathMax(high,iHigh(_Symbol,_Period,i)); low=MathMin(low,iLow(_Symbol,_Period,i)); }
 double close1=iClose(_Symbol,_Period,1); double close2=iClose(_Symbol,_Period,2); double up=high+atr*ATRBuffer, dn=low-atr*ATRBuffer; trade.SetExpertMagicNumber(Magic);
 if(close2<=up && close1>up){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=low; double tp=ask+(ask-sl)*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"DarvasBoxBreakout")){ tradesToday++; lastTradeBar=lastBar; }}
 else if(close2>=dn && close1<dn){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=high; double tp=bid-(sl-bid)*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"DarvasBoxBreakdown")){ tradesToday++; lastTradeBar=lastBar; }} }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
