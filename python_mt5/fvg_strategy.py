import MetaTrader5 as mt5
import pandas as pd
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import pytz

@dataclass
class FVGZone:
    direction: str
    gap_high: float
    gap_low: float
    gap_size: float
    formed_at: datetime
    candle_index: int
    filled: bool = False
    trade_taken: bool = False

class FVGStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_M15,
        lot_size: float = 0.1,
        risk_reward: float = 2.0,
        sl_buffer_pips: float = 5.0,
        min_gap_pips: float = 3.0,
        max_active_zones: int = 5,
        magic: int = 100002,
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.risk_reward = risk_reward
        self.sl_buffer_pips = sl_buffer_pips
        self.min_gap_pips = min_gap_pips
        self.max_active_zones = max_active_zones
        self.magic = magic
        self.tz = pytz.timezone(timezone)
        self.active_zones: list[FVGZone] = []
        self._pip_size: Optional[float] = None

    def _get_pip_size(self) -> float:
        if self._pip_size:
            return self._pip_size
        info = mt5.symbol_info(self.symbol)
        self._pip_size = info.point * 10 if info else 0.0001
        return self._pip_size

    def _pips_to_price(self, pips: float) -> float:
        return pips * self._get_pip_size()

    def get_candles(self, count: int = 200) -> pd.DataFrame:
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["time"] = df["time"].dt.tz_convert(self.tz)
        return df.reset_index(drop=True)

    def detect_fvg_zones(self, df: pd.DataFrame) -> list[FVGZone]:
        new_zones = []
        min_gap = self._pips_to_price(self.min_gap_pips)
        scan_start = max(2, len(df) - 50)
        for i in range(scan_start, len(df)):
            c1 = df.iloc[i - 2]
            c3 = df.iloc[i]
            if c3["low"] > c1["high"]:
                gap_size = c3["low"] - c1["high"]
                if gap_size >= min_gap:
                    zone = FVGZone("BULLISH", c3["low"], c1["high"], gap_size, c3["time"], i)
                    if not self._zone_exists(zone):
                        new_zones.append(zone)
            elif c1["low"] > c3["high"]:
                gap_size = c1["low"] - c3["high"]
                if gap_size >= min_gap:
                    zone = FVGZone("BEARISH", c1["low"], c3["high"], gap_size, c3["time"], i)
                    if not self._zone_exists(zone):
                        new_zones.append(zone)
        return new_zones

    def _zone_exists(self, new_zone: FVGZone) -> bool:
        for z in self.active_zones:
            if z.direction == new_zone.direction and abs(z.gap_high - new_zone.gap_high) < self._pips_to_price(1) and abs(z.gap_low - new_zone.gap_low) < self._pips_to_price(1):
                return True
        return False

    def update_active_zones(self, new_zones: list[FVGZone]):
        for z in new_zones:
            self.active_zones.append(z)
        self.active_zones = [z for z in self.active_zones if not z.filled and not z.trade_taken]
        if len(self.active_zones) > self.max_active_zones:
            self.active_zones = self.active_zones[-self.max_active_zones:]

    def check_retest(self, current_price: float, zone: FVGZone) -> bool:
        return zone.gap_low <= current_price <= zone.gap_high

    def mark_filled(self, current_price: float):
        for zone in self.active_zones:
            if zone.direction == "BULLISH" and current_price < zone.gap_low:
                zone.filled = True
            elif zone.direction == "BEARISH" and current_price > zone.gap_high:
                zone.filled = True

    def calculate_sl_tp(self, signal: str, entry_price: float, zone: FVGZone) -> tuple[float, float]:
        buffer = self._pips_to_price(self.sl_buffer_pips)
        if signal == "BUY":
            sl = zone.gap_low - buffer
            risk = entry_price - sl
            tp = entry_price + (risk * self.risk_reward)
        else:
            sl = zone.gap_high + buffer
            risk = sl - entry_price
            tp = entry_price - (risk * self.risk_reward)
        return round(sl, 5), round(tp, 5)

    def place_order(self, signal: str, zone: FVGZone) -> dict:
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {self.symbol} not found"}
        if not symbol_info.visible:
            mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        entry_price = tick.ask if signal == "BUY" else tick.bid
        sl, tp = self.calculate_sl_tp(signal, entry_price, zone)
        order_type = mt5.ORDER_TYPE_BUY if signal == "BUY" else mt5.ORDER_TYPE_SELL
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": self.lot_size,
            "type": order_type,
            "price": entry_price,
            "sl": sl,
            "tp": tp,
            "deviation": 10,
            "magic": self.magic,
            "comment": f"FVG_{signal}_{zone.direction}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            zone.trade_taken = True
            return {
                "success": True,
                "order_id": result.order,
                "signal": signal,
                "entry": entry_price,
                "sl": sl,
                "tp": tp,
                "fvg_zone": {
                    "direction": zone.direction,
                    "gap_high": zone.gap_high,
                    "gap_low": zone.gap_low,
                    "gap_size_pips": round(zone.gap_size / self._get_pip_size(), 1),
                    "formed_at": str(zone.formed_at),
                },
            }
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def run(self) -> dict:
        if not mt5.initialize():
            return {"success": False, "error": "MT5 init failed"}
        df = self.get_candles(count=200)
        if df.empty:
            return {"success": False, "error": "No candle data"}
        new_zones = self.detect_fvg_zones(df)
        self.update_active_zones(new_zones)
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return {"success": False, "error": "No tick data"}
        mid_price = (tick.ask + tick.bid) / 2
        self.mark_filled(mid_price)
        for zone in self.active_zones:
            if zone.filled or zone.trade_taken:
                continue
            if self.check_retest(mid_price, zone):
                signal = "BUY" if zone.direction == "BULLISH" else "SELL"
                return self.place_order(signal, zone)
        return {
            "success": True,
            "signal": "NONE",
            "active_zones": len(self.active_zones),
            "zones_detail": [
                {"direction": z.direction, "gap_high": z.gap_high, "gap_low": z.gap_low, "pips": round(z.gap_size / self._get_pip_size(), 1)}
                for z in self.active_zones
            ],
        }
