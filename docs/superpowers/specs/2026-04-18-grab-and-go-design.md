# Grab and Go Scanner — Design Spec

**Date:** 2026-04-18  
**Project:** Struktura  
**Language:** Pine Script 6.0  
**Platform:** TradingView  
**File:** `indicators/swing_points.pine` (extension of existing indicator)

---

## Overview

Extend `swing_points.pine` with a "Grab and Go" scanner that detects liquidity sweeps at labeled swing levels and marks two reversal signal types. A horizontal line is drawn from the swing level to the signal candle. Two signal types are supported, each independently togglable.

---

## New Inputs (group: "Grab and Go")

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| Show Signal 1 (Pin Bar) | bool | true | Show S1 signals |
| Show Signal 2 (Next Candle) | bool | true | Show S2 signals |
| Max Sweep Lines | int | 5 | How many recent sweep lines to track and draw |
| Bullish Signal Color | color | green | Color for bullish S1/S2 signals and lines |
| Bearish Signal Color | color | red | Color for bearish S1/S2 signals and lines |
| Signal Size | string | tiny | `[tiny, small, normal]` — size of signal labels |

---

## Logic

### Tracking Swing Levels

Two `array<float>` and two `array<int>` arrays track the most recent N confirmed swing highs and lows (price and bar_index). When a new swing high/low is confirmed by the existing detection logic, it is appended to the corresponding arrays. If the array size exceeds `Max Sweep Lines`, the oldest entry is removed.

```
sweepHiPrices : array<float>   — prices of tracked swing highs
sweepHiIdxs   : array<int>     — bar_index of tracked swing highs
sweepLoPrices : array<float>   — prices of tracked swing lows
sweepLoIdxs   : array<int>     — bar_index of tracked swing lows
```

### Sweep Detection

On each bar, iterate over all tracked swing levels:

- **High sweep:** `high > sweepHiPrices[i]` → signal candle broke above swing high
- **Low sweep:** `low < sweepLoPrices[i]` → signal candle broke below swing low

When a sweep is detected:
1. Draw a horizontal `line.new()` from `sweepHiIdxs[i]` (or `sweepLoIdxs[i]`) to `bar_index`, at the swing level price. Line ends at the signal candle — `extend=extend.none`.
2. Remove the swept level from the array (it has been consumed).
3. Record the signal candle's data for signal evaluation.

### Signal 1 — Pin Bar (evaluated on signal candle)

- **Low sweep:** lower wick ≥ 65% of total range → bullish signal
  - `lower_wick = min(open, close) - low`
  - `condition: lower_wick / (high - low) >= 0.65`
- **High sweep:** upper wick ≥ 65% of total range → bearish signal
  - `upper_wick = high - max(open, close)`
  - `condition: upper_wick / (high - low) >= 0.65`

Draw: `label.new()` with `label.style_triangleup` (bullish) or `label.style_triangledown` (bearish) on the signal candle.

### Signal 2 — Next Candle (evaluated on the bar after the signal candle)

Requires storing signal candle's high/low and direction via `var` variables.

- **Low sweep:** `close > signal_low + (signal_high - signal_low) * 0.5` → bullish
- **High sweep:** `close < signal_high - (signal_high - signal_low) * 0.5` → bearish

Signal candle's close does not matter — only the next candle's close is evaluated.

Draw: `label.new()` with `label.style_triangleup` / `label.style_triangledown` on the confirming candle.

---

## Visual Output

| Element | Description |
|---------|-------------|
| Horizontal line | From swing bar to signal candle bar, at swing level price, `extend.none` |
| S1 triangle | On signal candle, bullish = triangle up below bar, bearish = triangle down above bar |
| S2 triangle | On next candle after signal, same orientation as S1 |

Line and signal colors follow `Bullish Signal Color` / `Bearish Signal Color` inputs.

---

## Out of Scope

- Alerts
- Multi-timeframe
- Signal statistics or win rate tracking
- Combining S1 + S2 into a single "stronger" signal
