#!/usr/bin/env python3
"""Trend-following backtest on daily bars.

Long when the close is above its moving average, short when below.

    python3 backtest.py [data/bars.csv] [--window N]
"""
import argparse
import csv
import math
from dataclasses import dataclass

TRADING_DAYS = 252


@dataclass
class Bar:
    date: str
    open: float
    high: float
    low: float
    close: float
    volume: int


def load_bars(path):
    with open(path, newline="") as f:
        return [
            Bar(
                row["date"],
                float(row["open"]),
                float(row["high"]),
                float(row["low"]),
                float(row["close"]),
                int(row["volume"]),
            )
            for row in csv.DictReader(f)
        ]


def moving_average(values, window):
    """Trailing mean of the last `window` values, None until there are enough."""
    out = []
    total = 0.0
    for i, value in enumerate(values):
        total += value
        if i >= window:
            total -= values[i - window]
        out.append(total / window if i >= window - 1 else None)
    return out


def positions(closes, window):
    """+1 long, -1 short, 0 flat while the average warms up."""
    average = moving_average(closes, window)
    out = []
    for close, mean in zip(closes, average):
        if mean is None:
            out.append(0)
        else:
            out.append(1 if close > mean else -1)
    return out


def daily_returns(closes):
    return [0.0] + [closes[i] / closes[i - 1] - 1.0 for i in range(1, len(closes))]


def strategy_returns(closes, window):
    position = positions(closes, window)
    returns = daily_returns(closes)
    return [position[i] * returns[i] for i in range(len(closes))]


def sharpe(returns):
    mean = sum(returns) / len(returns)
    variance = sum((r - mean) ** 2 for r in returns) / (len(returns) - 1)
    return mean / math.sqrt(variance) * math.sqrt(TRADING_DAYS)


def max_drawdown(returns):
    equity = peak = 1.0
    worst = 0.0
    for r in returns:
        equity *= 1.0 + r
        peak = max(peak, equity)
        worst = min(worst, equity / peak - 1.0)
    return worst


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bars", nargs="?", default="data/bars.csv")
    parser.add_argument("--window", type=int, default=15)
    args = parser.parse_args()

    bars = load_bars(args.bars)
    closes = [bar.close for bar in bars]
    returns = strategy_returns(closes, args.window)[args.window:]

    total = math.prod(1.0 + r for r in returns) - 1.0
    print(f"bars         {len(bars)} ({bars[0].date} to {bars[-1].date})")
    print(f"window       {args.window}")
    print(f"total return {total:+.1%}")
    print(f"sharpe       {sharpe(returns):.2f}")
    print(f"max drawdown {max_drawdown(returns):.1%}")


if __name__ == "__main__":
    main()
