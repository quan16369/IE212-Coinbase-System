from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import numpy as np
import pandas as pd


BASE_COLUMNS = ("open", "high", "low", "close", "volume")
DEFAULT_LAGS = (1, 2, 3, 6, 12, 24)
DEFAULT_ROLLING_WINDOWS = (3, 6, 12, 24)


@dataclass(frozen=True)
class FeatureConfig:
    horizon: int = 4
    freq_minutes: int = 60
    lags: tuple[int, ...] = DEFAULT_LAGS
    rolling_windows: tuple[int, ...] = DEFAULT_ROLLING_WINDOWS


def normalize_ohlcv_frame(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize common OHLCV CSV shapes into a timestamp-indexed frame."""
    if df.empty:
        raise ValueError("Input data is empty")

    normalized = df.copy()
    normalized.columns = [str(col).strip() for col in normalized.columns]
    rename_map = {
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Volume": "volume",
        "start_time": "timestamp",
        "time": "timestamp",
        "date": "timestamp",
        "datetime": "timestamp",
    }
    normalized = normalized.rename(columns={k: v for k, v in rename_map.items() if k in normalized.columns})
    normalized.columns = [col.lower() if col in BASE_COLUMNS or col == "timestamp" else col for col in normalized.columns]

    if "timestamp" in normalized.columns:
        normalized["timestamp"] = pd.to_datetime(normalized["timestamp"], utc=False)
        normalized = normalized.set_index("timestamp")
    elif not isinstance(normalized.index, pd.DatetimeIndex):
        raise ValueError("Input data must include a timestamp column or a DatetimeIndex")

    missing = [col for col in BASE_COLUMNS if col not in normalized.columns]
    if missing:
        raise ValueError(f"Missing required OHLCV columns: {missing}")

    normalized = normalized.sort_index()
    normalized = normalized.loc[~normalized.index.duplicated(keep="last")]
    normalized = normalized[list(BASE_COLUMNS)].astype(float)
    return normalized


def load_ohlcv_csv(path: str) -> pd.DataFrame:
    return normalize_ohlcv_frame(pd.read_csv(path))


def resample_ohlcv_frame(df: pd.DataFrame, freq_minutes: int) -> pd.DataFrame:
    """Resample OHLCV candles to the model frequency."""
    if freq_minutes <= 0:
        raise ValueError("freq_minutes must be greater than zero")

    normalized = normalize_ohlcv_frame(df)
    rule = f"{freq_minutes}min"
    resampled = normalized.resample(rule).agg(
        {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
            "volume": "sum",
        }
    )
    return resampled.dropna(subset=list(BASE_COLUMNS))


def _add_lag_features(features: pd.DataFrame, source: pd.DataFrame, lags: Iterable[int]) -> None:
    for lag in lags:
        features[f"close_lag_{lag}"] = source["close"].shift(lag)
        features[f"volume_lag_{lag}"] = source["volume"].shift(lag)
        features[f"return_lag_{lag}"] = source["returns"].shift(lag)


def _add_rolling_features(features: pd.DataFrame, source: pd.DataFrame, windows: Iterable[int]) -> None:
    for window in windows:
        close_roll = source["close"].rolling(window)
        volume_roll = source["volume"].rolling(window)
        return_roll = source["returns"].rolling(window)
        features[f"close_mean_{window}"] = close_roll.mean()
        features[f"close_std_{window}"] = close_roll.std()
        features[f"close_min_{window}"] = close_roll.min()
        features[f"close_max_{window}"] = close_roll.max()
        features[f"volume_mean_{window}"] = volume_roll.mean()
        features[f"return_std_{window}"] = return_roll.std()


def build_feature_table(df: pd.DataFrame, config: FeatureConfig) -> pd.DataFrame:
    source = resample_ohlcv_frame(df, config.freq_minutes)
    features = source.copy()
    close = source["close"].replace(0, np.nan)
    open_price = source["open"].replace(0, np.nan)

    features["returns"] = source["close"].pct_change()
    features["log_returns"] = np.log(close / source["close"].shift(1).replace(0, np.nan))
    features["high_low_spread"] = (source["high"] - source["low"]) / close
    features["open_close_spread"] = (source["close"] - source["open"]) / open_price
    features["volume_change"] = source["volume"].pct_change()
    features["price_volume"] = source["close"] * source["volume"]

    _add_lag_features(features, features, config.lags)
    _add_rolling_features(features, features, config.rolling_windows)

    hour = features.index.hour + features.index.minute / 60.0
    features["hour_sin"] = np.sin(2 * np.pi * hour / 24.0)
    features["hour_cos"] = np.cos(2 * np.pi * hour / 24.0)
    features["day_of_week"] = features.index.dayofweek

    target = source["close"].shift(-config.horizon)
    features["target_close"] = target
    features["target_return"] = target / close - 1.0
    return features.replace([np.inf, -np.inf], np.nan)


def make_supervised_dataset(
    df: pd.DataFrame,
    config: FeatureConfig,
) -> tuple[pd.DataFrame, pd.Series, pd.Series, list[str]]:
    table = build_feature_table(df, config).dropna()
    if table.empty:
        raise ValueError("No usable rows after feature engineering; provide more historical data")

    feature_columns = [col for col in table.columns if col not in {"target_close", "target_return"}]
    return table[feature_columns], table["target_return"], table["target_close"], feature_columns


def make_latest_features(
    records: list[dict],
    feature_columns: list[str],
    config: FeatureConfig,
) -> tuple[pd.DataFrame, pd.Timestamp]:
    if not records:
        raise ValueError("At least one OHLCV record is required")

    raw = normalize_ohlcv_frame(pd.DataFrame(records))
    table = build_feature_table(raw, config)
    latest = table.drop(columns=["target_close", "target_return"], errors="ignore").tail(1)
    latest = latest.reindex(columns=feature_columns)
    latest = latest.replace([np.inf, -np.inf], np.nan)

    if latest.empty or latest.isna().all(axis=None):
        min_history = max(max(config.lags, default=1), max(config.rolling_windows, default=1)) + 1
        raise ValueError(
            f"Not enough history to build features; provide at least {min_history} "
            f"{config.freq_minutes}-minute OHLCV rows after resampling"
        )

    return latest, pd.Timestamp(latest.index[-1])
