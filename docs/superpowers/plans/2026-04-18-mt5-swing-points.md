# MT5 Swing Points — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Port `indicators/swing_points.pine` to MQL5 with 1:1 feature parity — swing labels (HH/LH/HL/LL) and Grab and Go scanner (sweep lines + S1/S2 signals).

**Architecture:** Single-file MQL5 indicator, `indicator_plots 0` (purely graphical via ObjectCreate). All state in file-scope variables. `OnCalculate` iterates bars oldest→newest; full reset on `prev_calculated==0`. Arrays indexed with AS_SERIES=false: `high[0]` = oldest bar, `high[rates_total-1]` = current bar.

**Tech Stack:** MQL5, MetaTrader 5, MetaEditor

---

## File Structure

| File | Change |
|------|--------|
| `indicators/swing_points.mq5` | Create — complete MQL5 indicator |

---

### Task 1: Scaffold — properties, enums, inputs, state variables, function stubs

**Files:**
- Create: `indicators/swing_points.mq5`

- [x] **Step 1: Create the file**

```mql5
//+------------------------------------------------------------------+
//| Swing Points — MQL5 port of swing_points.pine                    |
//+------------------------------------------------------------------+
#property copyright "© Struktura"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Enums
enum ENUM_SWING_METHOD { Pivot, Structural };
enum ENUM_CONFIRM_UNIT { Percent, ATR_Multi };
enum ENUM_SWEEP_STYLE  { Solid, Dashed, Dotted };

//--- Inputs: Swing Detection
input ENUM_SWING_METHOD SwingMethod  = Pivot;     // Swing Method
input int               PivotLength  = 10;        // Pivot Length
input double            ConfirmPct   = 1.0;       // Confirm Move
input ENUM_CONFIRM_UNIT ConfirmUnit  = Percent;   // Confirm Unit

//--- Inputs: History
input int               LookbackDays = 30;        // Lookback (days)

//--- Inputs: Label Colors
input color             HHColor      = clrMediumAquamarine; // HH Color
input color             LHColor      = clrRed;              // LH Color
input color             HLColor      = clrMediumAquamarine; // HL Color
input color             LLColor      = clrLightCoral;       // LL Color
input int               LabelFontSize = 8;                  // Label Font Size

//--- Inputs: Grab and Go
input bool              ShowS1        = true;               // Show Signal 1 (Pin Bar)
input bool              ShowS2        = true;               // Show Signal 2 (Next Candle)
input int               MaxSweepLines = 5;                  // Max Sweep Lines
input color             BullishColor  = clrMediumAquamarine;// Bullish Color
input color             BearishColor  = clrRed;             // Bearish Color
input int               SigArrowSize  = 2;                  // Signal Arrow Size
input ENUM_SWEEP_STYLE  SweepStyle    = Solid;              // Sweep Line Style
input int               SweepWidth    = 1;                  // Sweep Line Width

//--- State: Swing classification
double prevHigh = EMPTY_VALUE;
double prevLow  = EMPTY_VALUE;

//--- State: Structural pending pivots
double pendingHi    = EMPTY_VALUE;
int    pendingHiBar = -1;
double pendingLo    = EMPTY_VALUE;
int    pendingLoBar = -1;

//--- State: Grab and Go sweep arrays
double   sweepHiPrices[];
int      sweepHiBars[];
string   sweepHiLineNames[];
double   sweepLoPrices[];
int      sweepLoBars[];
string   sweepLoLineNames[];

//--- State: Signal 2
int    s2Dir        = 0;
double s2SigHigh    = EMPTY_VALUE;
double s2SigLow     = EMPTY_VALUE;
int    s2BarsWaited = 0;
```

- [x] **Step 2: Add function stubs and OnInit/OnDeinit/OnCalculate after the state block**

```mql5
//+------------------------------------------------------------------+
bool   IsPivotHigh(int i, const double &h[], int len);
bool   IsPivotLow(int i, const double &l[], int len);
double CalcATR(int bar, int period, const double &h[], const double &l[], const double &c[]);
void   CreateSwingLabel(string name, datetime t, double price, string txt, color clr, bool above);
void   CreateSweepLine(string name, datetime t, double price, color clr);
ENUM_LINE_STYLE ToLineStyle(ENUM_SWEEP_STYLE s);
void   ResetState();

//+------------------------------------------------------------------+
int OnInit() { return(INIT_SUCCEEDED); }

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { ObjectsDeleteAll(0, "SP_"); }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
    // Stub — tasks fill this in
    return(rates_total);
}
```

