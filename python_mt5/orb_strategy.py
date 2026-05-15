import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, time
import pytz

class ORBStrategy:
    def __init__(
        self,
        symbol: str,
        timeframe=mt5.TIMEFRAME_M5,
        orb_duration_minutes: int = 15,
        lot_size: float = 0.1,
        risk_reward: float = 2.0,
        magic: int = 100001,
        session_open_time: time = time(9, 15),
        timezone: str = "Asia/Kolkata",
    ):
        self.symbol = symbol
        self.timeframe = timeframe
        self.orb_duration_minutes = orb_duration_minutes
        self.lot_size = lot_size
        self.risk_reward = risk_reward
        self.magic = magic
        self.session_open_time = session_open_time
        self.tz = pytz.timezone(timezone)
        self.orb_high = None
        self.orb_low = None
        self.orb_established = False
        self.trade_taken = False

    def get_candles(self, count: int = 100) -> pd.DataFrame:
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None or len(rates) == 0:
            return pd.DataFrame()
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["time"] = df["time"].dt.tz_convert(self.tz)
        return df

    def calculate_orb(self, df: pd.DataFrame) -> bool:
        today = datetime.now(self.tz).date()
        session_start = self.tz.localize(datetime.combine(today, self.session_open_time))
        session_end = session_start + pd.Timedelta(minutes=self.orb_duration_minutes)
        orb_candles = df[(df["time"] >= session_start) & (df["time"] < session_end)]
        if orb_candles.empty:
            return False
        now = datetime.now(self.tz)
        if now < session_end:
            return False
        self.orb_high = orb_candles["high"].max()
        self.orb_low = orb_candles["low"].min()
        self.orb_established = True
        return True

    def get_signal(self, df: pd.DataFrame) -> str:
        if not self.orb_established or self.trade_taken:
            return "NONE"
        last_close = df["close"].iloc[-1]
        last_high = df["high"].iloc[-1]
        last_low = df["low"].iloc[-1]
        if last_high > self.orb_high:
            return "BUY"
        elif last_low < self.orb_low:
            return "SELL"
        return "NONE"

    def calculate_sl_tp(self, signal: str, entry_price: float) -> tuple:
        range_size = self.orb_high - self.orb_low
        if signal == "BUY":
            sl = self.orb_low
            tp = entry_price + (range_size * self.risk_reward)
        else:
            sl = self.orb_high
            tp = entry_price - (range_size * self.risk_reward)
        return round(sl, 5), round(tp, 5)

    def place_order(self, signal: str) -> dict:
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {self.symbol} not found"}
        if not symbol_info.visible:
            mt5.symbol_select(self.symbol, True)
        tick = mt5.symbol_info_tick(self.symbol)
        entry_price = tick.ask if signal == "BUY" else tick.bid
        sl, tp = self.calculate_sl_tp(signal, entry_price)
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
            "comment": f"ORB_{signal}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            self.trade_taken = True
            return {
                "success": True,
                "order_id": result.order,
                "signal": signal,
                "entry": entry_price,
                "sl": sl,
                "tp": tp,
                "orb_high": self.orb_high,
                "orb_low": self.orb_low,
            }
        return {"success": False, "retcode": result.retcode, "error": result.comment}

    def reset_daily(self):
        self.orb_high = None
        self.orb_low = None
        self.orb_established = False
        self.trade_taken = False

    def run(self) -> dict:
        if not mt5.initialize():
            return {"success": False, "error": "MT5 init failed"}
        df = self.get_candles(count=100)
        if df.empty:
            return {"success": False, "error": "No candle data"}
        if not self.orb_established:
            self.calculate_orb(df)
        signal = self.get_signal(df)
        if signal != "NONE":
            return self.place_order(signal)
        return {
            "success": True,
            "signal": "NONE",
            "orb_high": self.orb_high,
            "orb_low": self.orb_low,
            "orb_established": self.orb_established,
        }
