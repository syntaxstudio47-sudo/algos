#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int BBPeriod=20;
input double BBDev=2.0;
input int ATRPeriod=14;
input double SqueezeATRRatio=1.8;
input double ATRSLMult=1.4;
input double RR=2.6;
input int MaxTradesPerDay=2;
input ulong Magic=620012;
datetime lastBar=0; int tradesToday=0, atrHandle, bbHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool BB(double &upper,double &lower){ double up[], lo[]; ArraySetAsSeries(up,true); ArraySetAsSeries(lo,true); if(CopyBuffer(bbHandle,1,0,2,up)<2) return false; if(CopyBuffer(bbHandle,2,0,2,lo)<2) return false; upper=up[1]; lower=lo[1]; return true; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(), upper, lower; if(atr<=0 || !BB(upper,lower)) return; if((upper-lower) > atr*SqueezeATRRatio) return; double h1=iHigh(_Symbol,_Period,1), l1=iLow(_Symbol,_Period,1), c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); trade.SetExpertMagicNumber(Magic);
 if(h1>upper && c2<=upper && c1>upper){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"VolatilitySqueezeBuy")) tradesToday++; }
 else if(l1<lower && c2>=lower && c1<lower){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); double sl=bid+atr*ATRSLMult; double tp=bid-atr*ATRSLMult*RR; if(trade.Sell(Lots,_Symbol,bid,sl,tp,"VolatilitySqueezeSell")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); bbHandle=iBands(_Symbol,_Period,BBPeriod,0,BBDev,PRICE_CLOSE); return (atrHandle==INVALID_HANDLE||bbHandle==INVALID_HANDLE)?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); if(bbHandle!=INVALID_HANDLE) IndicatorRelease(bbHandle); }