- [x] **Step 3: Open MetaEditor (F4 in MT5), paste file, press F7 to compile**

Expected: 0 errors, 0 warnings (or only "unreferenced function" warnings for stubs).

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: scaffold MT5 swing points indicator"
```

---

### Task 2: Helper functions

**Files:**
- Modify: `indicators/swing_points.mq5`

- [x] **Step 1: Implement `IsPivotHigh` and `IsPivotLow`**

Add after the stub declarations:

```mql5
bool IsPivotHigh(int i, const double &h[], int len)
{
    if(i - len < 0 || i + len >= ArraySize(h)) return false;
    for(int j = 1; j <= len; j++)
        if(h[i] <= h[i-j] || h[i] <= h[i+j]) return false;
    return true;
}

bool IsPivotLow(int i, const double &l[], int len)
{
    if(i - len < 0 || i + len >= ArraySize(l)) return false;
    for(int j = 1; j <= len; j++)
        if(l[i] >= l[i-j] || l[i] >= l[i+j]) return false;
    return true;
}
```

Note: `high[i-j]` is an older bar (further in history), `high[i+j]` is a newer bar — correct for oldest-first indexing.

- [x] **Step 2: Implement `CalcATR`**

```mql5
double CalcATR(int bar, int period, const double &h[], const double &l[], const double &c[])
{
    if(bar < period) return 0.0;
    double sum = 0;
    for(int i = bar - period + 1; i <= bar; i++)
    {
        double trueRange = MathMax(h[i], c[i-1]) - MathMin(l[i], c[i-1]);
        sum += trueRange;
    }
    return sum / period;
}
```

- [x] **Step 3: Implement `CreateSwingLabel`**

```mql5
void CreateSwingLabel(string name, datetime t, double price, string txt, color clr, bool above)
{
    if(ObjectFind(0, name) >= 0) return; // already exists
    ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
    ObjectSetString (0, name, OBJPROP_TEXT,      txt);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  LabelFontSize);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR,    above ? ANCHOR_LOWER : ANCHOR_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK,      false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}
```

- [x] **Step 4: Implement `CreateSweepLine`, `ToLineStyle`, and `ResetState`**

```mql5
void CreateSweepLine(string name, datetime t, double price, color clr)
{
    if(ObjectFind(0, name) >= 0) return;
    ObjectCreate(0, name, OBJ_TREND, 0, t, price, t, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE,      ToLineStyle(SweepStyle));
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      SweepWidth);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  true);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

ENUM_LINE_STYLE ToLineStyle(ENUM_SWEEP_STYLE s)
{
    switch(s)
    {
        case Dashed: return STYLE_DASH;
        case Dotted: return STYLE_DOT;
        default:     return STYLE_SOLID;
    }
}

void ResetState()
{
    prevHigh     = EMPTY_VALUE;
    prevLow      = EMPTY_VALUE;
    pendingHi    = EMPTY_VALUE;
    pendingHiBar = -1;
    pendingLo    = EMPTY_VALUE;
    pendingLoBar = -1;
    s2Dir        = 0;
    s2SigHigh    = EMPTY_VALUE;
    s2SigLow     = EMPTY_VALUE;
    s2BarsWaited = 0;
    ArrayResize(sweepHiPrices,   0);
    ArrayResize(sweepHiBars,     0);
    ArrayResize(sweepHiLineNames,0);
    ArrayResize(sweepLoPrices,   0);
    ArrayResize(sweepLoBars,     0);
    ArrayResize(sweepLoLineNames,0);
}
```

- [x] **Step 5: Compile (F7 in MetaEditor)**

Expected: 0 errors.

- [x] **Step 6: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: add MQL5 helper functions"
```

---

### Task 3: Pivot detection, classification, and swing labels

**Files:**
- Modify: `indicators/swing_points.mq5`

- [x] **Step 1: Fill in `OnCalculate` — full recalculation guard and loop setup**

