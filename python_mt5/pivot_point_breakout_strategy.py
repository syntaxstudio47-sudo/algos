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

class PivotPointBreakoutStrategy:
    def __init__(self, symbol, timeframe=mt5.TIMEFRAME_M15, lot_size=0.1, atr_period=14, atr_sl_mult=1.4, rr_multiple=2.5, max_trades_per_day=3, magic=510008, timezone='Asia/Kolkata'):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
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

    def get_candles(self, tf, count=120):
        rates = mt5.copy_rates_from_pos(self.symbol, tf, 0, count)
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

    def _levels(self):
        daily = self.get_candles(mt5.TIMEFRAME_D1, 5)
        if len(daily) < 2:
            return None
        prev = daily.iloc[-2]
        p = (prev['high'] + prev['low'] + prev['close']) / 3
        r1 = (2 * p) - prev['low']
        s1 = (2 * p) - prev['high']
        return float(r1), float(s1)

    def get_signal(self, df):
        if len(df) < self.atr_period + 5:
            return None
        levels = self._levels()
        if levels is None:
            return None
        r1, s1 = levels
        df = df.copy()
        df['atr'] = self._atr(df)
        last = df.iloc[-1]
        prev = df.iloc[-2]
        if pd.isna(last['atr']):
            return None
        if prev['close'] <= r1 and last['close'] > r1:
            return Signal('BUY', round(r1, 5), round(last['atr'], 5), last['time'])
        if prev['close'] >= s1 and last['close'] < s1:
            return Signal('SELL', round(s1, 5), round(last['atr'], 5), last['time'])
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
        request = {'action': mt5.TRADE_ACTION_DEAL, 'symbol': self.symbol, 'volume': self.lot_size, 'type': order_type, 'price': entry, 'sl': round(sl, 5), 'tp': round(tp, 5), 'deviation': 10, 'magic': self.magic, 'comment': f'PIVOT_BREAK_{signal.signal}', 'type_time': mt5.ORDER_TIME_GTC, 'type_filling': mt5.ORDER_FILLING_IOC}
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
        df = self.get_candles(self.timeframe)
        if df.empty: return {'success': False, 'error': 'No data'}
        signal = self.get_signal(df)
        if not signal: return {'success': True, 'signal': 'NONE'}
        if self.last_signal_time == signal.detected_at: return {'success': True, 'signal': 'NONE', 'reason': 'Duplicate'}
        return self.place_order(signal)
