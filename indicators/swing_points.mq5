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

//+------------------------------------------------------------------+
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

    //--- Structural mode detection (Task 4)

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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
ENUM_LINE_STYLE ToLineStyle(ENUM_SWEEP_STYLE s)
{
    switch(s)
    {
        case Dashed: return STYLE_DASH;
        case Dotted: return STYLE_DOT;
        default:     return STYLE_SOLID;
    }
}

//+------------------------------------------------------------------+
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
    ArrayResize(sweepHiPrices,    0);
    ArrayResize(sweepHiBars,      0);
    ArrayResize(sweepHiLineNames, 0);
    ArrayResize(sweepLoPrices,    0);
    ArrayResize(sweepLoBars,      0);
    ArrayResize(sweepLoLineNames, 0);
}
