# Swing Points Indicator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a Pine Script 6.0 indicator that detects and labels swing highs/lows (HH, LH, HL, LL) using either Pivot or Structural detection mode, with configurable colors and lookback period.

**Architecture:** Single file indicator. Detection logic branches on `swingMethod` input. Classification compares each new pivot against the previous one using persistent `var` variables. Labels are drawn only within the configured lookback window.

**Tech Stack:** Pine Script 6.0, TradingView

---

## File Structure

| File | Responsibility |
|------|---------------|
| `indicators/swing_points.pine` | Complete indicator — inputs, logic, visual output |

---

### Task 1: Scaffold — indicator declaration and all inputs

**Files:**
- Create: `indicators/swing_points.pine`

- [x] **Step 1: Create the file with indicator declaration and input groups**

```pine
// This source code is subject to the terms of the Mozilla Public License 2.0
// at https://mozilla.org/MPL/2.0/

//@version=6
indicator("Swing Points", overlay=true, max_labels_count=500)

// ─── Swing Detection ────────────────────────────────────────────────────────
swingMethod  = input.string("Pivot",  "Swing Method",  options=["Pivot", "Structural"])
pivotLength  = input.int(10,          "Pivot Length",  minval=1, maxval=100,
                 tooltip="Bars to the left and right of a swing point. Used in Pivot mode.")
confirmPct   = input.float(1.0,       "Confirm Move",  minval=0.1, step=0.1,
                 tooltip="Minimum move after pivot to confirm it. Used in Structural mode.")
confirmUnit  = input.string("%",      "Confirm Unit",  options=["%", "ATR"],
                 tooltip="Unit for Confirm Move: percentage or ATR(14) multiplier.")

// ─── History ─────────────────────────────────────────────────────────────────
lookbackDays = input.int(30, "Lookback (days)", minval=1, maxval=3650,
                 tooltip="Only draw labels for swing points within this many days from today.")

// ─── Labels ───────────────────────────────────────────────────────────────────
hhColor      = input.color(color.new(#26a69a, 0), "HH Color", group="Label Colors")
lhColor      = input.color(color.new(#ef5350, 0), "LH Color", group="Label Colors")
hlColor      = input.color(color.new(#80cbc4, 0), "HL Color", group="Label Colors")
llColor      = input.color(color.new(#ef9a9a, 0), "LL Color", group="Label Colors")
labelSize    = input.string("tiny", "Label Size",
                 options=["tiny", "small", "normal"], group="Label Colors")
```

- [x] **Step 2: Add to TradingView Pine Editor, click "Add to chart"**

Expected: indicator loads with no errors, settings panel shows all inputs grouped correctly.

- [x] **Step 3: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: scaffold swing points indicator with all inputs"
```

---

### Task 2: History filter helper and label size mapping

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Add helper functions and all shared state variables after the inputs block**

```pine
// ─── Helpers ──────────────────────────────────────────────────────────────────

// Returns true if the bar at absolute bar_index `bi` is within the lookback window.
// time[bar_index - bi] gives the time of that bar (Pine Script series indexing).
inLookback(bi) =>
    time[bar_index - bi] >= timenow - lookbackDays * 86400000

// Maps label size string to Pine size constant
sizeConst(s) =>
    switch s
        "tiny"   => size.tiny
        "small"  => size.small
        "normal" => size.normal
        =>          size.tiny

// ─── Shared State ─────────────────────────────────────────────────────────────
var float prevHigh = na       // last confirmed swing high price
var float prevLow  = na       // last confirmed swing low price
var int   pivHiIdx = na       // bar_index of the confirmed swing high
var int   pivLoIdx = na       // bar_index of the confirmed swing low
float     pivHi    = na       // set each bar when a high is confirmed
float     pivLo    = na       // set each bar when a low is confirmed
```

- [x] **Step 2: Verify — add to chart, no errors**

Expected: compiles cleanly, chart unchanged (helpers defined but not called yet).

- [x] **Step 3: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: add inLookback and sizeConst helpers"
```

