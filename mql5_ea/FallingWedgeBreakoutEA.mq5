#property strict
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int Lookback=35;
input int ATRPeriod=14;
input double ATRSLMult=1.4;
input double RR=2.6;
input int MaxTradesPerDay=2;
input ulong Magic=620010;
datetime lastBar=0; int tradesToday=0, atrHandle;

bool NewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t!=lastBar){ lastBar=t; return true;} return false; }
void ResetDay(){ static int lastDay=-1; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day!=lastDay){ tradesToday=0; lastDay=dt.day; } }
double ATR(){ double b[]; ArraySetAsSeries(b,true); if(CopyBuffer(atrHandle,0,0,2,b)<2) return 0; return b[0]; }
bool HasPosition(){ for(int i=0;i<PositionsTotal();i++){ ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionSelectByTicket(ticket)){ if((string)PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true; }} return false; }
double Slope(const double &arr[]){ int n=ArraySize(arr); double sx=0,sy=0,sxy=0,sx2=0; for(int i=0;i<n;i++){ sx+=i; sy+=arr[i]; sxy+=i*arr[i]; sx2+=i*i; } double den=n*sx2-sx*sx; if(den==0) return 0; return (n*sxy-sx*sy)/den; }
void OnTick(){ if(!NewBar()) return; ResetDay(); if(tradesToday>=MaxTradesPerDay || HasPosition()) return; double atr=ATR(); if(atr<=0) return; double highs[], lows[]; ArrayResize(highs,Lookback); ArrayResize(lows,Lookback); double resistance=-DBL_MAX;
 for(int i=0;i<Lookback;i++){ highs[i]=iHigh(_Symbol,_Period,Lookback-i); lows[i]=iLow(_Symbol,_Period,Lookback-i); resistance=MathMax(resistance,highs[i]); }
 double hs=Slope(highs), ls=Slope(lows), c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2); if(!(hs<0 && ls<0 && MathAbs(hs)>MathAbs(ls))) return; trade.SetExpertMagicNumber(Magic);
 if(c2<=resistance && c1>resistance){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double sl=ask-atr*ATRSLMult; double tp=ask+atr*ATRSLMult*RR; if(trade.Buy(Lots,_Symbol,ask,sl,tp,"FallingWedgeBreakout")) tradesToday++; } }
int OnInit(){ atrHandle=iATR(_Symbol,_Period,ATRPeriod); return atrHandle==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }
void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }
