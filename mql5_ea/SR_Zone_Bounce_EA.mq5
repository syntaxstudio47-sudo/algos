#property strict
input string EA_Comment = "SR_BOUNCE";
input int MagicNumber = 200007;
input int SwingLookback = 200;
input int PivotStrength = 3;
input double ZoneThresholdPips = 10.0;
input int MinTouches = 2;
input int MaxZones = 20;
input double ZoneEntryBufferPips = 3.0;
input bool UsePinBarFilter = true;
input bool UseEngulfingFilter = true;
input double WickRatio = 1.5;
input double LotSize = 0.1;
input double ATR_SL_Mult = 1.5;
input double ATR_TP_Mult = 3.0;
input int ATR_Period = 14;
input int Slippage = 10;
input int MaxTradesPerDay = 3;
int hATR;
struct SRZone{ double price_level; double zone_top; double zone_bottom; int touches; string zone_type; bool active; };
SRZone Zones[]; int ZoneCount=0; int TradesToday=0; datetime LastTradeDay=0;
int OnInit(){ hATR=iATR(_Symbol,PERIOD_CURRENT,ATR_Period); if(hATR==INVALID_HANDLE){ Print("ERROR: ATR handle failed."); return(INIT_FAILED);} ArrayResize(Zones,MaxZones); Print("SR Zone Bounce EA initialized on ",_Symbol); return(INIT_SUCCEEDED);} 
void OnDeinit(const int reason){ IndicatorRelease(hATR);} 
double GetATR(int bar=1){ double atr[]; ArraySetAsSeries(atr,true); if(CopyBuffer(hATR,0,bar,1,atr)<1) return 0; return atr[0]; }
double PipSize(){ return (_Digits==5||_Digits==3)?_Point*10:_Point; }
double PipsToPrice(double pips){ return pips*PipSize(); }
bool IsSwingHigh(int bar){ double high_center=iHigh(_Symbol,PERIOD_CURRENT,bar); for(int i=1;i<=PivotStrength;i++){ if(iHigh(_Symbol,PERIOD_CURRENT,bar+i)>=high_center) return false; if(iHigh(_Symbol,PERIOD_CURRENT,bar-i)>=high_center) return false; } return true; }
bool IsSwingLow(int bar){ double low_center=iLow(_Symbol,PERIOD_CURRENT,bar); for(int i=1;i<=PivotStrength;i++){ if(iLow(_Symbol,PERIOD_CURRENT,bar+i)<=low_center) return false; if(iLow(_Symbol,PERIOD_CURRENT,bar-i)<=low_center) return false; } return true; }
void BuildZones(){ ZoneCount=0; double merge_threshold=PipsToPrice(ZoneThresholdPips); double raw_levels[]; string raw_types[]; int raw_count=0; ArrayResize(raw_levels,SwingLookback); ArrayResize(raw_types,SwingLookback); for(int i=PivotStrength+1;i<SwingLookback-PivotStrength;i++){ if(IsSwingHigh(i)){ raw_levels[raw_count]=iHigh(_Symbol,PERIOD_CURRENT,i); raw_types[raw_count]="RESISTANCE"; raw_count++; } if(IsSwingLow(i)){ raw_levels[raw_count]=iLow(_Symbol,PERIOD_CURRENT,i); raw_types[raw_count]="SUPPORT"; raw_count++; } if(raw_count>=SwingLookback-1) break; } bool merged[]; ArrayResize(merged,raw_count); ArrayInitialize(merged,false); for(int i=0;i<raw_count&&ZoneCount<MaxZones;i++){ if(merged[i]) continue; double zone_sum=raw_levels[i]; int zone_count=1; string zone_type=raw_types[i]; int touches=1; for(int j=i+1;j<raw_count;j++){ if(!merged[j]&&MathAbs(raw_levels[j]-raw_levels[i])<=merge_threshold){ zone_sum+=raw_levels[j]; zone_count++; touches++; merged[j]=true; if(raw_types[j]!=zone_type) zone_type="BOTH"; } } if(touches>=MinTouches){ double zone_center=zone_sum/zone_count; Zones[ZoneCount].price_level=zone_center; Zones[ZoneCount].zone_top=zone_center+merge_threshold*0.5; Zones[ZoneCount].zone_bottom=zone_center-merge_threshold*0.5; Zones[ZoneCount].touches=touches; Zones[ZoneCount].zone_type=zone_type; Zones[ZoneCount].active=true; ZoneCount++; } merged[i]=true; } PrintFormat("SR Zones built: %d zones detected.",ZoneCount); }
int FindNearestZone(double current_price){ double entry_buffer=PipsToPrice(ZoneEntryBufferPips); int best_idx=-1; double best_dist=DBL_MAX; for(int i=0;i<ZoneCount;i++){ if(!Zones[i].active) continue; double dist=MathAbs(current_price-Zones[i].price_level); if(dist<=entry_buffer&&dist<best_dist){ best_dist=dist; best_idx=i; } } return best_idx; }
bool IsBullishPinBar(int bar){ double o=iOpen(_Symbol,PERIOD_CURRENT,bar), h=iHigh(_Symbol,PERIOD_CURRENT,bar), l=iLow(_Symbol,PERIOD_CURRENT,bar), c=iClose(_Symbol,PERIOD_CURRENT,bar); double body=MathAbs(c-o); if(body==0) return false; double lower_wick=MathMin(o,c)-l; double upper_wick=h-MathMax(o,c); return (c>=o&&lower_wick>=WickRatio*body&&upper_wick<=body*0.5); }
bool IsBearishPinBar(int bar){ double o=iOpen(_Symbol,PERIOD_CURRENT,bar), h=iHigh(_Symbol,PERIOD_CURRENT,bar), l=iLow(_Symbol,PERIOD_CURRENT,bar), c=iClose(_Symbol,PERIOD_CURRENT,bar); double body=MathAbs(c-o); if(body==0) return false; double upper_wick=h-MathMax(o,c); double lower_wick=MathMin(o,c)-l; return (c<=o&&upper_wick>=WickRatio*body&&lower_wick<=body*0.5); }
bool IsBullishEngulfing(int bar){ double o1=iOpen(_Symbol,PERIOD_CURRENT,bar+1), c1=iClose(_Symbol,PERIOD_CURRENT,bar+1), o2=iOpen(_Symbol,PERIOD_CURRENT,bar), c2=iClose(_Symbol,PERIOD_CURRENT,bar); return (c1<o1&&c2>o2&&o2<c1&&c2>o1); }
bool IsBearishEngulfing(int bar){ double o1=iOpen(_Symbol,PERIOD_CURRENT,bar+1), c1=iClose(_Symbol,PERIOD_CURRENT,bar+1), o2=iOpen(_Symbol,PERIOD_CURRENT,bar), c2=iClose(_Symbol,PERIOD_CURRENT,bar); return (c1>o1&&c2<o2&&o2>c1&&c2<o1); }
bool HasBullishConfirmation(int bar){ if(UsePinBarFilter&&IsBullishPinBar(bar)) return true; if(UseEngulfingFilter&&IsBullishEngulfing(bar)) return true; return false; }
bool HasBearishConfirmation(int bar){ if(UsePinBarFilter&&IsBearishPinBar(bar)) return true; if(UseEngulfingFilter&&IsBearishEngulfing(bar)) return true; return false; }
int CountOpenPositions(){ int count=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong ticket=PositionGetTicket(i); if(PositionSelectByTicket(ticket)) if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MagicNumber) count++; } return count; }
bool PlaceOrder(string direction,int zone_idx){ double atr=GetATR(1); if(atr==0) return false; MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false; double entry=(direction=="BUY")?tick.ask:tick.bid; double sl=(direction=="BUY")?entry-atr*ATR_SL_Mult:entry+atr*ATR_SL_Mult; double tp=(direction=="BUY")?entry+atr*ATR_TP_Mult:entry-atr*ATR_TP_Mult; sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits); MqlTradeRequest req={}; MqlTradeResult res={}; req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize; req.type=(direction=="BUY")?ORDER_TYPE_BUY:ORDER_TYPE_SELL; req.price=entry; req.sl=sl; req.tp=tp; req.deviation=Slippage; req.magic=MagicNumber; req.comment=EA_Comment+"_"+direction+"_Z"+IntegerToString(zone_idx)+"_T"+IntegerToString(Zones[zone_idx].touches); req.type_time=ORDER_TIME_GTC; req.type_filling=ORDER_FILLING_IOC; if(OrderSend(req,res)&&res.retcode==TRADE_RETCODE_DONE){ TradesToday++; PrintFormat("SR Bounce order: %s | Zone: %.5f (touches: %d) | Entry: %.5f | SL: %.5f | TP: %.5f",direction,Zones[zone_idx].price_level,Zones[zone_idx].touches,entry,sl,tp); return true; } PrintFormat("Order FAILED: %d | %s",res.retcode,res.comment); return false; }
void CheckDailyReset(){ datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE)); if(today!=LastTradeDay){ TradesToday=0; LastTradeDay=today; } }
void OnTick(){ static datetime last_bar=0; datetime current_bar=iTime(_Symbol,PERIOD_CURRENT,0); if(current_bar==last_bar) return; last_bar=current_bar; CheckDailyReset(); static int bar_counter=0; bar_counter++; if(bar_counter%50==0||ZoneCount==0) BuildZones(); if(CountOpenPositions()>0) return; if(TradesToday>=MaxTradesPerDay) return; double current_price=iClose(_Symbol,PERIOD_CURRENT,1); int zone_idx=FindNearestZone(current_price); if(zone_idx<0) return; SRZone z=Zones[zone_idx]; if((z.zone_type=="SUPPORT"||z.zone_type=="BOTH")){ if(current_price<=z.zone_top&&HasBullishConfirmation(1)) PlaceOrder("BUY",zone_idx); } if((z.zone_type=="RESISTANCE"||z.zone_type=="BOTH")){ if(current_price>=z.zone_bottom&&HasBearishConfirmation(1)) PlaceOrder("SELL",zone_idx); } }
