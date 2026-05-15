import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, time
from typing import Optional
import pytz

class VWAPMeanReversionStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_M5,
        lot_size: float = 0.1,
        dev_entry: float = 1.5,
        dev_sl: float = 2.5,
        wick_ratio: float = 1.5,
        max_trades_per_session: int = 3,
        magic: int = 100003,
        session_open_time: time = time(9, 15),
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.dev_entry = dev_entry
        self.dev_sl = dev_sl
        self.wick_ratio = wick_ratio
        self.max_trades_per_session = max_trades_per_session
        self.magic = magic
        self.session_open_time = session_open_time
        self.tz = pytz.timezone(timezone)
        self.trades_today: int = 0
        self._last_trade_date: Optional[datetime.date] = None

    def get_candles(self, count: int = 300) -> pd.DataFrame:
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["time"] = df["time"].dt.tz_convert(self.tz)
        return df.reset_index(drop=True)

    def calculate_vwap(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        df["typical_price"] = (df["high"] + df["low"] + df["close"]) / 3
        df["date"] = df["time"].dt.date
        vwap_vals, upper_band_entry, lower_band_entry, upper_band_sl, lower_band_sl = [], [], [], [], []
        for _, group in df.groupby("date", sort=True):
            tp = group["typical_price"].values
            vol = group["tick_volume"].values.astype(float)
            cum_tp_vol = np.cumsum(tp * vol)
            cum_vol = np.cumsum(vol)
            vwap = cum_tp_vol / np.where(cum_vol == 0, 1, cum_vol)
            std = pd.Series(tp).expanding().std().fillna(0).values
            vwap_vals.extend(vwap.tolist())
            upper_band_entry.extend((vwap + self.dev_entry * std).tolist())
            lower_band_entry.extend((vwap - self.dev_entry * std).tolist())
            upper_band_sl.extend((vwap + self.dev_sl * std).tolist())
            lower_band_sl.extend((vwap - self.dev_sl * std).tolist())
        df["vwap"] = vwap_vals
        df["vwap_upper_entry"] = upper_band_entry
        df["vwap_lower_entry"] = lower_band_entry
        df["vwap_upper_sl"] = upper_band_sl
        df["vwap_lower_sl"] = lower_band_sl
        return df

    def is_bullish_rejection(self, candle: pd.Series) -> bool:
        body = abs(candle["close"] - candle["open"])
        if body == 0:
            return False
        lower_wick = candle["open"] - candle["low"] if candle["close"] >= candle["open"] else candle["close"] - candle["low"]
        return candle["close"] >= candle["open"] and lower_wick >= self.wick_ratio * body

    def is_bearish_rejection(self, candle: pd.Series) -> bool:
        body = abs(candle["close"] - candle["open"])
        if body == 0:
            return False
        upper_wick = candle["high"] - candle["open"] if candle["close"] <= candle["open"] else candle["high"] - candle["close"]
        return candle["close"] <= candle["open"] and upper_wick >= self.wick_ratio * body

    def get_signal(self, df: pd.DataFrame) -> tuple[str, dict]:
        if df.empty or len(df) < 10:
            return "NONE", {}
        last = df.iloc[-1]
        prev = df.iloc[-2]
        context = {
            "vwap": round(last["vwap"], 5),
            "upper_entry": round(last["vwap_upper_entry"], 5),
            "lower_entry": round(last["vwap_lower_entry"], 5),
            "close": round(last["close"], 5),
        }
        if prev["low"] <= prev["vwap_lower_entry"] and self.is_bullish_rejection(last) and last["close"] > last["vwap_lower_entry"]:
            return "BUY", context
        if prev["high"] >= prev["vwap_upper_entry"] and self.is_bearish_rejection(last) and last["close"] < last["vwap_upper_entry"]:
            return "SELL", context
        return "NONE", context

    def calculate_sl_tp(self, signal: str, entry_price: float, last_row: pd.Series) -> tuple[float, float]:
        if signal == "BUY":
            sl = last_row["vwap_lower_sl"]
            tp = last_row["vwap"]
        else:
            sl = last_row["vwap_upper_sl"]
            tp = last_row["vwap"]
        return round(sl, 5), round(tp, 5)

    def place_order(self, signal: str, df: pd.DataFrame) -> dict:
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {self.symbol} not found"}
        if not symbol_info.visible:
            mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        entry_price = tick.ask if signal == "BUY" else tick.bid
        last_row = df.iloc[-1]
        sl, tp = self.calculate_sl_tp(signal, entry_price, last_row)
        if signal == "BUY" and sl >= entry_price:
            return {"success": False, "error": "Invalid SL for BUY (SL >= entry)"}
        if signal == "SELL" and sl <= entry_price:
            return {"success": False, "error": "Invalid SL for SELL (SL <= entry)"}
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
            "comment": f"VWAP_MR_{signal}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.trades_today += 1
            return {
                "success": True,
                "order_id": result.order,
                "signal": signal,
                "entry": entry_price,
                "sl": sl,
                "tp": tp,
                "vwap": round(last_row["vwap"], 5),
                "band_hit": round(last_row["vwap_lower_entry"] if signal == "BUY" else last_row["vwap_upper_entry"], 5),
            }
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def _check_daily_reset(self):
        today = datetime.now(self.tz).date()
        if self._last_trade_date != today:
            self.trades_today = 0
            self._last_trade_date = today

    def run(self) -> dict:
        if not mt5.initialize():
            return {"success": False, "error": "MT5 init failed"}
        self._check_daily_reset()
        if self.trades_today >= self.max_trades_per_session:
            return {"success": True, "signal": "NONE", "reason": f"Max trades reached ({self.max_trades_per_session})"}
        df = self.get_candles(count=300)
        if df.empty:
            return {"success": False, "error": "No candle data"}
        df = self.calculate_vwap(df)
        signal, context = self.get_signal(df)
        if signal != "NONE":
            result = self.place_order(signal, df)
            result["context"] = context
            return result
        return {"success": True, "signal": "NONE", "trades_today": self.trades_today, **context}
