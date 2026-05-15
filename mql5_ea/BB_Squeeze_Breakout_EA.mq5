#property strict
input string EA_Comment = "BB_SQUEEZE";
input int MagicNumber = 200006;
input int BB_Period = 20;
input double BB_Deviation = 2.0;
input int KC_Period = 20;
input double KC_Multiplier = 1.5;
input int ATR_Period = 14;
input int Squeeze_Bars = 5;
input double LotSize = 0.1;
input double ATR_SL_Mult = 1.5;
input double ATR_TP_Mult = 3.0;
input int Slippage = 10;
input bool AllowBuy = true;
input bool AllowSell = true;
int hBB, hATR, hEMA;
int OnInit(){ hBB=iBands(_Symbol,PERIOD_CURRENT,BB_Period,0,BB_Deviation,PRICE_CLOSE); hATR=iATR(_Symbol,PERIOD_CURRENT,ATR_Period); hEMA=iMA(_Symbol,PERIOD_CURRENT,KC_Period,0,MODE_EMA,PRICE_CLOSE); if(hBB==INVALID_HANDLE||hATR==INVALID_HANDLE||hEMA==INVALID_HANDLE){ Print("ERROR: Failed to create indicator handles."); return(INIT_FAILED);} Print("BB Squeeze EA initialized on ",_Symbol); return(INIT_SUCCEEDED);} 
void OnDeinit(const int reason){ IndicatorRelease(hBB); IndicatorRelease(hATR); IndicatorRelease(hEMA);} 
int CountOpenPositions(){ int count=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong ticket=PositionGetTicket(i); if(PositionSelectByTicket(ticket)) if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MagicNumber) count++; } return count; }
double GetATR(int bar){ double atr[]; ArraySetAsSeries(atr,true); if(CopyBuffer(hATR,0,bar,1,atr)<1) return 0; return atr[0]; }
bool GetKeltner(int bar,double &kc_upper,double &kc_lower){ double ema[]; double atr[]; ArraySetAsSeries(ema,true); ArraySetAsSeries(atr,true); if(CopyBuffer(hEMA,0,bar,1,ema)<1) return false; if(CopyBuffer(hATR,0,bar,1,atr)<1) return false; kc_upper=ema[0]+KC_Multiplier*atr[0]; kc_lower=ema[0]-KC_Multiplier*atr[0]; return true; }
bool GetBB(int bar,double &bb_upper,double &bb_mid,double &bb_lower){ double upper[],mid[],lower[]; ArraySetAsSeries(upper,true); ArraySetAsSeries(mid,true); ArraySetAsSeries(lower,true); if(CopyBuffer(hBB,1,bar,1,upper)<1) return false; if(CopyBuffer(hBB,0,bar,1,mid)<1) return false; if(CopyBuffer(hBB,2,bar,1,lower)<1) return false; bb_upper=upper[0]; bb_mid=mid[0]; bb_lower=lower[0]; return true; }
bool IsSqueezeActive(){ for(int i=1;i<=Squeeze_Bars;i++){ double bb_upper,bb_mid,bb_lower,kc_upper,kc_lower; if(!GetBB(i,bb_upper,bb_mid,bb_lower)) return false; if(!GetKeltner(i,kc_upper,kc_lower)) return false; if(!(bb_upper<kc_upper&&bb_lower>kc_lower)) return false; } return true; }
string GetBreakoutDirection(){ double bb_upper_now,bb_mid_now,bb_lower_now,kc_upper_now,kc_lower_now,bb_upper_prev,bb_mid_prev,bb_lower_prev,kc_upper_prev,kc_lower_prev; if(!GetBB(1,bb_upper_now,bb_mid_now,bb_lower_now)) return "NONE"; if(!GetKeltner(1,kc_upper_now,kc_lower_now)) return "NONE"; if(!GetBB(2,bb_upper_prev,bb_mid_prev,bb_lower_prev)) return "NONE"; if(!GetKeltner(2,kc_upper_prev,kc_lower_prev)) return "NONE"; bool prev_squeezed=(bb_upper_prev<kc_upper_prev&&bb_lower_prev>kc_lower_prev); bool now_expanded=(bb_upper_now>kc_upper_now||bb_lower_now<kc_lower_now); if(!prev_squeezed||!now_expanded) return "NONE"; double close[]; ArraySetAsSeries(close,true); if(CopyClose(_Symbol,PERIOD_CURRENT,1,1,close)<1) return "NONE"; return (close[0]>bb_mid_now)?"BUY":"SELL"; }
bool PlaceOrder(string direction){ double atr=GetATR(1); if(atr==0) return false; MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false; double entry=(direction=="BUY")?tick.ask:tick.bid; double sl=(direction=="BUY")?entry-atr*ATR_SL_Mult:entry+atr*ATR_SL_Mult; double tp=(direction=="BUY")?entry+atr*ATR_TP_Mult:entry-atr*ATR_TP_Mult; sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits); MqlTradeRequest req={}; MqlTradeResult res={}; req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize; req.type=(direction=="BUY")?ORDER_TYPE_BUY:ORDER_TYPE_SELL; req.price=entry; req.sl=sl; req.tp=tp; req.deviation=Slippage; req.magic=MagicNumber; req.comment=EA_Comment+"_"+direction; req.type_time=ORDER_TIME_GTC; req.type_filling=ORDER_FILLING_IOC; if(OrderSend(req,res)){ if(res.retcode==TRADE_RETCODE_DONE){ PrintFormat("Order placed: %s | Entry: %.5f | SL: %.5f | TP: %.5f | ATR: %.5f",direction,entry,sl,tp,atr); return true; } } PrintFormat("Order FAILED: retcode=%d | %s",res.retcode,res.comment); return false; }
void OnTick(){ static datetime last_bar_time=0; datetime current_bar=iTime(_Symbol,PERIOD_CURRENT,0); if(current_bar==last_bar_time) return; last_bar_time=current_bar; if(CountOpenPositions()>0) return; if(!IsSqueezeActive()) return; string direction=GetBreakoutDirection(); if(direction=="NONE") return; if(direction=="BUY"&&!AllowBuy) return; if(direction=="SELL"&&!AllowSell) return; PlaceOrder(direction); }