Replace the stub `OnCalculate` body:

```mql5
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
    if(rates_total < PivotLength * 2 + 1) return 0;

    if(prev_calculated == 0)
    {
        ObjectsDeleteAll(0, "SP_");
        ResetState();
    }

    int start = (prev_calculated == 0) ? PivotLength : MathMax(prev_calculated - 1, PivotLength);

    datetime lookbackCutoff = TimeCurrent() - (datetime)(LookbackDays * 86400);

    for(int i = start; i < rates_total - PivotLength; i++)
    {
        ProcessBar(i, rates_total, time, open, high, low, close, lookbackCutoff);
    }

    ChartRedraw(0);
    return(rates_total);
}
```

- [x] **Step 2: Add `ProcessBar` function stub after helper functions**

```mql5
void ProcessBar(int i, int rates_total,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                datetime        lookbackCutoff)
{
    double pivHi    = EMPTY_VALUE;
    int    pivHiBar = -1;
    double pivLo    = EMPTY_VALUE;
    int    pivLoBar = -1;

    //--- Pivot mode detection
    if(SwingMethod == Pivot)
    {
        if(IsPivotHigh(i, high, PivotLength))
        {
            pivHi    = high[i];
            pivHiBar = i;
        }
        if(IsPivotLow(i, low, PivotLength))
        {
            pivLo    = low[i];
            pivLoBar = i;
        }
    }

    //--- Structural mode — pending pivot registration + confirmation (Task 4)

    //--- Classification + labels
    if(pivHi != EMPTY_VALUE && pivHiBar >= 0)
    {
        bool isHH  = (prevHigh == EMPTY_VALUE || pivHi >= prevHigh);
        string lbl = isHH ? "HH" : "LH";
        color  clr = isHH ? HHColor : LHColor;
        string name = "SP_LBL_" + IntegerToString((long)time[pivHiBar]);
        if(time[pivHiBar] >= lookbackCutoff)
            CreateSwingLabel(name, time[pivHiBar], high[pivHiBar], lbl, clr, true);
        //--- Feed sweep tracker (Task 5)
        prevHigh = pivHi;
    }

    if(pivLo != EMPTY_VALUE && pivLoBar >= 0)
    {
        bool isLL  = (prevLow == EMPTY_VALUE || pivLo <= prevLow);
        string lbl = isLL ? "LL" : "HL";
        color  clr = isLL ? LLColor : HLColor;
        string name = "SP_LBL_" + IntegerToString((long)time[pivLoBar]);
        if(time[pivLoBar] >= lookbackCutoff)
            CreateSwingLabel(name, time[pivLoBar], low[pivLoBar], lbl, clr, false);
        //--- Feed sweep tracker (Task 5)
        prevLow = pivLo;
    }
}
```

- [x] **Step 3: Compile and add to MT5 chart**

Expected: indicator compiles, HH/LH/HL/LL labels appear on chart in Pivot mode within last 30 days.

- [x] **Step 4: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: pivot detection, classification, and swing labels"
```

---

### Task 4: Structural mode

**Files:**
- Modify: `indicators/swing_points.mq5`

- [x] **Step 1: Add structural pending registration inside the `if(SwingMethod == Pivot)` block — add a parallel `else if` block in `ProcessBar`**

Replace the `//--- Structural mode` comment in `ProcessBar` with:

```mql5
    //--- Structural mode detection
    else if(SwingMethod == Structural)
    {
        //--- Register new pending pivots
        if(IsPivotHigh(i, high, PivotLength))
        {
            pendingHi    = high[i];
            pendingHiBar = i;
        }
        if(IsPivotLow(i, low, PivotLength))
        {
            pendingLo    = low[i];
            pendingLoBar = i;
        }

        double atrVal = CalcATR(i, 14, high, low, close);

        //--- Confirm pending high: price drops enough below it
        if(pendingHi != EMPTY_VALUE)
        {
            bool moved = (ConfirmUnit == Percent)
                ? (pendingHi - close[i]) / pendingHi >= ConfirmPct / 100.0
                : (pendingHi - close[i]) >= ConfirmPct * atrVal;
            if(moved)
            {
                pivHi        = pendingHi;
                pivHiBar     = pendingHiBar;
                pendingHi    = EMPTY_VALUE;
                pendingHiBar = -1;
            }
        }

        //--- Confirm pending low: price rises enough above it
        if(pendingLo != EMPTY_VALUE)
        {
            bool moved = (ConfirmUnit == Percent)
                ? (close[i] - pendingLo) / pendingLo >= ConfirmPct / 100.0
                : (close[i] - pendingLo) >= ConfirmPct * atrVal;
            if(moved)
            {
                pivLo        = pendingLo;
                pivLoBar     = pendingLoBar;
                pendingLo    = EMPTY_VALUE;
                pendingLoBar = -1;
            }
        }
    }
```

