# Supply & Demand Zones — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Pine Script 6.0 indicator that detects supply and demand zones (Skorupinski PFZ/WFZ methodology), scores each zone 0–10, and fades/removes zones as price revisits them.

**Architecture:** Single file `indicators/supply_demand.pine`. Zone detection fires when `ta.pivothigh`/`ta.pivotlow` confirms a pivot — the indicator scans backwards for a small-body base and forwards for a strong departure. Each zone stores two `box.new()` objects (PFZ + WFZ) and a `label.new()` score label in parallel `var` arrays. A mitigation loop runs every bar to track touch state and breach.

**Tech Stack:** Pine Script 6.0, TradingView

---

## File Structure

| File | Change |
|------|--------|
| `indicators/supply_demand.pine` | Create — complete indicator |
| `README.md` | Modify — add indicator entry |

---

### Task 1: Scaffold — indicator declaration, inputs, state arrays, stubs

**Files:**
- Create: `indicators/supply_demand.pine`

- [ ] **Step 1: Create the file**

```pine
// This source code is subject to the terms of the Mozilla Public License 2.0
// at https://mozilla.org/MPL/2.0/

//@version=6
indicator("Supply & Demand Zones", overlay=true, max_boxes_count=200, max_labels_count=200)

// ─── Zone Detection ───────────────────────────────────────────────────────────
pivotLength       = input.int(5,   "Pivot Length",          minval=1, maxval=20,
                     tooltip="Bars to the left and right required to confirm a pivot high/low.")
maxBaseCandles    = input.int(4,   "Max Base Candles",       minval=1, maxval=5,
                     tooltip="Maximum number of small-body candles that form the base before the impulse.")
baseBodyMult      = input.float(0.5, "Base Body Mult",       minval=0.1, step=0.1,
                     tooltip="A base candle's body must be smaller than this multiple of ATR(14).")
departureBodyMult = input.float(1.5, "Departure Body Mult",  minval=0.5, step=0.1,
                     tooltip="At least one departure candle's body must exceed this multiple of ATR(14).")

// ─── History ──────────────────────────────────────────────────────────────────
lookbackDays = input.int(60, "Lookback (days)", minval=1, maxval=3650,
                tooltip="Only draw zones for pivots within this many days from today.")

// ─── Filtering ────────────────────────────────────────────────────────────────
minScore    = input.int(3,     "Min Score",    minval=0, maxval=10, group="Filtering",
               tooltip="Hide zones with a quality score below this value. 0 = show all.")
trendFilter = input.bool(true, "Trend Filter", group="Filtering",
               tooltip="When enabled, only shows demand zones in uptrend and supply zones in downtrend.")

// ─── Visual ───────────────────────────────────────────────────────────────────
demandColor = input.color(color.new(#26a69a, 0), "Demand Color", group="Visual")
supplyColor = input.color(color.new(#ef5350, 0), "Supply Color", group="Visual")
showLabels  = input.bool(true, "Show Labels", group="Visual",
               tooltip="Show score label on the right edge of each zone.")
showWFZ     = input.bool(true, "Show WFZ",   group="Visual",
               tooltip="Show the Wider Fresh Zone (full base range) as a faded outer box.")

// ─── State constants ──────────────────────────────────────────────────────────
FRESH     = 0   // zone never touched
TOUCHED_1 = 1   // zone entered once
TOUCHED_2 = 2   // zone entered twice

// ─── Trend tracking (last 2 confirmed pivot highs and lows) ───────────────────
var float prevHi1 = na
var float prevHi2 = na
var float prevLo1 = na
var float prevLo2 = na

// ─── Zone storage (parallel arrays — one entry per active zone) ───────────────
var string[] zoneType   = array.new<string>(0)  // "D" or "S"
var int[]    zoneState  = array.new<int>(0)     // FRESH / TOUCHED_1 / TOUCHED_2
var bool[]   zoneInside = array.new<bool>(0)    // true while price is inside WFZ
var float[]  zPfzTop    = array.new<float>(0)
var float[]  zPfzBot    = array.new<float>(0)
var float[]  zWfzTop    = array.new<float>(0)
var float[]  zWfzBot    = array.new<float>(0)
var box[]    zWfzBox    = array.new<box>(0)
var box[]    zPfzBox    = array.new<box>(0)
var label[]  zLabel     = array.new<label>(0)
var int[]    zScore     = array.new<int>(0)
```

- [ ] **Step 2: Add function stubs after the state block**

