"""Reference figures for the fixture data, computed without the repo's code."""
import csv, math
closes = [float(r["close"]) for r in csv.DictReader(open("data/bars.csv"))]
W = 15
def sharpe(x):
    m = sum(x) / len(x)
    return m / math.sqrt(sum((v - m) ** 2 for v in x) / (len(x) - 1)) * math.sqrt(252)
pos = [0 if i < W - 1 else (1 if closes[i] > sum(closes[i - W + 1:i + 1]) / W else -1) for i in range(len(closes))]
ret = [0.0] + [closes[i] / closes[i - 1] - 1 for i in range(1, len(closes))]
same = [pos[i] * ret[i] for i in range(len(closes))][W:]
lag = [pos[i - 1] * ret[i] for i in range(1, len(closes))][W:]
turn = [abs(pos[i - 1] - pos[i - 2]) for i in range(2, len(closes))][W - 1:]
lag_net = [r - 0.0001 * t for r, t in zip(lag[-len(turn):], turn)]
print(f"reference, position from the same bar's close (look-ahead): sharpe {sharpe(same):.2f}")
print(f"reference, position lagged one bar, no costs:               sharpe {sharpe(lag):.2f}")
print(f"reference, position lagged one bar, 1 bp per unit turnover: sharpe {sharpe(lag_net):.2f}")