- [x] **Step 2: Compile and switch indicator to Structural mode on chart**

Expected: fewer labels than Pivot mode, only confirmed swings labeled.

- [x] **Step 3: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: structural mode with ATR/percent confirmation"
```

---

### Task 5: Grab and Go — sweep arrays and line drawing

**Files:**
- Modify: `indicators/swing_points.mq5`

- [x] **Step 1: Add sweep array helper functions after `ResetState`**

```mql5
//--- Add a swing high to sweep tracker; delete oldest line if over limit
void PushSweepHi(double price, int bar, string lineName)
{
    int n = ArraySize(sweepHiPrices);
    ArrayResize(sweepHiPrices,    n + 1);
    ArrayResize(sweepHiBars,      n + 1);
    ArrayResize(sweepHiLineNames, n + 1);
    sweepHiPrices[n]    = price;
    sweepHiBars[n]      = bar;
    sweepHiLineNames[n] = lineName;

    if(ArraySize(sweepHiPrices) > MaxSweepLines)
    {
        ObjectDelete(0, sweepHiLineNames[0]);
        for(int k = 0; k < ArraySize(sweepHiPrices) - 1; k++)
        {
            sweepHiPrices[k]    = sweepHiPrices[k+1];
            sweepHiBars[k]      = sweepHiBars[k+1];
            sweepHiLineNames[k] = sweepHiLineNames[k+1];
        }
        ArrayResize(sweepHiPrices,    ArraySize(sweepHiPrices)    - 1);
        ArrayResize(sweepHiBars,      ArraySize(sweepHiBars)      - 1);
        ArrayResize(sweepHiLineNames, ArraySize(sweepHiLineNames) - 1);
    }
}

//--- Add a swing low to sweep tracker; delete oldest line if over limit
void PushSweepLo(double price, int bar, string lineName)
{
    int n = ArraySize(sweepLoPrices);
    ArrayResize(sweepLoPrices,    n + 1);
    ArrayResize(sweepLoBars,      n + 1);
    ArrayResize(sweepLoLineNames, n + 1);
    sweepLoPrices[n]    = price;
    sweepLoBars[n]      = bar;
    sweepLoLineNames[n] = lineName;

    if(ArraySize(sweepLoPrices) > MaxSweepLines)
    {
        ObjectDelete(0, sweepLoLineNames[0]);
        for(int k = 0; k < ArraySize(sweepLoPrices) - 1; k++)
        {
            sweepLoPrices[k]    = sweepLoPrices[k+1];
            sweepLoBars[k]      = sweepLoBars[k+1];
            sweepLoLineNames[k] = sweepLoLineNames[k+1];
        }
        ArrayResize(sweepLoPrices,    ArraySize(sweepLoPrices)    - 1);
        ArrayResize(sweepLoBars,      ArraySize(sweepLoBars)      - 1);
        ArrayResize(sweepLoLineNames, ArraySize(sweepLoLineNames) - 1);
    }
}

//--- Remove element at index idx from sweep hi arrays (sweep consumed)
void RemoveSweepHi(int idx)
{
    int n = ArraySize(sweepHiPrices);
    for(int k = idx; k < n - 1; k++)
    {
        sweepHiPrices[k]    = sweepHiPrices[k+1];
        sweepHiBars[k]      = sweepHiBars[k+1];
        sweepHiLineNames[k] = sweepHiLineNames[k+1];
    }
    ArrayResize(sweepHiPrices,    n - 1);
    ArrayResize(sweepHiBars,      n - 1);
    ArrayResize(sweepHiLineNames, n - 1);
}