```pine
// ─── Stubs (replaced task by task) ───────────────────────────────────────────
inLookback(pivOffset)                                        => false
zoneOpacity(score, state)                                    => 85
currentTrend()                                               => 0
findBase(pivOffset, dir)                                     => [float(na), float(na), float(na), float(na), 0, false]
validateDeparture(pivOffset, dir)                             => false
departureStrength(pivOffset)                                 => float(0)
detectBOS(pivOffset, dir)                                    => false
calcScore(depStr, bos, state, bLen, tight, trendAligned)     => 0
createZone(dir, pT, pB, wT, wB, score)                       => na
updateZones()                                                => na

// ─── Main (filled in Task 8) ──────────────────────────────────────────────────
```

- [ ] **Step 3: Add to TradingView, verify 0 errors**

Open TradingView Pine Script editor, paste the file, click "Add to chart". Expected: loads with no errors, no boxes visible yet (stubs return na/false).

- [ ] **Step 4: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: scaffold supply & demand zones indicator"
```

---

### Task 2: Helper functions

**Files:**
- Modify: `indicators/supply_demand.pine`

- [ ] **Step 1: Replace the three helper stubs (`inLookback`, `zoneOpacity`, `currentTrend`) with implementations**

```pine
// Returns true if the pivot bar (pivOffset bars ago) is within the lookback window.
// Pine Script times are in milliseconds, hence 86400000 per day.
inLookback(pivOffset) =>
    time[pivOffset] >= timenow - lookbackDays * 86400000

// Base opacity (transparency %) from score and touch count.
// Higher opacity = more transparent = more faded.
zoneOpacity(score, state) =>
    base = score >= 8 ? 20 : score >= 5 ? 50 : score >= 3 ? 70 : 85
    math.min(base + state * 15, 90)

// Trend direction based on last two pivot highs and lows.
// Returns 1 (uptrend), -1 (downtrend), or 0 (neutral).
currentTrend() =>
    uptrend   = not na(prevLo1) and not na(prevLo2) and prevLo1 > prevLo2
    downtrend = not na(prevHi1) and not na(prevHi2) and prevHi1 < prevHi2
    uptrend ? 1 : downtrend ? -1 : 0
```

- [ ] **Step 2: Add to TradingView, verify 0 errors**

- [ ] **Step 3: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: helper functions (inLookback, zoneOpacity, currentTrend)"
```

---

### Task 3: Base detection — `findBase`

**Files:**
- Modify: `indicators/supply_demand.pine`

How it works: `ta.pivotlow` fires at `bar_index` when the pivot occurred `pivotLength` bars ago (offset = `pivotLength`). We scan candles starting at that offset (the pivot bar) and going further back (increasing offset). The first qualifying small-body candle is the "last base candle" — closest to the departure impulse. We collect up to `maxBaseCandles` consecutive small-body candles.

- [ ] **Step 1: Replace the `findBase` stub**

```pine
// Scan backwards from the pivot to find base candles.
// pivOffset = pivotLength (how many bars ago the pivot occurred)
// dir: 1 = demand (pivot low), -1 = supply (pivot high)
// Returns: [pfzTop, pfzBottom, wfzTop, wfzBottom, baseLen, baseTight]
// Returns [na,na,na,na,0,false] when no valid base exists.
findBase(pivOffset, dir) =>
    atr    = ta.atr(14)
    wHi    = float(na)
    wLo    = float(na)
    pHi    = float(na)
    pLo    = float(na)
    bLen   = 0
    lastJ  = -1      // offset of candle closest to departure (first qualifying candle)
    tight  = true    // all bodies < 0.3 × ATR

    for j = pivOffset to pivOffset + maxBaseCandles - 1
        cBody = math.abs(close[j] - open[j])
        if na(close[j]) or cBody >= baseBodyMult * atr
            break
        bLen  += 1
        wHi   := na(wHi) ? high[j] : math.max(wHi, high[j])
        wLo   := na(wLo) ? low[j]  : math.min(wLo, low[j])
        if cBody >= 0.3 * atr
            tight := false
        if lastJ < 0
            lastJ := j   // capture first qualifying candle (= last base candle before impulse)

    if bLen == 0 or lastJ < 0
        [float(na), float(na), float(na), float(na), 0, false]
    else
        if dir == 1  // demand: PFZ bottom = lowest body, PFZ top = wick high
            pLo := math.min(close[lastJ], open[lastJ])
            pHi := high[lastJ]
        else         // supply: PFZ top = highest body, PFZ bottom = wick low
            pHi := math.max(close[lastJ], open[lastJ])
            pLo := low[lastJ]
        [pHi, pLo, wHi, wLo, bLen, tight]
```

- [ ] **Step 2: Add to TradingView, verify 0 errors**

