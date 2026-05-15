import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from dataclasses import dataclass
from datetime import datetime
import pytz

@dataclass
class Signal:
    signal: str
    breakout_level: float
    atr: float
    detected_at: datetime

class DescendingTriangleBreakdownStrategy:
    def __init__(self, symbol, timeframe=mt5.TIMEFRAME_M15, lot_size=0.1, lookback=40, atr_period=14, atr_sl_mult=1.5, rr_multiple=2.5, max_trades_per_day=3, magic=510011, timezone='Asia/Kolkata'):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.lookback = lookback
        self.atr_period = atr_period
        self.atr_sl_mult = atr_sl_mult
        self.rr_multiple = rr_multiple
        self.max_trades_per_day = max_trades_per_day
        self.magic = magic
        self.tz = pytz.timezone(timezone)
        self.trades_today = 0
        self.last_trade_date = None
        self.last_signal_time = None

    def _reset_daily_counter(self):
        today = datetime.now(self.tz).date()
        if self.last_trade_date != today:
            self.trades_today = 0
            self.last_trade_date = today

    def get_candles(self, count=250):
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s', utc=True).dt.tz_convert(self.tz)
        return df.reset_index(drop=True)

    def _atr(self, df):
        hl = df['high'] - df['low']
        hc = (df['high'] - df['close'].shift(1)).abs()
        lc = (df['low'] - df['close'].shift(1)).abs()
        return pd.concat([hl, hc, lc], axis=1).max(axis=1).ewm(alpha=1/self.atr_period, min_periods=self.atr_period, adjust=False).mean()

    def _detect_triangle(self, df):
        w = df.tail(self.lookback).copy()
        highs = w['high'].values
        lows = w['low'].values
        x = np.arange(len(w))
        high_slope = np.polyfit(x, highs, 1)[0]
        low_slope = np.polyfit(x, lows, 1)[0]
        support = lows.min()
        if high_slope < 0 and abs(low_slope) < abs(high_slope) * 0.3:
            return float(support)
        return None

    def get_signal(self, df):
        if len(df) < self.lookback + 5:
            return None
        df = df.copy()
        df['atr'] = self._atr(df)
        support = self._detect_triangle(df)
        if support is None:
            return None
        last = df.iloc[-1]
        prev = df.iloc[-2]
        if pd.isna(last['atr']):
            return None
        if prev['close'] >= support and last['close'] < support and last['close'] < last['open']:
            return Signal('SELL', round(support, 5), round(last['atr'], 5), last['time'])
        return None

    def has_open_position(self):
        positions = mt5.positions_get(symbol=self.symbol)
        return any(p.magic == self.magic for p in positions) if positions else False

    def place_order(self, signal):
        mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        if not tick:
            return {'success': False, 'error': 'No tick'}
        entry = tick.bid
        sl = entry + signal.atr * self.atr_sl_mult
        tp = entry - signal.atr * self.atr_sl_mult * self.rr_multiple
        request = {'action': mt5.TRADE_ACTION_DEAL, 'symbol': self.symbol, 'volume': self.lot_size, 'type': mt5.ORDER_TYPE_SELL, 'price': entry, 'sl': round(sl, 5), 'tp': round(tp, 5), 'deviation': 10, 'magic': self.magic, 'comment': 'DESC_TRI_BREAK', 'type_time': mt5.ORDER_TIME_GTC, 'type_filling': mt5.ORDER_FILLING_IOC}
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.trades_today += 1
            self.last_signal_time = signal.detected_at
            return {'success': True, 'order_id': result.order}
        return {'success': False, 'retcode': result.retcode, 'error': result.comment}

    def run(self):
        if not mt5.initialize(): return {'success': False, 'error': 'MT5 init failed'}
        self._reset_daily_counter()
        if self.trades_today >= self.max_trades_per_day: return {'success': True, 'signal': 'NONE', 'reason': 'Max trades'}
        if self.has_open_position(): return {'success': True, 'signal': 'NONE', 'reason': 'Position open'}
        df = self.get_candles()
        if df.empty: return {'success': False, 'error': 'No data'}
        signal = self.get_signal(df)
        if not signal: return {'success': True, 'signal': 'NONE'}
        if self.last_signal_time == signal.detected_at: return {'success': True, 'signal': 'NONE', 'reason': 'Duplicate'}
        return self.place_order(signal)
