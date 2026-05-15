#property strict
input string EA_Comment = "MACD_VOL";
input int MagicNumber = 200008;
input int MACD_Fast = 12;
input int MACD_Slow = 26;
input int MACD_Signal = 9;
input ENUM_APPLIED_PRICE MACD_Price = PRICE_CLOSE;
input int Volume_MA_Period = 20;
input double Volume_Mult = 1.3;
input double Min_Histogram_Size = 0.00005;
input bool RequireHistoExpanding = true;
input bool RequireZeroCross = false;
input bool TradeWithTrend = true;
input double LotSize = 0.1;
input double ATR_SL_Mult = 1.5;
input double ATR_TP_Mult = 3.0;
input int ATR_Period = 14;
input int Slippage = 10;
input int MaxTradesPerDay = 4;
input int CooldownBars = 3;
int hMACD, hATR, hVolMA;
int TradesToday = 0; datetime LastTradeDay = 0; int LastTradeBar = 0;
int OnInit(){ hMACD=iMACD(_Symbol,PERIOD_CURRENT,MACD_Fast,MACD_Slow,MACD_Signal,MACD_Price); hATR=iATR(_Symbol,PERIOD_CURRENT,ATR_Period); hVolMA=iMA(_Symbol,PERIOD_CURRENT,Volume_MA_Period,0,MODE_SMA,VOLUME_TICK); if(hMACD==INVALID_HANDLE||hATR==INVALID_HANDLE||hVolMA==INVALID_HANDLE){ Print("ERROR: Failed to create indicator handles."); return INIT_FAILED;} Print("MACD Volume EA initialized on ",_Symbol); return INIT_SUCCEEDED; }
void OnDeinit(const int reason){ IndicatorRelease(hMACD); IndicatorRelease(hATR); IndicatorRelease(hVolMA); }
double GetMACDLine(int bar){ double buf[]; ArraySetAsSeries(buf,true); if(CopyBuffer(hMACD,0,bar,1,buf)<1) return 0; return buf[0]; }
double GetSignalLine(int bar){ double buf[]; ArraySetAsSeries(buf,true); if(CopyBuffer(hMACD,1,bar,1,buf)<1) return 0; return buf[0]; }
double GetHistogram(int bar){ double buf[]; ArraySetAsSeries(buf,true); if(CopyBuffer(hMACD,2,bar,1,buf)<1) return 0; return buf[0]; }
double GetATR(int bar=1){ double buf[]; ArraySetAsSeries(buf,true); if(CopyBuffer(hATR,0,bar,1,buf)<1) return 0; return buf[0]; }
double GetVolumeMA(int bar){ double buf[]; ArraySetAsSeries(buf,true); if(CopyBuffer(hVolMA,0,bar,1,buf)<1) return 0; return buf[0]; }
double GetVolume(int bar){ long vol[]; ArraySetAsSeries(vol,true); if(CopyTickVolume(_Symbol,PERIOD_CURRENT,bar,1,vol)<1) return 0; return (double)vol[0]; }
string GetTradeSignal(){ double macd_now=GetMACDLine(1), macd_prev=GetMACDLine(2), sig_now=GetSignalLine(1), sig_prev=GetSignalLine(2), histo_now=GetHistogram(1), histo_prev=GetHistogram(2), vol_now=GetVolume(1), vol_ma=GetVolumeMA(1); bool vol_confirmed=(vol_ma>0&&vol_now>=vol_ma*Volume_Mult); bool macd_cross_up=(macd_prev<=sig_prev)&&(macd_now>sig_now); bool histo_positive=(histo_now>Min_Histogram_Size); bool histo_expanding_up=(!RequireHistoExpanding)||(histo_now>histo_prev); bool zero_filter_buy=(!TradeWithTrend)||(macd_now>0); bool zero_cross_buy=(!RequireZeroCross)||(macd_prev<=0&&macd_now>0); if(macd_cross_up&&vol_confirmed&&histo_positive&&histo_expanding_up&&zero_filter_buy&&zero_cross_buy) return "BUY"; bool macd_cross_down=(macd_prev>=sig_prev)&&(macd_now<sig_now); bool histo_negative=(histo_now<-Min_Histogram_Size); bool histo_expanding_dn=(!RequireHistoExpanding)||(histo_now<histo_prev); bool zero_filter_sell=(!TradeWithTrend)||(macd_now<0); bool zero_cross_sell=(!RequireZeroCross)||(macd_prev>=0&&macd_now<0); if(macd_cross_down&&vol_confirmed&&histo_negative&&histo_expanding_dn&&zero_filter_sell&&zero_cross_sell) return "SELL"; return "NONE"; }
int CountPositions(){ int count=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong ticket=PositionGetTicket(i); if(PositionSelectByTicket(ticket)) if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MagicNumber) count++; } return count; }
void CheckDailyReset(){ datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE)); if(today!=LastTradeDay){ TradesToday=0; LastTradeDay=today; } }
bool PlaceOrder(string direction){ double atr=GetATR(1); if(atr==0) return false; MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false; double entry=(direction=="BUY")?tick.ask:tick.bid; double sl=(direction=="BUY")?entry-atr*ATR_SL_Mult:entry+atr*ATR_SL_Mult; double tp=(direction=="BUY")?entry+atr*ATR_TP_Mult:entry-atr*ATR_TP_Mult; sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits); double macd_val=GetMACDLine(1), sig_val=GetSignalLine(1), histo_val=GetHistogram(1), vol_now=GetVolume(1), vol_ma=GetVolumeMA(1); MqlTradeRequest req={}; MqlTradeResult res={}; req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize; req.type=(direction=="BUY")?ORDER_TYPE_BUY:ORDER_TYPE_SELL; req.price=entry; req.sl=sl; req.tp=tp; req.deviation=Slippage; req.magic=MagicNumber; req.comment=StringFormat("%s_%s_H%.5f_V%.0f",EA_Comment,direction,histo_val,vol_now); req.type_time=ORDER_TIME_GTC; req.type_filling=ORDER_FILLING_IOC; if(OrderSend(req,res)&&res.retcode==TRADE_RETCODE_DONE){ TradesToday++; PrintFormat("MACD Order: %s | Entry: %.5f | SL: %.5f | TP: %.5f | MACD: %.5f | Signal: %.5f | Histo: %.5f | Volume: %.0f | Vol MA: %.0f",direction,entry,sl,tp,macd_val,sig_val,histo_val,vol_now,vol_ma); return true; } PrintFormat("Order FAILED: %d | %s",res.retcode,res.comment); return false; }
void OnTick(){ static datetime last_bar=0; datetime current_bar=iTime(_Symbol,PERIOD_CURRENT,0); if(current_bar==last_bar) return; last_bar=current_bar; int current_bar_idx=Bars(_Symbol,PERIOD_CURRENT); CheckDailyReset(); if(CountPositions()>0) return; if(TradesToday>=MaxTradesPerDay) return; if(current_bar_idx-LastTradeBar<CooldownBars) return; string signal=GetTradeSignal(); if(signal=="NONE") return; if(PlaceOrder(signal)) LastTradeBar=current_bar_idx; }