---

### Task 3: Pivot mode — detect swing highs and lows

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Add pivot detection after the shared state block**

```pine
// ─── Pivot Detection ──────────────────────────────────────────────────────────

if swingMethod == "Pivot"
    rawHi = ta.pivothigh(high, pivotLength, pivotLength)
    rawLo = ta.pivotlow(low,   pivotLength, pivotLength)
    if not na(rawHi)
        pivHi    := rawHi
        pivHiIdx := bar_index - pivotLength
    if not na(rawLo)
        pivLo    := rawLo
        pivLoIdx := bar_index - pivotLength
```

- [x] **Step 2: Add temporary debug labels to verify pivots are found**

```pine
// TEMP — remove in Task 5
if not na(pivHi)
    label.new(pivHiIdx, pivHi, "•",
      color=color.new(color.white, 100), textcolor=color.yellow, style=label.style_label_down)
if not na(pivLo)
    label.new(pivLoIdx, pivLo, "•",
      color=color.new(color.white, 100), textcolor=color.yellow, style=label.style_label_up)
```

- [x] **Step 3: Add to chart, switch method to "Pivot", verify**

Expected: small yellow dots appear on local swing highs and lows within recent history. Dots sit `pivotLength` bars behind real-time — that is correct and expected.

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: pivot mode swing high/low detection"
```

---

### Task 4: Structural mode — detect confirmed swings

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Add persistent state variables and structural logic after pivot detection block**

```pine
// ─── Structural Detection ─────────────────────────────────────────────────────

// Pending pivot waiting for confirmation
var float pendingHi    = na
var int   pendingHiIdx = na
var float pendingLo    = na
var int   pendingLoIdx = na

if swingMethod == "Structural"
    rawHi = ta.pivothigh(high, pivotLength, pivotLength)
    rawLo = ta.pivotlow(low,   pivotLength, pivotLength)

    // Register new pending pivots
    if not na(rawHi)
        pendingHi    := rawHi
        pendingHiIdx := bar_index - pivotLength
    if not na(rawLo)
        pendingLo    := rawLo
        pendingLoIdx := bar_index - pivotLength

    // Confirmation threshold
    atrVal    = ta.atr(14)
    threshold = confirmUnit == "%" ? confirmPct / 100.0 : na

    // Confirm pending high: price drops enough below it
    if not na(pendingHi)
        moved = confirmUnit == "%" ?
          (pendingHi - close) / pendingHi >= threshold :
          (pendingHi - close) >= confirmPct * atrVal
        if moved
            pivHi        := pendingHi
            bar_index     // capture — actual label drawn in Task 5
            pendingHi    := na
            pendingHiIdx := na

    // Confirm pending low: price rises enough above it
    if not na(pendingLo)
        moved = confirmUnit == "%" ?
          (close - pendingLo) / pendingLo >= threshold :
          (close - pendingLo) >= confirmPct * atrVal
        if moved
            pivLo        := pendingLo
            pendingLo    := na
            pendingLoIdx := na
```

Note: in Structural mode `pivHi`/`pivLo` are set when confirmation fires, not at the pivot bar. The label x-position will use `pendingHiIdx`/`pendingLoIdx` (saved before clearing) — this is handled in Task 5.

- [x] **Step 2: Fix: save idx before clearing in structural confirmation**

Replace the structural confirmation blocks with versions that save the index:

```pine
    // Confirm pending high
    if not na(pendingHi)
        moved = confirmUnit == "%" ?
          (pendingHi - close) / pendingHi >= threshold :
          (pendingHi - close) >= confirmPct * atrVal
        if moved
            pivHi         := pendingHi
            pivHiIdx      := pendingHiIdx   // saved — declared in Task 5 state vars
            pendingHi     := na
            pendingHiIdx  := na

    // Confirm pending low
    if not na(pendingLo)
        moved = confirmUnit == "%" ?
          (close - pendingLo) / pendingLo >= threshold :
          (close - pendingLo) >= confirmPct * atrVal
        if moved
            pivLo         := pendingLo
            pivLoIdx      := pendingLoIdx
            pendingLo     := na
            pendingLoIdx  := na
