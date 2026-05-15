import MetaTrader5 as mt5
import pandas as pd
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import pytz


@dataclass
class GapContinuationSignal:
    signal: str
    prev_close: float
    session_open: float
    gap_size: float
    gap_percent_atr: float
    opening_range_high: float
    opening_range_low: float
    atr: float
    breakout_close: float
    detected_at: datetime


class OpeningGapContinuationStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_M15,
        lot_size: float = 0.1,
        atr_period: int = 14,
        opening_range_bars: int = 2,
        min_gap_atr_multiple: float = 0.4,
        max_gap_atr_multiple: float = 1.5,
        breakout_buffer_pips: float = 1.0,
        atr_sl_mult: float = 1.2,
        rr_multiple: float = 2.5,
        max_trades_per_day: int = 1,
        session_reset_hour: int = 0,
        magic: int = 110009,
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.atr_period = atr_period
        self.opening_range_bars = opening_range_bars
        self.min_gap_atr_multiple = min_gap_atr_multiple
        self.max_gap_atr_multiple = max_gap_atr_multiple
        self.breakout_buffer_pips = breakout_buffer_pips
        self.atr_sl_mult = atr_sl_mult
        self.rr_multiple = rr_multiple
        self.max_trades_per_day = max_trades_per_day
        self.session_reset_hour = session_reset_hour
        self.magic = magic
        self.tz = pytz.timezone(timezone)

        self.trades_today = 0
        self.last_trade_date: Optional[datetime.date] = None
        self.last_signal_time: Optional[datetime] = None
        self._pip_size: Optional[float] = None

    def _reset_daily_counter(self):
        now = datetime.now(self.tz)
        today = now.date()
        if self.last_trade_date != today:
            self.trades_today = 0
            self.last_trade_date = today

    def _get_pip_size(self) -> float:
        if self._pip_size:
            return self._pip_size
        info = mt5.symbol_info(self.symbol)
        self._pip_size = info.point * 10 if info and info.digits in (3, 5) else (info.point if info else 0.0001)
        return self._pip_size

    def _pips_to_price(self, pips: float) -> float:
        return pips * self._get_pip_size()

    def get_candles(self, count: int = 300) -> pd.DataFrame:
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()

        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["time"] = df["time"].dt.tz_convert(self.tz)
        return df.reset_index(drop=True)

    def calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()

        high_low = df["high"] - df["low"]
        high_close = (df["high"] - df["close"].shift(1)).abs()
        low_close = (df["low"] - df["close"].shift(1)).abs()
        true_range = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        df["atr"] = true_range.ewm(alpha=1 / self.atr_period, min_periods=self.atr_period, adjust=False).mean()

        df["trade_date"] = df["time"].dt.date
        return df

    def get_session_slice(self, df: pd.DataFrame) -> pd.DataFrame:
        current_date = df.iloc[-1]["trade_date"]
        session_df = df[df["trade_date"] == current_date].copy()
        return session_df.reset_index(drop=True)

    def get_signal(self, df: pd.DataFrame) -> Optional[GapContinuationSignal]:
        if len(df) < self.atr_period + 20:
            return None

        session_df = self.get_session_slice(df)
        if len(session_df) < self.opening_range_bars + 1:
            return None

        prev_day = df[df["trade_date"] < session_df.iloc[0]["trade_date"]]
        if prev_day.empty:
            return None

        prev_close = prev_day.iloc[-1]["close"]
        session_open = session_df.iloc[0]["open"]
        gap_size = session_open - prev_close
        atr = session_df.iloc[0]["atr"]

        if pd.isna(atr) or atr <= 0:
            return None

        gap_atr_multiple = abs(gap_size) / atr

        if gap_atr_multiple < self.min_gap_atr_multiple or gap_atr_multiple > self.max_gap_atr_multiple:
            return None

        opening_range = session_df.iloc[:self.opening_range_bars]
        breakout_bar = session_df.iloc[-1]

        if len(session_df) <= self.opening_range_bars:
            return None

        opening_range_high = opening_range["high"].max()
        opening_range_low = opening_range["low"].min()
        buffer_price = self._pips_to_price(self.breakout_buffer_pips)

        bullish_gap = gap_size > 0
        bearish_gap = gap_size < 0

        long_breakout = bullish_gap and breakout_bar["close"] > opening_range_high + buffer_price
        short_breakout = bearish_gap and breakout_bar["close"] < opening_range_low - buffer_price

        if long_breakout:
            return GapContinuationSignal(
                signal="BUY",
                prev_close=round(prev_close, 5),
                session_open=round(session_open, 5),
                gap_size=round(gap_size, 5),
                gap_percent_atr=round(gap_atr_multiple, 2),
                opening_range_high=round(opening_range_high, 5),
                opening_range_low=round(opening_range_low, 5),
                atr=round(breakout_bar["atr"], 5),
                breakout_close=round(breakout_bar["close"], 5),
                detected_at=breakout_bar["time"],
            )

        if short_breakout:
            return GapContinuationSignal(
                signal="SELL",
                prev_close=round(prev_close, 5),
                session_open=round(session_open, 5),
                gap_size=round(gap_size, 5),
                gap_percent_atr=round(gap_atr_multiple, 2),
                opening_range_high=round(opening_range_high, 5),
                opening_range_low=round(opening_range_low, 5),
                atr=round(breakout_bar["atr"], 5),
                breakout_close=round(breakout_bar["close"], 5),
                detected_at=breakout_bar["time"],
            )

        return None
