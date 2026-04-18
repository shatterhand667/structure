# MT5 Swing Points — Design Spec

**Date:** 2026-04-18  
**Project:** Struktura  
**Language:** MQL5  
**Platform:** MetaTrader 5  
**File:** `indicators/swing_points.mq5`  
**Reference:** `indicators/swing_points.pine` (1:1 feature parity)

---

## Overview

MQL5 port of `swing_points.pine`. Purely graphical indicator (`indicator_plots 0`) that detects and labels swing highs/lows (HH, LH, HL, LL) and runs a Grab and Go liquidity sweep scanner. All features and inputs mirror the Pine Script version.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `indicators/swing_points.mq5` | Complete indicator — inputs, OnCalculate, all logic and visuals |

---

## Inputs

```mql5
enum ENUM_SWING_METHOD { Pivot, Structural };
enum ENUM_CONFIRM_UNIT { Percent, ATR_Multi };
enum ENUM_LINE_STYLE   { Solid, Dashed, Dotted };

// Swing Detection
input ENUM_SWING_METHOD SwingMethod   = Pivot;
input int               PivotLength   = 10;
input double            ConfirmPct    = 1.0;
input ENUM_CONFIRM_UNIT ConfirmUnit   = Percent;

// History
input int               LookbackDays  = 30;

// Label Colors
input color             HHColor       = clrMediumAquamarine;
input color             LHColor       = clrRed;
input color             HLColor       = clrMediumAquamarine;
input color             LLColor       = clrLightCoral;
input int               LabelFontSize = 8;

// Grab and Go
input bool              ShowS1        = true;
input bool              ShowS2        = true;
input int               MaxSweepLines = 5;
input color             BullishColor  = clrMediumAquamarine;
input color             BearishColor  = clrRed;
input int               SigArrowSize  = 2;
input ENUM_LINE_STYLE   SweepStyle    = Solid;
input int               SweepWidth    = 1;
```

---

## Architecture

Single file, `OnCalculate`-based. Logic split into focused functions called from `OnCalculate`.

### Object Naming Convention

All chart objects prefixed `"SP_"` for bulk deletion on full recalculation:
- Swing labels: `"SP_LBL_" + (string)barTime`
- Sweep lines: `"SP_LINE_" + (string)barTime`
- S1 signals: `"SP_S1_" + (string)barTime`
- S2 signals: `"SP_S2_" + (string)barTime`

### Full Recalculation

When `prev_calculated == 0`: `ObjectsDeleteAll(0, "SP_")`, reset all state variables, reprocess full history.

### Bar Iteration

MT5 bars: `0 = current`, `rates_total-1 = oldest`. Iterate oldest→newest:
```
int start = (prev_calculated == 0) ? PivotLength : prev_calculated - 1;
for(int i = start; i < rates_total - PivotLength; i++) { ... }
```

---

## Logic

### Pivot Detection

```mql5
bool IsPivotHigh(int i, const double &h[], int len) {
    for(int j = 1; j <= len; j++)
        if(h[i] <= h[i-j] || h[i] <= h[i+j]) return false;
    return true;
}
bool IsPivotLow(int i, const double &l[], int len) {
    for(int j = 1; j <= len; j++)
        if(l[i] >= l[i-j] || l[i] >= l[i+j]) return false;
    return true;
}
```

Note: in OnCalculate, explicitly call `ArraySetAsSeries(high, false)` etc. so that index 0 = oldest bar, index `rates_total-1` = current bar. Iteration goes oldest→newest, consistent with the loop above.

### Structural Mode

When `IsPivotHigh(i)` → store `pendingHi = high[i]`, `pendingHiBar = i`. On subsequent bars check confirmation:
- `%`: `(pendingHi - close[i]) / pendingHi >= ConfirmPct / 100.0`
- `ATR`: `(pendingHi - close[i]) >= ConfirmPct * iATR(Symbol(), Period(), 14, i)`

When confirmed: set `pivHi = pendingHi`, `pivHiBar = pendingHiBar`, clear pending.

### Classification

```mql5
static double prevHigh = EMPTY_VALUE;
static double prevLow  = EMPTY_VALUE;
// pivHi >= prevHigh → HH, else LH
// pivLo <= prevLow  → LL, else HL
```

### History Filter

```mql5
datetime barTime = iTime(Symbol(), Period(), rates_total - 1 - i);
if(barTime < TimeCurrent() - LookbackDays * 86400) continue; // skip old bars
```

Wait — in OnCalculate with AS_SERIES=true, `time[i]` gives bar time directly.

Corrected:
```mql5
if(time[i] < TimeCurrent() - (datetime)(LookbackDays * 86400)) skip drawing label
```

### Swing Labels

`ObjectCreate(0, name, OBJ_TEXT, 0, time[pivBar], price)` with `OBJPROP_COLOR`, `OBJPROP_FONTSIZE`, `OBJPROP_TEXT` = "HH"/"LH"/"HL"/"LL", `OBJPROP_ANCHOR` = ANCHOR_LOWER (for highs) / ANCHOR_UPPER (for lows).

### Grab and Go — Sweep Tracking

Parallel arrays (max `MaxSweepLines` entries):
```mql5
double   sweepHiPrices[];
datetime sweepHiTimes[];
string   sweepHiLineNames[];
// same for Lo
```

When swing high confirmed: draw `OBJ_TREND` line from `time[pivBar]` extending right (`OBJPROP_RAY_RIGHT = true`). Store name, price, time in arrays. If array exceeds `MaxSweepLines`, delete oldest line object and shift array.

When `high[i] > sweepHiPrices[j]`: `ObjectSetInteger(0, lineNames[j], OBJPROP_TIME, 1, time[i])` sets x2 to signal bar, `ObjectSetInteger(0, lineNames[j], OBJPROP_RAY_RIGHT, false)` stops extension. Remove from array.

### Signal 1 — Pin Bar

On sweep bar `i`:
- High sweep: `upperWick = high[i] - MathMax(open[i], close[i])`, condition: `upperWick / (high[i] - low[i]) >= 0.65`
- Low sweep: `lowerWick = MathMin(open[i], close[i]) - low[i]`, condition: `lowerWick / (high[i] - low[i]) >= 0.65`

Draw `OBJ_ARROW` with `OBJPROP_ARROWCODE = 233` (down triangle) for bearish, `234` (up triangle) for bullish.

### Signal 2 — Next Candle (1st or 2nd)

State variables:
```mql5
static int    s2Dir        = 0;
static double s2SigHigh    = EMPTY_VALUE;
static double s2SigLow     = EMPTY_VALUE;
static int    s2BarsWaited = 0;
```

On each bar, before sweep detection: if `s2Dir != 0`, increment `s2BarsWaited`. Check condition:
- Bullish (`s2Dir == 1`): `close[i] > s2SigLow + (s2SigHigh - s2SigLow) * 0.5`
- Bearish (`s2Dir == -1`): `close[i] < s2SigHigh - (s2SigHigh - s2SigLow) * 0.5`

If met: draw S2 arrow, reset state. If `s2BarsWaited >= 2`: reset state (give up).

---

## Visual Object Summary

| Object | Type | Condition |
|--------|------|-----------|
| HH/LH/HL/LL | `OBJ_TEXT` | Swing confirmed + in lookback |
| Sweep line | `OBJ_TREND` | Swing confirmed (extends right, stopped at sweep) |
| S1 arrow | `OBJ_ARROW` | Sweep bar is pin bar |
| S2 arrow | `OBJ_ARROW` | 1st or 2nd bar after sweep closes past 50% |

---

## Out of Scope

- Alerts
- Multi-timeframe
- EA / Script mode