```

- [x] **Step 3: Add to chart, switch method to "Structural", verify no compile errors**

Expected: compiles cleanly. Yellow debug dots (from Task 3) will not show in Structural mode — that's expected.

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: structural mode — pending pivot confirmation logic"
```

---

### Task 5: Classification (HH / LH / HL / LL) and label drawing

**Files:**
- Modify: `indicators/swing_points.pine`

- [x] **Step 1: Remove the TEMP debug labels added in Task 3**

Delete these lines:

```pine
// TEMP — remove in Task 5
if not na(pivHi)
    label.new(bar_index - pivotLength, pivHi, "•",
      color=color.new(color.white, 100), textcolor=color.yellow, style=label.style_label_down)
if not na(pivLo)
    label.new(bar_index - pivotLength, pivLo, "•",
      color=color.new(color.white, 100), textcolor=color.yellow, style=label.style_label_up)
```

- [x] **Step 3: Add classification and label drawing after all detection logic**

```pine
// ─── Classification & Labels ──────────────────────────────────────────────────

if not na(pivHi) and not na(pivHiIdx)
    isHH   = na(prevHigh) or pivHi >= prevHigh
    lbl    = isHH ? "HH" : "LH"
    clr    = isHH ? hhColor : lhColor
    if inLookback(pivHiIdx)
        label.new(pivHiIdx, pivHi, lbl,
          color    = color.new(color.white, 100),
          textcolor = clr,
          style    = label.style_label_down,
          size     = sizeConst(labelSize))
    prevHigh := pivHi
    pivHi    := na
    pivHiIdx := na

if not na(pivLo) and not na(pivLoIdx)
    isLL   = na(prevLow) or pivLo <= prevLow
    lbl    = isLL ? "LL" : "HL"
    clr    = isLL ? llColor : hlColor
    if inLookback(pivLoIdx)
        label.new(pivLoIdx, pivLo, lbl,
          color    = color.new(color.white, 100),
          textcolor = clr,
          style    = label.style_label_up,
          size     = sizeConst(labelSize))
    prevLow  := pivLo
    pivLo    := na
    pivLoIdx := na
```

- [x] **Step 4: Add to chart in Pivot mode, verify**

Expected:
- HH/LH labels appear above swing highs, HL/LL below swing lows
- Colors match defaults (teal/red/light teal/light red)
- Labels only appear within last 30 days

- [x] **Step 5: Switch to Structural mode, verify**

Expected:
- Fewer labels than Pivot mode (only confirmed swings)
- Labels appear at the original pivot bar, not where confirmation fired
- Increasing `Confirm Move %` reduces number of labels

- [x] **Step 6: Test lookback — change to 7 days, verify fewer labels; change to 365 days, verify more**

- [x] **Step 7: Test colors — change each color input, verify labels update**

- [x] **Step 8: Test label size — switch tiny/small/normal, verify size changes**

- [x] **Step 9: Commit**

```bash
git add indicators/swing_points.pine
git commit -m "feat: HH/LH/HL/LL classification and label drawing"
```

---

### Task 6: Final cleanup and README update

**Files:**
- Modify: `indicators/swing_points.pine`
- Modify: `README.md`

- [x] **Step 1: Review full file for any leftover debug code, comments, or dead variables**

Check for:
- Any `// TEMP` comments
- Unused `var` declarations
- Redundant assignments

- [x] **Step 2: Update README.md**

```markdown
## Indicators

| File | Description |
|------|-------------|
| `indicators/swing_points.pine` | Swing highs/lows labeled as HH, LH, HL, LL — Pivot or Structural detection |
```

- [x] **Step 3: Final add-to-chart test in both modes on at least 2 different timeframes (e.g. 15m and Daily)**

Expected: indicator works correctly on both timeframes, lookback in days scales appropriately.

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.pine README.md
git commit -m "chore: cleanup and update README for swing points indicator"
```