- [ ] **Step 3: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: base detection (findBase)"
```

---

### Task 4: Departure helpers — `validateDeparture`, `departureStrength`, `detectBOS`

**Files:**
- Modify: `indicators/supply_demand.pine`

Departure candles are at offsets 1 to `pivotLength - 1` (bars between the pivot and the current bar). At `bar_index`, offset 1 = last closed bar, offset `pivotLength - 1` = bar just after the pivot.

- [ ] **Step 1: Replace the `validateDeparture` stub**

```pine
// True if at least one bar between the pivot and now is a strong directional candle.
// dir 1 = demand (need at least one big bullish candle after pivot low).
// dir -1 = supply (need at least one big bearish candle after pivot high).
validateDeparture(pivOffset, dir) =>
    atr   = ta.atr(14)
    found = false
    for j = 1 to pivOffset - 1
        cBody = math.abs(close[j] - open[j])
        if cBody > departureBodyMult * atr
            if dir == 1  and close[j] > open[j]
                found := true
                break
            if dir == -1 and close[j] < open[j]
                found := true
                break
    found
```

- [ ] **Step 2: Replace the `departureStrength` stub**

```pine
// Returns max departure candle body / ATR — used by calcScore for 0–3 points.
departureStrength(pivOffset) =>
    atr     = ta.atr(14)
    maxBody = float(0)
    for j = 1 to pivOffset - 1
        cBody = math.abs(close[j] - open[j])
        if cBody > maxBody
            maxBody := cBody
    atr > 0 ? maxBody / atr : float(0)
```

- [ ] **Step 3: Replace the `detectBOS` stub**

```pine
// Break of Structure: did the departure impulse close beyond the previous swing level?
// Demand (dir 1): any departure close > prevHi1 (previous confirmed pivot high).
// Supply (dir -1): any departure close < prevLo1 (previous confirmed pivot low).
// prevHi1 / prevLo1 are updated in the main section before zone creation,
// so at the moment of detection they already hold the most recent pivot
// before the current base.
detectBOS(pivOffset, dir) =>
    bos = false
    if dir == 1 and not na(prevHi1)
        for j = 1 to pivOffset - 1
            if close[j] > prevHi1
                bos := true
                break
    else if dir == -1 and not na(prevLo1)
        for j = 1 to pivOffset - 1
            if close[j] < prevLo1
                bos := true
                break
    bos
```

- [ ] **Step 4: Add to TradingView, verify 0 errors**

- [ ] **Step 5: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: departure validation, strength, and BOS detection"
```

---

### Task 5: Quality scoring — `calcScore`

**Files:**
- Modify: `indicators/supply_demand.pine`

- [ ] **Step 1: Replace the `calcScore` stub**

```pine
// Returns zone quality score 0–10.
// depStr      : max departure body / ATR (float)
// bos         : Break of Structure detected (bool)
// state       : zone touch state — FRESH=0, TOUCHED_1=1, TOUCHED_2=2
// bLen        : number of base candles (int)
// tight       : all base bodies < 0.3 × ATR (bool)
// trendAligned: zone direction matches current trend (bool)
calcScore(depStr, bos, state, bLen, tight, trendAligned) =>
    s = 0
    s += depStr >= 4.0 ? 3 : depStr >= 2.5 ? 2 : depStr >= 1.5 ? 1 : 0  // departure strength (0–3)
    s += bos ? 2 : 0                                                        // BOS (0–2)
    s += state == FRESH ? 2 : state == TOUCHED_1 ? 1 : 0                   // freshness (0–2)
    s += bLen <= 3 ? 1 : 0                                                  // base length (0–1)
    s += tight ? 1 : 0                                                      // base tightness (0–1)
    s += trendAligned ? 1 : 0                                               // trend alignment (0–1)
    s
```

- [ ] **Step 2: Add to TradingView, verify 0 errors**