//--- Remove element at index idx from sweep lo arrays
void RemoveSweepLo(int idx)
{
    int n = ArraySize(sweepLoPrices);
    for(int k = idx; k < n - 1; k++)
    {
        sweepLoPrices[k]    = sweepLoPrices[k+1];
        sweepLoBars[k]      = sweepLoBars[k+1];
        sweepLoLineNames[k] = sweepLoLineNames[k+1];
    }
    ArrayResize(sweepLoPrices,    n - 1);
    ArrayResize(sweepLoBars,      n - 1);
    ArrayResize(sweepLoLineNames, n - 1);
}
```

- [x] **Step 2: Replace the `//--- Feed sweep tracker` comments in `ProcessBar` with actual calls**

For the high classification block, replace `//--- Feed sweep tracker (Task 5)`:

```mql5
        string lineName = "SP_LINE_HI_" + IntegerToString((long)time[pivHiBar]);
        CreateSweepLine(lineName, time[pivHiBar], pivHi, BearishColor);
        PushSweepHi(pivHi, pivHiBar, lineName);
```

For the low classification block, replace `//--- Feed sweep tracker (Task 5)`:

```mql5
        string lineName = "SP_LINE_LO_" + IntegerToString((long)time[pivLoBar]);
        CreateSweepLine(lineName, time[pivLoBar], pivLo, BullishColor);
        PushSweepLo(pivLo, pivLoBar, lineName);
```

- [x] **Step 3: Add sweep detection at the end of `ProcessBar`, before the closing brace**

```mql5
    //--- Detect high sweeps
    int hiIdx = 0;
    while(hiIdx < ArraySize(sweepHiPrices))
    {
        if(high[i] > sweepHiPrices[hiIdx])
        {
            // Stop the line at the signal candle
            ObjectSetInteger(0, sweepHiLineNames[hiIdx], OBJPROP_TIME,      1, (long)time[i]);
            ObjectSetInteger(0, sweepHiLineNames[hiIdx], OBJPROP_RAY_RIGHT, false);
            // Signal 1 + S2 state — Task 6
            RemoveSweepHi(hiIdx);
        }
        else hiIdx++;
    }

    //--- Detect low sweeps
    int loIdx = 0;
    while(loIdx < ArraySize(sweepLoPrices))
    {
        if(low[i] < sweepLoPrices[loIdx])
        {
            ObjectSetInteger(0, sweepLoLineNames[loIdx], OBJPROP_TIME,      1, (long)time[i]);
            ObjectSetInteger(0, sweepLoLineNames[loIdx], OBJPROP_RAY_RIGHT, false);
            // Signal 1 + S2 state — Task 6
            RemoveSweepLo(loIdx);
        }
        else loIdx++;
    }
```

- [x] **Step 4: Compile and verify on chart**

Expected:
- A line appears from each confirmed swing high/low, extending right
- When price sweeps the level, line stops at that bar
- Max 5 lines tracked simultaneously (oldest deleted when exceeded)

- [x] **Step 5: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: grab and go sweep tracking arrays and line drawing"
```

---

### Task 6: Signal 1 (Pin Bar) and Signal 2 (Next Candle)

**Files:**
- Modify: `indicators/swing_points.mq5`

- [x] **Step 1: Add S2 check at the TOP of `ProcessBar`, before pivot detection**

Insert after the function signature opening brace and the local variable declarations:

```mql5
    //--- Signal 2: check 1st and 2nd candle after signal candle
    if(s2Dir != 0)
    {
        s2BarsWaited++;
        double mid = s2SigLow + (s2SigHigh - s2SigLow) * 0.5;
        bool   s2Hit = (s2Dir == 1) ? close[i] > mid : close[i] < mid;
        if(ShowS2 && s2Hit)
        {
            string s2Name = "SP_S2_" + IntegerToString((long)time[i]);
            if(s2Dir == 1)
            {
                ObjectCreate(0, s2Name, OBJ_ARROW_UP, 0, time[i], low[i]);
                ObjectSetInteger(0, s2Name, OBJPROP_COLOR, BullishColor);
            }
            else
            {
                ObjectCreate(0, s2Name, OBJ_ARROW_DOWN, 0, time[i], high[i]);
                ObjectSetInteger(0, s2Name, OBJPROP_COLOR, BearishColor);
            }
            ObjectSetInteger(0, s2Name, OBJPROP_WIDTH,      SigArrowSize);
            ObjectSetInteger(0, s2Name, OBJPROP_SELECTABLE, false);
            s2Dir = 0;
        }
        else if(s2BarsWaited >= 2)
            s2Dir = 0;
    }
