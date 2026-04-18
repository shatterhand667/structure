# Supply & Demand Zones — Design Spec

**Date:** 2026-04-18  
**Project:** Struktura  
**Language:** Pine Script 6.0  
**Platform:** TradingView  
**File:** `indicators/supply_demand.pine`  
**Methodology:** Bernd Skorupinski — PFZ / WFZ, unfilled institutional orders

---

## Overview

Standalone Pine Script 6.0 indicator that automatically detects supply and demand zones using Bernd Skorupinski's methodology. Each zone consists of a short base of small-body candles followed (or preceded) by a strong impulse departure. Two boxes are drawn per zone: PFZ (Preferred Fresh Zone — tightest part of base) and WFZ (Wider Fresh Zone — full base range). Each zone receives a quality score 0–10. Zones degrade in color as price revisits them and are removed when fully breached.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `indicators/supply_demand.pine` | Complete indicator — inputs, detection, scoring, visualization, mitigation |

---

## Inputs

```pine
// ─── Zone Detection
input int   pivotLength        = 4     // Pivot Length (bars left and right)
input int   maxBaseCandles     = 2     // Max candles in base (1–5)
input bool  useBaseFilter      = true  // Enable base body size filter
input float baseBodyMult       = 1.0   // Base candle body < X × ATR(14)
input bool  useDepartureFilter = true  // Enable departure strength filter
input float departureBodyMult  = 0.8   // Departure candle body > X × ATR(14)

// ─── History
input int   lookbackDays      = 365   // Only draw zones within this many days

// ─── Filtering
input int   minScore          = 3     // Hide zones below this score (0 = show all)
input bool  trendFilter       = false // Show only zones aligned with current trend

// ─── Visual
input color demandColor       = #26a69a           // Demand zone color
input color supplyColor       = #ef5350           // Supply zone color
input bool  showLabels        = true              // Show score labels on zones
input string labelSize        = "normal"          // Label size (tiny/small/normal/large/huge)
input bool  showWFZ           = true              // Show Wider Fresh Zone box
input bool  showHistory       = false             // Keep breached zones as faded outlines
```

---

## Zone Detection

### Anchor: pivot high / pivot low

`ta.pivotlow(low, pivotLength, pivotLength)` and `ta.pivothigh(high, pivotLength, pivotLength)` are used as anchors. The pivot bar is the extreme point of the base (lowest candle of demand zone, highest candle of supply zone).

### Base identification

Starting at the pivot bar and scanning backwards (up to `maxBaseCandles` bars), a candle is classified as a **base candle** if:
- `body < baseBodyMult × ATR(14)` where `body = |close - open|`

Scanning stops when a candle fails the body threshold. At least 1 base candle is required.

### Departure validation

After the pivot bar, at least one of the next `pivotLength` bars must be a departure candle:
- **Demand:** bullish candle with `body > departureBodyMult × ATR(14)`
- **Supply:** bearish candle with `body > departureBodyMult × ATR(14)`

If no departure is found, the zone is rejected (no box drawn).

### Zone patterns supported

| Pattern | Type | Direction |
|---------|------|-----------|
| DBR (Drop → Base → Rally) | Demand | Bullish |
| RBR (Rally → Base → Rally) | Demand | Bullish |
| RBD (Rally → Base → Drop) | Supply | Bearish |
| DBD (Drop → Base → Drop) | Supply | Bearish |

---

## PFZ and WFZ Boundaries

### Demand zone (base below impulse)

- **WFZ:** `bottom = lowest wick of all base candles`, `top = highest wick of all base candles`
- **PFZ:** `bottom = lowest body of last base candle`, `top = high (wick) of last base candle`

### Supply zone (base above impulse)

- **WFZ:** `bottom = lowest wick of all base candles`, `top = highest wick of all base candles`
- **PFZ:** `bottom = low (wick) of last base candle`, `top = highest body of last base candle`

"Last base candle" = the base candle closest to the departure (the one directly before the impulse).