- [ ] **Step 3: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: zone quality scoring (calcScore)"
```

---

### Task 6: Zone creation — `createZone`

**Files:**
- Modify: `indicators/supply_demand.pine`

- [ ] **Step 1: Replace the `createZone` stub**

```pine
// Draw PFZ box, WFZ box, and score label. Append to all zone storage arrays.
// dir: 1=demand, -1=supply
// pT/pB: PFZ top/bottom; wT/wB: WFZ top/bottom; score: initial quality score
createZone(dir, pT, pB, wT, wB, score) =>
    baseClr  = dir == 1 ? demandColor : supplyColor
    opacity  = zoneOpacity(score, FRESH)
    leftBar  = bar_index - pivotLength

    // WFZ: wide faded outer box (hidden via full transparency when showWFZ=false)
    wOp  = math.min(opacity + 20, 95)
    wBox = box.new(leftBar, wT, bar_index, wB,
             border_color = showWFZ ? color.new(baseClr, 60)  : color.new(baseClr, 100),
             bgcolor      = showWFZ ? color.new(baseClr, wOp) : color.new(baseClr, 100),
             extend       = extend.right)

    // PFZ: tight vivid inner box
    pBox = box.new(leftBar, pT, bar_index, pB,
             border_color = color.new(baseClr, 0),
             bgcolor      = color.new(baseClr, opacity),
             extend       = extend.right)

    // Score label on right edge of PFZ
    txt = (dir == 1 ? "D " : "S ") + str.tostring(score)
    lbl = label.new(bar_index, dir == 1 ? pT : pB,
             showLabels ? txt : "",
             color     = color.new(baseClr, 70),
             textcolor = color.new(baseClr, 0),
             style     = dir == 1 ? label.style_label_upper_left : label.style_label_lower_left,
             size      = size.small)

    // Append to all parallel arrays
    array.push(zoneType,   dir == 1 ? "D" : "S")
    array.push(zoneState,  FRESH)
    array.push(zoneInside, false)
    array.push(zPfzTop,    pT)
    array.push(zPfzBot,    pB)
    array.push(zWfzTop,    wT)
    array.push(zWfzBot,    wB)
    array.push(zWfzBox,    wBox)
    array.push(zPfzBox,    pBox)
    array.push(zLabel,     lbl)
    array.push(zScore,     score)
```

- [ ] **Step 2: Add to TradingView, verify 0 errors**

- [ ] **Step 3: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: zone creation (createZone)"
```

---

### Task 7: Zone mitigation — `updateZones`

**Files:**
- Modify: `indicators/supply_demand.pine`

Runs every bar. For each active zone:
- **Breach** (`close` beyond far side of WFZ) → delete objects, remove from all arrays
- **New entry** (wick enters WFZ from outside) → increment touch state, fade colors, update score
- **Exit** (price leaves WFZ without breaching) → clear inside flag

- [ ] **Step 1: Replace the `updateZones` stub**

```pine
updateZones() =>
    i = 0
    while i < array.size(zoneType)
        typ     = array.get(zoneType,   i)
        state   = array.get(zoneState,  i)
        inside  = array.get(zoneInside, i)
        wT      = array.get(zWfzTop,    i)
        wB      = array.get(zWfzBot,    i)
        wBox    = array.get(zWfzBox,    i)
        pBox    = array.get(zPfzBox,    i)
        lbl     = array.get(zLabel,     i)
        scr     = array.get(zScore,     i)
        isDmnd  = typ == "D"
        baseClr = isDmnd ? demandColor : supplyColor

        // Breach: candle closes beyond the far side of WFZ
        breached = isDmnd ? close < wB : close > wT
        if breached
            box.delete(wBox)
            box.delete(pBox)
            label.delete(lbl)
            array.remove(zoneType,   i)
            array.remove(zoneState,  i)
            array.remove(zoneInside, i)
            array.remove(zPfzTop,    i)
            array.remove(zPfzBot,    i)
            array.remove(zWfzTop,    i)
            array.remove(zWfzBot,    i)
            array.remove(zWfzBox,    i)
            array.remove(zPfzBox,    i)
            array.remove(zLabel,     i)
            array.remove(zScore,     i)
            continue  // i now points to the next element — do not increment

        // Is price inside WFZ this bar?
        inNow = isDmnd ? low < wT : high > wB

        if not inside and inNow
            // Price just entered the zone from outside
            array.set(zoneInside, i, true)
            if state < TOUCHED_2
                newState = state + 1
                newScr   = math.max(scr - 1, 0)   // lose 1 freshness point
                array.set(zoneState, i, newState)
                array.set(zScore,    i, newScr)

                // Fade box colors to reflect lower freshness
                newOp  = zoneOpacity(newScr, newState)
                wNewOp = math.min(newOp + 20, 95)
                box.set_bgcolor(pBox, color.new(baseClr, newOp))
                if showWFZ
                    box.set_bgcolor(wBox, color.new(baseClr, wNewOp))

                // Update label text
                if showLabels
                    label.set_text(lbl, (isDmnd ? "D " : "S ") + str.tostring(newScr))

        else if inside and not inNow
            // Price exited zone without breaching
            array.set(zoneInside, i, false)

        i += 1
```

- [ ] **Step 2: Add to TradingView, verify 0 errors**

- [ ] **Step 3: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: zone mitigation state machine (updateZones)"
```

---

### Task 8: Main logic

**Files:**
- Modify: `indicators/supply_demand.pine`

This connects everything. Replace the `// ─── Main (filled in Task 8)` comment with the code below.

