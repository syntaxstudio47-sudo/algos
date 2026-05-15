import MetaTrader5 as mt5
import pandas as pd
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import pytz

@dataclass
class CrossoverSignal:
    signal: str
    fast_ema: float
    medium_ema: float
    slow_ema: float
    atr: float
    entry_price: float
    detected_at: datetime
    trend: str

class EMACrossoverStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_H1,
        lot_size: float = 0.1,
        ema_fast: int = 9,
        ema_medium: int = 21,
        ema_slow: int = 50,
        atr_period: int = 14,
        atr_multiplier_sl: float = 1.5,
        atr_multiplier_tp: float = 3.0,
        atr_trail_activation: float = 1.5,
        atr_trail_distance: float = 1.0,
        cooldown_candles: int = 3,
        magic: int = 100005,
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.lot_size = lot_size
        self.ema_fast = ema_fast
        self.ema_medium = ema_medium
        self.ema_slow = ema_slow
        self.atr_period = atr_period
        self.atr_multiplier_sl = atr_multiplier_sl
        self.atr_multiplier_tp = atr_multiplier_tp
        self.atr_trail_activation = atr_trail_activation
        self.atr_trail_distance = atr_trail_distance
        self.cooldown_candles = cooldown_candles
        self.magic = magic
        self.tz = pytz.timezone(timezone)
        self.last_signal_candle: Optional[int] = None
        self.last_signal: Optional[CrossoverSignal] = None
        self.open_ticket: Optional[int] = None

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
        df["ema_fast"] = df["close"].ewm(span=self.ema_fast, adjust=False).mean()
        df["ema_medium"] = df["close"].ewm(span=self.ema_medium, adjust=False).mean()
        df["ema_slow"] = df["close"].ewm(span=self.ema_slow, adjust=False).mean()
        high_low = df["high"] - df["low"]
        high_close = (df["high"] - df["close"].shift()).abs()
        low_close = (df["low"] - df["close"].shift()).abs()
        true_range = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        df["atr"] = true_range.ewm(alpha=1 / self.atr_period, min_periods=self.atr_period, adjust=False).mean()
        df["cross_up"] = (df["ema_fast"] > df["ema_medium"]) & (df["ema_fast"].shift() <= df["ema_medium"].shift())
        df["cross_down"] = (df["ema_fast"] < df["ema_medium"]) & (df["ema_fast"].shift() >= df["ema_medium"].shift())
        df["uptrend"] = (df["ema_fast"] > df["ema_slow"]) & (df["ema_medium"] > df["ema_slow"]) & (df["close"] > df["ema_slow"])
        df["downtrend"] = (df["ema_fast"] < df["ema_slow"]) & (df["ema_medium"] < df["ema_slow"]) & (df["close"] < df["ema_slow"])
        return df

    def get_signal(self, df: pd.DataFrame) -> Optional[CrossoverSignal]:
        last = df.iloc[-1]
        current_candle = len(df) - 1
        if self.last_signal_candle is not None and current_candle - self.last_signal_candle < self.cooldown_candles:
            return None
        if last["cross_up"] and last["uptrend"]:
            return CrossoverSignal("BUY", round(last["ema_fast"], 5), round(last["ema_medium"], 5), round(last["ema_slow"], 5), round(last["atr"], 5), round(last["close"], 5), last["time"], "UPTREND")
        if last["cross_down"] and last["downtrend"]:
            return CrossoverSignal("SELL", round(last["ema_fast"], 5), round(last["ema_medium"], 5), round(last["ema_slow"], 5), round(last["atr"], 5), round(last["close"], 5), last["time"], "DOWNTREND")
        return None

    def calculate_sl_tp(self, signal: str, entry_price: float, atr: float) -> tuple[float, float]:
        sl_distance = atr * self.atr_multiplier_sl
        tp_distance = atr * self.atr_multiplier_tp
        if signal == "BUY":
            sl = entry_price - sl_distance
            tp = entry_price + tp_distance
        else:
            sl = entry_price + sl_distance
            tp = entry_price - tp_distance
        return round(sl, 5), round(tp, 5)

    def place_order(self, crossover: CrossoverSignal) -> dict:
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {self.symbol} not found"}
        if not symbol_info.visible:
            mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        entry_price = tick.ask if crossover.signal == "BUY" else tick.bid
        sl, tp = self.calculate_sl_tp(crossover.signal, entry_price, crossover.atr)
        order_type = mt5.ORDER_TYPE_BUY if crossover.signal == "BUY" else mt5.ORDER_TYPE_SELL
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
            "comment": f"EMA_{crossover.signal}_{crossover.ema_fast:.5f}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.open_ticket = result.order
            self.last_signal = crossover
            self.last_signal_candle = len(mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, 1)) - 1
            return {
                "success": True,
                "order_id": result.order,
                "signal": crossover.signal,
                "entry": entry_price,
                "sl": sl,
                "tp": tp,
                "atr": crossover.atr,
                "ema_fast": crossover.fast_ema,
                "ema_medium": crossover.medium_ema,
                "ema_slow": crossover.slow_ema,
                "trend": crossover.trend,
            }
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def _modify_sl(self, ticket: int, new_sl: float, tp: float, action: str) -> dict:
        request = {"action": mt5.TRADE_ACTION_SLTP, "ticket": ticket, "sl": round(new_sl, 5), "tp": tp}
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            return {"action": action, "success": True, "new_sl": round(new_sl, 5)}
        return {"action": action, "success": False, "retcode": result.retcode, "error": result.comment}

    def manage_trailing_stop(self) -> dict:
        if self.open_ticket is None or self.last_signal is None:
            return {"action": "NONE", "reason": "No open trade"}
        positions = mt5.positions_get(ticket=self.open_ticket)
        if not positions:
            self.open_ticket = None
            return {"action": "NONE", "reason": "Position already closed"}
        pos = positions[0]
        tick = mt5.symbol_info_tick(self.symbol)
        current_price = tick.bid if pos.type == mt5.ORDER_TYPE_BUY else tick.ask
        atr = self.last_signal.atr
        trail_distance = atr * self.atr_trail_distance
        activation_distance = atr * self.atr_trail_activation
        if pos.type == mt5.ORDER_TYPE_BUY:
            profit_distance = current_price - pos.price_open
            new_sl = current_price - trail_distance
            if profit_distance >= activation_distance and new_sl > pos.sl:
                return self._modify_sl(pos.ticket, new_sl, pos.tp, "TRAIL_BUY")
        else:
            profit_distance = pos.price_open - current_price
            new_sl = current_price + trail_distance
            if profit_distance >= activation_distance and new_sl < pos.sl:
                return self._modify_sl(pos.ticket, new_sl, pos.tp, "TRAIL_SELL")
        return {"action": "NONE", "reason": "Trail not yet activated", "profit_distance": round(profit_distance, 5), "activation_at": round(activation_distance, 5)}

    def check_exit_signal(self, df: pd.DataFrame) -> bool:
        if self.open_ticket is None or self.last_signal is None:
            return False
        last = df.iloc[-1]
        if self.last_signal.signal == "BUY" and last["cross_down"]:
            return True
        if self.last_signal.signal == "SELL" and last["cross_up"]:
            return True
        return False

    def close_position(self) -> dict:
        if self.open_ticket is None:
            return {"success": False, "error": "No open ticket"}
        positions = mt5.positions_get(ticket=self.open_ticket)
        if not positions:
            self.open_ticket = None
            return {"success": False, "error": "Position not found"}
        pos = positions[0]
        tick = mt5.symbol_info_tick(self.symbol)
        close_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
        close_price = tick.bid if pos.type == mt5.ORDER_TYPE_BUY else tick.ask
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": pos.volume,
            "type": close_type,
            "position": pos.ticket,
            "price": close_price,
            "deviation": 10,
            "magic": self.magic,
            "comment": "EMA_REVERSE_EXIT",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.open_ticket = None
            self.last_signal = None
            return {"success": True, "closed_ticket": pos.ticket, "close_price": close_price}
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def run(self) -> dict:
        if not mt5.initialize():
            return {"success": False, "error": "MT5 init failed"}
        df = self.get_candles(count=300)
        if df.empty:
            return {"success": False, "error": "No candle data"}
        df = self.calculate_indicators(df)
        last = df.iloc[-1]
        trail_result = self.manage_trailing_stop()
        if self.check_exit_signal(df):
            exit_result = self.close_position()
            return {"action": "REVERSE_EXIT", "exit": exit_result, "trail": trail_result}
        positions = mt5.positions_get(magic=self.magic)
        if positions and len(positions) > 0:
            return {
                "success": True,
                "signal": "NONE",
                "reason": "Position already open",
                "trail": trail_result,
                "ema_fast": round(last["ema_fast"], 5),
                "ema_medium": round(last["ema_medium"], 5),
                "ema_slow": round(last["ema_slow"], 5),
                "atr": round(last["atr"], 5),
            }
        crossover = self.get_signal(df)
        if crossover:
            return self.place_order(crossover)
        return {
            "success": True,
            "signal": "NONE",
            "ema_fast": round(last["ema_fast"], 5),
            "ema_medium": round(last["ema_medium"], 5),
            "ema_slow": round(last["ema_slow"], 5),
            "atr": round(last["atr"], 5),
            "uptrend": bool(last["uptrend"]),
            "downtrend": bool(last["downtrend"]),
        }
