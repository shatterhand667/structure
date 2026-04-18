# Grab and Go Scanner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Extend `indicators/swing_points.pine` with a Grab and Go scanner that detects liquidity sweeps at swing levels, draws a horizontal line to the signal candle, and marks two reversal signal types (pin bar and next-candle close).

**Architecture:** New inputs group added to existing file. Sweep levels tracked in four `array` variables fed from the existing classification block. Sweep detection uses a `while` loop per bar. Signal 1 evaluated on the sweep bar itself; Signal 2 state persisted via `var` and evaluated on the following bar.

**Tech Stack:** Pine Script 6.0, TradingView

---

## File Structure

| File | Change |
|------|--------|
| `indicators/swing_points.pine` | Modify — add inputs, arrays, sweep detection, S1, S2 |

---

### Task 1: Add inputs and update indicator declaration

**Files:**
- Modify: `indicators/swing_points.pine:5`

- [x] **Step 1: Add `max_lines_count` to indicator declaration (line 5)**

Replace:
```pine
indicator("Swing Points", overlay=true, max_labels_count=500)
```
With:
```pine
indicator("Swing Points", overlay=true, max_labels_count=500, max_lines_count=500)
```

- [x] **Step 2: Add Grab and Go input group after the Label Colors block (after line 26)**

```pine
// ─── Grab and Go ─────────────────────────────────────────────────────────────
showS1       = input.bool(true,  "Show Signal 1 (Pin Bar)",     group="Grab and Go",
                 tooltip="Mark the signal candle when its wick is 65%+ of the candle range, in the direction of the sweep.")
showS2       = input.bool(true,  "Show Signal 2 (Next Candle)", group="Grab and Go",
                 tooltip="Mark the candle after the signal candle when it closes past the 50% level of the signal candle's range, reversing the sweep direction.")
maxSweepLines = input.int(5,     "Max Sweep Lines",             group="Grab and Go",
                 minval=1, maxval=20,
                 tooltip="How many recent swing levels to watch for sweeps. Oldest levels are dropped when the limit is reached.")
bullishColor  = input.color(color.new(#26a69a, 0), "Bullish Color", group="Grab and Go",
                 tooltip="Color for bullish signals and lines (sweep of a low, reversal up).")
bearishColor  = input.color(color.new(#ef5350, 0), "Bearish Color", group="Grab and Go",
                 tooltip="Color for bearish signals and lines (sweep of a high, reversal down).")
sigSize       = input.string("small", "Signal Size",            group="Grab and Go",
                 options=["tiny", "small", "normal"])
```

- [x] **Step 3: Add to TradingView, verify no errors and inputs appear under "Grab and Go" group**

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: add Grab and Go inputs and update indicator declaration"
```

---

### Task 2: Add sweep tracking arrays and feed from classification block

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Add array declarations to the Shared State block (after the existing `var` declarations, before Pivot Detection)**

```pine
// Sweep level tracking arrays (Grab and Go)
var sweepHiPrices = array.new_float(0)
var sweepHiIdxs   = array.new_int(0)
var sweepLoPrices = array.new_float(0)
var sweepLoIdxs   = array.new_int(0)
```

- [x] **Step 2: Feed swing highs into sweep array — add inside the Classification block for highs, before `pivHiIdx := na`**

Current classification block for highs:
```pine
if not na(pivHi) and not na(pivHiIdx)
    isHH = na(prevHigh) or pivHi >= prevHigh
    lbl  = isHH ? "HH" : "LH"
    clr  = isHH ? hhColor : lhColor
    if inLookback(pivHiIdx)
        label.new(pivHiIdx, pivHi, lbl,
          color     = color.new(color.white, 100),
          textcolor = clr,
          style     = label.style_label_down,
          size      = sizeConst(labelSize))
    prevHigh := pivHi
    pivHiIdx := na
```

Replace with:
```pine
if not na(pivHi) and not na(pivHiIdx)
    isHH = na(prevHigh) or pivHi >= prevHigh
    lbl  = isHH ? "HH" : "LH"
    clr  = isHH ? hhColor : lhColor
    if inLookback(pivHiIdx)
        label.new(pivHiIdx, pivHi, lbl,
          color     = color.new(color.white, 100),
          textcolor = clr,
          style     = label.style_label_down,
          size      = sizeConst(labelSize))
    // Feed sweep tracker
    array.push(sweepHiPrices, pivHi)
    array.push(sweepHiIdxs,   pivHiIdx)
    if array.size(sweepHiPrices) > maxSweepLines
        array.shift(sweepHiPrices)
        array.shift(sweepHiIdxs)
    prevHigh := pivHi
    pivHiIdx := na
```

- [x] **Step 3: Feed swing lows into sweep array — same pattern for the lows classification block**

Replace:
```pine
if not na(pivLo) and not na(pivLoIdx)
    isLL = na(prevLow) or pivLo <= prevLow
    lbl  = isLL ? "LL" : "HL"
    clr  = isLL ? llColor : hlColor
    if inLookback(pivLoIdx)
        label.new(pivLoIdx, pivLo, lbl,
          color     = color.new(color.white, 100),
          textcolor = clr,
          style     = label.style_label_up,
          size      = sizeConst(labelSize))
    prevLow  := pivLo
    pivLoIdx := na