- [ ] **Step 1: Add the main logic section at the end of the file**

```pine
// ─── Main ─────────────────────────────────────────────────────────────────────

rawHi = ta.pivothigh(high, pivotLength, pivotLength)
rawLo = ta.pivotlow(low,   pivotLength, pivotLength)

// Update trend tracking BEFORE zone creation so BOS check uses correct reference levels.
// When rawHi fires, prevLo1 is unchanged (correct reference for supply BOS).
// When rawLo fires, prevHi1 is unchanged (correct reference for demand BOS).
if not na(rawHi)
    prevHi2 := prevHi1
    prevHi1 := rawHi

if not na(rawLo)
    prevLo2 := prevLo1
    prevLo1 := rawLo

// Attempt to create a SUPPLY zone on a confirmed pivot high
if not na(rawHi) and inLookback(pivotLength)
    [pT, pB, wT, wB, bLen, tight] = findBase(pivotLength, -1)
    if not na(pT) and validateDeparture(pivotLength, -1)
        depStr       = departureStrength(pivotLength)
        bos          = detectBOS(pivotLength, -1)
        trend        = currentTrend()
        trendAligned = trend == -1
        showZone     = not trendFilter or trend <= 0
        scr          = calcScore(depStr, bos, FRESH, bLen, tight, trendAligned)
        if scr >= minScore and showZone
            createZone(-1, pT, pB, wT, wB, scr)

// Attempt to create a DEMAND zone on a confirmed pivot low
if not na(rawLo) and inLookback(pivotLength)
    [pT, pB, wT, wB, bLen, tight] = findBase(pivotLength, 1)
    if not na(pT) and validateDeparture(pivotLength, 1)
        depStr       = departureStrength(pivotLength)
        bos          = detectBOS(pivotLength, 1)
        trend        = currentTrend()
        trendAligned = trend == 1
        showZone     = not trendFilter or trend >= 0
        scr          = calcScore(depStr, bos, FRESH, bLen, tight, trendAligned)
        if scr >= minScore and showZone
            createZone(1, pT, pB, wT, wB, scr)

// Update all existing zones every bar (mitigation)
updateZones()
```

- [ ] **Step 2: Add to TradingView**

Expected: PFZ and WFZ boxes appear at swing zones. Each has a "D N" or "S N" score label.

- [ ] **Step 3: Test zone creation**

Verify on chart:
- Pivot lows with small-body base candles followed by strong bullish bars → green demand boxes
- Pivot highs with small-body base candles followed by strong bearish bars → red supply boxes
- Zones without a clear departure (pivots in sideways market) → no box drawn

- [ ] **Step 4: Test mitigation**

Find a demand zone. Scroll forward to where price re-entered it:
- First re-entry: box fades, label score drops by 1
- Second re-entry: box fades further
- Close below WFZ bottom: zone disappears

- [ ] **Step 5: Test filters**

- Set `minScore = 8` → only high-quality zones visible
- Set `trendFilter = false` → both demand and supply visible in any market condition
- Toggle `showWFZ` off → outer boxes disappear, PFZ boxes remain
- Toggle `showLabels` off → labels disappear

- [ ] **Step 6: Commit**

```bash
git add indicators/supply_demand.pine
git commit -m "feat: main logic — zone creation trigger and mitigation loop"
```

---

### Task 9: Final cleanup and README

**Files:**
- Modify: `indicators/supply_demand.pine`
- Modify: `README.md`

- [ ] **Step 1: Remove all remaining stub comments from the file**

Search for and remove:
- Any `// ─── Stubs` section header if it still exists
- Any `// (filled in Task N)` comments
- Any `=> na` or `=> false` lines that were stubs

- [ ] **Step 2: Test edge cases**

- `pivotLength = 1`: indicator compiles and loads, zones may be noisy but functional
- `maxBaseCandles = 1`: only single-candle bases accepted — fewer, higher-quality zones
- `baseBodyMult = 1.0`: more permissive base detection — more zones appear
- `departureBodyMult = 3.0`: strict departure filter — only very strong impulses create zones
- `lookbackDays = 7`: only recent zones visible

- [ ] **Step 3: Update README.md**

Add a row to the indicators table:

```markdown
| `indicators/supply_demand.pine` | Supply & Demand Zones — PFZ/WFZ detection with 0–10 quality scoring (Skorupinski methodology) |
```

- [ ] **Step 4: Commit and push**

```bash
git add indicators/supply_demand.pine README.md
git commit -m "feat: supply & demand zones indicator complete"
git push
```