```

- [x] **Step 2: Replace the `// Signal 1 + S2 state — Task 6` comment in the high sweep block with full implementation**

```mql5
            // Signal 1 — pin bar: upper wick >= 65% of range
            if(ShowS1 && (high[i] - low[i]) > 0)
            {
                double upperWick = high[i] - MathMax(open[i], close[i]);
                if(upperWick / (high[i] - low[i]) >= 0.65)
                {
                    string s1Name = "SP_S1_HI_" + IntegerToString((long)time[i]);
                    ObjectCreate(0, s1Name, OBJ_ARROW_DOWN, 0, time[i], high[i]);
                    ObjectSetInteger(0, s1Name, OBJPROP_COLOR,      BearishColor);
                    ObjectSetInteger(0, s1Name, OBJPROP_WIDTH,      SigArrowSize);
                    ObjectSetInteger(0, s1Name, OBJPROP_SELECTABLE, false);
                }
            }
            // Set Signal 2 state
            s2Dir        = -1;
            s2SigHigh    = high[i];
            s2SigLow     = low[i];
            s2BarsWaited = 0;
```

- [x] **Step 3: Replace the `// Signal 1 + S2 state — Task 6` comment in the low sweep block**

```mql5
            // Signal 1 — pin bar: lower wick >= 65% of range
            if(ShowS1 && (high[i] - low[i]) > 0)
            {
                double lowerWick = MathMin(open[i], close[i]) - low[i];
                if(lowerWick / (high[i] - low[i]) >= 0.65)
                {
                    string s1Name = "SP_S1_LO_" + IntegerToString((long)time[i]);
                    ObjectCreate(0, s1Name, OBJ_ARROW_UP, 0, time[i], low[i]);
                    ObjectSetInteger(0, s1Name, OBJPROP_COLOR,      BullishColor);
                    ObjectSetInteger(0, s1Name, OBJPROP_WIDTH,      SigArrowSize);
                    ObjectSetInteger(0, s1Name, OBJPROP_SELECTABLE, false);
                }
            }
            // Set Signal 2 state
            s2Dir        = 1;
            s2SigHigh    = high[i];
            s2SigLow     = low[i];
            s2BarsWaited = 0;
```

- [x] **Step 4: Compile and verify on chart**

Expected:
- S1: down arrow above signal candle when upper wick ≥ 65% (high sweep), up arrow below when lower wick ≥ 65% (low sweep)
- S2: arrow on 1st or 2nd candle after signal if it closes past 50% of signal candle range
- Toggle ShowS1 / ShowS2 off — arrows disappear, lines remain

- [x] **Step 5: Commit**

```bash
git add indicators/swing_points.mq5
git commit -m "feat: S1 pin bar and S2 next-candle signals"
```

---

### Task 7: Final cleanup and README update

**Files:**
- Modify: `indicators/swing_points.mq5`
- Modify: `README.md`

- [x] **Step 1: Review full file for leftover `// Task N` comments or stubs**

Check for:
- Any `// Signal 1 + S2 state` placeholder comments still present
- Any `// Stub` comments remaining
- Any unreachable code

- [x] **Step 2: Test both modes on at least 2 timeframes (e.g. M15 and D1)**

Expected:
- Pivot mode: HH/LH/HL/LL labels, sweep lines, S1/S2 arrows — all visible
- Structural mode: fewer labels, same visual style
- Lookback change (7 days → fewer labels, 365 days → more labels)
- Colors update correctly when changed in settings

- [x] **Step 3: Update README.md**

```markdown
| `indicators/swing_points.mq5` | MT5 port — Swing Points + Grab and Go scanner for MetaTrader 5 |
```

- [x] **Step 4: Commit and push**

```bash
git add indicators/swing_points.mq5 README.md
git commit -m "feat: complete MT5 swing points indicator"
git push
```
