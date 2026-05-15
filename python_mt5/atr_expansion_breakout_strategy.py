import MetaTrader5 as mt5
import pandas as pd
from dataclasses import dataclass
from datetime import datetime
import pytz

@dataclass
class Signal:
    signal: str
    breakout_level: float
    atr: float
    detected_at: datetime

class ATRExpansionBreakoutStrategy:
    def __init__(self, symbol, timeframe=mt5.TIMEFRAME_M15, lot_size=0.1, breakout_lookback=20, atr_period=14, expansion_mult=1.4, atr_sl_mult=1.3, rr_multiple=2.5, max_trades_per_day=3, magic=510010, timezone='Asia/Kolkata'):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.breakout_lookback = breakout_lookback
        self.atr_period = atr_period
        self.expansion_mult = expansion_mult
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

    def get_signal(self, df):
        if len(df) < self.breakout_lookback + self.atr_period + 5:
            return None
        df = df.copy()
        df['atr'] = self._atr(df)
        last = df.iloc[-1]
        prev = df.iloc[-2]
        if pd.isna(last['atr']):
            return None
        breakout_high = df['high'].shift(1).rolling(self.breakout_lookback).max().iloc[-1]
        breakout_low = df['low'].shift(1).rolling(self.breakout_lookback).min().iloc[-1]
        candle_range = last['high'] - last['low']
        expansion_ok = candle_range >= last['atr'] * self.expansion_mult
        if expansion_ok and prev['close'] <= breakout_high and last['close'] > breakout_high:
            return Signal('BUY', round(breakout_high, 5), round(last['atr'], 5), last['time'])
        if expansion_ok and prev['close'] >= breakout_low and last['close'] < breakout_low:
            return Signal('SELL', round(breakout_low, 5), round(last['atr'], 5), last['time'])
        return None

    def has_open_position(self):
        positions = mt5.positions_get(symbol=self.symbol)
        return any(p.magic == self.magic for p in positions) if positions else False

    def place_order(self, signal):
        mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        if not tick:
            return {'success': False, 'error': 'No tick'}
        entry = tick.ask if signal.signal == 'BUY' else tick.bid
        if signal.signal == 'BUY':
            sl = entry - signal.atr * self.atr_sl_mult
            tp = entry + signal.atr * self.atr_sl_mult * self.rr_multiple
            order_type = mt5.ORDER_TYPE_BUY
        else:
            sl = entry + signal.atr * self.atr_sl_mult
            tp = entry - signal.atr * self.atr_sl_mult * self.rr_multiple
            order_type = mt5.ORDER_TYPE_SELL
        request = {'action': mt5.TRADE_ACTION_DEAL, 'symbol': self.symbol, 'volume': self.lot_size, 'type': order_type, 'price': entry, 'sl': round(sl, 5), 'tp': round(tp, 5), 'deviation': 10, 'magic': self.magic, 'comment': f'ATR_EXP_{signal.signal}', 'type_time': mt5.ORDER_TIME_GTC, 'type_filling': mt5.ORDER_FILLING_IOC}
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