```

With:
```pine
if not na(pivLo) and not na(pivLoIdx)
    isLL = na(prevLow) or pivLo <= prevLow
    lbl  = isLL ? "LL" : "HL"
    clr  = isLL ? llColor : hlColor
    if inLookback(pivLoIdx)
        label.new(pivLoIdx, pivLo, lbl,
          color     = color.new(color.white, 100),
          textcolor = clr,
          style     = label.style_label_up,
          size      = sizeConst(labelSize))
    // Feed sweep tracker
    array.push(sweepLoPrices, pivLo)
    array.push(sweepLoIdxs,   pivLoIdx)
    if array.size(sweepLoPrices) > maxSweepLines
        array.shift(sweepLoPrices)
        array.shift(sweepLoIdxs)
    prevLow  := pivLo
    pivLoIdx := na
```

- [x] **Step 4: Add to TradingView, verify no errors. Swing labels should still work normally.**

- [x] **Step 5: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: track swing levels in sweep arrays"
```

---

### Task 3: Sweep detection and line drawing

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Add Signal 2 state variables to the Shared State block (after sweep arrays)**

```pine
// Signal 2 pending state
var int   s2Dir     = 0    // 1 = bullish pending, -1 = bearish pending, 0 = none
var float s2SigHigh = na   // signal candle high
var float s2SigLow  = na   // signal candle low
```

- [x] **Step 2: Add sweep detection section at the end of the file**

```pine
// ─── Grab and Go ──────────────────────────────────────────────────────────────

// Signal 2: check previous bar's sweep against current close
if s2Dir == 1 and showS2
    if close > s2SigLow + (s2SigHigh - s2SigLow) * 0.5
        label.new(bar_index, low, "",
          color = bullishColor, style = label.style_triangleup,
          size  = sizeConst(sigSize))
    s2Dir := 0

if s2Dir == -1 and showS2
    if close < s2SigHigh - (s2SigHigh - s2SigLow) * 0.5
        label.new(bar_index, high, "",
          color = bearishColor, style = label.style_triangledown,
          size  = sizeConst(sigSize))
    s2Dir := 0

// Detect high sweeps
int hiI = 0
while hiI < array.size(sweepHiPrices)
    swingPrice = array.get(sweepHiPrices, hiI)
    swingIdx   = array.get(sweepHiIdxs,   hiI)
    if high > swingPrice
        line.new(swingIdx, swingPrice, bar_index, swingPrice,
          color  = bearishColor,
          width  = 1,
          extend = extend.none)
        // Signal 1 — pin bar (upper wick >= 65% of range)
        if showS1 and (high - low) > 0
            upperWick = high - math.max(open, close)
            if upperWick / (high - low) >= 0.65
                label.new(bar_index, high, "",
                  color = bearishColor, style = label.style_triangledown,
                  size  = sizeConst(sigSize))
        // Set Signal 2 state
        s2Dir     := -1
        s2SigHigh := high
        s2SigLow  := low
        array.remove(sweepHiPrices, hiI)
        array.remove(sweepHiIdxs,   hiI)
    else
        hiI += 1

// Detect low sweeps
int loI = 0
while loI < array.size(sweepLoPrices)
    swingPrice = array.get(sweepLoPrices, loI)
    swingIdx   = array.get(sweepLoIdxs,   loI)
    if low < swingPrice
        line.new(swingIdx, swingPrice, bar_index, swingPrice,
          color  = bullishColor,
          width  = 1,
          extend = extend.none)
        // Signal 1 — pin bar (lower wick >= 65% of range)
        if showS1 and (high - low) > 0
            lowerWick = math.min(open, close) - low
            if lowerWick / (high - low) >= 0.65
                label.new(bar_index, low, "",
                  color = bullishColor, style = label.style_triangleup,
                  size  = sizeConst(sigSize))
        // Set Signal 2 state
        s2Dir     := 1
        s2SigHigh := high
        s2SigLow  := low
        array.remove(sweepLoPrices, loI)
        array.remove(sweepLoIdxs,   loI)
    else
        loI += 1
```

- [x] **Step 3: Add to TradingView, verify no compile errors**

Expected: compiles cleanly. Swing labels unchanged.

- [x] **Step 4: Test — find a visible swing high on chart, wait or scroll to a candle that swept it**

Expected:
- A horizontal line appears from the swing high to the sweeping candle
- If the sweeping candle has a long upper wick — a red triangle appears above it
- If next candle closes below 50% of signal candle range — a red triangle appears above that candle

- [x] **Step 5: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: sweep detection, line drawing, S1 pin bar, S2 next candle"
```

---

### Task 4: Final verification and cleanup

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Review full file — check for any leftover issues**

Verify:
- `max_lines_count=500` present in `indicator()` declaration
- No dead variables or duplicate declarations
- All input groups clearly separated with comments

- [x] **Step 2: Test Show S1 / Show S2 toggles**

Expected:
- Disabling Show S1 removes pin bar triangles, lines still appear
- Disabling Show S2 removes next-candle triangles, lines still appear
- Both can be disabled simultaneously — only lines remain

- [x] **Step 3: Test Max Sweep Lines = 1 (edge case)**

Expected: only the most recent swing level tracked, older ones ignored.

- [x] **Step 4: Test color inputs — change bullish/bearish colors**

Expected: lines and triangles update to match.

- [x] **Step 5: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "chore: verify and finalize grab and go scanner"
```