---

## Quality Scoring (0–10)

| Criterion | Points | Measurement |
|-----------|--------|-------------|
| Departure strength | 0–3 | Average body of departure candles / ATR(14): <1.5×→0, 1.5–2.5×→1, 2.5–4×→2, >4×→3 |
| Break of Structure | 0–2 | Did the departure impulse close beyond the previous swing high (demand) or swing low (supply)? Yes→2, No→0 |
| Freshness | 0–2 | FRESH→2, TOUCHED_1→1, TOUCHED_2→0 |
| Base length | 0–1 | 1–3 candles→1, 4–5 candles→0 |
| Base tightness | 0–1 | All base candle bodies < 0.3×ATR→1, else→0 |
| Trend alignment | 0–1 | Demand in uptrend or Supply in downtrend→1, else→0 |

**Score → color opacity:**
- 8–10 → 20% transparent (vivid)
- 5–7 → 50% transparent (medium)
- 3–4 → 70% transparent (faded)
- 0–2 → hidden (if `minScore > 0`) or 85% transparent

Score label is shown on the right edge of the WFZ box: `D 7` or `S 4`. After mitigation, label shows current and initial score: `D 6(8)`.

---

## Trend Detection

Trend is determined by tracking the last 2 confirmed pivot highs and last 2 confirmed pivot lows (using the same `pivotLength` as zone detection):
- **Uptrend:** most recent pivot low > previous pivot low (HL structure)
- **Downtrend:** most recent pivot high < previous pivot high (LH structure)
- **Neutral:** neither condition met — zones of both types shown regardless of `trendFilter`

---

## Break of Structure (BOS) Detection

At zone creation time:
- **Demand:** check if the departure impulse's highest close exceeds the most recent confirmed pivot high before the base.
- **Supply:** check if the departure impulse's lowest close is below the most recent confirmed pivot low before the base.

If yes → BOS = true → +2 points.

---

## Mitigation (Zone State Machine)

```
FRESH → TOUCHED_1 → TOUCHED_2 → BREACHED
```

State transitions evaluated on each closed bar:

| Transition | Condition |
|-----------|-----------|
| FRESH → TOUCHED_1 | `low < WFZ.top` (demand) or `high > WFZ.bottom` (supply) |
| TOUCHED_1 → TOUCHED_2 | Same condition on a subsequent bar |
| Any → BREACHED | `close < WFZ.bottom` (demand) or `close > WFZ.top` (supply) |

On BREACHED: delete both boxes and label (if `showHistory=true` and score ≥ `minScore`, keep as faded outline instead). On TOUCHED_N: update box color transparency and recalculate score (freshness points decrease). If score drops below `minScore` after a touch, zone is hidden in place (remains in state machine, removed on breach).

---

## Visual Objects

| Object | Type | Condition |
|--------|------|-----------|
| WFZ box | `box.new()` | Zone valid + `showWFZ = true` |
| PFZ box | `box.new()` | Zone valid always |
| Score label | `label.new()` | Zone valid + `showLabels = true` |

Both boxes extend right (`extend.right`) until BREACHED.

---

## Zone Storage

Zones are stored in parallel arrays (one entry per active zone):
```
zoneType[]      // "D" or "S"
zoneState[]     // 0=FRESH, 1=TOUCHED_1, 2=TOUCHED_2
pfzTop[]        // PFZ upper price
pfzBottom[]     // PFZ lower price
wfzTop[]        // WFZ upper price
wfzBottom[]     // WFZ lower price
wfzBox[]        // box ID for WFZ
pfzBox[]        // box ID for PFZ
scoreLabel[]    // label ID
score[]         // current score (recalculated on mitigation)
```

Max active zones bounded by `max_boxes_count=500` (250 zones × 2 boxes each). Higher limit needed when `showHistory=true` keeps breached zones on chart.

---

## Out of Scope

- Alerts
- Multi-timeframe confluence
- EA / automated trading signals
- HTF zone overlay
