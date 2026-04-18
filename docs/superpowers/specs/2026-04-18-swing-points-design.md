# Swing Points Indicator — Design Spec

**Date:** 2026-04-18  
**Project:** Struktura  
**Language:** Pine Script 6.0  
**Platform:** TradingView  

---

## Overview

A single-file Pine Script indicator that detects and labels swing highs and lows on any timeframe. Each point is classified as HH (Higher High), LH (Lower High), HL (Higher Low), or LL (Lower Low). The user can choose between two detection methods and configure visual appearance.

---

## Inputs

### Swing Detection

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| Swing Method | string | `Pivot` | `[Pivot, Structural]` |
| Pivot Length | int | `10` | Used in Pivot mode — bars left/right |
| Confirm Move % | float | `1.0` | Used in Structural mode — minimum move after pivot |
| Confirm Move Unit | string | `%` | `[%, ATR]` — how to measure the confirmation move |

### History

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| Lookback (days) | int | `30` | Only draw labels for points within this many days |

### Labels

| Input | Type | Default |
|-------|------|---------|
| HH Color | color | green |
| LH Color | color | red |
| HL Color | color | lime |
| LL Color | color | orange |
| Label Size | string | `tiny` — `[tiny, small, normal]` |

---

## Logic

### Pivot Mode

Uses `ta.pivothigh(high, length, length)` and `ta.pivotlow(low, length, length)` to detect local extrema. A point is confirmed as a swing high when `length` bars to the left and right are all lower. Classification happens immediately when the pivot is confirmed (i.e., `length` bars after the actual swing bar).

### Structural Mode

Same pivot detection as above, but the label is only drawn once price has moved at least `Confirm Move` units away from the pivot level after confirmation:
- In `%` mode: price moves `Confirm Move %` percent below the pivot high (or above the pivot low)
- In `ATR` mode: price moves `Confirm Move × ATR(14)` away from the pivot level

The confirmation is checked on each subsequent bar after the pivot is detected. Once confirmed, the label is placed at the original pivot bar.

### Classification (both modes)

Two persistent variables track the most recent confirmed swing high and low:

```
var float prevHigh = na
var float prevLow  = na
```

- `pivHi >= prevHigh` → **HH**, otherwise → **LH**
- `pivLo <= prevLow`  → **LL**, otherwise → **HL**

### History Filter

Labels are only drawn if the pivot bar's `time` falls within the lookback window:

```
time >= (timenow - lookback_days * 86400000)
```

---

## Visual Output

Each confirmed swing point generates a `label.new()` call:

| Property | Value |
|----------|-------|
| x | `bar_index` of the pivot bar |
| y | `pivHi` or `pivLo` |
| text | `"HH"`, `"LH"`, `"HL"`, or `"LL"` |
| color | transparent background |
| textcolor | user-selected color per label type |
| style | `label.style_label_down` for highs, `label.style_label_up` for lows |
| size | user-selected label size |

Indicator declaration: `indicator("Swing Points", overlay=true, max_labels_count=500)`

---

## Out of Scope

- Trend lines connecting swing points
- BOS / CHoCH detection
- Alerts
- Multi-timeframe analysis
