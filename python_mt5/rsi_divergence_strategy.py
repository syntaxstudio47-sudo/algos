import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import pytz

@dataclass
class DivergenceSignal:
    divergence_type: str
    signal: str
    price_pivot_1: float
    price_pivot_2: float
    rsi_pivot_1: float
    rsi_pivot_2: float
    pivot_1_index: int
    pivot_2_index: int
    detected_at: datetime
    strength: float

class RSIDivergenceStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_M15,
        lot_size: float = 0.1,
        rsi_period: int = 14,
        rsi_oversold: float = 30.0,
        rsi_overbought: float = 70.0,
        pivot_strength: int = 3,
        divergence_lookback: int = 50,
        min_rsi_divergence: float = 3.0,
        risk_reward: float = 2.0,
        sl_buffer_pips: float = 5.0,
        magic: int = 100004,
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.rsi_period = rsi_period
        self.rsi_oversold = rsi_oversold
        self.rsi_overbought = rsi_overbought
        self.pivot_strength = pivot_strength
        self.divergence_lookback = divergence_lookback
        self.min_rsi_divergence = min_rsi_divergence
        self.risk_reward = risk_reward
        self.sl_buffer_pips = sl_buffer_pips
        self.magic = magic
        self.tz = pytz.timezone(timezone)
        self._pip_size: Optional[float] = None
        self.last_signal: Optional[DivergenceSignal] = None

    def get_candles(self, count: int = 300) -> pd.DataFrame:
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["time"] = df["time"].dt.tz_convert(self.tz)
        return df.reset_index(drop=True)

    def _get_pip_size(self) -> float:
        if self._pip_size:
            return self._pip_size
        info = mt5.symbol_info(self.symbol)
        self._pip_size = info.point * 10 if info else 0.0001
        return self._pip_size

    def calculate_rsi(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        delta = df["close"].diff()
        gain = delta.clip(lower=0)
        loss = -delta.clip(upper=0)
        avg_gain = gain.ewm(alpha=1 / self.rsi_period, min_periods=self.rsi_period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1 / self.rsi_period, min_periods=self.rsi_period, adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0, np.nan)
        df["rsi"] = 100 - (100 / (1 + rs))
        df["rsi"] = df["rsi"].fillna(50)
        return df

    def find_swing_lows(self, df: pd.DataFrame) -> list[int]:
        pivots = []
        n = self.pivot_strength
        start = max(n, len(df) - self.divergence_lookback)
        for i in range(start, len(df) - n):
            low = df["low"].iloc[i]
            left_lows = df["low"].iloc[i - n:i]
            right_lows = df["low"].iloc[i + 1:i + n + 1]
            if (left_lows > low).all() and (right_lows > low).all():
                pivots.append(i)
        return pivots

    def find_swing_highs(self, df: pd.DataFrame) -> list[int]:
        pivots = []
        n = self.pivot_strength
        start = max(n, len(df) - self.divergence_lookback)
        for i in range(start, len(df) - n):
            high = df["high"].iloc[i]
            left_highs = df["high"].iloc[i - n:i]
            right_highs = df["high"].iloc[i + 1:i + n + 1]
            if (left_highs < high).all() and (right_highs < high).all():
                pivots.append(i)
        return pivots

    def detect_bullish_divergence(self, df: pd.DataFrame) -> Optional[DivergenceSignal]:
        swing_lows = self.find_swing_lows(df)
        if len(swing_lows) < 2:
            return None
        idx1, idx2 = swing_lows[-2], swing_lows[-1]
        price1, price2 = df["low"].iloc[idx1], df["low"].iloc[idx2]
        rsi1, rsi2 = df["rsi"].iloc[idx1], df["rsi"].iloc[idx2]
        price_lower_low = price2 < price1
        rsi_higher_low = rsi2 > rsi1
        rsi_divergence_size = rsi2 - rsi1
        in_oversold = rsi1 < 45 and rsi2 < 45
        if price_lower_low and rsi_higher_low and rsi_divergence_size >= self.min_rsi_divergence and in_oversold:
            return DivergenceSignal("BULLISH", "BUY", price1, price2, round(rsi1, 2), round(rsi2, 2), idx1, idx2, df["time"].iloc[idx2], round(rsi_divergence_size, 2))
        return None

    def detect_bearish_divergence(self, df: pd.DataFrame) -> Optional[DivergenceSignal]:
        swing_highs = self.find_swing_highs(df)
        if len(swing_highs) < 2:
            return None
        idx1, idx2 = swing_highs[-2], swing_highs[-1]
        price1, price2 = df["high"].iloc[idx1], df["high"].iloc[idx2]
        rsi1, rsi2 = df["rsi"].iloc[idx1], df["rsi"].iloc[idx2]
        price_higher_high = price2 > price1
        rsi_lower_high = rsi2 < rsi1
        rsi_divergence_size = rsi1 - rsi2
        in_overbought = rsi1 > 55 and rsi2 > 55
        if price_higher_high and rsi_lower_high and rsi_divergence_size >= self.min_rsi_divergence and in_overbought:
            return DivergenceSignal("BEARISH", "SELL", price1, price2, round(rsi1, 2), round(rsi2, 2), idx1, idx2, df["time"].iloc[idx2], round(rsi_divergence_size, 2))
        return None

    def is_confirmed(self, df: pd.DataFrame, div: DivergenceSignal) -> bool:
        last_rsi = df["rsi"].iloc[-1]
        prev_rsi = df["rsi"].iloc[-2]
        if div.signal == "BUY":
            return prev_rsi <= self.rsi_oversold and last_rsi > self.rsi_oversold
        return prev_rsi >= self.rsi_overbought and last_rsi < self.rsi_overbought

    def calculate_sl_tp(self, signal: str, entry_price: float, div: DivergenceSignal) -> tuple[float, float]:
        buffer = self.sl_buffer_pips * self._get_pip_size()
        if signal == "BUY":
            sl = div.price_pivot_2 - buffer
            risk = entry_price - sl
            tp = entry_price + risk * self.risk_reward
        else:
            sl = div.price_pivot_2 + buffer
            risk = sl - entry_price
            tp = entry_price - risk * self.risk_reward
        return round(sl, 5), round(tp, 5)

    def place_order(self, div: DivergenceSignal, df: pd.DataFrame) -> dict:
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {self.symbol} not found"}
        if not symbol_info.visible:
            mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        entry_price = tick.ask if div.signal == "BUY" else tick.bid
        sl, tp = self.calculate_sl_tp(div.signal, entry_price, div)
        if div.signal == "BUY" and sl >= entry_price:
            return {"success": False, "error": "Invalid SL for BUY"}
        if div.signal == "SELL" and sl <= entry_price:
            return {"success": False, "error": "Invalid SL for SELL"}
        order_type = mt5.ORDER_TYPE_BUY if div.signal == "BUY" else mt5.ORDER_TYPE_SELL
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
            "comment": f"RSI_DIV_{div.signal}_{div.strength}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.last_signal = div
            return {
                "success": True,
                "order_id": result.order,
                "signal": div.signal,
                "entry": entry_price,
                "sl": sl,
                "tp": tp,
                "divergence": {
                    "type": div.divergence_type,
                    "strength": div.strength,
                    "price_pivot_1": div.price_pivot_1,
                    "price_pivot_2": div.price_pivot_2,
                    "rsi_pivot_1": div.rsi_pivot_1,
                    "rsi_pivot_2": div.rsi_pivot_2,
                    "detected_at": str(div.detected_at),
                },
            }
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def _is_duplicate(self, div: DivergenceSignal) -> bool:
        if self.last_signal is None:
            return False
        return self.last_signal.divergence_type == div.divergence_type and self.last_signal.pivot_2_index == div.pivot_2_index

    def run(self) -> dict:
        if not mt5.initialize():
            return {"success": False, "error": "MT5 init failed"}
        df = self.get_candles(count=300)
        if df.empty:
            return {"success": False, "error": "No candle data"}
        df = self.calculate_rsi(df)
        bullish_div = self.detect_bullish_divergence(df)
        bearish_div = self.detect_bearish_divergence(df)
        last_rsi = round(df["rsi"].iloc[-1], 2)
        for div in [bullish_div, bearish_div]:
            if div is None:
                continue
            if self._is_duplicate(div):
                continue
            if self.is_confirmed(df, div):
                result = self.place_order(div, df)
                result["rsi_current"] = last_rsi
                return result
        return {
            "success": True,
            "signal": "NONE",
            "rsi_current": last_rsi,
            "bullish_div_detected": bullish_div is not None,
            "bearish_div_detected": bearish_div is not None,
            "awaiting_confirmation": bullish_div is not None or bearish_div is not None,
        }
