//+------------------------------------------------------------------+
//|                    SMC_Scalp_Martingale_XAUUSD_iux.mq5           |
//|                    SMC Scalping Bot v3.4.3                       |
//|                    For DEMO Account Only - XAUUSD variants       |
//|                    + Strategy Change B: TP2 + Partial Close at TP1|
//|                    + Trailing Stop + Exit Classification         |
//+------------------------------------------------------------------+
#property copyright "SMC Scalping Bot v3.4.3"
#property link      ""
#property version   "3.43"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== ENUMS ===
enum ENUM_EA_STATE
{
   STATE_WAIT_SWEEP,      // รอ Sweep
   STATE_WAIT_CHOCH,      // รอ CHOCH
   STATE_WAIT_RETRACE,    // รอราคา retrace เข้า zone
   STATE_PLACE_ORDER,     // วาง order
   STATE_MANAGE_TRADE,    // จัดการ trade
   STATE_COOLDOWN         // พักหลังปิด order
};

enum ENUM_BIAS
{
   BIAS_NONE,
   BIAS_BULLISH,
   BIAS_BEARISH
};

enum ENUM_SWEEP_TYPE
{
   SWEEP_NONE,
   SWEEP_BULLISH,   // Sweep ลง (เตรียม long)
   SWEEP_BEARISH    // Sweep ขึ้น (เตรียม short)
};

enum ENUM_ZONE_TYPE
{
   ZONE_NONE,
   ZONE_FVG,
   ZONE_OB
};

enum ENUM_LIQUIDITY_TYPE
{
   LIQ_NONE,
   LIQ_PDH,
   LIQ_PDL,
   LIQ_SESSION_HIGH,
   LIQ_SESSION_LOW,
   LIQ_EQH,
   LIQ_EQL,
   LIQ_SWING_HIGH,
   LIQ_SWING_LOW
};

enum ENUM_MARTINGALE_MODE
{
   MART_OFF,
   MART_AFTER_LOSS,
   MART_SCALE_IN      // stub for future
};

enum ENUM_BIAS_MODE
{
   BIAS_MODE_STRUCTURE_M15,  // Structure-based (swing high/low)
   BIAS_MODE_EMA200_M15      // EMA200-based
};

enum ENUM_TRADE_MODE
{
   MODE_STRICT,              // Normal mode with full requirements
   MODE_RELAX,               // Relaxed mode with easier entry conditions
   MODE_RELAX2               // Final relaxed mode (end of day)
};

enum ENUM_CANCEL_REASON
{
   CANCEL_NONE = 0,
   CANCEL_SPREAD,
   CANCEL_SPREAD_SPIKE,
   CANCEL_NO_SWEEP,
   CANCEL_NO_CHOCH,
   CANCEL_NO_RETRACE,
   CANCEL_TIMEFILTER,
   CANCEL_BIAS_NONE,
   CANCEL_COOLDOWN,
   CANCEL_NO_TRADE_ZONE,
   CANCEL_HARD_BLOCK,
   CANCEL_SL_BLOCKED,
   CANCEL_MAX_TRADES_DAY,
   CANCEL_CONSECUTIVE_LOSSES,
   CANCEL_DAILY_LOSS,
   CANCEL_ROLLOVER,
   CANCEL_ATR_LOW,
   CANCEL_SWEEP_TIMEOUT,
   CANCEL_CHOCH_TIMEOUT,
   CANCEL_RETRACE_TIMEOUT,
   CANCEL_OTHER,             // Catch-all for unknown reasons
   INFO_MICROCHOCH_USED,     // Info: micro CHOCH fallback was used (not a cancel)
   CANCEL_COUNT              // Total count of reasons
};

enum ENUM_CHOCH_MODE
{
   CHOCH_CLOSE_ONLY,         // CHOCH requires close beyond level (strict)
   CHOCH_WICK_OK             // CHOCH allows wick beyond level (relaxed)
};

//=== INPUT PARAMETERS ===
input group "=== Symbol & Timeframe ==="
input string   InpTradeSymbol       = "";             // Symbol (empty = use chart symbol)
input ENUM_TIMEFRAMES InpBiasTF     = PERIOD_M15;     // Bias Timeframe
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M5;      // Entry Timeframe

input group "=== Bias Settings ==="
input ENUM_BIAS_MODE InpBiasMode    = BIAS_MODE_EMA200_M15; // Bias detection mode
input bool     InpRequireBias       = true;           // Require bias for entry (strict)
input bool     InpAllowBiasNone     = false;          // Allow trade when bias=none (reduced lot)
input double   InpBiasNoneLotFactor = 0.5;            // Lot factor when bias=none (0.5 = 50%)
input int      InpEMAPeriod         = 200;            // EMA period for bias

input group "=== SMC Parameters (STRICT) ==="
input int      InpSwingK            = 2;              // Swing lookback (fractal)
input int      InpEqThresholdPoints = 80;             // EQH/EQL threshold (points)
input int      InpReclaimMaxBars    = 2;              // Reclaim max bars after sweep
input int      InpSweepBreakPoints  = 30;             // Min sweep break (points) - STRICT
input int      InpConfirmMaxBars    = 8;              // CHOCH confirm max bars - STRICT (increased)
input int      InpEntryTimeoutBars  = 10;             // Entry timeout bars - STRICT
input double   InpRetraceRatio      = 0.50;           // Retrace ratio - STRICT (0.50 = 50%)

input group "=== ATR-Adaptive Sweep ==="
input bool     InpUseATRSweepThreshold = true;        // Use ATR-adaptive sweep threshold
input double   InpSweepATRFactor    = 0.20;           // ATR factor for sweep (0.20 = 20% of ATR, lower = easier sweep)
input int      InpATRPeriod         = 14;             // ATR period

input group "=== CHOCH Mode ==="
input ENUM_CHOCH_MODE InpChochModeStrict = CHOCH_CLOSE_ONLY;  // CHOCH mode STRICT
input ENUM_CHOCH_MODE InpChochModeRelax  = CHOCH_WICK_OK;     // CHOCH mode RELAX/RELAX2
input bool     InpUse2StageChoch     = true;           // Use 2-stage CHOCH for RELAX modes
input int      InpStage2ConfirmBars  = 3;              // Stage2 close-confirm window (bars after wick BOS)

input group "=== SL/TP Parameters ==="
input int      InpSLBufferPoints    = 40;             // SL buffer min (points)
input int      InpMinTP1Points      = 120;            // Min TP1 distance (points) - skip partial if closer
input int      InpMinTP2Points      = 250;            // Min TP2 distance (points) - fallback if closer
input int      InpMaxTPPoints       = 2000;           // Max TP distance (points) - clamp TP2
input bool     InpUseBrokerTP       = true;           // Use broker TP (false = no TP, manage manually)

input group "=== TP1 Partial Close ==="
input bool     InpUseTP1PartialClose = true;          // Enable partial close at TP1
input double   InpTP1CloseFraction   = 0.50;          // Fraction to close at TP1 (0.50 = 50%)
input bool     InpMoveSLToBEOnTP1    = true;          // Move SL to BE after TP1 partial close
input int      InpBEOffsetPoints     = 25;            // BE offset points (+ for profit buffer)
input double   InpMoveSLToLockR      = 0.0;           // Lock R multiple (0=use BE, >0=entry +/- LockR*riskPts)
input int      InpTP1TriggerBufferPoints = 1;         // TP1 trigger buffer (allow slightly before/after)
input double   InpMinPartialLots     = 0.01;          // Min partial close lots
input double   InpPartialClosePercent = 50.0;         // Partial close % at TP1/1R (legacy)

input group "=== Trailing Stop ==="
input bool     InpUseTrailing            = true;      // Enable trailing stop

enum TRAIL_START_MODE { TRAIL_AFTER_TP1, TRAIL_AFTER_R };
input TRAIL_START_MODE InpTrailStartMode = TRAIL_AFTER_TP1;  // When to start trailing

input double   InpTrailStartR             = 1.0;      // Start trailing at this R (for TRAIL_AFTER_R)
input int      InpTrailATRPeriod          = 14;       // ATR period for trailing
input double   InpTrailATRMult            = 1.2;      // ATR multiplier for trail distance
input int      InpTrailMinPoints          = 120;      // Min trailing distance (points) - prevent easy stops
input int      InpTrailStepPoints         = 20;       // Min improvement to modify SL (points)
input int      InpTrailCooldownSec        = 30;       // Cooldown between trail modifications (sec)
input int      InpTrailLockMinAfterTP1Points = 25;    // Min lock-in above BE after TP1 (points)
input bool     InpTrailUpdateOnNewBarOnly = true;     // Update trail only on new bar (reduce noise)

input group "=== Risk Guardrails ==="
input int      InpCooldownBars      = 3;              // Cooldown bars after close
input int      InpMaxConsecLosses   = 3;              // Max consecutive losses
input double   InpDailyLossLimitPct = 2.0;            // Daily loss limit (%)

input group "=== Spread Filter (Mode-Based) ==="
input int      InpMaxSpreadStrict   = 45;             // Max spread STRICT mode (points)
input int      InpMaxSpreadRelax    = 70;             // Max spread RELAX/RELAX2 mode (points)
input int      InpMaxSpreadRollover = 30;             // Max spread near rollover (points)
input int      InpSpreadSpikeWindowSec = 60;          // Spread spike window (seconds)
input double   InpSpreadSpikeMultiplier = 2.0;        // Spread spike multiplier (cur > avg*mult = cancel)
input int      InpLogSpreadCancelEverySec = 60;       // Log spread cancel throttle (seconds)

input group "=== SL Hit Protection ==="
input long     InpMagic             = 202601;         // Magic number for EA
input int      InpMaxSLHitsPerDay   = 3;              // Max SL hits per day
input bool     InpStopTradingOnSLHits = true;         // Stop trading after max SL hits

input group "=== Frequency Boost (Tiered RELAX) ==="
input int      InpTargetTradesPerDay = 3;             // Soft target trades/day (2-3)
input int      InpMaxTradesPerDay    = 30;            // Hard cap trades/day
input int      InpMinMinutesBetweenTrades = 10;       // Min minutes between trades (reduced from 15)
input bool     InpUseTargetFirstPolicy = true;        // Target-first: RELAX until target reached, then STRICT

input group "=== No-Trade Zone (Rollover Quarantine) ==="
input int      InpNoTradeStartHHMM   = 2355;          // No-trade zone start (HHMM) - default 23:55
input int      InpNoTradeEndHHMM     = 10;            // No-trade zone end (HHMM) - default 00:10
input bool     InpBlockAllModesInNoTrade = true;      // Block ALL modes in no-trade zone
input bool     InpEnableHardBlock    = false;         // Enable hard block (0=disabled)
input int      InpHardBlockAfterHHMM = 2300;          // Hard block after this time (HHMM) - only if enabled

input group "=== RELAX Mode ==="
input bool     InpEnableRelaxMode    = true;          // Enable RELAX mode
input int      InpRelaxSwitchHour    = 15;            // Switch to RELAX after this hour (earlier = more time)
input double   InpRelaxLotFactor     = 0.5;           // RELAX lot factor (reduce lot)
input bool     InpRelaxAllowBiasNone = true;          // RELAX allows bias=none
input bool     InpRelaxIgnoreTimeFilter = true;       // RELAX ignores timefilter when below target
input int      InpRelaxSweepBreakPoints = 12;         // RELAX sweep break points (user requested)
input int      InpRelaxRollingLiqBars   = 36;         // RELAX rolling liquidity bars
input int      InpRelaxReclaimMaxBars   = 3;          // RELAX reclaim max bars (increased)
input int      InpRelaxSwingK           = 1;          // RELAX swing lookback (1 = faster swing detection)
input int      InpRelaxConfirmMaxBars   = 12;         // RELAX CHOCH confirm max bars (user requested)
input int      InpRelaxEntryTimeoutBars = 35;         // RELAX entry timeout bars (slightly increased)
input double   InpRelaxRetraceRatio     = 0.30;       // RELAX retrace ratio (0.30 = 30%, easier entry)

input group "=== RELAX2 Mode (End of Day) ==="
input bool     InpEnableRelax2       = true;          // Enable RELAX2 mode (ON for more frequency)
input int      InpRelax2Hour         = 20;            // Switch to RELAX2 after this hour (earlier)
input double   InpRelax2LotFactor    = 0.3;           // RELAX2 lot factor (more reduced)
input int      InpRelax2SweepBreakPoints = 10;        // RELAX2 sweep break points (user requested)
input int      InpRelax2RollingLiqBars   = 24;        // RELAX2 rolling liquidity bars (reduced)
input bool     InpRelax2AllowBiasNone    = true;      // RELAX2 allows bias=none
input int      InpRelax2ReclaimMaxBars   = 4;         // RELAX2 reclaim max bars (more relaxed)
input int      InpRelax2SwingK           = 1;         // RELAX2 swing lookback (1 = faster swing detection)
input int      InpRelax2ConfirmMaxBars   = 18;        // RELAX2 CHOCH confirm max bars (user requested)
input int      InpRelax2EntryTimeoutBars = 50;        // RELAX2 entry timeout bars (slightly increased)
input double   InpRelax2RetraceRatio     = 0.22;      // RELAX2 retrace ratio (0.20-0.25 range)
input bool     InpEnableMicroChochRelax  = true;       // Enable micro CHOCH for RELAX mode
input bool     InpEnableMicroChochRelax2 = true;       // Enable micro CHOCH for RELAX2 mode
input double   InpMicroChochStartPct     = 0.55;       // Start micro CHOCH at this % of window (0.55 = 55%)
input int      InpMicroBreakPtsRelax     = 3;          // RELAX: min break size (points)
input int      InpMicroBodyPtsRelax      = 3;          // RELAX: min body size (points)
input int      InpMicroBreakPtsRelax2    = 3;          // RELAX2: min break size (points)
input int      InpMicroBodyPtsRelax2     = 3;          // RELAX2: min body size (points)
input int      InpMicroSwingLookback     = 1;          // Micro swing lookback bars (1-2)
input bool     InpMicroAllowWickBreak    = true;       // Allow wick break (then require body confirm)

input group "=== Martingale ==="
input bool     InpMartingaleStrictOnly = true;        // Martingale only in STRICT mode

input group "=== Time Filter ==="
input string   InpTradeStart        = "14:00";        // Trade start time (server)
input string   InpTradeEnd          = "23:30";        // Trade end time (server)
input bool     InpEnable24hTrading  = true;           // Enable 24h trading (default ON, respects rollover)

input group "=== CSV Logging ==="
input bool     InpEnableCSVLogging  = true;           // Enable daily CSV logging
input string   InpCSVFolder         = "SMC_Scalp_Logs"; // CSV folder name

input group "=== Martingale ==="
input ENUM_MARTINGALE_MODE InpMartingaleMode = MART_AFTER_LOSS; // Martingale mode
input double   InpBaseLot           = 0.01;           // Base lot
input double   InpMartMultiplier    = 2.0;            // Martingale multiplier
input int      InpMartMaxLevel      = 3;              // Max martingale level
input double   InpLotCapMax         = 0.08;           // Max lot cap

input group "=== Recovery TP (Martingale) ==="
input bool     InpUseRecoveryTP     = true;           // Use Recovery TP when martLevel>0
input double   InpRecoveryFactor    = 1.05;           // Recovery factor (1.05 = recover 105%)
input double   InpRecoveryBufferMoney = 0.0;          // Extra buffer money to recover ($)
// Note: InpMinTPPoints and InpMaxTPPoints moved to SL/TP Parameters section
input bool     InpDisablePartialOnRecovery = true;    // Disable partial close/BE/trailing during recovery

input group "=== Same Setup Only (Martingale) ==="
input bool     InpMartSameSetupOnly = true;           // Only continue mart if same setup
input int      InpMartMaxBarsSinceLoss = 200;         // Max bars since loss to continue mart
input bool     InpMartResetIfSetupChanged = true;     // Reset martLevel if setup changed

input group "=== Visual ==="
input bool     InpShowPanel         = true;           // Show info panel
input bool     InpShowLiquidity     = true;           // Show liquidity lines
input bool     InpShowZones         = true;           // Show FVG/OB zones
input color    InpColorPDH          = clrRed;         // PDH color
input color    InpColorPDL          = clrGreen;       // PDL color
input color    InpColorSessionH     = clrOrange;      // Session High color
input color    InpColorSessionL     = clrDodgerBlue;  // Session Low color
input color    InpColorFVG          = clrYellow;      // FVG zone color
input color    InpColorOB           = clrMagenta;     // OB zone color

input group "=== Logging ==="
input bool     InpEnableLogging     = true;           // Enable CSV logging

//=== GLOBAL VARIABLES ===
string         tradeSym;             // Resolved trading symbol
CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     orderInfo;

// State machine
ENUM_EA_STATE  g_state = STATE_WAIT_SWEEP;
ENUM_BIAS      g_bias = BIAS_NONE;
ENUM_SWEEP_TYPE g_sweepType = SWEEP_NONE;

// Liquidity levels
double         g_pdh = 0, g_pdl = 0;
double         g_sessionHigh = 0, g_sessionLow = 0;
double         g_eqh[], g_eql[];
double         g_swingHighs[], g_swingLows[];

// Current setup
double         g_sweepLevel = 0;
ENUM_LIQUIDITY_TYPE g_sweepLiqType = LIQ_NONE;
int            g_sweepBar = 0;
double         g_chochLevel = 0;
int            g_chochBar = 0;

// 2-stage CHOCH tracking
bool           g_chochStage1 = false;      // Stage1: wick BOS detected
double         g_chochStage1Level = 0;     // Level where wick BOS occurred
int            g_chochStage1Bar = 0;       // Bar counter since stage1
double         g_zoneHigh = 0, g_zoneLow = 0;
ENUM_ZONE_TYPE g_zoneType = ZONE_NONE;
int            g_zoneBar = 0;

// Trade management
double         g_entryPrice = 0;
double         g_slPrice = 0;
double         g_tp1Price = 0;
double         g_tp2Price = 0;
bool           g_partialClosed = false;
ulong          g_currentTicket = 0;
ulong          g_pendingTicket = 0;

// Risk tracking
int            g_tradesToday = 0;
int            g_consecLosses = 0;
double         g_dailyStartEquity = 0;
double         g_dailyPnL = 0;
int            g_cooldownCounter = 0;
datetime       g_lastTradeDay = 0;
datetime       g_lastTradeTime = 0;        // Time of last trade (for cooldown)

// Martingale
int            g_martLevel = 0;
double         g_currentLot = 0;
string         g_martLevelKey = "";  // GlobalVariable key for persistence

// Recovery TP
double         g_recoveryLoss = 0;           // Cumulative loss to recover
string         g_recoveryLossKey = "";       // GlobalVariable key for persistence

// Same Setup Only
string         g_lastSetupSignature = "";   // Signature of last losing trade setup
datetime       g_lastLossTime = 0;           // Time of last loss (for bars since loss)
int            g_lastLossBarIndex = 0;       // Bar index of last loss

// Entry tracking (for comment/lot consistency)
int            g_entryMartLevel = 0;         // MartLevel used when opening current position

// Position-based profit tracking (for partial close support)
struct PositionProfitData
{
   ulong    positionId;
   double   volumeIn;         // Total volume opened
   double   volumeOut;        // Total volume closed
   double   profitAccum;      // Accumulated profit (including partial closes)
   bool     isActive;
};
PositionProfitData g_positionData;            // Current position data

// Logging
int            g_tradesFileHandle = INVALID_HANDLE;
int            g_setupsFileHandle = INVALID_HANDLE;

// Swing arrays
double         g_m5SwingHighs[];
double         g_m5SwingLows[];
int            g_m5SwingHighBars[];
int            g_m5SwingLowBars[];
double         g_m15SwingHighs[];
double         g_m15SwingLows[];
int            g_m15SwingHighBars[];
int            g_m15SwingLowBars[];

// Visual objects
string         g_objPrefix = "SMC_";

// Bias tracking
int            g_emaHandle = INVALID_HANDLE;
string         g_biasNoneReason = "";
bool           g_tradingWithBiasNone = false;

// ATR handle for adaptive sweep
int            g_atrHandle = INVALID_HANDLE;
double         g_currentATR = 0;

// SL Hit tracking (daily)
int            g_slHitsToday = 0;
bool           g_blockedToday = false;
int            g_dayKeyYYYYMMDD = 0;
ulong          g_countedPositionIds[];

// Trade Mode (STRICT/RELAX)
ENUM_TRADE_MODE g_tradeMode = MODE_STRICT;
ENUM_TRADE_MODE g_prevTradeMode = MODE_STRICT;

// Rolling liquidity for RELAX mode
double         g_rollingHigh = 0;
double         g_rollingLow = 0;

// Spread Spike Filter (rolling average)
double         g_spreadHistory[];          // Rolling spread history
datetime       g_spreadTimeHistory[];      // Timestamps for spread history
int            g_spreadHistoryIdx = 0;     // Current index in circular buffer
int            g_spreadHistorySize = 120;  // Max samples (2 per second for 60 sec)
double         g_avgSpread = 0;            // Current rolling average spread
double         g_currentSpread = 0;        // Current spread for display
int            g_currentSpreadLimit = 0;   // Current spread limit for display

// Last cancel reason for panel display
string         g_lastCancelReason = "";
datetime       g_lastCancelTime = 0;

// Cancel Counters (daily statistics) - using array indexed by ENUM_CANCEL_REASON
int            g_cancelCounters[CANCEL_COUNT];     // Daily counters (legacy, keep for compatibility)
int            g_totalCancelCounters[CANCEL_COUNT]; // Total counters for final summary (legacy)
datetime       g_lastCancelBarTime[CANCEL_COUNT];  // Per-bar throttle: last bar time counted
ENUM_CANCEL_REASON g_lastCancelReasonEnum = CANCEL_NONE; // Last cancel reason as enum
bool           g_dailyLossDisabledLogged = false;  // Log once when disabled

// 2D Cancel Counters by MODE [3 modes][CANCEL_COUNT reasons]
// Index 0=STRICT, 1=RELAX, 2=RELAX2
int            g_cancelByMode[3][CANCEL_COUNT];      // Daily counters by mode
int            g_totalCancelByMode[3][CANCEL_COUNT]; // Total counters by mode

// Microchoch Diagnostic Counters by MODE
int            g_microchochAttempted[3];    // How many times TryMicroChoch was called
int            g_microchochPass[3];         // How many times it succeeded
int            g_microchochFailBreak[3];    // Failed: no break detected
int            g_microchochFailBody[3];     // Failed: body too small
int            g_totalMicrochochAttempted[3];
int            g_totalMicrochochPass[3];
int            g_totalMicrochochFailBreak[3];
int            g_totalMicrochochFailBody[3];

// Period tracking for final summary
int            g_totalTradingDays = 0;
int            g_totalTradesExecuted = 0;
double         g_totalPnL = 0;
int            g_totalSlHits = 0;

// Mode time counters (bars spent in each mode)
int            g_modeTimeBars[3];           // Daily: bars in STRICT/RELAX/RELAX2
int            g_totalModeTimeBars[3];      // All time: bars in each mode

// CSV file handle
int            g_csvFileHandle = INVALID_HANDLE;
string         g_csvFileName = "";

// TP1 Partial Close tracking (per position)
bool           g_tp1Done = false;              // TP1 partial close done for current position
ulong          g_tp1PositionId = 0;            // Position ID for TP1 tracking

// TP1 Diagnostic Counters
int            g_tp1PartialTriggeredCount = 0;  // Daily count
int            g_tp1PartialFailedCount = 0;     // Daily count (with reason)
int            g_tp1PartialSkippedCount = 0;    // Daily: skipped because TP1 too close
int            g_beMovedCount = 0;              // Daily count
int            g_totalTP1PartialTriggered = 0;  // All time
int            g_totalTP1PartialFailed = 0;     // All time
int            g_totalTP1PartialSkipped = 0;    // All time
int            g_totalBEMoved = 0;              // All time
string         g_lastTP1FailReason = "";        // Last failure reason

// Exit Classification Counters (Daily)
int            g_slLossHitsCount = 0;           // SL hits with actual loss (profit < -eps)
int            g_beStopCount = 0;               // SL hits but profit ~= 0 (BE stop, |profit| <= eps)
int            g_trailStopCount = 0;            // SL hits but profit > eps (trail/lock profit)
int            g_tpHitsCount = 0;               // TP hits
int            g_manualCloseCount = 0;          // Manual/other close

// Exit Classification Counters (All Time)
int            g_totalSlLossHits = 0;
int            g_totalBeStops = 0;
int            g_totalTrailStops = 0;
int            g_totalTpHits = 0;
int            g_totalManualClose = 0;

// Track if TP1 partial is disabled for current position (TP1 too close)
bool           g_tp1PartialDisabled = false;    // Set in PlaceOrder if tp1Pts < InpMinTP1Points

// Trailing Stop tracking (per position)
// Note: g_entryPrice is already declared in Trade management section
int            g_initialRiskPoints = 0;          // Initial risk (abs(entry-sl)/_Point) at entry
datetime       g_lastTrailModifyTime = 0;        // Last time trailing modified SL

// Trailing Stop Diagnostic Counters (Daily)
int            g_trailAttemptedCount = 0;
int            g_trailMovedCount = 0;
int            g_trailRejectCount = 0;          // Rejected due to stops/freeze constraints
int            g_trailSkippedCooldown = 0;
int            g_trailSkippedStep = 0;
int            g_trailSkippedNotAfterPartial = 0;
int            g_trailSkippedNotReachedR = 0;
int            g_trailSkippedNewBar = 0;        // Skipped due to not new bar
int            g_trailFailedCount = 0;

// Trailing Stop Diagnostic Counters (All Time)
int            g_totalTrailAttempted = 0;
int            g_totalTrailMoved = 0;
int            g_totalTrailReject = 0;
int            g_totalTrailSkippedCooldown = 0;
int            g_totalTrailSkippedStep = 0;
int            g_totalTrailSkippedNotAfterPartial = 0;
int            g_totalTrailSkippedNotReachedR = 0;
int            g_totalTrailSkippedNewBar = 0;
int            g_totalTrailFailed = 0;

// New bar tracking for trailing
datetime       g_lastTrailBarTime = 0;

// Trailing skip log throttle
datetime       g_lastTrailSkipLogTime = 0;
string         g_lastTrailSkipReason = "";

// Note: RELAX mode parameters are now controlled via input parameters
// InpRelaxSweepBreakPoints, InpRelaxRollingLiqBars, InpRelax2SweepBreakPoints, etc.

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Resolve trading symbol
   if(InpTradeSymbol == "")
   {
      tradeSym = _Symbol;
   }
   else
   {
      tradeSym = InpTradeSymbol;
   }
   
   // Validate symbol - flexible matching for XAUUSD variants
   if(StringFind(InpTradeSymbol, "XAUUSD") == 0 || InpTradeSymbol == "")
   {
      // Accept any symbol starting with XAUUSD (XAUUSD, XAUUSDm, XAUUSD.iux, etc.)
      if(StringFind(_Symbol, "XAUUSD") != 0 && InpTradeSymbol != "")
      {
         Print("Warning: Chart symbol ", _Symbol, " does not match expected XAUUSD variant");
      }
   }
   
   Print("Trading symbol resolved: ", tradeSym);
   
   // Initialize trade object with user-defined magic
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize lot
   g_currentLot = InpBaseLot;
   
   // Initialize daily tracking
   ResetDailyCounters();
   
   // Initialize SL hit tracking
   DailyResetIfNeeded();
   
   // Initialize logging
   if(InpEnableLogging)
   {
      InitLogging();
   }
   
   // Initialize EMA for bias detection
   if(InpBiasMode == BIAS_MODE_EMA200_M15)
   {
      g_emaHandle = iMA(tradeSym, InpBiasTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE)
      {
         Print("Error creating EMA indicator: ", GetLastError());
         return(INIT_FAILED);
      }
      Print("EMA", InpEMAPeriod, " initialized for bias detection");
   }
   
   // Initialize ATR for adaptive sweep threshold
   if(InpUseATRSweepThreshold)
   {
      g_atrHandle = iATR(tradeSym, InpEntryTF, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator: ", GetLastError());
         return(INIT_FAILED);
      }
      Print("ATR", InpATRPeriod, " initialized for adaptive sweep threshold");
   }
   
   // Initialize trade mode
   g_tradeMode = MODE_STRICT;
   g_prevTradeMode = MODE_STRICT;
   
   // === MARTINGALE PERSISTENCE ===
   // Create GlobalVariable key for this symbol+magic combination
   g_martLevelKey = "MART_LEVEL_" + tradeSym + "_" + IntegerToString(InpMagic);
   g_recoveryLossKey = "MART_RECLOSS_" + tradeSym + "_" + IntegerToString(InpMagic);
   
   // Load martLevel from GlobalVariable if exists (persistence across restarts)
   if(GlobalVariableCheck(g_martLevelKey))
   {
      g_martLevel = (int)GlobalVariableGet(g_martLevelKey);
      PrintFormat("MART_PERSIST: Loaded martLevel=%d from GlobalVariable key=%s", g_martLevel, g_martLevelKey);
   }
   else
   {
      g_martLevel = 0;
      GlobalVariableSet(g_martLevelKey, g_martLevel);
      PrintFormat("MART_PERSIST: Created new GlobalVariable key=%s with martLevel=0", g_martLevelKey);
   }
   
   // Load recoveryLoss from GlobalVariable if exists
   if(GlobalVariableCheck(g_recoveryLossKey))
   {
      g_recoveryLoss = GlobalVariableGet(g_recoveryLossKey);
      PrintFormat("MART_PERSIST: Loaded recoveryLoss=%.2f from GlobalVariable key=%s", g_recoveryLoss, g_recoveryLossKey);
   }
   else
   {
      g_recoveryLoss = 0;
      GlobalVariableSet(g_recoveryLossKey, g_recoveryLoss);
      PrintFormat("MART_PERSIST: Created new GlobalVariable key=%s with recoveryLoss=0", g_recoveryLossKey);
   }
   
   // Initialize spread history for spike detection
   ArrayResize(g_spreadHistory, g_spreadHistorySize);
   ArrayResize(g_spreadTimeHistory, g_spreadHistorySize);
   ArrayInitialize(g_spreadHistory, 0);
   ArrayInitialize(g_spreadTimeHistory, 0);
   g_spreadHistoryIdx = 0;
   g_avgSpread = 0;
   
   // Initialize cancel counters
   ArrayInitialize(g_cancelCounters, 0);
   ArrayInitialize(g_totalCancelCounters, 0);
   ArrayInitialize(g_lastCancelBarTime, 0);
   g_lastCancelReasonEnum = CANCEL_NONE;
   g_totalTradingDays = 0;
   g_totalTradesExecuted = 0;
   g_totalPnL = 0;
   g_totalSlHits = 0;
   
   // Initialize 2D cancel counters by mode
   for(int m = 0; m < 3; m++)
   {
      for(int r = 0; r < CANCEL_COUNT; r++)
      {
         g_cancelByMode[m][r] = 0;
         g_totalCancelByMode[m][r] = 0;
      }
      // Initialize microchoch diagnostic counters
      g_microchochAttempted[m] = 0;
      g_microchochPass[m] = 0;
      g_microchochFailBreak[m] = 0;
      g_microchochFailBody[m] = 0;
      g_totalMicrochochAttempted[m] = 0;
      g_totalMicrochochPass[m] = 0;
      g_totalMicrochochFailBreak[m] = 0;
      g_totalMicrochochFailBody[m] = 0;
      // Initialize mode time counters
      g_modeTimeBars[m] = 0;
      g_totalModeTimeBars[m] = 0;
   }
   
   // Initialize CSV logging
   if(InpEnableCSVLogging)
   {
      InitCSVLogging();
   }
   
   // Set timer for periodic updates
   EventSetTimer(1);
   
   // Initial calculations
   CalculateLiquidityLevels();
   CalculateRollingLiquidity();
   
   Print("SMC Scalping Bot v3.4.3 initialized on ", tradeSym);
   Print("Strategy Change B: TP at TP2, Partial close at TP1, BE move after TP1");
   Print("Trailing: Mode=", EnumToString(InpTrailStartMode), " ATRmult=", InpTrailATRMult, " MinPts=", InpTrailMinPoints, " Cooldown=", InpTrailCooldownSec, "s");
   Print("Magic: ", InpMagic, " | Bias Mode: ", EnumToString(InpBiasMode));
   Print("Bias TF: ", EnumToString(InpBiasTF), " | Entry TF: ", EnumToString(InpEntryTF));
   Print("Max SL Hits/Day: ", InpMaxSLHitsPerDay, " | Stop on SL Hits: ", InpStopTradingOnSLHits);
   Print("Target Trades: ", InpTargetTradesPerDay, " | Max Trades: ", InpMaxTradesPerDay, " | Cooldown: ", InpMinMinutesBetweenTrades, "m");
   Print("Policy: ", InpUseTargetFirstPolicy ? "TARGET-FIRST (RELAX until target)" : "TIME-BASED (hour-based)");
   Print("RELAX: ", InpEnableRelaxMode, " @", InpRelaxSwitchHour, ":00 | Sweep: ", InpRelaxSweepBreakPoints, "pts | SwingK: ", InpRelaxSwingK, " | ConfirmBars: ", InpRelaxConfirmMaxBars);
   Print("RELAX2: ", InpEnableRelax2, " @", InpRelax2Hour, ":00 | Sweep: ", InpRelax2SweepBreakPoints, "pts | SwingK: ", InpRelax2SwingK, " | ConfirmBars: ", InpRelax2ConfirmMaxBars);
   Print("ATR Sweep: ", InpUseATRSweepThreshold, " | Factor: ", InpSweepATRFactor, " | STRICT ConfirmBars: ", InpConfirmMaxBars);
   Print("2-Stage CHOCH: ", InpUse2StageChoch, " | Stage2 Confirm: ", InpStage2ConfirmBars, " bars");
   Print("Micro CHOCH: RELAX=", InpEnableMicroChochRelax, " RELAX2=", InpEnableMicroChochRelax2, 
         " | Start@", (int)(InpMicroChochStartPct*100), "% | WickBreak=", InpMicroAllowWickBreak);
   Print("Micro Params: RELAX Break/Body=", InpMicroBreakPtsRelax, "/", InpMicroBodyPtsRelax, 
         "pts | RELAX2 Break/Body=", InpMicroBreakPtsRelax2, "/", InpMicroBodyPtsRelax2, "pts");
   Print("NoTrade Zone: ", InpNoTradeStartHHMM, "-", InpNoTradeEndHHMM, " | Hard Block: ", InpEnableHardBlock ? StringFormat("%04d", InpHardBlockAfterHHMM) : "OFF");
   Print("24h Trading: ", InpEnable24hTrading, " | CSV Logging: ", InpEnableCSVLogging);
   Print("Spread: STRICT=", InpMaxSpreadStrict, " RELAX=", InpMaxSpreadRelax, " Rollover=", InpMaxSpreadRollover, " | Spike mult=", InpSpreadSpikeMultiplier);
   Print("Martingale: Mode=", EnumToString(InpMartingaleMode), " | Mult=", InpMartMultiplier, " | MaxLvl=", InpMartMaxLevel, " | StrictOnly=", InpMartingaleStrictOnly);
   Print("Recovery TP: Enabled=", InpUseRecoveryTP, " | Factor=", InpRecoveryFactor, " | Buffer=", InpRecoveryBufferMoney, 
         " | MinTP1=", InpMinTP1Points, " | MinTP2=", InpMinTP2Points, " | MaxTP=", InpMaxTPPoints, " | DisablePartial=", InpDisablePartialOnRecovery);
   Print("Same Setup: Enabled=", InpMartSameSetupOnly, " | MaxBars=", InpMartMaxBarsSinceLoss, " | ResetIfChanged=", InpMartResetIfSetupChanged);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Print final daily summary before exit
   PrintDailySummary();
   
   // Print FINAL SUMMARY (period summary)
   PrintFinalSummary();
   
   // Write final CSV entry
   if(InpEnableCSVLogging)
   {
      WriteCSVDailyEntry();
      if(g_csvFileHandle != INVALID_HANDLE)
         FileClose(g_csvFileHandle);
   }
   
   // Release EMA indicator
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
   
   // Release ATR indicator
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   
   // Close log files
   if(g_tradesFileHandle != INVALID_HANDLE)
      FileClose(g_tradesFileHandle);
   if(g_setupsFileHandle != INVALID_HANDLE)
      FileClose(g_setupsFileHandle);
   
   // Remove visual objects
   ObjectsDeleteAll(0, g_objPrefix);
   
   // === MARTINGALE PERSISTENCE ===
   // Save martLevel to GlobalVariable for persistence across restarts
   if(g_martLevelKey != "")
   {
      GlobalVariableSet(g_martLevelKey, g_martLevel);
      PrintFormat("MART_PERSIST: Saved martLevel=%d to GlobalVariable key=%s", g_martLevel, g_martLevelKey);
   }
   
   // Save recoveryLoss to GlobalVariable
   if(g_recoveryLossKey != "")
   {
      GlobalVariableSet(g_recoveryLossKey, g_recoveryLoss);
      PrintFormat("MART_PERSIST: Saved recoveryLoss=%.2f to GlobalVariable key=%s", g_recoveryLoss, g_recoveryLossKey);
   }
   
   Print("SMC Scalping Bot v3.4.3 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Update panel
   if(InpShowPanel)
      UpdatePanel();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new day and reset SL hit counter
   CheckNewDay();
   DailyResetIfNeeded();
   
   // Check if blocked due to SL hits
   if(g_blockedToday && InpStopTradingOnSLHits)
   {
      return;  // Stop all trading activity for today
   }
   
   // Check if max trades reached
   if(g_tradesToday >= InpMaxTradesPerDay)
   {
      return;  // Hard cap reached
   }
   
   // Update trade mode (STRICT/RELAX)
   UpdateTradeMode();
   
   // Update liquidity levels periodically
   static datetime lastLiqUpdate = 0;
   if(TimeCurrent() - lastLiqUpdate > 60)
   {
      CalculateLiquidityLevels();
      CalculateRollingLiquidity();
      UpdateATR();  // Update ATR for adaptive sweep
      lastLiqUpdate = TimeCurrent();
   }
   
   // Draw visuals
   if(InpShowLiquidity)
      DrawLiquidityLevels();
   
   // Check if we have open position
   if(PositionSelect(tradeSym))
   {
      g_state = STATE_MANAGE_TRADE;
      ManageTrade();
      return;
   }
   
   // Check pending orders
   if(HasPendingOrder())
   {
      CheckPendingOrder();
      return;
   }
   
   // Risk checks before looking for setups
   if(!PassRiskChecks())
   {
      return;
   }
   
   // State machine
   switch(g_state)
   {
      case STATE_WAIT_SWEEP:
         LookForSweep();
         break;
         
      case STATE_WAIT_CHOCH:
         LookForChoCH();
         break;
         
      case STATE_WAIT_RETRACE:
         LookForRetrace();
         break;
         
      case STATE_PLACE_ORDER:
         PlaceOrder();
         break;
         
      case STATE_COOLDOWN:
         HandleCooldown();
         break;
         
      default:
         g_state = STATE_WAIT_SWEEP;
         break;
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Check for daily reset first
   DailyResetIfNeeded();
   
   // DEBUG: Log all transaction types
   PrintFormat("TRANS_DEBUG: type=%d symbol=%s deal=%I64u order=%I64u",
               trans.type, trans.symbol, trans.deal, trans.order);
   
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      PrintFormat("TRANS_DEBUG: DEAL_ADD detected - symbol=%s tradeSym=%s deal=%I64u",
                  trans.symbol, tradeSym, trans.deal);
      
      // A deal was added - check if it's ours
      if(trans.symbol == tradeSym)
      {
         Print("TRANS_DEBUG: Symbol matches, processing deal...");
         
         // Check for SL hit (for daily SL counter)
         CheckDealForSLHit(trans.deal);
         
         // Update martingale level based on deal result
         UpdateMartingaleFromDeal(trans.deal);
      }
      else
      {
         PrintFormat("TRANS_DEBUG: Symbol mismatch - trans.symbol=%s tradeSym=%s",
                     trans.symbol, tradeSym);
      }
   }
}

//=== SWING DETECTION ===
//+------------------------------------------------------------------+
//| Detect swing points using fractal method                           |
//+------------------------------------------------------------------+
void DetectSwings(ENUM_TIMEFRAMES tf, double &swingHighs[], double &swingLows[], 
                  int &swingHighBars[], int &swingLowBars[], int lookback = 100)
{
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLowBars, 0);
   
   // Use tiered SwingK based on trade mode
   int k = GetSwingK();
   
   for(int i = k; i < lookback - k; i++)
   {
      double high_i = iHigh(tradeSym, tf, i);
      double low_i = iLow(tradeSym, tf, i);
      
      bool isSwingHigh = true;
      bool isSwingLow = true;
      
      for(int j = 1; j <= k; j++)
      {
         if(high_i <= iHigh(tradeSym, tf, i - j) || high_i <= iHigh(tradeSym, tf, i + j))
            isSwingHigh = false;
         if(low_i >= iLow(tradeSym, tf, i - j) || low_i >= iLow(tradeSym, tf, i + j))
            isSwingLow = false;
      }
      
      if(isSwingHigh)
      {
         int size = ArraySize(swingHighs);
         ArrayResize(swingHighs, size + 1);
         ArrayResize(swingHighBars, size + 1);
         swingHighs[size] = high_i;
         swingHighBars[size] = i;
      }
      
      if(isSwingLow)
      {
         int size = ArraySize(swingLows);
         ArrayResize(swingLows, size + 1);
         ArrayResize(swingLowBars, size + 1);
         swingLows[size] = low_i;
         swingLowBars[size] = i;
      }
   }
}

//+------------------------------------------------------------------+
//| Get latest minor swing high                                        |
//+------------------------------------------------------------------+
double GetLatestMinorSwingHigh(ENUM_TIMEFRAMES tf, int &barIndex)
{
   double swingHighs[], swingLows[];
   int swingHighBars[], swingLowBars[];
   
   DetectSwings(tf, swingHighs, swingLows, swingHighBars, swingLowBars, 50);
   
   if(ArraySize(swingHighs) > 0)
   {
      barIndex = swingHighBars[0];
      return swingHighs[0];
   }
   
   barIndex = -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Get latest minor swing low                                         |
//+------------------------------------------------------------------+
double GetLatestMinorSwingLow(ENUM_TIMEFRAMES tf, int &barIndex)
{
   double swingHighs[], swingLows[];
   int swingHighBars[], swingLowBars[];
   
   DetectSwings(tf, swingHighs, swingLows, swingHighBars, swingLowBars, 50);
   
   if(ArraySize(swingLows) > 0)
   {
      barIndex = swingLowBars[0];
      return swingLows[0];
   }
   
   barIndex = -1;
   return 0;
}

//=== LIQUIDITY DETECTION ===
//+------------------------------------------------------------------+
//| Calculate all liquidity levels                                     |
//+------------------------------------------------------------------+
void CalculateLiquidityLevels()
{
   // PDH/PDL
   g_pdh = iHigh(tradeSym, PERIOD_D1, 1);
   g_pdl = iLow(tradeSym, PERIOD_D1, 1);
   
   // Session High/Low (current day)
   CalculateSessionHighLow();
   
   // EQH/EQL
   CalculateEqualHighsLows();
   
   // Store swing levels - use appropriate swing K based on mode
   // RELAX/RELAX2 use smaller swing K (1) for internal structure detection
   int swingK = (g_tradeMode == MODE_STRICT) ? InpSwingK : 1;
   DetectSwings(InpEntryTF, g_m5SwingHighs, g_m5SwingLows, g_m5SwingHighBars, g_m5SwingLowBars, 100);
   DetectSwings(InpBiasTF, g_m15SwingHighs, g_m15SwingLows, g_m15SwingHighBars, g_m15SwingLowBars, 100);
}

//+------------------------------------------------------------------+
//| Calculate rolling high/low for RELAX mode                          |
//+------------------------------------------------------------------+
void CalculateRollingLiquidity()
{
   g_rollingHigh = 0;
   g_rollingLow = DBL_MAX;
   
   // Use mode-based rolling bars
   int rollingBars = GetRollingLiqBars();
   int barsToCheck = MathMin(rollingBars, iBars(tradeSym, InpEntryTF));
   
   for(int i = 0; i < barsToCheck; i++)
   {
      double high = iHigh(tradeSym, InpEntryTF, i);
      double low = iLow(tradeSym, InpEntryTF, i);
      
      if(high > g_rollingHigh) g_rollingHigh = high;
      if(low < g_rollingLow) g_rollingLow = low;
   }
   
   if(g_rollingLow == DBL_MAX) g_rollingLow = 0;
}

//+------------------------------------------------------------------+
//| Calculate session high/low                                         |
//+------------------------------------------------------------------+
void CalculateSessionHighLow()
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   g_sessionHigh = 0;
   g_sessionLow = DBL_MAX;
   
   int bars = iBars(tradeSym, InpEntryTF);
   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(tradeSym, InpEntryTF, i);
      if(barTime < dayStart)
         break;
      
      double high = iHigh(tradeSym, InpEntryTF, i);
      double low = iLow(tradeSym, InpEntryTF, i);
      
      if(high > g_sessionHigh) g_sessionHigh = high;
      if(low < g_sessionLow) g_sessionLow = low;
   }
   
   if(g_sessionLow == DBL_MAX) g_sessionLow = 0;
}

//+------------------------------------------------------------------+
//| Calculate equal highs/lows                                         |
//+------------------------------------------------------------------+
void CalculateEqualHighsLows()
{
   ArrayResize(g_eqh, 0);
   ArrayResize(g_eql, 0);
   
   double threshold = InpEqThresholdPoints * _Point;
   
   // Find EQH
   for(int i = 0; i < ArraySize(g_m5SwingHighs); i++)
   {
      for(int j = i + 1; j < ArraySize(g_m5SwingHighs); j++)
      {
         if(MathAbs(g_m5SwingHighs[i] - g_m5SwingHighs[j]) <= threshold)
         {
            double avg = (g_m5SwingHighs[i] + g_m5SwingHighs[j]) / 2;
            bool exists = false;
            for(int k = 0; k < ArraySize(g_eqh); k++)
            {
               if(MathAbs(g_eqh[k] - avg) <= threshold)
               {
                  exists = true;
                  break;
               }
            }
            if(!exists)
            {
               int size = ArraySize(g_eqh);
               ArrayResize(g_eqh, size + 1);
               g_eqh[size] = avg;
            }
         }
      }
   }
   
   // Find EQL
   for(int i = 0; i < ArraySize(g_m5SwingLows); i++)
   {
      for(int j = i + 1; j < ArraySize(g_m5SwingLows); j++)
      {
         if(MathAbs(g_m5SwingLows[i] - g_m5SwingLows[j]) <= threshold)
         {
            double avg = (g_m5SwingLows[i] + g_m5SwingLows[j]) / 2;
            bool exists = false;
            for(int k = 0; k < ArraySize(g_eql); k++)
            {
               if(MathAbs(g_eql[k] - avg) <= threshold)
               {
                  exists = true;
                  break;
               }
            }
            if(!exists)
            {
               int size = ArraySize(g_eql);
               ArrayResize(g_eql, size + 1);
               g_eql[size] = avg;
            }
         }
      }
   }
}

//=== SWEEP DETECTION ===
//+------------------------------------------------------------------+
//| Look for liquidity sweep                                           |
//+------------------------------------------------------------------+
void LookForSweep()
{
   // Get bias first
   g_bias = GetBias();
   g_tradingWithBiasNone = false;  // Reset flag
   
   // Handle BIAS_NONE cases
   if(g_bias == BIAS_NONE)
   {
      // Check if bias none is allowed (considers mode)
      if(!IsBiasNoneAllowed())
      {
         LogSetup("WAIT_SWEEP", "nobias_strict", g_bias, false, false, ZONE_NONE, 0, 0, 0);
         RecordCancel(CANCEL_BIAS_NONE);
         return;
      }
      
      // Bias none is allowed - trade with reduced lot
      g_tradingWithBiasNone = true;
      Print("Trading with BIAS_NONE [", EnumToString(g_tradeMode), "]. Reason: ", g_biasNoneReason);
      // Look for both directions when bias is none
      LookForSweepBothDirections();
      return;
   }
   
   // Use mode-based sweep break points
   int sweepBreakPts = GetSweepBreakPoints();
   double sweepBreak = MathMax(sweepBreakPts, (int)MathCeil(2 * GetSpreadPoints())) * _Point;
   
   // Check for sweep based on bias
   if(g_bias == BIAS_BULLISH)
   {
      // Look for sweep down (liquidity grab below)
      if(CheckSweepDown(sweepBreak))
      {
         g_sweepType = SWEEP_BULLISH;
         g_state = STATE_WAIT_CHOCH;
         Print("Sweep DOWN detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ") [Bias: BULLISH] [", EnumToString(g_tradeMode), "]");
      }
      else
      {
         RecordCancel(CANCEL_NO_SWEEP);
      }
   }
   else if(g_bias == BIAS_BEARISH)
   {
      // Look for sweep up (liquidity grab above)
      if(CheckSweepUp(sweepBreak))
      {
         g_sweepType = SWEEP_BEARISH;
         g_state = STATE_WAIT_CHOCH;
         Print("Sweep UP detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ") [Bias: BEARISH] [", EnumToString(g_tradeMode), "]");
      }
      else
      {
         RecordCancel(CANCEL_NO_SWEEP);
      }
   }
}

//+------------------------------------------------------------------+
//| Look for sweep in both directions (when bias is none)              |
//+------------------------------------------------------------------+
void LookForSweepBothDirections()
{
   int sweepBreakPts = GetSweepBreakPoints();
   double sweepBreak = MathMax(sweepBreakPts, (int)MathCeil(2 * GetSpreadPoints())) * _Point;
   
   // Try sweep down first (for potential long)
   if(CheckSweepDown(sweepBreak))
   {
      g_sweepType = SWEEP_BULLISH;
      g_state = STATE_WAIT_CHOCH;
      Print("Sweep DOWN detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ") [Bias: NONE] [", EnumToString(g_tradeMode), "]");
      return;
   }
   
   // Try sweep up (for potential short)
   if(CheckSweepUp(sweepBreak))
   {
      g_sweepType = SWEEP_BEARISH;
      g_state = STATE_WAIT_CHOCH;
      Print("Sweep UP detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ") [Bias: NONE] [", EnumToString(g_tradeMode), "]");
      return;
   }
   
   RecordCancel(CANCEL_NO_SWEEP);
}

//+------------------------------------------------------------------+
//| Check for sweep down (below liquidity)                             |
//+------------------------------------------------------------------+
bool CheckSweepDown(double sweepBreak)
{
   // Check liquidity levels: PDL, Session Low, EQL, Swing Lows, Rolling Low (RELAX)
   double levels[];
   ENUM_LIQUIDITY_TYPE types[];
   
   // Collect all lower liquidity levels
   int count = 0;
   
   // PDL
   if(g_pdl > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_pdl;
      types[count] = LIQ_PDL;
      count++;
   }
   
   // Session Low
   if(g_sessionLow > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_sessionLow;
      types[count] = LIQ_SESSION_LOW;
      count++;
   }
   
   // Rolling Low (RELAX mode additional liquidity)
   if(g_tradeMode == MODE_RELAX && g_rollingLow > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_rollingLow;
      types[count] = LIQ_SWING_LOW;  // Use swing low type for rolling
      count++;
   }
   
   // EQL
   for(int i = 0; i < ArraySize(g_eql); i++)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_eql[i];
      types[count] = LIQ_EQL;
      count++;
   }
   
   // Swing Lows
   for(int i = 0; i < ArraySize(g_m5SwingLows) && i < 5; i++)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_m5SwingLows[i];
      types[count] = LIQ_SWING_LOW;
      count++;
   }
   
   // Check each level for sweep
   for(int i = 0; i < count; i++)
   {
      if(IsSweepLevel(levels[i], sweepBreak, false))
      {
         g_sweepLevel = levels[i];
         g_sweepLiqType = types[i];
         g_sweepBar = 0;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for sweep up (above liquidity)                               |
//+------------------------------------------------------------------+
bool CheckSweepUp(double sweepBreak)
{
   double levels[];
   ENUM_LIQUIDITY_TYPE types[];
   
   int count = 0;
   
   // PDH
   if(g_pdh > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_pdh;
      types[count] = LIQ_PDH;
      count++;
   }
   
   // Session High
   if(g_sessionHigh > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_sessionHigh;
      types[count] = LIQ_SESSION_HIGH;
      count++;
   }
   
   // Rolling High (RELAX mode additional liquidity)
   if(g_tradeMode == MODE_RELAX && g_rollingHigh > 0)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_rollingHigh;
      types[count] = LIQ_SWING_HIGH;  // Use swing high type for rolling
      count++;
   }
   
   // EQH
   for(int i = 0; i < ArraySize(g_eqh); i++)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_eqh[i];
      types[count] = LIQ_EQH;
      count++;
   }
   
   // Swing Highs
   for(int i = 0; i < ArraySize(g_m5SwingHighs) && i < 5; i++)
   {
      ArrayResize(levels, count + 1);
      ArrayResize(types, count + 1);
      levels[count] = g_m5SwingHighs[i];
      types[count] = LIQ_SWING_HIGH;
      count++;
   }
   
   for(int i = 0; i < count; i++)
   {
      if(IsSweepLevel(levels[i], sweepBreak, true))
      {
         g_sweepLevel = levels[i];
         g_sweepLiqType = types[i];
         g_sweepBar = 0;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if a level was swept                                         |
//+------------------------------------------------------------------+
bool IsSweepLevel(double level, double sweepBreak, bool isHigh)
{
   for(int bar = 0; bar <= InpReclaimMaxBars; bar++)
   {
      double high = iHigh(tradeSym, InpEntryTF, bar);
      double low = iLow(tradeSym, InpEntryTF, bar);
      double close = iClose(tradeSym, InpEntryTF, bar);
      
      if(isHigh)
      {
         // Sweep up: wick above level, close back below
         if(high > level + sweepBreak && close < level)
         {
            return true;
         }
      }
      else
      {
         // Sweep down: wick below level, close back above
         if(low < level - sweepBreak && close > level)
         {
            return true;
         }
      }
   }
   
   return false;
}

//=== CHOCH DETECTION ===
//+------------------------------------------------------------------+
//| Look for Change of Character (with optional 2-stage confirm)       |
//| Includes micro CHOCH fallback for RELAX2 mode                       |
//+------------------------------------------------------------------+
void LookForChoCH()
{
   // Check timeout using mode-based parameter
   int confirmMaxBars = GetConfirmMaxBars();
   int barsSinceSweep = g_sweepBar;
   
   // For 2-stage mode: also check stage2 timeout
   if(g_chochStage1 && g_chochStage1Bar > InpStage2ConfirmBars)
   {
      // Stage1 wick BOS detected but close-confirm timed out
      LogSetup("WAIT_CHOCH", "stage2_timeout", g_bias, true, false, ZONE_NONE, 0, 0, 0);
      RecordCancel(CANCEL_CHOCH_TIMEOUT);
      ResetSetup();
      return;
   }
   
   // Check if we should try micro CHOCH fallback (RELAX or RELAX2)
   // Start considering micro CHOCH at InpMicroChochStartPct of window (e.g., 55% = bar 10 of 18)
   bool microChochEnabled = false;
   if(g_tradeMode == MODE_RELAX && InpEnableMicroChochRelax) microChochEnabled = true;
   if(g_tradeMode == MODE_RELAX2 && InpEnableMicroChochRelax2) microChochEnabled = true;
   
   int microChochStartBar = (int)(confirmMaxBars * InpMicroChochStartPct);
   if(microChochEnabled && barsSinceSweep >= microChochStartBar)
   {
      // Try micro CHOCH every bar from start point onwards
      if(TryMicroChochFallback())
      {
         // Micro CHOCH succeeded
         return;
      }
   }
   
   if(barsSinceSweep > confirmMaxBars)
   {
      LogSetup("WAIT_CHOCH", "timeout", g_bias, true, false, ZONE_NONE, 0, 0, 0);
      RecordCancel(CANCEL_CHOCH_TIMEOUT);
      ResetSetup();
      return;
   }
   
   // Get CHOCH mode based on trade mode
   ENUM_CHOCH_MODE chochMode = GetChochMode();
   bool use2Stage = InpUse2StageChoch && (g_tradeMode != MODE_STRICT);
   
   int minorSwingBar;
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      // After sweep down, look for bullish CHOCH
      double minorSwingHigh = GetLatestMinorSwingHigh(InpEntryTF, minorSwingBar);
      
      if(minorSwingHigh > 0 && minorSwingBar > 0)
      {
         double close = iClose(tradeSym, InpEntryTF, 0);
         double high = iHigh(tradeSym, InpEntryTF, 0);
         
         bool chochConfirmed = false;
         
         if(chochMode == CHOCH_CLOSE_ONLY || !use2Stage)
         {
            // STRICT or non-2stage: require close above level
            chochConfirmed = (close > minorSwingHigh);
         }
         else // CHOCH_WICK_OK with 2-stage
         {
            // 2-stage confirmation for RELAX modes
            if(!g_chochStage1)
            {
               // Stage1: check for wick BOS
               if(high > minorSwingHigh)
               {
                  g_chochStage1 = true;
                  g_chochStage1Level = minorSwingHigh;
                  g_chochStage1Bar = 0;
                  Print("Bullish CHOCH Stage1 (wick BOS) at ", minorSwingHigh);
               }
            }
            else
            {
               // Stage2: require close-confirm within N bars
               if(close > g_chochStage1Level)
               {
                  chochConfirmed = true;
                  Print("Bullish CHOCH Stage2 (close confirm) at ", g_chochStage1Level, " after ", g_chochStage1Bar, " bars");
               }
               g_chochStage1Bar++;
            }
         }
         
         if(chochConfirmed)
         {
            g_chochLevel = (g_chochStage1) ? g_chochStage1Level : minorSwingHigh;
            g_chochBar = 0;
            g_state = STATE_WAIT_RETRACE;
            
            // Reset stage1 tracking
            g_chochStage1 = false;
            g_chochStage1Level = 0;
            g_chochStage1Bar = 0;
            
            // Build zones
            BuildZones(true);
            
            Print("Bullish CHOCH confirmed at ", g_chochLevel, " (mode: ", EnumToString(chochMode), ", 2stage: ", use2Stage, ")");
         }
      }
   }
   else if(g_sweepType == SWEEP_BEARISH)
   {
      // After sweep up, look for bearish CHOCH
      double minorSwingLow = GetLatestMinorSwingLow(InpEntryTF, minorSwingBar);
      
      if(minorSwingLow > 0 && minorSwingBar > 0)
      {
         double close = iClose(tradeSym, InpEntryTF, 0);
         double low = iLow(tradeSym, InpEntryTF, 0);
         
         bool chochConfirmed = false;
         
         if(chochMode == CHOCH_CLOSE_ONLY || !use2Stage)
         {
            // STRICT or non-2stage: require close below level
            chochConfirmed = (close < minorSwingLow);
         }
         else // CHOCH_WICK_OK with 2-stage
         {
            // 2-stage confirmation for RELAX modes
            if(!g_chochStage1)
            {
               // Stage1: check for wick BOS
               if(low < minorSwingLow)
               {
                  g_chochStage1 = true;
                  g_chochStage1Level = minorSwingLow;
                  g_chochStage1Bar = 0;
                  Print("Bearish CHOCH Stage1 (wick BOS) at ", minorSwingLow);
               }
            }
            else
            {
               // Stage2: require close-confirm within N bars
               if(close < g_chochStage1Level)
               {
                  chochConfirmed = true;
                  Print("Bearish CHOCH Stage2 (close confirm) at ", g_chochStage1Level, " after ", g_chochStage1Bar, " bars");
               }
               g_chochStage1Bar++;
            }
         }
         
         if(chochConfirmed)
         {
            g_chochLevel = (g_chochStage1) ? g_chochStage1Level : minorSwingLow;
            g_chochBar = 0;
            g_state = STATE_WAIT_RETRACE;
            
            // Reset stage1 tracking
            g_chochStage1 = false;
            g_chochStage1Level = 0;
            g_chochStage1Bar = 0;
            
            // Build zones
            BuildZones(false);
            
            Print("Bearish CHOCH confirmed at ", g_chochLevel, " (mode: ", EnumToString(chochMode), ", 2stage: ", use2Stage, ")");
         }
      }
   }
   
   g_sweepBar++;
}

//+------------------------------------------------------------------+
//| Try micro CHOCH fallback for RELAX/RELAX2 mode                      |
//| SIMPLIFIED VERSION for debugging - minimal requirements             |
//| Requirements: close break >= InpMicroBreakPts AND body >= InpMicroMinBodyPts |
//+------------------------------------------------------------------+
bool TryMicroChochFallback()
{
   // Get mode index for diagnostic counters
   int modeIdx = (int)g_tradeMode;
   if(modeIdx < 0 || modeIdx > 2) modeIdx = 0;
   
   // Increment attempted counter
   g_microchochAttempted[modeIdx]++;
   
   // Get current bar data
   double open = iOpen(tradeSym, InpEntryTF, 0);
   double close = iClose(tradeSym, InpEntryTF, 0);
   double high = iHigh(tradeSym, InpEntryTF, 0);
   double low = iLow(tradeSym, InpEntryTF, 0);
   
   // Calculate body size
   double bodySize = MathAbs(close - open);
   int bodyPoints = (int)(bodySize / _Point);
   
   // Get mode-specific parameters
   int minBodyPts, minBreakPts;
   if(g_tradeMode == MODE_RELAX2)
   {
      minBodyPts = InpMicroBodyPtsRelax2;
      minBreakPts = InpMicroBreakPtsRelax2;
   }
   else // MODE_RELAX or fallback
   {
      minBodyPts = InpMicroBodyPtsRelax;
      minBreakPts = InpMicroBreakPtsRelax;
   }
   
   // Check body size first
   if(bodyPoints < minBodyPts)
   {
      g_microchochFailBody[modeIdx]++;
      return false;
   }
   
   // Find micro swing using simple lookback
   int lookback = MathMax(1, MathMin(2, InpMicroSwingLookback));
   bool hasBreak = false;
   double microLevel = 0;
   int breakPts = 0;
   bool isWickBreak = false;
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      // Find micro swing high from last N bars
      double microSwingHigh = 0;
      for(int i = 1; i <= lookback; i++)
      {
         double h = iHigh(tradeSym, InpEntryTF, i);
         if(h > microSwingHigh) microSwingHigh = h;
      }
      
      if(microSwingHigh > 0)
      {
         // Check close break first
         if(close > microSwingHigh)
         {
            breakPts = (int)((close - microSwingHigh) / _Point);
            if(breakPts >= minBreakPts)
            {
               hasBreak = true;
               microLevel = microSwingHigh;
            }
         }
         // If no close break, check wick break (if enabled)
         else if(InpMicroAllowWickBreak && high > microSwingHigh)
         {
            breakPts = (int)((high - microSwingHigh) / _Point);
            if(breakPts >= minBreakPts && bodyPoints >= minBodyPts)
            {
               // Wick break with body confirmation
               hasBreak = true;
               microLevel = microSwingHigh;
               isWickBreak = true;
            }
         }
      }
   }
   else if(g_sweepType == SWEEP_BEARISH)
   {
      // Find micro swing low from last N bars
      double microSwingLow = DBL_MAX;
      for(int i = 1; i <= lookback; i++)
      {
         double l = iLow(tradeSym, InpEntryTF, i);
         if(l < microSwingLow) microSwingLow = l;
      }
      
      if(microSwingLow < DBL_MAX)
      {
         // Check close break first
         if(close < microSwingLow)
         {
            breakPts = (int)((microSwingLow - close) / _Point);
            if(breakPts >= minBreakPts)
            {
               hasBreak = true;
               microLevel = microSwingLow;
            }
         }
         // If no close break, check wick break (if enabled)
         else if(InpMicroAllowWickBreak && low < microSwingLow)
         {
            breakPts = (int)((microSwingLow - low) / _Point);
            if(breakPts >= minBreakPts && bodyPoints >= minBodyPts)
            {
               // Wick break with body confirmation
               hasBreak = true;
               microLevel = microSwingLow;
               isWickBreak = true;
            }
         }
      }
   }
   
   if(!hasBreak)
   {
      g_microchochFailBreak[modeIdx]++;
      return false;
   }
   
   // SUCCESS - micro CHOCH confirmed
   g_microchochPass[modeIdx]++;
   
   g_chochLevel = microLevel;
   g_chochBar = 0;
   g_state = STATE_WAIT_RETRACE;
   
   // Reset stage1 tracking
   g_chochStage1 = false;
   g_chochStage1Level = 0;
   g_chochStage1Bar = 0;
   
   // Build zones
   BuildZones(g_sweepType == SWEEP_BULLISH);
   
   // Record that micro CHOCH was used (info counter)
   RecordCancel(INFO_MICROCHOCH_USED);
   
   string breakType = isWickBreak ? "WICK" : "CLOSE";
   Print("MICRO CHOCH [", EnumToString(g_tradeMode), "] at ", microLevel, 
         " | ", breakType, " Break: ", breakPts, "pts (min:", minBreakPts, ") | Body: ", bodyPoints, "pts (min:", minBodyPts, ")");
   return true;
}

//=== ZONE BUILDING ===
//+------------------------------------------------------------------+
//| Build FVG and OB zones after CHOCH                                 |
//+------------------------------------------------------------------+
void BuildZones(bool isBullish)
{
   g_zoneType = ZONE_NONE;
   g_zoneHigh = 0;
   g_zoneLow = 0;
   
   // Try to find FVG first
   if(FindFVG(isBullish))
   {
      g_zoneType = ZONE_FVG;
      Print("FVG zone found: ", g_zoneLow, " - ", g_zoneHigh);
   }
   // If no FVG, find OB
   else if(FindOB(isBullish))
   {
      g_zoneType = ZONE_OB;
      Print("OB zone found: ", g_zoneLow, " - ", g_zoneHigh);
   }
   else
   {
      LogSetup("WAIT_RETRACE", "nozone", g_bias, true, true, ZONE_NONE, 0, 0, 0);
      ResetSetup();
   }
   
   // Draw zone
   if(g_zoneType != ZONE_NONE && InpShowZones)
   {
      DrawZone();
   }
}

//+------------------------------------------------------------------+
//| Find Fair Value Gap                                                |
//+------------------------------------------------------------------+
bool FindFVG(bool isBullish)
{
   // Look for FVG in recent bars after CHOCH
   for(int i = 1; i <= 10; i++)
   {
      double high1 = iHigh(tradeSym, InpEntryTF, i);
      double low1 = iLow(tradeSym, InpEntryTF, i);
      double high3 = iHigh(tradeSym, InpEntryTF, i + 2);
      double low3 = iLow(tradeSym, InpEntryTF, i + 2);
      
      if(isBullish)
      {
         // Bullish FVG: Low(c1) > High(c3)
         if(low1 > high3)
         {
            g_zoneHigh = low1;
            g_zoneLow = high3;
            g_zoneBar = i;
            return true;
         }
      }
      else
      {
         // Bearish FVG: High(c1) < Low(c3)
         if(high1 < low3)
         {
            g_zoneHigh = low3;
            g_zoneLow = high1;
            g_zoneBar = i;
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Find Order Block                                                   |
//+------------------------------------------------------------------+
bool FindOB(bool isBullish)
{
   // Look for OB - last opposite candle before impulse
   for(int i = 1; i <= 15; i++)
   {
      double open_i = iOpen(tradeSym, InpEntryTF, i);
      double close_i = iClose(tradeSym, InpEntryTF, i);
      double high_i = iHigh(tradeSym, InpEntryTF, i);
      double low_i = iLow(tradeSym, InpEntryTF, i);
      
      if(isBullish)
      {
         // Bullish OB = bearish candle before impulse up
         if(close_i < open_i)
         {
            // Check if next candle is bullish impulse
            double close_next = iClose(tradeSym, InpEntryTF, i - 1);
            double open_next = iOpen(tradeSym, InpEntryTF, i - 1);
            
            if(close_next > open_next && close_next > high_i)
            {
               g_zoneHigh = open_i;
               g_zoneLow = low_i;
               g_zoneBar = i;
               return true;
            }
         }
      }
      else
      {
         // Bearish OB = bullish candle before impulse down
         if(close_i > open_i)
         {
            double close_next = iClose(tradeSym, InpEntryTF, i - 1);
            double open_next = iOpen(tradeSym, InpEntryTF, i - 1);
            
            if(close_next < open_next && close_next < low_i)
            {
               g_zoneHigh = high_i;
               g_zoneLow = open_i;
               g_zoneBar = i;
               return true;
            }
         }
      }
   }
   
   return false;
}

//=== ENTRY LOGIC ===
//+------------------------------------------------------------------+
//| Look for price to retrace into zone                                |
//+------------------------------------------------------------------+
void LookForRetrace()
{
   // Check timeout using mode-based parameter
   int entryTimeout = GetEntryTimeoutBars();
   g_zoneBar++;
   if(g_zoneBar > entryTimeout)
   {
      LogSetup("WAIT_RETRACE", "timeout", g_bias, true, true, g_zoneType, g_zoneLow, g_zoneHigh, 0);
      RecordCancel(CANCEL_RETRACE_TIMEOUT);
      ResetSetup();
      return;
   }
   
   double bid = SymbolInfoDouble(tradeSym, SYMBOL_BID);
   double ask = SymbolInfoDouble(tradeSym, SYMBOL_ASK);
   
   // Get retrace ratio based on mode
   double retraceRatio = GetRetraceRatio();
   
   // Check if price is in zone
   bool inZone = false;
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      // For long: price should retrace down into zone
      if(bid <= g_zoneHigh && bid >= g_zoneLow)
      {
         inZone = true;
      }
      // RELAX/RELAX2 mode: also allow retrace based on ratio
      else if(g_tradeMode != MODE_STRICT && g_chochLevel > 0 && g_sweepLevel > 0)
      {
         double displacement = g_chochLevel - g_sweepLevel;
         double retraceLevel = g_chochLevel - (displacement * retraceRatio);
         if(bid <= retraceLevel && bid > g_sweepLevel)
         {
            inZone = true;
            Print(EnumToString(g_tradeMode), ": ", (int)(retraceRatio*100), "%% retrace entry at ", bid);
         }
      }
      
      if(inZone)
      {
         g_state = STATE_PLACE_ORDER;
         Print("Price retraced into zone for LONG entry [", EnumToString(g_tradeMode), "]");
      }
   }
   else if(g_sweepType == SWEEP_BEARISH)
   {
      // For short: price should retrace up into zone
      if(ask >= g_zoneLow && ask <= g_zoneHigh)
      {
         inZone = true;
      }
      // RELAX/RELAX2 mode: also allow retrace based on ratio
      else if(g_tradeMode != MODE_STRICT && g_chochLevel > 0 && g_sweepLevel > 0)
      {
         double displacement = g_sweepLevel - g_chochLevel;
         double retraceLevel = g_chochLevel + (displacement * retraceRatio);
         if(ask >= retraceLevel && ask < g_sweepLevel)
         {
            inZone = true;
            Print(EnumToString(g_tradeMode), ": ", (int)(retraceRatio*100), "%% retrace entry at ", ask);
         }
      }
      
      if(inZone)
      {
         g_state = STATE_PLACE_ORDER;
         Print("Price retraced into zone for SHORT entry [", EnumToString(g_tradeMode), "]");
      }
   }
   
   if(!inZone)
   {
      RecordCancel(CANCEL_NO_RETRACE);
   }
}

//+------------------------------------------------------------------+
//| Place order                                                        |
//+------------------------------------------------------------------+
void PlaceOrder()
{
   // Declare variables at the beginning of function
   ENUM_ORDER_TYPE orderType;
   double price = 0, sl = 0, tp = 0;
   
   // Final risk check
   if(!PassRiskChecks())
   {
      ResetSetup();
      return;
   }
   
   // Calculate SL/TP
   CalculateSLTP();
   
   // === SAME SETUP ONLY CHECK (BEFORE lot calculation) ===
   // Check if martingale should continue based on setup signature
   if(g_martLevel > 0 && InpMartSameSetupOnly)
   {
      if(!CheckSameSetup())
      {
         PrintFormat("SAME_SETUP: Setup changed or timeout - martLevel was reset to 0");
         // martLevel was reset in CheckSameSetup(), recalculate lot
      }
   }
   
   // Store current setup signature (for next loss comparison)
   g_lastSetupSignature = GetSetupSignature();
   
   // === CAPTURE martLevelUsed BEFORE lot calculation ===
   // This ensures comment and lot use the SAME level
   int martLevelUsed = g_martLevel;
   
   // Get current lot based on martingale (uses g_martLevel)
   g_currentLot = CalculateLot();
   double finalLotUsed = g_currentLot;
   
   // === DEBUG: Show recovery status ===
   bool inRecovery = (g_recoveryLoss > 0);
   PrintFormat("MART_STATUS: level=%d recLoss=%.2f inRecovery=%d base=%.2f mult=%.2f expectedLot=%.2f",
               g_martLevel, g_recoveryLoss, inRecovery, InpBaseLot, InpMartMultiplier,
               InpBaseLot * MathPow(InpMartMultiplier, g_martLevel));
   
   PrintFormat("ENTRY_PREP: martLevelUsed=%d finalLotUsed=%.2f signature=%s recLoss=%.2f",
               martLevelUsed, finalLotUsed, g_lastSetupSignature, g_recoveryLoss);
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      orderType = ORDER_TYPE_BUY;
      price = SymbolInfoDouble(tradeSym, SYMBOL_ASK);
      sl = g_slPrice;
      // === STRATEGY CHANGE B: Use TP2 instead of TP1 ===
      tp = InpUseBrokerTP ? g_tp2Price : 0;  // TP2 or no TP if disabled
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = SymbolInfoDouble(tradeSym, SYMBOL_BID);
      sl = g_slPrice;
      // === STRATEGY CHANGE B: Use TP2 instead of TP1 ===
      tp = InpUseBrokerTP ? g_tp2Price : 0;  // TP2 or no TP if disabled
   }
   
   // Normalize prices
   price = NormalizeDouble(price, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   // === RECOVERY TP ===
   // Calculate Recovery TP if martLevel > 0
   double recoveryTP = CalculateRecoveryTP(price, g_currentLot, g_sweepType == SWEEP_BULLISH);
   double originalTP = tp;
   int recoveryTPPoints = 0;
   
   if(recoveryTP > 0)
   {
      // Use Recovery TP instead of normal TP
      tp = recoveryTP;
      recoveryTPPoints = (int)MathAbs((tp - price) / _Point);
      PrintFormat("REC_TP: Using Recovery TP=%.5f instead of normal TP=%.5f (recLoss=%.2f)",
                  tp, originalTP, g_recoveryLoss);
   }
   
   // Comment format: SMC_LONG_L0_MA_R{tpPoints} (MA=AllModes, R=Recovery TP points)
   // MUST use martLevelUsed (captured before lot calc) to ensure comment matches lot
   string strictOnlyStr = InpMartingaleStrictOnly ? "S" : "A";
   string dirStr = (g_sweepType == SWEEP_BULLISH) ? "LONG" : "SHORT";
   string comment;
   if(recoveryTP > 0)
   {
      comment = StringFormat("SMC_%s_L%d_M%s_R%d", 
                             dirStr,
                             martLevelUsed,  // Use captured level, not g_martLevel
                             strictOnlyStr,
                             recoveryTPPoints);
   }
   else
   {
      comment = StringFormat("SMC_%s_L%d_M%s", 
                             dirStr,
                             martLevelUsed,  // Use captured level, not g_martLevel
                             strictOnlyStr);
   }
   
   // === DETAILED ENTRY LOG (Strategy Change B) ===
   double slPts = MathAbs(price - sl) / _Point;
   double tp1Pts = MathAbs(g_tp1Price - price) / _Point;
   double tp2Pts = MathAbs(g_tp2Price - price) / _Point;
   double spreadPts = GetSpreadPoints();
   string setupType = (g_sweepType == SWEEP_BULLISH) ? "LONG" : "SHORT";
   bool isRecovery = (g_recoveryLoss > 0 || g_martLevel > 0);
   
   // Check if TP1 is too close - disable partial close for this position
   g_tp1PartialDisabled = (tp1Pts < InpMinTP1Points);
   if(g_tp1PartialDisabled)
   {
      PrintFormat("[ENTRY] TP1 too close (%.0f < %d pts) - partial close DISABLED for this position",
                  tp1Pts, InpMinTP1Points);
      g_tp1PartialSkippedCount++;
   }
   
   PrintFormat("[ENTRY] %s entry=%.5f sl=%.5f tp1=%.5f tp2=%.5f slPts=%.0f tp1Pts=%.0f tp2Pts=%.0f spreadPts=%.1f mode=%s isRecovery=%s tp1Disabled=%s",
               setupType, price, sl, g_tp1Price, g_tp2Price, slPts, tp1Pts, tp2Pts, spreadPts, 
               EnumToString(g_tradeMode), isRecovery ? "Y" : "N", g_tp1PartialDisabled ? "Y" : "N");
   PrintFormat("ENTRY: levelUsed=%d lot=%.2f recLoss=%.2f tpPts=%d signature=%s comment=%s",
               martLevelUsed, finalLotUsed, g_recoveryLoss, recoveryTPPoints, g_lastSetupSignature, comment);
   
   if(trade.PositionOpen(tradeSym, orderType, finalLotUsed, price, sl, tp, comment))
   {
      g_currentTicket = trade.ResultOrder();
      g_entryPrice = price;
      g_partialClosed = false;
      g_tradesToday++;
      g_lastTradeTime = TimeCurrent();  // Update last trade time for cooldown
      g_state = STATE_MANAGE_TRADE;
      
      // Store entry level for this position (for close verification)
      g_entryMartLevel = martLevelUsed;
      
      // Initialize position tracking for partial close support
      g_positionData.volumeIn = finalLotUsed;
      g_positionData.volumeOut = 0;
      g_positionData.profitAccum = 0;
      g_positionData.isActive = true;
      // positionId will be set when first DEAL_ENTRY_OUT arrives
      
      // Detailed martingale entry log
      PrintFormat("MART_ENTRY: dir=%s levelUsed=%d base=%.2f mult=%.2f final=%.2f comment=%s",
                  dirStr, martLevelUsed, InpBaseLot, MathPow(InpMartMultiplier, martLevelUsed), finalLotUsed, comment);
      
      // Reset TP1 tracking for new position
      g_tp1Done = false;
      g_tp1PositionId = g_currentTicket;
      
      // Store initial risk for trailing stop calculation
      g_initialRiskPoints = (int)MathRound(MathAbs(price - sl) / _Point);
      g_lastTrailModifyTime = 0;  // Reset trailing cooldown for new position
      PrintFormat("TRAIL_INIT: entryPrice=%.5f sl=%.5f initialRiskPts=%d", price, sl, g_initialRiskPoints);
      
      Print("Order placed: ", EnumToString(orderType), " Lot: ", g_currentLot, 
            " Entry: ", price, " SL: ", sl, " TP(TP2): ", tp, " TP1: ", g_tp1Price, " Mode: ", EnumToString(g_tradeMode));
      
      // Log setup success
      double distToTP1 = MathAbs(tp - price) / _Point;
      LogSetup("PLACE_ORDER", "success", g_bias, true, true, g_zoneType, 
               g_zoneLow, g_zoneHigh, distToTP1);
   }
   else
   {
      Print("Order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      LogSetup("PLACE_ORDER", "order_failed", g_bias, true, true, g_zoneType, 
               g_zoneLow, g_zoneHigh, 0);
      ResetSetup();
   }
}

//+------------------------------------------------------------------+
//| Calculate SL and TP levels                                         |
//+------------------------------------------------------------------+
void CalculateSLTP()
{
   double spreadPoints = GetSpreadPoints();
   double atr = GetATR(14);
   double currentPrice = SymbolInfoDouble(tradeSym, (g_sweepType == SWEEP_BULLISH) ? SYMBOL_ASK : SYMBOL_BID);
   
   // SL buffer calculation
   double slBuffer = MathMax(InpSLBufferPoints * _Point,
                     MathMax(2 * spreadPoints * _Point,
                             0.25 * atr));
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      // Long: SL below sweep low
      double sweepLow = GetSweepExtreme(false);
      g_slPrice = sweepLow - slBuffer;
      
      // TP1: nearest opposite liquidity
      g_tp1Price = GetNearestOppositeLiquidity(true);
      
      // TP2: further liquidity (with fallback)
      g_tp2Price = GetFurtherLiquidity(true);
      
      // === TP2 FALLBACK ===
      // If TP2 not found or too close, use InpMinTP2Points as fallback
      double tp2Distance = (g_tp2Price - currentPrice) / _Point;
      double tp1Distance = (g_tp1Price - currentPrice) / _Point;
      
      if(g_tp2Price <= g_tp1Price || tp2Distance < InpMinTP2Points)
      {
         // Fallback: entry + InpMinTP2Points
         g_tp2Price = currentPrice + InpMinTP2Points * _Point;
      }
      
      // Clamp TP2 to InpMaxTPPoints
      double maxTP2 = currentPrice + InpMaxTPPoints * _Point;
      if(g_tp2Price > maxTP2)
         g_tp2Price = maxTP2;
   }
   else
   {
      // Short: SL above sweep high
      double sweepHigh = GetSweepExtreme(true);
      g_slPrice = sweepHigh + slBuffer;
      
      // TP1: nearest opposite liquidity
      g_tp1Price = GetNearestOppositeLiquidity(false);
      
      // TP2: further liquidity (with fallback)
      g_tp2Price = GetFurtherLiquidity(false);
      
      // === TP2 FALLBACK ===
      // If TP2 not found or too close, use InpMinTP2Points as fallback
      double tp2Distance = (currentPrice - g_tp2Price) / _Point;
      double tp1Distance = (currentPrice - g_tp1Price) / _Point;
      
      if(g_tp2Price >= g_tp1Price || tp2Distance < InpMinTP2Points)
      {
         // Fallback: entry - InpMinTP2Points
         g_tp2Price = currentPrice - InpMinTP2Points * _Point;
      }
      
      // Clamp TP2 to InpMaxTPPoints
      double minTP2 = currentPrice - InpMaxTPPoints * _Point;
      if(g_tp2Price < minTP2)
         g_tp2Price = minTP2;
   }
   
   // Normalize prices
   g_slPrice = NormalizeDouble(g_slPrice, _Digits);
   g_tp1Price = NormalizeDouble(g_tp1Price, _Digits);
   g_tp2Price = NormalizeDouble(g_tp2Price, _Digits);
}

//+------------------------------------------------------------------+
//| Get sweep extreme price                                            |
//+------------------------------------------------------------------+
double GetSweepExtreme(bool isHigh)
{
   double extreme = isHigh ? 0 : DBL_MAX;
   
   for(int i = 0; i <= InpReclaimMaxBars + 2; i++)
   {
      if(isHigh)
      {
         double h = iHigh(tradeSym, InpEntryTF, i);
         if(h > extreme) extreme = h;
      }
      else
      {
         double l = iLow(tradeSym, InpEntryTF, i);
         if(l < extreme) extreme = l;
      }
   }
   
   return extreme;
}

//+------------------------------------------------------------------+
//| Get nearest opposite liquidity for TP1                             |
//+------------------------------------------------------------------+
double GetNearestOppositeLiquidity(bool isLong)
{
   double currentPrice = SymbolInfoDouble(tradeSym, isLong ? SYMBOL_ASK : SYMBOL_BID);
   double nearest = isLong ? DBL_MAX : 0;
   
   if(isLong)
   {
      // Look for resistance levels above
      if(g_pdh > currentPrice && g_pdh < nearest) nearest = g_pdh;
      if(g_sessionHigh > currentPrice && g_sessionHigh < nearest) nearest = g_sessionHigh;
      
      for(int i = 0; i < ArraySize(g_eqh); i++)
      {
         if(g_eqh[i] > currentPrice && g_eqh[i] < nearest) nearest = g_eqh[i];
      }
      
      for(int i = 0; i < ArraySize(g_m5SwingHighs); i++)
      {
         if(g_m5SwingHighs[i] > currentPrice && g_m5SwingHighs[i] < nearest) 
            nearest = g_m5SwingHighs[i];
      }
      
      if(nearest == DBL_MAX)
         nearest = currentPrice + 100 * _Point; // Default 100 points
   }
   else
   {
      // Look for support levels below
      if(g_pdl < currentPrice && g_pdl > nearest) nearest = g_pdl;
      if(g_sessionLow < currentPrice && g_sessionLow > nearest) nearest = g_sessionLow;
      
      for(int i = 0; i < ArraySize(g_eql); i++)
      {
         if(g_eql[i] < currentPrice && g_eql[i] > nearest) nearest = g_eql[i];
      }
      
      for(int i = 0; i < ArraySize(g_m5SwingLows); i++)
      {
         if(g_m5SwingLows[i] < currentPrice && g_m5SwingLows[i] > nearest) 
            nearest = g_m5SwingLows[i];
      }
      
      if(nearest == 0)
         nearest = currentPrice - 100 * _Point;
   }
   
   return nearest;
}

//+------------------------------------------------------------------+
//| Get further liquidity for TP2                                      |
//+------------------------------------------------------------------+
double GetFurtherLiquidity(bool isLong)
{
   double tp1 = g_tp1Price;
   double further = isLong ? DBL_MAX : 0;
   
   if(isLong)
   {
      if(g_pdh > tp1 && g_pdh < further) further = g_pdh;
      if(g_sessionHigh > tp1 && g_sessionHigh < further) further = g_sessionHigh;
      
      if(further == DBL_MAX)
         further = tp1 + 50 * _Point;
   }
   else
   {
      if(g_pdl < tp1 && g_pdl > further) further = g_pdl;
      if(g_sessionLow < tp1 && g_sessionLow > further) further = g_sessionLow;
      
      if(further == 0)
         further = tp1 - 50 * _Point;
   }
   
   return further;
}

//=== TRADE MANAGEMENT ===
//+------------------------------------------------------------------+
//| Normalize volume to broker constraints                             |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double minVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_STEP);
   
   // Round to volume step
   volume = MathFloor(volume / stepVol) * stepVol;
   
   // Clamp to min/max
   if(volume < minVol) volume = minVol;
   if(volume > maxVol) volume = maxVol;
   
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Normalize volume to step (floor only, no min clamp)                 |
//| For partial close: returns 0 if result < minVol (caller decides)    |
//+------------------------------------------------------------------+
double NormalizeVolumeToStep(double volume)
{
   double minVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_STEP);
   
   // Floor to volume step (never round up to avoid closing more than intended)
   volume = MathFloor(volume / stepVol) * stepVol;
   
   // If result is less than minVol, return 0 (caller should skip partial close)
   if(volume < minVol)
      return 0;
   
   // Clamp to max only
   if(volume > maxVol)
      volume = maxVol;
   
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Check if price modification respects broker constraints            |
//+------------------------------------------------------------------+
bool CanModifyStopLevel(double price, double newSL, long posType)
{
   double stopsLevel = SymbolInfoInteger(tradeSym, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLevel = SymbolInfoInteger(tradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(tradeSym, SYMBOL_BID) :
                         SymbolInfoDouble(tradeSym, SYMBOL_ASK);
   
   // Check stops level
   if(stopsLevel > 0)
   {
      double distanceToSL = MathAbs(currentPrice - newSL);
      if(distanceToSL < stopsLevel)
         return false;
   }
   
   // Check freeze level
   if(freezeLevel > 0)
   {
      double distanceToSL = MathAbs(currentPrice - newSL);
      if(distanceToSL < freezeLevel)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Manage open trade                                                  |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!PositionSelect(tradeSym))
   {
      // Position closed
      CheckTradeResult();
      g_state = STATE_COOLDOWN;
      g_cooldownCounter = 0;
      return;
   }
   
   double posProfit = PositionGetDouble(POSITION_PROFIT);
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   double posVolume = PositionGetDouble(POSITION_VOLUME);
   long posType = PositionGetInteger(POSITION_TYPE);
   ulong posTicket = PositionGetInteger(POSITION_TICKET);
   
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(tradeSym, SYMBOL_BID) :
                         SymbolInfoDouble(tradeSym, SYMBOL_ASK);
   
   double riskPoints = MathAbs(posOpenPrice - posSL);
   double profitPoints = (posType == POSITION_TYPE_BUY) ?
                         (currentPrice - posOpenPrice) :
                         (posOpenPrice - currentPrice);
   
   // === SKIP PARTIAL CLOSE DURING RECOVERY ===
   bool inRecoveryMode = (InpUseRecoveryTP && (g_martLevel > 0 || g_recoveryLoss > 0));
   
   if(InpDisablePartialOnRecovery && inRecoveryMode)
   {
      // Skip partial close, BE move, and trailing during recovery
      // Only SL and Recovery TP will close the position
      // Log once per position
      static ulong lastLoggedPosId = 0;
      if(lastLoggedPosId != g_positionData.positionId)
      {
         PrintFormat("RECOVERY_GUARD: Partial close/BE disabled - martLevel=%d recLoss=%.2f",
                     g_martLevel, g_recoveryLoss);
         lastLoggedPosId = g_positionData.positionId;
      }
      return;  // Skip all management during recovery
   }
   
   // === STRATEGY CHANGE B: TP1 PARTIAL CLOSE ===
   // Check if TP1 action should be triggered
   // Skip if TP1 partial was disabled at entry (TP1 too close)
   if(InpUseTP1PartialClose && !g_tp1Done && !g_tp1PartialDisabled)
   {
      // Check if this is the same position we're tracking
      if(g_tp1PositionId != posTicket)
      {
         // New position, reset tracking
         g_tp1Done = false;
         g_tp1PositionId = posTicket;
      }
      
      // Check if price reached TP1 (with buffer)
      bool atTP1 = false;
      double tp1Buffer = InpTP1TriggerBufferPoints * _Point;
      
      if(posType == POSITION_TYPE_BUY)
         atTP1 = currentPrice >= (g_tp1Price - tp1Buffer);
      else
         atTP1 = currentPrice <= (g_tp1Price + tp1Buffer);
      
      if(atTP1)
      {
         // Calculate partial close volume using NormalizeVolumeToStep
         double closeVolume = NormalizeVolumeToStep(posVolume * InpTP1CloseFraction);
         double minVol = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MIN);
         double minStep = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_STEP);
         
         // Check if volume is valid
         bool volumeValid = (closeVolume >= InpMinPartialLots && closeVolume >= minVol);
         bool canPartialClose = volumeValid && (closeVolume < posVolume);  // Must leave some volume
         
         // Special case: if posVolume == minVol, skip partial (can't split further)
         if(posVolume <= minVol)
         {
            g_tp1Done = true;
            PrintFormat("[TP1] Partial close SKIPPED: posVolume=%.2f == minVol=%.2f (cannot split)",
                        posVolume, minVol);
         }
         else if(canPartialClose)
         {
            // Execute partial close
            if(trade.PositionClosePartial(tradeSym, closeVolume))
            {
               g_tp1Done = true;
               g_tp1PartialTriggeredCount++;
               g_partialClosed = true;  // Legacy flag
               
               double remainingVol = posVolume - closeVolume;
               PrintFormat("[TP1] price=%.5f closeVol=%.2f remainingVol=%.2f reason=tp1_partial", 
                           currentPrice, closeVolume, remainingVol);
               
               // === MOVE SL ===
               if(InpMoveSLToBEOnTP1)
               {
                  double newSL;
                  double spreadPts = GetSpreadPoints();
                  
                  // Calculate new SL based on LockR or BE offset
                  if(InpMoveSLToLockR > 0)
                  {
                     // LockR mode: entry +/- (LockR * riskPoints)
                     double lockOffset = InpMoveSLToLockR * riskPoints;
                     if(posType == POSITION_TYPE_BUY)
                        newSL = posOpenPrice + lockOffset;
                     else
                        newSL = posOpenPrice - lockOffset;
                  }
                  else
                  {
                     // BE mode: entry +/- (spreadPoints + BEOffsetPoints)
                     double beOffset = (spreadPts + InpBEOffsetPoints) * _Point;
                     if(posType == POSITION_TYPE_BUY)
                        newSL = posOpenPrice + beOffset;
                     else
                        newSL = posOpenPrice - beOffset;
                  }
                  
                  newSL = NormalizeDouble(newSL, _Digits);
                  
                  // Check broker constraints
                  if(CanModifyStopLevel(posOpenPrice, newSL, posType))
                  {
                     // Keep TP at TP2 (do NOT change)
                     if(trade.PositionModify(tradeSym, newSL, posTP))
                     {
                        g_beMovedCount++;
                        if(InpMoveSLToLockR > 0)
                           PrintFormat("[TP1] SL moved to LockR: newSL=%.5f (%.2fR) newTP=%.5f",
                                       newSL, InpMoveSLToLockR, posTP);
                        else
                           PrintFormat("[TP1] SL moved to BE: newSL=%.5f (spread+%d pts) newTP=%.5f",
                                       newSL, InpBEOffsetPoints, posTP);
                     }
                     else
                     {
                        PrintFormat("[TP1] SL move FAILED: error=%d", GetLastError());
                     }
                  }
                  else
                  {
                     PrintFormat("[TP1] SL move SKIPPED: stops_level constraint");
                  }
               }
            }
            else
            {
               g_tp1PartialFailedCount++;
               g_lastTP1FailReason = "trade_error_" + IntegerToString(GetLastError());
               PrintFormat("[TP1] Partial close FAILED: error=%d", GetLastError());
            }
         }
         else if(!volumeValid)
         {
            // Volume too small - mark as done but don't close
            g_tp1Done = true;
            g_tp1PartialFailedCount++;
            g_lastTP1FailReason = "invalid_volume";
            PrintFormat("[TP1] Partial close SKIPPED: closeVol=%.2f < minPartial=%.2f or minVol=%.2f",
                        closeVolume, InpMinPartialLots, minVol);
            
            // Still move SL to BE if enabled
            if(InpMoveSLToBEOnTP1)
            {
               double newSL;
               double spreadPts = GetSpreadPoints();
               
               if(InpMoveSLToLockR > 0)
               {
                  double lockOffset = InpMoveSLToLockR * riskPoints;
                  if(posType == POSITION_TYPE_BUY)
                     newSL = posOpenPrice + lockOffset;
                  else
                     newSL = posOpenPrice - lockOffset;
               }
               else
               {
                  double beOffset = (spreadPts + InpBEOffsetPoints) * _Point;
                  if(posType == POSITION_TYPE_BUY)
                     newSL = posOpenPrice + beOffset;
                  else
                     newSL = posOpenPrice - beOffset;
               }
               
               newSL = NormalizeDouble(newSL, _Digits);
               
               if(CanModifyStopLevel(posOpenPrice, newSL, posType))
               {
                  if(trade.PositionModify(tradeSym, newSL, posTP))
                  {
                     g_beMovedCount++;
                     PrintFormat("[TP1] SL moved (no partial): newSL=%.5f", newSL);
                  }
               }
            }
         }
      }
   }
   
   // === LEGACY PARTIAL CLOSE (at 1R if TP1 not used) ===
   // Only trigger if TP1 partial close is disabled
   if(!InpUseTP1PartialClose && !g_partialClosed)
   {
      bool at1R = profitPoints >= riskPoints;
      
      if(at1R)
      {
         // Partial close at 1R
         double closeVolume = NormalizeVolume(posVolume * InpPartialClosePercent / 100.0);
         if(closeVolume >= 0.01)
         {
            if(trade.PositionClosePartial(tradeSym, closeVolume))
            {
               g_partialClosed = true;
               
               // Move SL to BE + spread
               double spreadPoints = GetSpreadPoints();
               double newSL;
               
               if(posType == POSITION_TYPE_BUY)
                  newSL = posOpenPrice + spreadPoints * _Point;
               else
                  newSL = posOpenPrice - spreadPoints * _Point;
               
               trade.PositionModify(tradeSym, newSL, posTP);
               
               Print("Legacy partial close done. New SL: ", newSL);
            }
         }
      }
   }
   
   // === TRAILING STOP ===
   // Apply trailing stop after TP1 partial close (if enabled)
   ApplyTrailingStop();
}

//+------------------------------------------------------------------+
//| Apply trailing stop to open position                                |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   // Check if trailing is enabled
   if(!InpUseTrailing)
      return;
   
   // Check if position exists
   if(!PositionSelect(tradeSym))
      return;
   
   // Get position info
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   long posType = PositionGetInteger(POSITION_TYPE);
   long posMagic = PositionGetInteger(POSITION_MAGIC);
   
   // Check magic number
   if(posMagic != InpMagic)
      return;
   
   g_trailAttemptedCount++;
   
   // Check trailing start condition based on mode
   if(InpTrailStartMode == TRAIL_AFTER_TP1)
   {
      // Only trail after TP1 partial close
      if(!g_tp1Done)
      {
         g_trailSkippedNotAfterPartial++;
         LogTrailSkip("not_after_partial");
         return;
      }
   }
   else  // TRAIL_AFTER_R
   {
      // Calculate profit in R using INITIAL risk (not current SL)
      if(g_initialRiskPoints <= 0)
      {
         // Fallback: use current SL if initial risk not set
         g_initialRiskPoints = (int)MathRound(MathAbs(g_entryPrice - posSL) / _Point);
         if(g_initialRiskPoints <= 0)
            return;
      }
      
      double currentBidR = SymbolInfoDouble(tradeSym, SYMBOL_BID);
      double profitPointsR = (posType == POSITION_TYPE_BUY) ?
                            (currentBidR - g_entryPrice) / _Point :
                            (g_entryPrice - SymbolInfoDouble(tradeSym, SYMBOL_ASK)) / _Point;
      double profitR = profitPointsR / g_initialRiskPoints;
      
      if(profitR < InpTrailStartR)
      {
         g_trailSkippedNotReachedR++;
         LogTrailSkip("not_reached_R");
         return;
      }
   }
   
   // Check new bar only mode
   if(InpTrailUpdateOnNewBarOnly)
   {
      datetime currentBarTime = iTime(tradeSym, InpEntryTF, 0);
      if(currentBarTime == g_lastTrailBarTime)
      {
         g_trailSkippedNewBar++;
         LogTrailSkip("not_new_bar");
         return;
      }
   }
   
   // Check cooldown
   if(TimeCurrent() - g_lastTrailModifyTime < InpTrailCooldownSec)
   {
      g_trailSkippedCooldown++;
      LogTrailSkip("cooldown");
      return;
   }
   
   // Get current prices
   double currentBid = SymbolInfoDouble(tradeSym, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(tradeSym, SYMBOL_ASK);
   double spreadPts = GetSpreadPoints();
   
   // Calculate trailing distance using ATR
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrHandle = iATR(tradeSym, InpEntryTF, InpTrailATRPeriod);
   double distPts = InpTrailMinPoints;  // Default
   
   if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
   {
      distPts = MathMax(InpTrailMinPoints, (atrBuffer[0] / _Point) * InpTrailATRMult);
   }
   
   // Calculate candidate SL
   double candidateSL;
   double minLockSL;
   
   if(posType == POSITION_TYPE_BUY)
   {
      candidateSL = currentBid - distPts * _Point;
      // Enforce minimum lock-in above BE after TP1
      minLockSL = g_entryPrice + (spreadPts + InpTrailLockMinAfterTP1Points) * _Point;
      candidateSL = MathMax(candidateSL, minLockSL);
   }
   else  // SELL
   {
      candidateSL = currentAsk + distPts * _Point;
      // Enforce maximum lock-in below BE after TP1
      minLockSL = g_entryPrice - (spreadPts + InpTrailLockMinAfterTP1Points) * _Point;
      candidateSL = MathMin(candidateSL, minLockSL);
   }
   
   candidateSL = NormalizeDouble(candidateSL, _Digits);
   
   // Check if improvement is significant (step check) - TIGHTEN ONLY
   bool significantImprovement = false;
   if(posType == POSITION_TYPE_BUY)
      significantImprovement = (candidateSL > posSL + InpTrailStepPoints * _Point);
   else
      significantImprovement = (candidateSL < posSL - InpTrailStepPoints * _Point);
   
   if(!significantImprovement)
   {
      g_trailSkippedStep++;
      LogTrailSkip("step");
      return;
   }
   
   // Check broker constraints (SYMBOL_TRADE_STOPS_LEVEL + SYMBOL_TRADE_FREEZE_LEVEL)
   double currentPrice = (posType == POSITION_TYPE_BUY) ? currentBid : currentAsk;
   int stopsLevel = (int)SymbolInfoInteger(tradeSym, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(tradeSym, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance = MathMax(stopsLevel, freezeLevel) * _Point;
   double slDistance = MathAbs(currentPrice - candidateSL);
   
   if(slDistance < minDistance)
   {
      g_trailRejectCount++;
      PrintFormat("[TRAIL_REJECT] reason=stops_freeze slDist=%.0f minDist=%.0f stopsLevel=%d freezeLevel=%d",
                  slDistance/_Point, minDistance/_Point, stopsLevel, freezeLevel);
      return;
   }
   
   // Modify position
   if(trade.PositionModify(tradeSym, candidateSL, posTP))
   {
      g_trailMovedCount++;
      g_lastTrailModifyTime = TimeCurrent();
      g_lastTrailBarTime = iTime(tradeSym, InpEntryTF, 0);  // Update bar time
      
      string typeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double profitPts = (posType == POSITION_TYPE_BUY) ?
                         (currentBid - g_entryPrice) / _Point :
                         (g_entryPrice - currentAsk) / _Point;
      PrintFormat("[TRAIL] type=%s profitPts=%.0f distPts=%.0f oldSL=%.5f newSL=%.5f reason=trail",
                  typeStr, profitPts, distPts, posSL, candidateSL);
   }
   else
   {
      g_trailFailedCount++;
      PrintFormat("[TRAIL_FAIL] err=%d oldSL=%.5f newSL=%.5f", GetLastError(), posSL, candidateSL);
   }
}

//+------------------------------------------------------------------+
//| Log trailing skip reason (throttled)                               |
//+------------------------------------------------------------------+
void LogTrailSkip(string reason)
{
   // Throttle: only log same reason once per 60 seconds
   if(reason == g_lastTrailSkipReason && TimeCurrent() - g_lastTrailSkipLogTime < 60)
      return;
   
   g_lastTrailSkipReason = reason;
   g_lastTrailSkipLogTime = TimeCurrent();
   
   PrintFormat("[TRAIL_SKIP] reason=%s", reason);
}

//+------------------------------------------------------------------+
//| Check trade result after close                                     |
//+------------------------------------------------------------------+
void CheckTradeResult()
{
   // NOTE: Martingale level is now updated in UpdateMartingaleFromDeal() via OnTradeTransaction
   // This function only handles logging and daily PnL tracking
   
   // Get last deal result
   HistorySelect(TimeCurrent() - 86400, TimeCurrent());
   
   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;
   
   ulong dealTicket = HistoryDealGetTicket(totalDeals - 1);
   if(dealTicket == 0) return;
   
   double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double totalPnL = dealProfit + dealCommission + dealSwap;
   
   g_dailyPnL += totalPnL;
   
   string result;
   if(totalPnL > 0)
   {
      result = "win";
   }
   else if(totalPnL < 0)
   {
      result = "lose";
   }
   else
   {
      result = "breakeven";
   }
   
   // Log trade
   LogTrade(result, totalPnL);
   
   Print("Trade closed: ", result, " PnL: ", totalPnL, " Consec losses: ", g_consecLosses, " MartLevel: ", g_martLevel);
}

//=== RISK MANAGEMENT ===
//+------------------------------------------------------------------+
//| Check all risk conditions                                          |
//+------------------------------------------------------------------+
bool PassRiskChecks()
{
   int currentHHMM = GetCurrentHHMM();
   
   // Check SL blocked first (highest priority)
   if(g_blockedToday && InpStopTradingOnSLHits)
   {
      RecordCancel(CANCEL_SL_BLOCKED);
      return false;
   }
   
   // Check hard block (after InpHardBlockAfterHHMM)
   if(IsHardBlockTime())
   {
      RecordCancel(CANCEL_HARD_BLOCK);
      return false;
   }
   
   // Check no-trade zone (rollover quarantine)
   if(InpBlockAllModesInNoTrade && IsInNoTradeZone())
   {
      RecordCancel(CANCEL_NO_TRADE_ZONE);
      return false;
   }
   
   // Time filter with RELAX mode support
   if(!CheckTradingTime())
   {
      RecordCancel(CANCEL_TIMEFILTER);
      return false;
   }
   
   // Cooldown between trades
   if(g_lastTradeTime > 0 && InpMinMinutesBetweenTrades > 0)
   {
      int minutesSinceLastTrade = (int)((TimeCurrent() - g_lastTradeTime) / 60);
      if(minutesSinceLastTrade < InpMinMinutesBetweenTrades)
      {
         RecordCancel(CANCEL_COOLDOWN);
         return false;
      }
   }
   
   // Update spread history for spike detection
   double spreadPoints = GetSpreadPoints();
   UpdateSpreadHistory(spreadPoints);
   
   // Get mode-based spread limit
   int spreadLimit = GetCurrentSpreadLimit();
   
   // Spread check (mode-based limit)
   if(spreadPoints > spreadLimit)
   {
      RecordCancel(CANCEL_SPREAD);
      return false;
   }
   
   // Spread spike check (sudden increase)
   if(IsSpreadSpiking(spreadPoints))
   {
      RecordCancel(CANCEL_SPREAD_SPIKE);
      return false;
   }
   
   // Max trades per day
   if(g_tradesToday >= InpMaxTradesPerDay)
   {
      RecordCancel(CANCEL_MAX_TRADES_DAY);
      return false;
   }
   
   // Consecutive losses
   if(g_consecLosses >= InpMaxConsecLosses)
   {
      RecordCancel(CANCEL_CONSECUTIVE_LOSSES);
      return false;
   }
   
   // Daily loss limit (skip if InpDailyLossLimitPct <= 0, meaning disabled)
   if(InpDailyLossLimitPct > 0)
   {
      double dailyLossLimit = g_dailyStartEquity * InpDailyLossLimitPct / 100.0;
      if(g_dailyPnL <= -dailyLossLimit)
      {
         RecordCancel(CANCEL_DAILY_LOSS);
         return false;
      }
   }
   else
   {
      // Log once that daily loss limit is disabled
      if(!g_dailyLossDisabledLogged)
      {
         Print("[INFO] Daily loss limit disabled (InpDailyLossLimitPct <= 0)");
         g_dailyLossDisabledLogged = true;
      }
   }
   
   // No overlapping positions
   if(PositionSelect(tradeSym))
   {
      return false;  // No log needed - normal behavior
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   
   int startHour, startMin, endHour, endMin;
   
   if(StringFind(InpTradeStart, ":") > 0)
   {
      string parts[];
      StringSplit(InpTradeStart, ':', parts);
      startHour = (int)StringToInteger(parts[0]);
      startMin = (int)StringToInteger(parts[1]);
   }
   else
   {
      startHour = 14;
      startMin = 0;
   }
   
   if(StringFind(InpTradeEnd, ":") > 0)
   {
      string parts[];
      StringSplit(InpTradeEnd, ':', parts);
      endHour = (int)StringToInteger(parts[0]);
      endMin = (int)StringToInteger(parts[1]);
   }
   else
   {
      endHour = 23;
      endMin = 30;
   }
   
   int startMinutes = startHour * 60 + startMin;
   int endMinutes = endHour * 60 + endMin;
   
   return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Get current HHMM from server time                                   |
//+------------------------------------------------------------------+
int GetCurrentHHMM()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour * 100 + dt.min;
}

//+------------------------------------------------------------------+
//| Check if in no-trade zone (rollover quarantine)                     |
//| Blocks ALL modes when InpBlockAllModesInNoTrade = true              |
//+------------------------------------------------------------------+
bool IsInNoTradeZone()
{
   int currentHHMM = GetCurrentHHMM();
   
   // Handle rollover zone that spans midnight
   if(InpNoTradeStartHHMM > InpNoTradeEndHHMM)
   {
      // Zone spans midnight (e.g., 2300 to 0020)
      return (currentHHMM >= InpNoTradeStartHHMM || currentHHMM <= InpNoTradeEndHHMM);
   }
   else
   {
      // Normal zone within same day
      return (currentHHMM >= InpNoTradeStartHHMM && currentHHMM <= InpNoTradeEndHHMM);
   }
}

//+------------------------------------------------------------------+
//| Check if hard block time (after InpHardBlockAfterHHMM)              |
//| This blocks new orders after specified time regardless of mode     |
//+------------------------------------------------------------------+
bool IsHardBlockTime()
{
   // If hard block is disabled, always return false
   if(!InpEnableHardBlock)
      return false;
   
   int currentHHMM = GetCurrentHHMM();
   
   // Hard block after specified time until midnight
   // e.g., InpHardBlockAfterHHMM = 2300 means block from 23:00 to 23:59
   // No-trade zone handles 00:00 onwards
   return (currentHHMM >= InpHardBlockAfterHHMM && currentHHMM < 2400);
}

//+------------------------------------------------------------------+
//| Check trading time with RELAX mode support                         |
//+------------------------------------------------------------------+
bool CheckTradingTime()
{
   // Always block no-trade zone (rollover quarantine) for ALL modes
   // This is checked separately in PassRiskChecks for proper logging
   // But we double-check here for safety
   if(InpBlockAllModesInNoTrade && IsInNoTradeZone())
   {
      return false;
   }
   
   // Hard block after specified time - blocks ALL modes
   if(IsHardBlockTime())
   {
      return false;
   }
   
   // 24h trading mode: allow all times except rollover (already checked above)
   if(InpEnable24hTrading)
   {
      return true;
   }
   
   // MODE_STRICT: use original timefilter
   if(g_tradeMode == MODE_STRICT)
   {
      return IsWithinTradingHours();
   }
   
   // MODE_RELAX/RELAX2: check if we can ignore timefilter
   if((g_tradeMode == MODE_RELAX || g_tradeMode == MODE_RELAX2) && InpRelaxIgnoreTimeFilter)
   {
      // Only ignore timefilter if below target
      if(g_tradesToday < InpTargetTradesPerDay)
      {
         return true;  // Allow trading outside normal hours
      }
   }
   
   // Default: use original timefilter
   return IsWithinTradingHours();
}

//+------------------------------------------------------------------+
//| Get bias from M15 (supports multiple modes)                        |
//+------------------------------------------------------------------+
ENUM_BIAS GetBias()
{
   g_biasNoneReason = "";  // Reset reason
   
   if(InpBiasMode == BIAS_MODE_EMA200_M15)
   {
      return GetBiasEMA();
   }
   else
   {
      return GetBiasStructure();
   }
}

//+------------------------------------------------------------------+
//| Get bias using EMA200 method                                       |
//+------------------------------------------------------------------+
ENUM_BIAS GetBiasEMA()
{
   if(g_emaHandle == INVALID_HANDLE)
   {
      g_biasNoneReason = "EMA handle invalid";
      LogBiasNone(g_biasNoneReason);
      return BIAS_NONE;
   }
   
   double emaValue[];
   ArraySetAsSeries(emaValue, true);
   
   if(CopyBuffer(g_emaHandle, 0, 0, 1, emaValue) <= 0)
   {
      g_biasNoneReason = "Failed to copy EMA buffer";
      LogBiasNone(g_biasNoneReason);
      return BIAS_NONE;
   }
   
   double close = iClose(tradeSym, InpBiasTF, 0);
   double ema = emaValue[0];
   
   // Clear bias determination
   if(close > ema)
   {
      return BIAS_BULLISH;
   }
   else if(close < ema)
   {
      return BIAS_BEARISH;
   }
   
   g_biasNoneReason = "Price exactly at EMA (ambiguous)";
   LogBiasNone(g_biasNoneReason);
   return BIAS_NONE;
}

//+------------------------------------------------------------------+
//| Get bias using Structure method (original)                         |
//+------------------------------------------------------------------+
ENUM_BIAS GetBiasStructure()
{
   int barIndex;
   double close = iClose(tradeSym, InpBiasTF, 0);
   
   double minorSwingHigh = GetLatestMinorSwingHigh(InpBiasTF, barIndex);
   double minorSwingLow = GetLatestMinorSwingLow(InpBiasTF, barIndex);
   
   // Check for no swing detection
   if(minorSwingHigh <= 0 && minorSwingLow <= 0)
   {
      g_biasNoneReason = "No swing points detected (not enough bars)";
      LogBiasNone(g_biasNoneReason);
      return BIAS_NONE;
   }
   
   if(minorSwingHigh <= 0)
   {
      g_biasNoneReason = "No swing high detected";
      LogBiasNone(g_biasNoneReason);
   }
   
   if(minorSwingLow <= 0)
   {
      g_biasNoneReason = "No swing low detected";
      LogBiasNone(g_biasNoneReason);
   }
   
   // Bullish: close above swing high
   if(minorSwingHigh > 0 && close > minorSwingHigh)
      return BIAS_BULLISH;
   
   // Bearish: close below swing low
   if(minorSwingLow > 0 && close < minorSwingLow)
      return BIAS_BEARISH;
   
   // Ambiguous: price between swing high and low
   g_biasNoneReason = StringFormat("Ambiguous: Close %.2f between SwingLow %.2f and SwingHigh %.2f",
                                    close, minorSwingLow, minorSwingHigh);
   LogBiasNone(g_biasNoneReason);
   return BIAS_NONE;
}

//+------------------------------------------------------------------+
//| Log bias none reason                                               |
//+------------------------------------------------------------------+
void LogBiasNone(string reason)
{
   if(!InpEnableLogging) return;
   
   static datetime lastLogTime = 0;
   // Limit logging to once per minute to avoid spam
   if(TimeCurrent() - lastLogTime < 60) return;
   lastLogTime = TimeCurrent();
   
   Print("Bias NONE: ", reason);
}

//+------------------------------------------------------------------+
//| Calculate lot size with martingale and mode adjustments            |
//| Order: baseLot -> martingale -> modeFactor -> biasNoneFactor -> cap -> normalize
//+------------------------------------------------------------------+
double CalculateLot()
{
   double baseLot = InpBaseLot;
   double lot = baseLot;
   
   // Determine if martingale is allowed
   bool allowMartingale = true;
   string martStatus = "ALLOWED";
   
   // Check mode restriction
   if((g_tradeMode == MODE_RELAX || g_tradeMode == MODE_RELAX2) && InpMartingaleStrictOnly)
   {
      allowMartingale = false;
      martStatus = "DISABLED_MODE";
   }
   
   // Check bias none restriction
   if(g_tradingWithBiasNone)
   {
      allowMartingale = false;
      martStatus = "DISABLED_BIASNONE";
   }
   
   // Check if martingale mode is enabled
   if(InpMartingaleMode != MART_AFTER_LOSS)
   {
      allowMartingale = false;
      martStatus = "DISABLED_OFF";
   }
   
   // Apply martingale multiplier if allowed and level > 0
   double martMultiplier = 1.0;
   if(allowMartingale && g_martLevel > 0)
   {
      martMultiplier = MathPow(InpMartMultiplier, g_martLevel);
      lot = baseLot * martMultiplier;
   }
   
   // Apply mode-based lot factor (RELAX/RELAX2 reduction)
   double lotFactor = GetLotFactor();
   double lotAfterFactor = lot;
   if(lotFactor < 1.0)
   {
      lotAfterFactor = lot * lotFactor;
   }
   lot = lotAfterFactor;
   
   // Apply bias none lot factor if trading without bias (additional reduction)
   double lotAfterBias = lot;
   if(g_tradingWithBiasNone && g_tradeMode == MODE_STRICT)
   {
      lotAfterBias = lot * InpBiasNoneLotFactor;
   }
   lot = lotAfterBias;
   
   // Apply cap
   double lotAfterCap = MathMin(lot, InpLotCapMax);
   lot = lotAfterCap;
   
   // Normalize to symbol specifications
   double minLot = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   double finalLot = NormalizeDouble(lot, 2);
   
   // Debug log - always print for martingale tracking
   string strictOnlyStr = InpMartingaleStrictOnly ? "S" : "A";
   PrintFormat("MART_CALC: mode=%s level=%d base=%.2f mult=%.2f factor=%.2f final=%.2f status=%s",
               EnumToString(g_tradeMode), g_martLevel, baseLot, martMultiplier, lotFactor, finalLot, martStatus);
   
   return finalLot;
}

//+------------------------------------------------------------------+
//| Calculate Recovery TP price                                         |
//| Returns TP price that will recover cumulative losses + buffer       |
//+------------------------------------------------------------------+
double CalculateRecoveryTP(double entryPrice, double lot, bool isBuy)
{
   // If Recovery TP is disabled or martLevel is 0, return 0 (use normal TP)
   if(!InpUseRecoveryTP || g_martLevel == 0 || g_recoveryLoss <= 0)
   {
      PrintFormat("REC_TP: Disabled or not needed (UseRecTP=%d, level=%d, recLoss=%.2f)",
                  InpUseRecoveryTP, g_martLevel, g_recoveryLoss);
      return 0;
   }
   
   // Calculate target money to recover
   double recoveryTargetMoney = g_recoveryLoss * InpRecoveryFactor + InpRecoveryBufferMoney;
   
   // Get tick value and tick size for money-to-points conversion
   double tickValue = SymbolInfoDouble(tradeSym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(tradeSym, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = SymbolInfoDouble(tradeSym, SYMBOL_POINT);
   
   if(tickValue <= 0 || tickSize <= 0 || lot <= 0)
   {
      PrintFormat("REC_TP: Invalid values (tickValue=%.5f, tickSize=%.5f, lot=%.2f)",
                  tickValue, tickSize, lot);
      return 0;
   }
   
   // Calculate money per point
   // moneyPerPoint = tickValue / tickSize * pointValue * lot
   double moneyPerPoint = (tickValue / tickSize) * pointValue * lot;
   
   if(moneyPerPoint <= 0)
   {
      PrintFormat("REC_TP: Invalid moneyPerPoint=%.5f", moneyPerPoint);
      return 0;
   }
   
   // Calculate required TP distance in points
   int tpPoints = (int)MathCeil(recoveryTargetMoney / moneyPerPoint);
   
   // Apply min/max constraints (use InpMinTP2Points as minimum for recovery TP)
   tpPoints = MathMax(InpMinTP2Points, MathMin(InpMaxTPPoints, tpPoints));
   
   // Calculate TP price
   double tpPrice;
   if(isBuy)
      tpPrice = entryPrice + tpPoints * pointValue;
   else
      tpPrice = entryPrice - tpPoints * pointValue;
   
   tpPrice = NormalizeDouble(tpPrice, _Digits);
   
   // Log recovery TP calculation
   PrintFormat("REC_TP: level=%d lot=%.2f recLoss=%.2f target=%.2f moneyPerPt=%.4f tpPts=%d tpPrice=%.5f",
               g_martLevel, lot, g_recoveryLoss, recoveryTargetMoney, moneyPerPoint, tpPoints, tpPrice);
   
   return tpPrice;
}

//+------------------------------------------------------------------+
//| Get current setup signature for Same Setup Only check              |
//+------------------------------------------------------------------+
string GetSetupSignature()
{
   // Create signature from: direction + bias + zone type
   string direction = (g_sweepType == SWEEP_BULLISH) ? "BULL" : "BEAR";
   string bias = EnumToString(g_bias);
   string zone = EnumToString(g_zoneType);
   
   string signature = direction + "_" + bias + "_" + zone;
   return signature;
}

//+------------------------------------------------------------------+
//| Check if current setup matches last losing setup                    |
//| Returns true if martingale should continue, false if should reset   |
//+------------------------------------------------------------------+
bool CheckSameSetup()
{
   // If Same Setup Only is disabled, always allow
   if(!InpMartSameSetupOnly)
      return true;
   
   // If martLevel is 0, no need to check
   if(g_martLevel == 0)
      return true;
   
   // If no previous signature, allow (first loss)
   if(g_lastSetupSignature == "")
      return true;
   
   // === CRITICAL: If recoveryLoss > 0, NEVER reset martLevel ===
   // Must continue recovery regardless of setup change
   bool inRecoveryMode = (g_recoveryLoss > 0);
   
   // Check bars since last loss
   int currentBar = iBarShift(tradeSym, InpEntryTF, TimeCurrent());
   int barsSinceLoss = g_lastLossBarIndex - currentBar;  // Note: bar index decreases over time
   if(barsSinceLoss < 0) barsSinceLoss = -barsSinceLoss;
   
   if(barsSinceLoss > InpMartMaxBarsSinceLoss)
   {
      if(inRecoveryMode)
      {
         // In recovery mode: DO NOT reset, just log and continue
         PrintFormat("SAME_SETUP: Bars since loss (%d) > max (%d) but IN RECOVERY (recLoss=%.2f) - KEEP martLevel=%d",
                     barsSinceLoss, InpMartMaxBarsSinceLoss, g_recoveryLoss, g_martLevel);
         return true;  // Allow trade to continue recovery
      }
      else
      {
         PrintFormat("SAME_SETUP: Bars since loss (%d) > max (%d) - %s martLevel",
                     barsSinceLoss, InpMartMaxBarsSinceLoss,
                     InpMartResetIfSetupChanged ? "RESET" : "KEEP");
         
         if(InpMartResetIfSetupChanged)
         {
            g_martLevel = 0;
            g_recoveryLoss = 0;
            g_lastSetupSignature = "";
            // Save to GlobalVariable
            if(g_martLevelKey != "") GlobalVariableSet(g_martLevelKey, g_martLevel);
            if(g_recoveryLossKey != "") GlobalVariableSet(g_recoveryLossKey, g_recoveryLoss);
         }
         return false;
      }
   }
   
   // Check signature match
   string currentSignature = GetSetupSignature();
   bool match = (currentSignature == g_lastSetupSignature);
   
   PrintFormat("SAME_SETUP: current=%s last=%s match=%d barsSinceLoss=%d inRecovery=%d",
               currentSignature, g_lastSetupSignature, match, barsSinceLoss, inRecoveryMode);
   
   if(!match)
   {
      if(inRecoveryMode)
      {
         // In recovery mode: DO NOT reset, just log and continue
         PrintFormat("SAME_SETUP: Signature mismatch but IN RECOVERY (recLoss=%.2f) - KEEP martLevel=%d",
                     g_recoveryLoss, g_martLevel);
         return true;  // Allow trade to continue recovery
      }
      else if(InpMartResetIfSetupChanged)
      {
         PrintFormat("SAME_SETUP: Signature mismatch - RESET martLevel from %d to 0", g_martLevel);
         g_martLevel = 0;
         g_recoveryLoss = 0;
         g_lastSetupSignature = "";
         // Save to GlobalVariable
         if(g_martLevelKey != "") GlobalVariableSet(g_martLevelKey, g_martLevel);
         if(g_recoveryLossKey != "") GlobalVariableSet(g_recoveryLossKey, g_recoveryLoss);
         return false;
      }
   }
   
   return match || inRecoveryMode;  // Allow if match OR in recovery
}

//=== TRADE MODE (STRICT/RELAX) ===
//+------------------------------------------------------------------+
//| Update trade mode based on time and trades                         |
//+------------------------------------------------------------------+
void UpdateTradeMode()
{
   // Save previous mode for logging
   g_prevTradeMode = g_tradeMode;
   
   // Check if below target
   bool belowTarget = (g_tradesToday < InpTargetTradesPerDay);
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   // === TARGET-FIRST POLICY ===
   // If enabled: Use RELAX until target reached, then switch to STRICT
   if(InpUseTargetFirstPolicy)
   {
      if(belowTarget)
      {
         // Below target: Use RELAX or RELAX2 based on time
         if(InpEnableRelax2 && currentHour >= InpRelax2Hour)
         {
            g_tradeMode = MODE_RELAX2;
         }
         else if(InpEnableRelaxMode)
         {
            // Use RELAX as default mode when below target
            g_tradeMode = MODE_RELAX;
         }
         else
         {
            // Fallback to STRICT if RELAX disabled
            g_tradeMode = MODE_STRICT;
         }
      }
      else
      {
         // Target reached: Switch to STRICT for quality control
         g_tradeMode = MODE_STRICT;
      }
   }
   // === LEGACY TIME-BASED POLICY ===
   else
   {
      // Default to STRICT
      g_tradeMode = MODE_STRICT;
      
      if(belowTarget)
      {
         // Tiered RELAX logic based on time
         if(InpEnableRelax2 && currentHour >= InpRelax2Hour)
         {
            g_tradeMode = MODE_RELAX2;
         }
         else if(InpEnableRelaxMode && currentHour >= InpRelaxSwitchHour)
         {
            g_tradeMode = MODE_RELAX;
         }
      }
   }
   
   // Update mode time counter (per bar)
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(tradeSym, InpEntryTF, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      int modeIdx = (int)g_tradeMode;
      if(modeIdx >= 0 && modeIdx < 3)
      {
         g_modeTimeBars[modeIdx]++;
      }
   }
   
   // Log mode change
   if(g_tradeMode != g_prevTradeMode)
   {
      LogModeChange();
   }
}

//+------------------------------------------------------------------+
//| Log mode change event                                              |
//+------------------------------------------------------------------+
void LogModeChange()
{
   string reason = "";
   string policy = InpUseTargetFirstPolicy ? "TARGET-FIRST" : "TIME-BASED";
   
   switch(g_tradeMode)
   {
      case MODE_RELAX2:
         reason = StringFormat("Below target (%d/%d) + late hour (%d:00+)",
                               g_tradesToday, InpTargetTradesPerDay, InpRelax2Hour);
         break;
      case MODE_RELAX:
         if(InpUseTargetFirstPolicy)
            reason = StringFormat("Below target (%d/%d) - using RELAX to find opportunities",
                                  g_tradesToday, InpTargetTradesPerDay);
         else
            reason = StringFormat("Below target (%d/%d) after RELAX hour (%d:00)",
                                  g_tradesToday, InpTargetTradesPerDay, InpRelaxSwitchHour);
         break;
      default:
         reason = StringFormat("Target reached (%d/%d) - switching to STRICT for quality",
                               g_tradesToday, InpTargetTradesPerDay);
         break;
   }
   
   Print("=== MODE CHANGE [", policy, "] ===");
   Print(EnumToString(g_prevTradeMode), " -> ", EnumToString(g_tradeMode));
   Print("Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Update ATR value                                                    |
//+------------------------------------------------------------------+
void UpdateATR()
{
   if(!InpUseATRSweepThreshold || g_atrHandle == INVALID_HANDLE)
   {
      g_currentATR = 0;
      return;
   }
   
   double atrBuffer[];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) > 0)
   {
      g_currentATR = atrBuffer[0];
   }
}

//+------------------------------------------------------------------+
//| Get current sweep break points based on mode (ATR-adaptive)        |
//+------------------------------------------------------------------+
int GetSweepBreakPoints()
{
   int staticPoints;
   switch(g_tradeMode)
   {
      case MODE_RELAX2: staticPoints = InpRelax2SweepBreakPoints; break;
      case MODE_RELAX:  staticPoints = InpRelaxSweepBreakPoints; break;
      default:          staticPoints = InpSweepBreakPoints; break;
   }
   
   // ATR-adaptive: use max of static and ATR-based
   if(InpUseATRSweepThreshold && g_currentATR > 0)
   {
      // Convert ATR to points
      int atrPoints = (int)(g_currentATR * InpSweepATRFactor / _Point);
      return MathMax(staticPoints, atrPoints);
   }
   
   return staticPoints;
}

//+------------------------------------------------------------------+
//| Get current reclaim max bars based on mode                         |
//+------------------------------------------------------------------+
int GetReclaimMaxBars()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2ReclaimMaxBars;
      case MODE_RELAX:  return InpRelaxReclaimMaxBars;
      default:          return InpReclaimMaxBars;
   }
}

//+------------------------------------------------------------------+
//| Get current confirm max bars based on mode                         |
//+------------------------------------------------------------------+
int GetConfirmMaxBars()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2ConfirmMaxBars;
      case MODE_RELAX:  return InpRelaxConfirmMaxBars;
      default:          return InpConfirmMaxBars;
   }
}

//+------------------------------------------------------------------+
//| Get current entry timeout bars based on mode                       |
//+------------------------------------------------------------------+
int GetEntryTimeoutBars()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2EntryTimeoutBars;
      case MODE_RELAX:  return InpRelaxEntryTimeoutBars;
      default:          return InpEntryTimeoutBars;
   }
}

//+------------------------------------------------------------------+
//| Get current retrace ratio based on mode                            |
//+------------------------------------------------------------------+
double GetRetraceRatio()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2RetraceRatio;
      case MODE_RELAX:  return InpRelaxRetraceRatio;
      default:          return InpRetraceRatio;
   }
}

//+------------------------------------------------------------------+
//| Get swing K based on trade mode                                     |
//+------------------------------------------------------------------+
int GetSwingK()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2SwingK;
      case MODE_RELAX:  return InpRelaxSwingK;
      default:          return InpSwingK;
   }
}

//+------------------------------------------------------------------+
//| Get current CHOCH mode based on trade mode                         |
//+------------------------------------------------------------------+
ENUM_CHOCH_MODE GetChochMode()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpChochModeRelax;
      case MODE_RELAX:  return InpChochModeRelax;
      default:          return InpChochModeStrict;
   }
}

//+------------------------------------------------------------------+
//| Get rolling liquidity bars based on mode                           |
//+------------------------------------------------------------------+
int GetRollingLiqBars()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2RollingLiqBars;
      case MODE_RELAX:  return InpRelaxRollingLiqBars;
      default:          return 96;  // Default for STRICT (not used)
   }
}

//+------------------------------------------------------------------+
//| Check if bias none is allowed based on mode                        |
//+------------------------------------------------------------------+
bool IsBiasNoneAllowed()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2AllowBiasNone;
      case MODE_RELAX:  return InpRelaxAllowBiasNone;
      default:          return InpAllowBiasNone;
   }
}

//+------------------------------------------------------------------+
//| Get lot factor based on mode                                       |
//+------------------------------------------------------------------+
double GetLotFactor()
{
   switch(g_tradeMode)
   {
      case MODE_RELAX2: return InpRelax2LotFactor;
      case MODE_RELAX:  return InpRelaxLotFactor;
      default:          return 1.0;
   }
}

//=== SL HIT TRACKING ===
//+------------------------------------------------------------------+
//| Get current day key as YYYYMMDD integer                            |
//+------------------------------------------------------------------+
int GetDayKeyYYYYMMDD()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
//| Check if position ID already counted today                         |
//+------------------------------------------------------------------+
bool IsPositionIdCounted(ulong positionId)
{
   for(int i = 0; i < ArraySize(g_countedPositionIds); i++)
   {
      if(g_countedPositionIds[i] == positionId)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add position ID to counted list                                    |
//+------------------------------------------------------------------+
void AddCountedPositionId(ulong positionId)
{
   int size = ArraySize(g_countedPositionIds);
   ArrayResize(g_countedPositionIds, size + 1);
   g_countedPositionIds[size] = positionId;
}

//+------------------------------------------------------------------+
//| Daily reset if needed (call in OnTick and OnTradeTransaction)      |
//+------------------------------------------------------------------+
void DailyResetIfNeeded()
{
   int currentDayKey = GetDayKeyYYYYMMDD();
   
   if(currentDayKey != g_dayKeyYYYYMMDD)
   {
      // New day detected - reset all counters
      g_dayKeyYYYYMMDD = currentDayKey;
      g_slHitsToday = 0;
      g_blockedToday = false;
      ArrayResize(g_countedPositionIds, 0);
      
      Print("=== DAILY RESET ===");
      Print("Date: ", currentDayKey, " | SL Hits reset to 0 | Trading enabled");
   }
}

//+------------------------------------------------------------------+
//| Check deal for SL hit                                              |
//+------------------------------------------------------------------+
void CheckDealForSLHit(ulong dealTicket)
{
   if(dealTicket == 0) return;
   
   // Select deal from history
   if(!HistoryDealSelect(dealTicket))
   {
      // Try selecting history for today
      datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      HistorySelect(dayStart, TimeCurrent() + 3600);
      if(!HistoryDealSelect(dealTicket))
         return;
   }
   
   // Check if it's an exit deal (DEAL_ENTRY_OUT)
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT)
      return;
   
   // Check symbol
   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != tradeSym)
      return;
   
   // Check magic number
   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != InpMagic)
      return;
   
   // Check if reason is SL
   ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
   if(dealReason != DEAL_REASON_SL)
      return;
   
   // Get position ID for deduplication
   ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   
   // Check if already counted (prevent partial fill double counting)
   if(IsPositionIdCounted(positionId))
      return;
   
   double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   double profitNet = dealProfit + dealCommission + dealSwap;
   
   // === CRITICAL FIX: Only count as SL hit if actual loss ===
   // BE stop (profit >= 0 or >= -commission_epsilon) should NOT count toward daily limit
   double commissionEpsilon = 0.50;  // Allow small negative from commission
   bool isActualLoss = (profitNet < -commissionEpsilon);
   
   // Always mark position as counted to prevent double counting
   AddCountedPositionId(positionId);
   
   if(isActualLoss)
   {
      // Real SL loss - count toward daily limit
      g_slHitsToday++;
      
      Print("=== SL LOSS COUNTED ===");
      Print("Deal: ", dealTicket, " | Position: ", positionId);
      Print("Volume: ", dealVolume, " | Profit: ", dealProfit, " | Net: ", profitNet);
      Print("SL Loss Hits Today: ", g_slHitsToday, "/", InpMaxSLHitsPerDay);
      
      // Check if max SL hits reached
      if(g_slHitsToday >= InpMaxSLHitsPerDay && InpStopTradingOnSLHits)
      {
         g_blockedToday = true;
         Print("=== DAILY STOP TRIGGERED ===");
         Print("Max SL loss hits (", InpMaxSLHitsPerDay, ") reached. Trading blocked for today.");
      }
   }
   else
   {
      // BE stop - do NOT count toward daily limit
      Print("=== BE STOP (NOT COUNTED) ===");
      Print("Deal: ", dealTicket, " | Position: ", positionId);
      Print("Volume: ", dealVolume, " | Profit: ", dealProfit, " | Net: ", profitNet);
      Print("This was a BE stop, not counting toward SL limit. Current SL Loss Hits: ", g_slHitsToday);
   }
}

//+------------------------------------------------------------------+
//| Update martingale level from deal result                            |
//| Called from OnTradeTransaction for accurate martLevel tracking      |
//+------------------------------------------------------------------+
void UpdateMartingaleFromDeal(ulong dealTicket)
{
   // DEBUG: Function called
   PrintFormat("MART_DEBUG: UpdateMartingaleFromDeal called with deal=%I64u", dealTicket);
   
   if(dealTicket == 0)
   {
      Print("MART_DEBUG: dealTicket is 0, returning");
      return;
   }
   
   // IMPORTANT: Always call HistorySelect first to load history
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(dayStart, TimeCurrent() + 3600))
   {
      Print("MART_DEBUG: HistorySelect failed");
      return;
   }
   
   // Now select the specific deal
   if(!HistoryDealSelect(dealTicket))
   {
      PrintFormat("MART_DEBUG: HistoryDealSelect failed for deal=%I64u", dealTicket);
      return;
   }
   
   // Check if it's an exit deal (DEAL_ENTRY_OUT)
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   PrintFormat("MART_DEBUG: dealEntry=%d (OUT=%d)", dealEntry, DEAL_ENTRY_OUT);
   
   if(dealEntry != DEAL_ENTRY_OUT)
   {
      Print("MART_DEBUG: Not an exit deal, returning");
      return;
   }
   
   // Check symbol
   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   PrintFormat("MART_DEBUG: dealSymbol=%s tradeSym=%s", dealSymbol, tradeSym);
   
   if(dealSymbol != tradeSym)
   {
      Print("MART_DEBUG: Symbol mismatch, returning");
      return;
   }
   
   // Check magic number
   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   PrintFormat("MART_DEBUG: dealMagic=%I64d InpMagic=%I64d", dealMagic, InpMagic);
   
   if(dealMagic != InpMagic)
   {
      Print("MART_DEBUG: Magic mismatch, returning");
      return;
   }
   
   // === POSITION-BASED TRACKING (for partial close support) ===
   ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double dealProfitNet = dealProfit + dealCommission + dealSwap;
   double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   
   PrintFormat("MART_DEBUG: posId=%I64u profit=%.2f comm=%.2f swap=%.2f net=%.2f vol=%.2f",
               positionId, dealProfit, dealCommission, dealSwap, dealProfitNet, dealVolume);
   
   // Accumulate profit for this position
   if(g_positionData.positionId == positionId && g_positionData.isActive)
   {
      // Same position - accumulate
      g_positionData.volumeOut += dealVolume;
      g_positionData.profitAccum += dealProfitNet;
      PrintFormat("MART_DEBUG: Accumulated - volOut=%.2f profitAccum=%.2f",
                  g_positionData.volumeOut, g_positionData.profitAccum);
   }
   else
   {
      // New position or first deal - initialize
      g_positionData.positionId = positionId;
      g_positionData.volumeOut = dealVolume;
      g_positionData.profitAccum = dealProfitNet;
      g_positionData.isActive = true;
      // volumeIn should be set when position opens, but use dealVolume as fallback
      if(g_positionData.volumeIn <= 0)
         g_positionData.volumeIn = g_currentLot;
      PrintFormat("MART_DEBUG: New position tracking - posId=%I64u volIn=%.2f volOut=%.2f profitAccum=%.2f",
                  positionId, g_positionData.volumeIn, g_positionData.volumeOut, g_positionData.profitAccum);
   }
   
   // Check if position is fully closed
   // Allow small tolerance for floating point comparison
   bool positionFullyClosed = (g_positionData.volumeOut >= g_positionData.volumeIn - 0.001);
   
   if(!positionFullyClosed)
   {
      // Partial close - don't update martingale yet
      PrintFormat("MART_DEBUG: PARTIAL CLOSE - volOut=%.2f < volIn=%.2f - waiting for full close",
                  g_positionData.volumeOut, g_positionData.volumeIn);
      return;
   }
   
   // === POSITION FULLY CLOSED - NOW UPDATE MARTINGALE ===
   PrintFormat("MART_DEBUG: POSITION FULLY CLOSED - posId=%I64u totalProfit=%.2f",
               positionId, g_positionData.profitAccum);
   
   double profitNet = g_positionData.profitAccum;  // Use accumulated profit
   
   // Reset position tracking
   g_positionData.isActive = false;
   g_positionData.volumeIn = 0;
   g_positionData.volumeOut = 0;
   g_positionData.profitAccum = 0;
   
   // Store previous level for logging
   int prevMartLevel = g_martLevel;
   double prevRecoveryLoss = g_recoveryLoss;
   
   // Update martingale level and recovery loss
   if(profitNet > 0)
   {
      // Win: reduce recoveryLoss by profit amount
      double newRecoveryLoss = MathMax(0, g_recoveryLoss - profitNet);
      
      PrintFormat("MART_DEBUG: WIN - profit=%.2f recoveryLoss=%.2f -> %.2f",
                  profitNet, g_recoveryLoss, newRecoveryLoss);
      
      g_recoveryLoss = newRecoveryLoss;
      
      // Only reset martLevel when recoveryLoss reaches 0
      if(g_recoveryLoss <= 0)
      {
         PrintFormat("MART_DEBUG: FULL RECOVERY - martLevel %d -> 0", g_martLevel);
         g_martLevel = 0;
         g_recoveryLoss = 0;
         g_consecLosses = 0;
         g_currentLot = InpBaseLot;
         g_lastSetupSignature = "";
      }
      else
      {
         PrintFormat("MART_DEBUG: PARTIAL RECOVERY - martLevel stays at %d, remaining recLoss=%.2f",
                     g_martLevel, g_recoveryLoss);
      }
   }
   else if(profitNet < 0)
   {
      // Loss: accumulate recovery loss and increment level
      g_recoveryLoss += MathAbs(profitNet);
      g_consecLosses++;
      
      // Store loss time and bar index for Same Setup Only check
      g_lastLossTime = TimeCurrent();
      g_lastLossBarIndex = iBarShift(tradeSym, InpEntryTF, TimeCurrent());
      
      PrintFormat("MART_DEBUG: LOSS - MartMode=%d level=%d maxLevel=%d recoveryLoss=%.2f",
                  InpMartingaleMode, g_martLevel, InpMartMaxLevel, g_recoveryLoss);
      
      if(InpMartingaleMode == MART_AFTER_LOSS && g_martLevel < InpMartMaxLevel)
      {
         g_martLevel++;
         PrintFormat("MART_DEBUG: Level incremented to %d", g_martLevel);
      }
      else
      {
         PrintFormat("MART_DEBUG: Level NOT incremented (mode=%d or at max)", InpMartingaleMode);
      }
   }
   else
   {
      Print("MART_DEBUG: BREAKEVEN - level unchanged");
   }
   
   // === EXIT CLASSIFICATION ===
   // Classify the exit reason: SL_LOSS, BE_STOP, TRAIL_STOP, TP, MANUAL
   ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
   string exitClass = "MANUAL";
   double eps = 0.50;  // Epsilon for BE classification (allow small commission)
   
   if(dealReason == DEAL_REASON_SL)
   {
      // SL triggered - classify based on profit
      if(profitNet < -eps)
      {
         // Actual loss
         exitClass = "SL_LOSS";
         g_slLossHitsCount++;
      }
      else if(MathAbs(profitNet) <= eps)
      {
         // Breakeven (profit ~= 0)
         exitClass = "BE_STOP";
         g_beStopCount++;
      }
      else  // profitNet > eps
      {
         // Profit from trailing/lock
         exitClass = "TRAIL_STOP";
         g_trailStopCount++;
      }
   }
   else if(dealReason == DEAL_REASON_TP)
   {
      exitClass = "TP";
      g_tpHitsCount++;
   }
   else
   {
      // Other reasons (manual close, etc.)
      exitClass = "MANUAL";
      g_manualCloseCount++;
   }
   
   // === FINAL CLOSE LOG ===
   PrintFormat("[CLOSE] deal_reason=%s profit=%.2f classify=%s posId=%I64u",
               EnumToString(dealReason), profitNet, exitClass, positionId);
   PrintFormat("CLOSE: posId=%I64u net=%.2f martLevel=%d->%d recLoss=%.2f->%.2f exitClass=%s",
               positionId, profitNet, prevMartLevel, g_martLevel, prevRecoveryLoss, g_recoveryLoss, exitClass);
   
   // === SAVE TO GLOBALVARIABLE ===
   // Persist martLevel immediately after any change
   if(g_martLevelKey != "")
   {
      GlobalVariableSet(g_martLevelKey, g_martLevel);
      PrintFormat("MART_PERSIST: Saved martLevel=%d to GlobalVariable (after deal close)", g_martLevel);
   }
   
   // Persist recoveryLoss
   if(g_recoveryLossKey != "")
   {
      GlobalVariableSet(g_recoveryLossKey, g_recoveryLoss);
      PrintFormat("MART_PERSIST: Saved recoveryLoss=%.2f to GlobalVariable (after deal close)", g_recoveryLoss);
   }
   
   // Calculate what next lot will be
   double nextLot = InpBaseLot * MathPow(InpMartMultiplier, g_martLevel);
   nextLot = MathMin(nextLot, InpLotCapMax);
   
   // Normalize
   double minLot = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(tradeSym, SYMBOL_VOLUME_STEP);
   nextLot = MathMax(minLot, MathMin(maxLot, nextLot));
   nextLot = MathFloor(nextLot / lotStep) * lotStep;
   
   // Final summary log
   PrintFormat("MART_UPDATE: deal=%I64u profit=%.2f (net=%.2f) vol=%.2f | level: %d->%d | nextLot=%.2f",
               dealTicket, dealProfit, profitNet, dealVolume, prevMartLevel, g_martLevel, nextLot);
}

//+------------------------------------------------------------------+
//| Log no-trade zone cancel (throttled)                                |
//+------------------------------------------------------------------+
void LogNoTradeZoneCancel(string reason, int currentHHMM)
{
   if(!InpEnableLogging) return;
   
   // Throttle to 60 seconds
   static datetime lastNoTradeLog = 0;
   static string lastNoTradeReason = "";
   
   if(reason == lastNoTradeReason && TimeCurrent() - lastNoTradeLog < 60)
   {
      g_lastCancelReason = reason;
      g_lastCancelTime = TimeCurrent();
      return;
   }
   
   lastNoTradeLog = TimeCurrent();
   lastNoTradeReason = reason;
   g_lastCancelReason = reason;
   g_lastCancelTime = TimeCurrent();
   
   // Detailed log format
   Print(StringFormat("[CANCEL] reason=%s hhmm=%04d start=%04d end=%04d",
                      reason, currentHHMM, InpNoTradeStartHHMM, InpNoTradeEndHHMM));
}

//+------------------------------------------------------------------+
//| Log spread cancel with details (throttled)                         |
//+------------------------------------------------------------------+
void LogSpreadCancel(string reason, double curSpread, double avgSpread, int limit)
{
   if(!InpEnableLogging) return;
   
   // Throttle spread cancel logs using InpLogSpreadCancelEverySec
   static datetime lastSpreadLog = 0;
   static string lastSpreadReason = "";
   
   // Only log if different reason or enough time passed
   if(reason == lastSpreadReason && TimeCurrent() - lastSpreadLog < InpLogSpreadCancelEverySec)
   {
      // Still update last cancel reason for panel
      g_lastCancelReason = reason;
      g_lastCancelTime = TimeCurrent();
      return;
   }
   
   lastSpreadLog = TimeCurrent();
   lastSpreadReason = reason;
   g_lastCancelReason = reason;
   g_lastCancelTime = TimeCurrent();
   
   // Detailed log format
   if(reason == "spread_spike")
   {
      Print(StringFormat("[CANCEL] reason=%s mode=%s cur=%.1f avg=%.1f limit=%d mult=%.1f",
                         reason, EnumToString(g_tradeMode), curSpread, avgSpread, limit, InpSpreadSpikeMultiplier));
   }
   else
   {
      Print(StringFormat("[CANCEL] reason=%s mode=%s cur=%.1f avg=%.1f limit=%d",
                         reason, EnumToString(g_tradeMode), curSpread, avgSpread, limit));
   }
}

//+------------------------------------------------------------------+
//| Get cancel reason name from enum                                    |
//+------------------------------------------------------------------+
string GetCancelReasonName(ENUM_CANCEL_REASON reason)
{
   switch(reason)
   {
      case CANCEL_SPREAD:            return "spread";
      case CANCEL_SPREAD_SPIKE:      return "spread_spike";
      case CANCEL_NO_SWEEP:          return "no_sweep";
      case CANCEL_NO_CHOCH:          return "no_choch";
      case CANCEL_NO_RETRACE:        return "no_retrace";
      case CANCEL_TIMEFILTER:        return "timefilter";
      case CANCEL_BIAS_NONE:         return "bias_none";
      case CANCEL_COOLDOWN:          return "cooldown";
      case CANCEL_NO_TRADE_ZONE:     return "no_trade_zone";
      case CANCEL_HARD_BLOCK:        return "hard_block";
      case CANCEL_SL_BLOCKED:        return "sl_blocked";
      case CANCEL_MAX_TRADES_DAY:    return "max_trades";
      case CANCEL_CONSECUTIVE_LOSSES: return "consec_losses";
      case CANCEL_DAILY_LOSS:        return "daily_loss";
      case CANCEL_ROLLOVER:          return "rollover";
      case CANCEL_ATR_LOW:           return "atr_low";
      case CANCEL_SWEEP_TIMEOUT:     return "sweep_timeout";
      case CANCEL_CHOCH_TIMEOUT:     return "choch_timeout";
      case CANCEL_RETRACE_TIMEOUT:   return "retrace_timeout";
      case INFO_MICROCHOCH_USED:     return "microchoch_used";
      default:                       return "unknown";
   }
}

//+------------------------------------------------------------------+
//| Record cancel reason with per-bar throttle                          |
//| Counts max 1 time per bar per reason to avoid inflated numbers      |
//+------------------------------------------------------------------+
void RecordCancel(ENUM_CANCEL_REASON reason)
{
   if(reason == CANCEL_NONE || reason >= CANCEL_COUNT) return;
   
   // Update last cancel reason for panel
   g_lastCancelReasonEnum = reason;
   g_lastCancelReason = GetCancelReasonName(reason);
   g_lastCancelTime = TimeCurrent();
   
   // Per-bar throttle: only count once per bar per reason
   datetime currentBarTime = iTime(tradeSym, InpEntryTF, 0);
   if(g_lastCancelBarTime[reason] == currentBarTime)
      return;  // Already counted this bar
   
   g_lastCancelBarTime[reason] = currentBarTime;
   g_cancelCounters[reason]++;
   
   // Also record in 2D array by mode
   int modeIdx = (int)g_tradeMode; // 0=STRICT, 1=RELAX, 2=RELAX2
   if(modeIdx >= 0 && modeIdx < 3)
   {
      g_cancelByMode[modeIdx][reason]++;
   }
   
   // Throttled logging (60 sec per reason)
   static datetime lastLogTimes[CANCEL_COUNT];
   if(InpEnableLogging && (TimeCurrent() - lastLogTimes[reason] >= 60))
   {
      lastLogTimes[reason] = TimeCurrent();
      Print(StringFormat("[%s] Cancel: %s (count: %d)", 
            EnumToString(g_tradeMode), g_lastCancelReason, g_cancelCounters[reason]));
   }
}

//+------------------------------------------------------------------+
//| Legacy wrapper for string-based cancel recording                    |
//+------------------------------------------------------------------+
void IncrementCancelCounter(string reason)
{
   ENUM_CANCEL_REASON enumReason = CANCEL_OTHER;
   
   if(reason == "spread") enumReason = CANCEL_SPREAD;
   else if(reason == "spread_spike") enumReason = CANCEL_SPREAD_SPIKE;
   else if(reason == "no_sweep") enumReason = CANCEL_NO_SWEEP;
   else if(reason == "no_choch") enumReason = CANCEL_NO_CHOCH;
   else if(reason == "no_retrace") enumReason = CANCEL_NO_RETRACE;
   else if(reason == "timefilter") enumReason = CANCEL_TIMEFILTER;
   else if(reason == "bias_none") enumReason = CANCEL_BIAS_NONE;
   else if(reason == "cooldown") enumReason = CANCEL_COOLDOWN;
   else if(reason == "no_trade_zone") enumReason = CANCEL_NO_TRADE_ZONE;
   else if(reason == "hard_block") enumReason = CANCEL_HARD_BLOCK;
   else if(reason == "sl_blocked") enumReason = CANCEL_SL_BLOCKED;
   else if(reason == "max_trades") enumReason = CANCEL_MAX_TRADES_DAY;
   else if(reason == "consec_losses") enumReason = CANCEL_CONSECUTIVE_LOSSES;
   else if(reason == "daily_loss") enumReason = CANCEL_DAILY_LOSS;
   
   RecordCancel(enumReason);
}

//+------------------------------------------------------------------+
//| Legacy wrapper for throttled logging                                |
//+------------------------------------------------------------------+
void LogCancelReasonThrottled(string reason)
{
   IncrementCancelCounter(reason);  // Now uses RecordCancel internally
}

//+------------------------------------------------------------------+
//| Legacy wrapper for logging (no throttle - but now uses per-bar)     |
//+------------------------------------------------------------------+
void LogCancelReason(string reason)
{
   IncrementCancelCounter(reason);  // Now uses RecordCancel internally
}

//=== UTILITY FUNCTIONS ===
//+------------------------------------------------------------------+
//| Get spread in points                                               |
//+------------------------------------------------------------------+
double GetSpreadPoints()
{
   double ask = SymbolInfoDouble(tradeSym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(tradeSym, SYMBOL_BID);
   double spread = (ask - bid) / _Point;
   
   // Update spread for display
   g_currentSpread = spread;
   
   return spread;
}

//+------------------------------------------------------------------+
//| Update spread history for spike detection                          |
//+------------------------------------------------------------------+
void UpdateSpreadHistory(double spreadPoints)
{
   datetime now = TimeCurrent();
   
   // Add to circular buffer
   g_spreadHistory[g_spreadHistoryIdx] = spreadPoints;
   g_spreadTimeHistory[g_spreadHistoryIdx] = now;
   g_spreadHistoryIdx = (g_spreadHistoryIdx + 1) % g_spreadHistorySize;
   
   // Calculate rolling average within window
   double sum = 0;
   int count = 0;
   datetime windowStart = now - InpSpreadSpikeWindowSec;
   
   for(int i = 0; i < g_spreadHistorySize; i++)
   {
      if(g_spreadTimeHistory[i] >= windowStart && g_spreadHistory[i] > 0)
      {
         sum += g_spreadHistory[i];
         count++;
      }
   }
   
   if(count > 0)
      g_avgSpread = sum / count;
   else
      g_avgSpread = spreadPoints;  // First sample
}

//+------------------------------------------------------------------+
//| Check if spread is spiking                                         |
//+------------------------------------------------------------------+
bool IsSpreadSpiking(double currentSpread)
{
   if(g_avgSpread <= 0) return false;
   
   // Spike if current > avg * multiplier
   return (currentSpread > g_avgSpread * InpSpreadSpikeMultiplier);
}

//+------------------------------------------------------------------+
//| Check if near rollover zone (extended)                             |
//+------------------------------------------------------------------+
bool IsNearRollover()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHHMM = dt.hour * 100 + dt.min;
   
   // Extended rollover zone: 23:50 - 00:20
   // This is wider than the no-trade zone to apply stricter spread limits
   if(currentHHMM >= 2350 || currentHHMM <= 20)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Get current spread limit based on mode and time                    |
//+------------------------------------------------------------------+
int GetCurrentSpreadLimit()
{
   // Near rollover: use strictest limit
   if(IsNearRollover())
   {
      g_currentSpreadLimit = InpMaxSpreadRollover;
      return InpMaxSpreadRollover;
   }
   
   // Based on trade mode
   switch(g_tradeMode)
   {
      case MODE_RELAX:
      case MODE_RELAX2:
         // RELAX modes: use relaxed limit only if below target
         if(g_tradesToday < InpTargetTradesPerDay)
         {
            g_currentSpreadLimit = InpMaxSpreadRelax;
            return InpMaxSpreadRelax;
         }
         // After reaching target, use strict limit
         g_currentSpreadLimit = InpMaxSpreadStrict;
         return InpMaxSpreadStrict;
         
      default:
         // STRICT mode
         g_currentSpreadLimit = InpMaxSpreadStrict;
         return InpMaxSpreadStrict;
   }
}

//+------------------------------------------------------------------+
//| Get ATR value                                                      |
//+------------------------------------------------------------------+
double GetATR(int period)
{
   int handle = iATR(tradeSym, InpEntryTF, period);
   if(handle == INVALID_HANDLE) return 0;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle, 0, 0, 1, atr) <= 0) return 0;
   
   IndicatorRelease(handle);
   return atr[0];
}

//+------------------------------------------------------------------+
//| Check for new day                                                  |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   datetime currentDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   if(currentDay != g_lastTradeDay)
   {
      ResetDailyCounters();
      g_lastTradeDay = currentDay;
   }
}

//+------------------------------------------------------------------+
//| Reset daily counters                                               |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   // Print daily summary before reset (if we have data)
   bool hasData = (g_tradesToday > 0);
   for(int i = 0; i < CANCEL_COUNT && !hasData; i++)
   {
      if(g_cancelCounters[i] > 0) hasData = true;
   }
   
   if(hasData)
   {
      PrintDailySummary();
      
      // Write CSV entry before reset
      if(InpEnableCSVLogging)
         WriteCSVDailyEntry();
      
      // Accumulate totals for final summary
      g_totalTradingDays++;
      g_totalTradesExecuted += g_tradesToday;
      g_totalPnL += g_dailyPnL;
      g_totalSlHits += g_slHitsToday;
      
      // Add daily counters to total counters
      for(int i = 0; i < CANCEL_COUNT; i++)
      {
         g_totalCancelCounters[i] += g_cancelCounters[i];
      }
      
      // Add daily 2D counters to totals
      for(int m = 0; m < 3; m++)
      {
         for(int r = 0; r < CANCEL_COUNT; r++)
         {
            g_totalCancelByMode[m][r] += g_cancelByMode[m][r];
         }
         // Add microchoch counters
         g_totalMicrochochAttempted[m] += g_microchochAttempted[m];
         g_totalMicrochochPass[m] += g_microchochPass[m];
         g_totalMicrochochFailBreak[m] += g_microchochFailBreak[m];
         g_totalMicrochochFailBody[m] += g_microchochFailBody[m];
         // Add mode time counters
         g_totalModeTimeBars[m] += g_modeTimeBars[m];
      }
      
      // Add TP1 partial close counters to totals
      g_totalTP1PartialTriggered += g_tp1PartialTriggeredCount;
      g_totalTP1PartialFailed += g_tp1PartialFailedCount;
      g_totalTP1PartialSkipped += g_tp1PartialSkippedCount;
      g_totalBEMoved += g_beMovedCount;
      
      // Add exit classification counters to totals
      g_totalSlLossHits += g_slLossHitsCount;
      g_totalBeStops += g_beStopCount;
      g_totalTrailStops += g_trailStopCount;
      g_totalTpHits += g_tpHitsCount;
      g_totalManualClose += g_manualCloseCount;
      
      // Add trailing stop counters to totals
      g_totalTrailAttempted += g_trailAttemptedCount;
      g_totalTrailMoved += g_trailMovedCount;
      g_totalTrailReject += g_trailRejectCount;
      g_totalTrailSkippedCooldown += g_trailSkippedCooldown;
      g_totalTrailSkippedStep += g_trailSkippedStep;
      g_totalTrailSkippedNotAfterPartial += g_trailSkippedNotAfterPartial;
      g_totalTrailSkippedNotReachedR += g_trailSkippedNotReachedR;
      g_totalTrailSkippedNewBar += g_trailSkippedNewBar;
      g_totalTrailFailed += g_trailFailedCount;
   }
   
   g_tradesToday = 0;
   g_consecLosses = 0;
   g_dailyPnL = 0;
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // NOTE: martLevel is NOT reset on new day - it persists until a winning trade
   // g_martLevel = 0;  // REMOVED - martingale continues across days
   // g_currentLot = InpBaseLot;  // REMOVED - lot is calculated from martLevel
   PrintFormat("MART_PERSIST: New day - martLevel=%d persists (not reset)", g_martLevel);
   
   // Reset trade mode to STRICT at start of day
   g_tradeMode = MODE_STRICT;
   g_prevTradeMode = MODE_STRICT;
   
   // Reset cancel counters (array-based)
   ArrayInitialize(g_cancelCounters, 0);
   ArrayInitialize(g_lastCancelBarTime, 0);
   g_lastCancelReasonEnum = CANCEL_NONE;
   g_dailyLossDisabledLogged = false;
   
   // Reset 2D cancel counters and microchoch diagnostics
   for(int m = 0; m < 3; m++)
   {
      for(int r = 0; r < CANCEL_COUNT; r++)
      {
         g_cancelByMode[m][r] = 0;
      }
      g_microchochAttempted[m] = 0;
      g_microchochPass[m] = 0;
      g_microchochFailBreak[m] = 0;
      g_microchochFailBody[m] = 0;
      g_modeTimeBars[m] = 0;
   }
   
   // Reset TP1 partial close counters
   g_tp1PartialTriggeredCount = 0;
   g_tp1PartialFailedCount = 0;
   g_tp1PartialSkippedCount = 0;
   g_beMovedCount = 0;
   
   // Reset exit classification counters
   g_slLossHitsCount = 0;
   g_beStopCount = 0;
   g_trailStopCount = 0;
   g_tpHitsCount = 0;
   g_manualCloseCount = 0;
   
   // Reset trailing stop counters
   g_trailAttemptedCount = 0;
   g_trailMovedCount = 0;
   g_trailRejectCount = 0;
   g_trailSkippedCooldown = 0;
   g_trailSkippedStep = 0;
   g_trailSkippedNotAfterPartial = 0;
   g_trailSkippedNotReachedR = 0;
   g_trailSkippedNewBar = 0;
   g_trailFailedCount = 0;
   
   Print("=== DAILY RESET ===");
   Print("Start equity: ", g_dailyStartEquity);
   Print("Trade mode reset to STRICT");
}

//+------------------------------------------------------------------+
//| Print daily summary of cancel reasons                              |
//+------------------------------------------------------------------+
void PrintDailySummary()
{
   Print("=== DAILY SUMMARY ===");
   Print("Trades executed: ", g_tradesToday);
   Print("SL Loss Hits: ", g_slHitsToday, "/", InpMaxSLHitsPerDay, " (guardrail uses this)");
   Print("Daily PnL: ", DoubleToString(g_dailyPnL, 2));
   
   // Exit Classification (Today)
   Print("--- Exit Classification (Today) ---");
   Print("  SL_LOSS hits: ", g_slLossHitsCount, " (guardrail uses this)");
   Print("  BE stops: ", g_beStopCount);
   Print("  TRAIL stops: ", g_trailStopCount);
   Print("  TP hits: ", g_tpHitsCount);
   Print("  Manual close: ", g_manualCloseCount);
   
   // TP1 Partial Close diagnostics
   Print("--- TP1 Partial Close (Today) ---");
   Print("  PartialTP1_triggers: ", g_tp1PartialTriggeredCount);
   Print("  PartialTP1_failed: ", g_tp1PartialFailedCount, " (last reason: ", g_lastTP1FailReason, ")");
   Print("  PartialTP1_skipped: ", g_tp1PartialSkippedCount, " (TP1 too close)");
   Print("  BE_move_count: ", g_beMovedCount);
   
   // Trailing Stop diagnostics
   Print("--- Trailing Stop (Today) ---");
   Print("  Trail moves: ", g_trailMovedCount);
   Print("  Trail rejects: ", g_trailRejectCount, " (stops/freeze constraints)");
   Print("  Trail failed: ", g_trailFailedCount);
   
   // Top trail skip reasons
   int trailSkipCounts[7];
   string trailSkipNames[7];
   trailSkipCounts[0] = g_trailSkippedCooldown;     trailSkipNames[0] = "cooldown";
   trailSkipCounts[1] = g_trailSkippedStep;         trailSkipNames[1] = "step";
   trailSkipCounts[2] = g_trailSkippedNotAfterPartial; trailSkipNames[2] = "not_after_partial";
   trailSkipCounts[3] = g_trailSkippedNotReachedR;  trailSkipNames[3] = "not_reached_R";
   trailSkipCounts[4] = g_trailSkippedNewBar;       trailSkipNames[4] = "not_new_bar";
   trailSkipCounts[5] = 0;                          trailSkipNames[5] = "";
   trailSkipCounts[6] = 0;                          trailSkipNames[6] = "";
   
   // Sort and print top 3
   for(int i = 0; i < 5; i++)
   {
      for(int j = i + 1; j < 5; j++)
      {
         if(trailSkipCounts[j] > trailSkipCounts[i])
         {
            int tmpCnt = trailSkipCounts[i];
            string tmpName = trailSkipNames[i];
            trailSkipCounts[i] = trailSkipCounts[j];
            trailSkipNames[i] = trailSkipNames[j];
            trailSkipCounts[j] = tmpCnt;
            trailSkipNames[j] = tmpName;
         }
      }
   }
   string skipLine = "  Top skip: ";
   for(int i = 0; i < 3 && trailSkipCounts[i] > 0; i++)
   {
      skipLine += trailSkipNames[i] + "=" + IntegerToString(trailSkipCounts[i]) + " ";
   }
   Print(skipLine);
   
   // Print microchoch diagnostics by mode
   Print("--- Microchoch Diagnostics (Today) ---");
   string modeNames[3] = {"STRICT", "RELAX", "RELAX2"};
   for(int m = 0; m < 3; m++)
   {
      if(g_microchochAttempted[m] > 0)
      {
         Print("  ", modeNames[m], ": Attempted=", g_microchochAttempted[m], 
               " Pass=", g_microchochPass[m], 
               " FailBreak=", g_microchochFailBreak[m], 
               " FailBody=", g_microchochFailBody[m]);
      }
   }
   
   // Print cancel by mode (top 3 per mode)
   Print("--- Cancel by Mode (Top 3) ---");
   for(int m = 0; m < 3; m++)
   {
      int modeTotal = 0;
      for(int r = 0; r < CANCEL_COUNT; r++) modeTotal += g_cancelByMode[m][r];
      if(modeTotal == 0) continue;
      
      // Sort this mode's cancels
      int sortedIdx[CANCEL_COUNT];
      int sortedCounts[CANCEL_COUNT];
      for(int i = 0; i < CANCEL_COUNT; i++)
      {
         sortedIdx[i] = i;
         sortedCounts[i] = g_cancelByMode[m][i];
      }
      for(int i = 0; i < CANCEL_COUNT - 1; i++)
      {
         for(int j = i + 1; j < CANCEL_COUNT; j++)
         {
            if(sortedCounts[j] > sortedCounts[i])
            {
               int tmpIdx = sortedIdx[i];
               int tmpCnt = sortedCounts[i];
               sortedIdx[i] = sortedIdx[j];
               sortedCounts[i] = sortedCounts[j];
               sortedIdx[j] = tmpIdx;
               sortedCounts[j] = tmpCnt;
            }
         }
      }
      
      string line = modeNames[m] + "(" + IntegerToString(modeTotal) + "): ";
      for(int i = 0; i < 3 && sortedCounts[i] > 0; i++)
      {
         double pct = (double)sortedCounts[i] / modeTotal * 100;
         line += GetCancelReasonName((ENUM_CANCEL_REASON)sortedIdx[i]) + "=" + 
                 IntegerToString(sortedCounts[i]) + "(" + DoubleToString(pct, 0) + "%) ";
      }
      Print("  ", line);
   }
   Print("====================");
}

//+------------------------------------------------------------------+
//| Print final summary (period summary)                               |
//+------------------------------------------------------------------+
void PrintFinalSummary()
{
   // Include current day in totals if not yet reset
   int totalDays = g_totalTradingDays;
   int totalTrades = g_totalTradesExecuted + g_tradesToday;
   double totalPnL = g_totalPnL + g_dailyPnL;
   int totalSL = g_totalSlHits + g_slHitsToday;
   
   // Add current day's cancel counters to totals for display
   int finalCounters[CANCEL_COUNT];
   for(int i = 0; i < CANCEL_COUNT; i++)
   {
      finalCounters[i] = g_totalCancelCounters[i] + g_cancelCounters[i];
   }
   
   // Add current day's 2D counters to totals
   int finalByMode[3][CANCEL_COUNT];
   for(int m = 0; m < 3; m++)
   {
      for(int r = 0; r < CANCEL_COUNT; r++)
      {
         finalByMode[m][r] = g_totalCancelByMode[m][r] + g_cancelByMode[m][r];
      }
   }
   
   // Add current day's microchoch counters to totals
   int finalMicroAttempted[3], finalMicroPass[3], finalMicroFailBreak[3], finalMicroFailBody[3];
   int finalModeTimeBars[3];
   for(int m = 0; m < 3; m++)
   {
      finalMicroAttempted[m] = g_totalMicrochochAttempted[m] + g_microchochAttempted[m];
      finalMicroPass[m] = g_totalMicrochochPass[m] + g_microchochPass[m];
      finalMicroFailBreak[m] = g_totalMicrochochFailBreak[m] + g_microchochFailBreak[m];
      finalMicroFailBody[m] = g_totalMicrochochFailBody[m] + g_microchochFailBody[m];
      finalModeTimeBars[m] = g_totalModeTimeBars[m] + g_modeTimeBars[m];
   }
   
   if(totalDays == 0 && g_tradesToday > 0)
      totalDays = 1;
   
   Print("========================================");
   Print("=== FINAL SUMMARY (Period Statistics) ===");
   Print("========================================");
   Print("Total trading days: ", totalDays);
   Print("Total trades executed: ", totalTrades);
   Print("Average trades/day: ", totalDays > 0 ? DoubleToString((double)totalTrades / totalDays, 2) : "0");
   Print("Total SL hits: ", totalSL);
   Print("Total PnL: ", DoubleToString(totalPnL, 2));
   Print("Policy: ", InpUseTargetFirstPolicy ? "TARGET-FIRST" : "TIME-BASED");
   Print("");
   
   // Exit Classification (All Time)
   int finalSlLossHits = g_totalSlLossHits + g_slLossHitsCount;
   int finalBeStops = g_totalBeStops + g_beStopCount;
   int finalTpHits = g_totalTpHits + g_tpHitsCount;
   int finalManualClose = g_totalManualClose + g_manualCloseCount;
   Print("--- Exit Classification (All Time) ---");
   int finalTrailStops = g_totalTrailStops + g_trailStopCount;
   Print("  SL_LOSS hits: ", finalSlLossHits, " (guardrail uses this)");
   Print("  BE stops: ", finalBeStops);
   Print("  TRAIL stops: ", finalTrailStops);
   Print("  TP hits: ", finalTpHits);
   Print("  Manual close: ", finalManualClose);
   Print("");
   
   // TP1 Partial Close diagnostics (All Time)
   int finalTP1Triggered = g_totalTP1PartialTriggered + g_tp1PartialTriggeredCount;
   int finalTP1Failed = g_totalTP1PartialFailed + g_tp1PartialFailedCount;
   int finalTP1Skipped = g_totalTP1PartialSkipped + g_tp1PartialSkippedCount;
   int finalBEMoved = g_totalBEMoved + g_beMovedCount;
   Print("--- TP1 Partial Close (All Time) ---");
   Print("  PartialTP1_triggers: ", finalTP1Triggered);
   Print("  PartialTP1_failed: ", finalTP1Failed);
   Print("  PartialTP1_skipped: ", finalTP1Skipped, " (TP1 too close)");
   Print("  BE_move_count: ", finalBEMoved);
   if(finalTP1Triggered > 0)
   {
      double successRate = (double)finalTP1Triggered / (finalTP1Triggered + finalTP1Failed) * 100;
      Print("  Success rate: ", DoubleToString(successRate, 1), "%");
   }
   Print("");
   
   // Trailing Stop diagnostics (All Time)
   int finalTrailAttempted = g_totalTrailAttempted + g_trailAttemptedCount;
   int finalTrailMoved = g_totalTrailMoved + g_trailMovedCount;
   int finalTrailReject = g_totalTrailReject + g_trailRejectCount;
   int finalTrailFailed = g_totalTrailFailed + g_trailFailedCount;
   Print("--- Trailing Stop (All Time) ---");
   Print("  Trail moves: ", finalTrailMoved);
   Print("  Trail rejects: ", finalTrailReject, " (stops/freeze constraints)");
   Print("  Trail failed: ", finalTrailFailed);
   
   // Top trail skip reasons (all time)
   int finalSkipCounts[6];
   string finalSkipNames[6];
   finalSkipCounts[0] = g_totalTrailSkippedCooldown + g_trailSkippedCooldown;
   finalSkipNames[0] = "cooldown";
   finalSkipCounts[1] = g_totalTrailSkippedStep + g_trailSkippedStep;
   finalSkipNames[1] = "step";
   finalSkipCounts[2] = g_totalTrailSkippedNotAfterPartial + g_trailSkippedNotAfterPartial;
   finalSkipNames[2] = "not_after_partial";
   finalSkipCounts[3] = g_totalTrailSkippedNotReachedR + g_trailSkippedNotReachedR;
   finalSkipNames[3] = "not_reached_R";
   finalSkipCounts[4] = g_totalTrailSkippedNewBar + g_trailSkippedNewBar;
   finalSkipNames[4] = "not_new_bar";
   finalSkipCounts[5] = 0;
   finalSkipNames[5] = "";
   
   // Sort and print top 3
   for(int i = 0; i < 4; i++)
   {
      for(int j = i + 1; j < 5; j++)
      {
         if(finalSkipCounts[j] > finalSkipCounts[i])
         {
            int tmpCnt = finalSkipCounts[i];
            string tmpName = finalSkipNames[i];
            finalSkipCounts[i] = finalSkipCounts[j];
            finalSkipNames[i] = finalSkipNames[j];
            finalSkipCounts[j] = tmpCnt;
            finalSkipNames[j] = tmpName;
         }
      }
   }
   string skipLineAll = "  Top skip reasons: ";
   for(int i = 0; i < 3 && finalSkipCounts[i] > 0; i++)
   {
      skipLineAll += finalSkipNames[i] + "=" + IntegerToString(finalSkipCounts[i]) + " ";
   }
   Print(skipLineAll);
   Print("");
   
   // Print mode time distribution
   Print("--- Mode Time Distribution (Bars) ---");
   int totalBars = finalModeTimeBars[0] + finalModeTimeBars[1] + finalModeTimeBars[2];
   string modeNamesTime[3] = {"STRICT", "RELAX", "RELAX2"};
   if(totalBars > 0)
   {
      for(int m = 0; m < 3; m++)
      {
         if(finalModeTimeBars[m] > 0)
         {
            double pct = (double)finalModeTimeBars[m] / totalBars * 100;
            Print("  ", modeNamesTime[m], ": ", finalModeTimeBars[m], " bars (", DoubleToString(pct, 1), "%)");
         }
      }
   }
   Print("");
   
   // Print microchoch diagnostics (ALL TIME)
   Print("--- Microchoch Diagnostics (All Time) ---");
   string modeNames[3] = {"STRICT", "RELAX", "RELAX2"};
   for(int m = 0; m < 3; m++)
   {
      if(finalMicroAttempted[m] > 0)
      {
         double passRate = (double)finalMicroPass[m] / finalMicroAttempted[m] * 100;
         Print("  ", modeNames[m], ": Attempted=", finalMicroAttempted[m], 
               " Pass=", finalMicroPass[m], " (", DoubleToString(passRate, 1), "%)",
               " FailBreak=", finalMicroFailBreak[m], 
               " FailBody=", finalMicroFailBody[m]);
      }
   }
   Print("");
   
   // Print cancel by mode (Top 5 per mode)
   Print("--- Cancel by Mode (Top 5 each) ---");
   for(int m = 0; m < 3; m++)
   {
      int modeTotal = 0;
      for(int r = 0; r < CANCEL_COUNT; r++) modeTotal += finalByMode[m][r];
      if(modeTotal == 0) continue;
      
      Print(modeNames[m], " (Total: ", modeTotal, ")");
      
      // Sort this mode's cancels
      int sortedIdx[CANCEL_COUNT];
      int sortedCounts[CANCEL_COUNT];
      for(int i = 0; i < CANCEL_COUNT; i++)
      {
         sortedIdx[i] = i;
         sortedCounts[i] = finalByMode[m][i];
      }
      for(int i = 0; i < CANCEL_COUNT - 1; i++)
      {
         for(int j = i + 1; j < CANCEL_COUNT; j++)
         {
            if(sortedCounts[j] > sortedCounts[i])
            {
               int tmpIdx = sortedIdx[i];
               int tmpCnt = sortedCounts[i];
               sortedIdx[i] = sortedIdx[j];
               sortedCounts[i] = sortedCounts[j];
               sortedIdx[j] = tmpIdx;
               sortedCounts[j] = tmpCnt;
            }
         }
      }
      
      for(int i = 0; i < 5 && sortedCounts[i] > 0; i++)
      {
         double pct = (double)sortedCounts[i] / modeTotal * 100;
         Print("    ", i+1, ". ", GetCancelReasonName((ENUM_CANCEL_REASON)sortedIdx[i]), 
               ": ", sortedCounts[i], " (", DoubleToString(pct, 1), "%)");
      }
   }
   Print("");
   
   // Print overall top 10
   Print("--- Top 10 Cancel Reasons (All Modes Combined) ---");
   int sortedIdx[];
   int sortedCounts[];
   ArrayResize(sortedIdx, CANCEL_COUNT);
   ArrayResize(sortedCounts, CANCEL_COUNT);
   
   for(int i = 0; i < CANCEL_COUNT; i++)
   {
      sortedIdx[i] = i;
      sortedCounts[i] = finalCounters[i];
   }
   
   for(int i = 0; i < CANCEL_COUNT - 1; i++)
   {
      for(int j = i + 1; j < CANCEL_COUNT; j++)
      {
         if(sortedCounts[j] > sortedCounts[i])
         {
            int tmpIdx = sortedIdx[i];
            int tmpCnt = sortedCounts[i];
            sortedIdx[i] = sortedIdx[j];
            sortedCounts[i] = sortedCounts[j];
            sortedIdx[j] = tmpIdx;
            sortedCounts[j] = tmpCnt;
         }
      }
   }
   
   int totalCancels = 0;
   for(int j = 0; j < CANCEL_COUNT; j++) totalCancels += finalCounters[j];
   
   Print("Total cancel events: ", totalCancels);
   for(int i = 0; i < 10 && i < CANCEL_COUNT; i++)
   {
      if(sortedCounts[i] > 0)
      {
         double pct = totalCancels > 0 ? (double)sortedCounts[i] / totalCancels * 100 : 0;
         Print("  ", i+1, ". ", GetCancelReasonName((ENUM_CANCEL_REASON)sortedIdx[i]), 
               ": ", sortedCounts[i], " (", DoubleToString(pct, 1), "%)");
      }
   }
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Reset setup state                                                  |
//+------------------------------------------------------------------+
void ResetSetup()
{
   g_state = STATE_WAIT_SWEEP;
   g_sweepType = SWEEP_NONE;
   g_sweepLevel = 0;
   g_sweepLiqType = LIQ_NONE;
   g_sweepBar = 0;
   g_chochLevel = 0;
   g_chochBar = 0;
   
   // Reset 2-stage CHOCH
   g_chochStage1 = false;
   g_chochStage1Level = 0;
   g_chochStage1Bar = 0;
   
   g_zoneHigh = 0;
   g_zoneLow = 0;
   g_zoneType = ZONE_NONE;
   g_zoneBar = 0;
   
   // Remove zone drawing
   ObjectDelete(0, g_objPrefix + "Zone");
}

//+------------------------------------------------------------------+
//| Handle cooldown period                                             |
//+------------------------------------------------------------------+
void HandleCooldown()
{
   g_cooldownCounter++;
   
   if(g_cooldownCounter >= InpCooldownBars)
   {
      ResetSetup();
      Print("Cooldown complete. Ready for new setup.");
   }
}

//+------------------------------------------------------------------+
//| Check if there's a pending order                                   |
//+------------------------------------------------------------------+
bool HasPendingOrder()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(orderInfo.SelectByIndex(i))
      {
         if(orderInfo.Symbol() == tradeSym)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check pending order status                                         |
//+------------------------------------------------------------------+
void CheckPendingOrder()
{
   // Pending order management if needed
}

//=== LOGGING FUNCTIONS ===
//+------------------------------------------------------------------+
//| Initialize logging files                                           |
//+------------------------------------------------------------------+
void InitLogging()
{
   // Trades log
   g_tradesFileHandle = FileOpen("SMC_trades.csv", FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(g_tradesFileHandle != INVALID_HANDLE)
   {
      FileWrite(g_tradesFileHandle,
         "timestamp_open", "timestamp_close", "symbol", "direction", "lot",
         "entry", "sl", "tp1", "tp2", "spread_points_open", "spread_points_avg",
         "sl_buffer_points", "setup_type", "sweep_level_type", "mfe_points",
         "mae_points", "result", "r_multiple", "martingale_level", "comment");
      FileClose(g_tradesFileHandle);
   }
   
   // Setups log
   g_setupsFileHandle = FileOpen("SMC_setups.csv", FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(g_setupsFileHandle != INVALID_HANDLE)
   {
      FileWrite(g_setupsFileHandle,
         "timestamp", "state_reached", "reason_cancel", "bias",
         "sweep_detected", "choch_detected", "zone_type", "zone_price_range",
         "distance_to_tp1_points");
      FileClose(g_setupsFileHandle);
   }
}

//+------------------------------------------------------------------+
//| Initialize CSV logging for daily summary                           |
//+------------------------------------------------------------------+
void InitCSVLogging()
{
   // Create folder if needed
   FolderCreate(InpCSVFolder, FILE_COMMON);
   
   // Create filename with date
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_csvFileName = StringFormat("%s/daily_summary_%04d%02d.csv", 
                                InpCSVFolder, dt.year, dt.mon);
   
   // Check if file exists, if not create with header
   g_csvFileHandle = FileOpen(g_csvFileName, FILE_READ|FILE_CSV|FILE_COMMON);
   if(g_csvFileHandle == INVALID_HANDLE)
   {
      // Create new file with header
      g_csvFileHandle = FileOpen(g_csvFileName, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(g_csvFileHandle != INVALID_HANDLE)
      {
         FileWrite(g_csvFileHandle,
            "date", "trades", "sl_hits", "pnl", "start_equity", "end_equity",
            "cancel_spread", "cancel_spike", "cancel_no_sweep", "cancel_no_choch",
            "cancel_no_retrace", "cancel_timefilter", "cancel_bias_none",
            "cancel_cooldown", "cancel_no_trade_zone", "cancel_hard_block",
            "cancel_sl_blocked", "cancel_max_trades", "cancel_consec_losses",
            "cancel_daily_loss", "cancel_other");
         FileClose(g_csvFileHandle);
      }
   }
   else
   {
      FileClose(g_csvFileHandle);
   }
   
   Print("CSV logging initialized: ", g_csvFileName);
}

//+------------------------------------------------------------------+
//| Write daily entry to CSV                                           |
//+------------------------------------------------------------------+
void WriteCSVDailyEntry()
{
   if(!InpEnableCSVLogging) return;
   
   // Open file for append
   int handle = FileOpen(g_csvFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("Error opening CSV file for writing: ", GetLastError());
      return;
   }
   
   FileSeek(handle, 0, SEEK_END);
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string dateStr = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
   
   double endEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   FileWrite(handle,
      dateStr,
      g_tradesToday,
      g_slHitsToday,
      DoubleToString(g_dailyPnL, 2),
      DoubleToString(g_dailyStartEquity, 2),
      DoubleToString(endEquity, 2),
      g_cancelCounters[CANCEL_SPREAD],
      g_cancelCounters[CANCEL_SPREAD_SPIKE],
      g_cancelCounters[CANCEL_NO_SWEEP],
      g_cancelCounters[CANCEL_NO_CHOCH],
      g_cancelCounters[CANCEL_NO_RETRACE],
      g_cancelCounters[CANCEL_TIMEFILTER],
      g_cancelCounters[CANCEL_BIAS_NONE],
      g_cancelCounters[CANCEL_COOLDOWN],
      g_cancelCounters[CANCEL_NO_TRADE_ZONE],
      g_cancelCounters[CANCEL_HARD_BLOCK],
      g_cancelCounters[CANCEL_SL_BLOCKED],
      g_cancelCounters[CANCEL_MAX_TRADES_DAY],
      g_cancelCounters[CANCEL_CONSECUTIVE_LOSSES],
      g_cancelCounters[CANCEL_DAILY_LOSS],
      g_cancelCounters[CANCEL_OTHER]);
   
   FileClose(handle);
   Print("CSV daily entry written for ", dateStr);
}

//+------------------------------------------------------------------+
//| Log trade to CSV                                                   |
//+------------------------------------------------------------------+
void LogTrade(string result, double pnl)
{
   if(!InpEnableLogging) return;
   
   int handle = FileOpen("SMC_trades.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return;
   
   FileSeek(handle, 0, SEEK_END);
   
   double rMultiple = 0;
   if(g_slPrice != 0 && g_entryPrice != 0)
   {
      double risk = MathAbs(g_entryPrice - g_slPrice);
      if(risk > 0)
         rMultiple = pnl / (risk * g_currentLot * 100);
   }
   
   string direction = (g_sweepType == SWEEP_BULLISH) ? "LONG" : "SHORT";
   string setupType = StringFormat("sweep+choch+%s", EnumToString(g_zoneType));
   
   FileWrite(handle,
      TimeToString(TimeCurrent() - 300, TIME_DATE|TIME_MINUTES),
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      tradeSym,
      direction,
      DoubleToString(g_currentLot, 2),
      DoubleToString(g_entryPrice, _Digits),
      DoubleToString(g_slPrice, _Digits),
      DoubleToString(g_tp1Price, _Digits),
      DoubleToString(g_tp2Price, _Digits),
      DoubleToString(GetSpreadPoints(), 1),
      DoubleToString(GetSpreadPoints(), 1),
      IntegerToString(InpSLBufferPoints),
      setupType,
      EnumToString(g_sweepLiqType),
      "0", // MFE - would need tracking
      "0", // MAE - would need tracking
      result,
      DoubleToString(rMultiple, 2),
      IntegerToString(g_martLevel),
      "");
   
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Log setup to CSV                                                   |
//+------------------------------------------------------------------+
void LogSetup(string stateReached, string reasonCancel, ENUM_BIAS bias,
              bool sweepDetected, bool chochDetected, ENUM_ZONE_TYPE zoneType,
              double zoneLow, double zoneHigh, double distToTP1)
{
   if(!InpEnableLogging) return;
   
   int handle = FileOpen("SMC_setups.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return;
   
   FileSeek(handle, 0, SEEK_END);
   
   string zoneRange = (zoneHigh > 0 && zoneLow > 0) ? 
                      StringFormat("%.2f-%.2f", zoneLow, zoneHigh) : "";
   
   FileWrite(handle,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      stateReached,
      reasonCancel,
      EnumToString(bias),
      sweepDetected ? "true" : "false",
      chochDetected ? "true" : "false",
      EnumToString(zoneType),
      zoneRange,
      DoubleToString(distToTP1, 1));
   
   FileClose(handle);
}

//=== VISUAL FUNCTIONS ===
//+------------------------------------------------------------------+
//| Draw liquidity levels                                              |
//+------------------------------------------------------------------+
void DrawLiquidityLevels()
{
   datetime startTime = iTime(tradeSym, PERIOD_D1, 1);
   datetime endTime = TimeCurrent() + 3600;
   
   // PDH
   DrawHLine(g_objPrefix + "PDH", g_pdh, InpColorPDH, STYLE_DASH, "PDH");
   
   // PDL
   DrawHLine(g_objPrefix + "PDL", g_pdl, InpColorPDL, STYLE_DASH, "PDL");
   
   // Session High
   DrawHLine(g_objPrefix + "SessionH", g_sessionHigh, InpColorSessionH, STYLE_DOT, "Session H");
   
   // Session Low
   DrawHLine(g_objPrefix + "SessionL", g_sessionLow, InpColorSessionL, STYLE_DOT, "Session L");
}

//+------------------------------------------------------------------+
//| Draw horizontal line                                               |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style, string label)
{
   if(price <= 0) return;
   
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   }
   
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Draw zone rectangle                                                |
//+------------------------------------------------------------------+
void DrawZone()
{
   string name = g_objPrefix + "Zone";
   datetime startTime = iTime(tradeSym, InpEntryTF, g_zoneBar + 5);
   datetime endTime = TimeCurrent() + 3600;
   
   color zoneColor = (g_zoneType == ZONE_FVG) ? InpColorFVG : InpColorOB;
   
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, startTime, g_zoneHigh, endTime, g_zoneLow);
   }
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, g_zoneHigh);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, g_zoneLow);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, startTime);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
}

//+------------------------------------------------------------------+
//| Update info panel                                                  |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   string panelName = g_objPrefix + "Panel";
   
   // Delete old labels
   for(int i = 0; i < 20; i++)
   {
      ObjectDelete(0, panelName + IntegerToString(i));
   }
   
   int x = 10, y = 30, lineHeight = 16;
   color textColor = clrWhite;
   
   // Panel background - increased height for cancel counters
   string bgName = panelName + "BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 5);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 5);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 320);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, lineHeight * 17);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // Create labels
   CreateLabel(panelName + "0", x, y, "SMC Scalp Bot v3.1", textColor);
   
   // Trade Mode display with color (Tiered RELAX)
   string modeStr;
   color modeColor;
   switch(g_tradeMode)
   {
      case MODE_RELAX2:
         modeStr = "RELAX2";
         modeColor = clrOrange;
         break;
      case MODE_RELAX:
         modeStr = "RELAX";
         modeColor = clrYellow;
         break;
      default:
         modeStr = "STRICT";
         modeColor = clrLime;
         break;
   }
   CreateLabel(panelName + "1", x, y + lineHeight, "Mode: " + modeStr, modeColor);
   
   CreateLabel(panelName + "2", x, y + lineHeight*2, "State: " + GetStateString(), textColor);
   CreateLabel(panelName + "3", x, y + lineHeight*3, "Bias: " + EnumToString(g_bias), textColor);
   
   // Spread display with details: cur / avg / limit
   int spreadLimit = GetCurrentSpreadLimit();
   color spreadColor = (g_currentSpread > spreadLimit) ? clrRed : textColor;
   CreateLabel(panelName + "4", x, y + lineHeight*4, 
               StringFormat("Spread: %.1f/%.1f/%d (%s)", g_currentSpread, g_avgSpread, spreadLimit, modeStr), 
               spreadColor);
   
   // Trades with target info
   CreateLabel(panelName + "5", x, y + lineHeight*5, 
               StringFormat("Trades: %d/%d (T:%d)", g_tradesToday, InpMaxTradesPerDay, InpTargetTradesPerDay),
               g_tradesToday >= InpTargetTradesPerDay ? clrLime : textColor);
   
   CreateLabel(panelName + "6", x, y + lineHeight*6, StringFormat("Losses: %d/%d", g_consecLosses, InpMaxConsecLosses), 
               g_consecLosses >= InpMaxConsecLosses ? clrRed : textColor);
   CreateLabel(panelName + "7", x, y + lineHeight*7, StringFormat("Mart Lvl: %d", g_martLevel), textColor);
   
   double dailyPct = (g_dailyStartEquity > 0) ? (g_dailyPnL / g_dailyStartEquity * 100) : 0;
   CreateLabel(panelName + "8", x, y + lineHeight*8, StringFormat("Daily PnL: %.2f%%", dailyPct), 
               dailyPct < 0 ? clrRed : clrLime);
   
   // SL Hits display
   CreateLabel(panelName + "9", x, y + lineHeight*9, StringFormat("SL Hits: %d/%d", g_slHitsToday, InpMaxSLHitsPerDay),
               g_slHitsToday >= InpMaxSLHitsPerDay ? clrRed : textColor);
   
   // Blocked status
   string blockedStr = g_blockedToday ? "YES" : "NO";
   CreateLabel(panelName + "10", x, y + lineHeight*10, "Blocked: " + blockedStr,
               g_blockedToday ? clrRed : clrLime);
   
   // Last cancel reason
   string cancelStr = g_lastCancelReason;
   if(cancelStr == "") cancelStr = "-";
   color cancelColor = clrGray;
   if(cancelStr == "spread" || cancelStr == "spread_spike") cancelColor = clrYellow;
   if(cancelStr == "no_trade_zone" || cancelStr == "hard_block_after") cancelColor = clrRed;
   CreateLabel(panelName + "11", x, y + lineHeight*11, "LastCancel: " + cancelStr, cancelColor);
   
   // No-trade zone status
   int currentHHMM = GetCurrentHHMM();
   bool inNoTrade = IsInNoTradeZone() || IsHardBlockTime();
   string noTradeStr = inNoTrade ? StringFormat("ON (%04d)", currentHHMM) : "OFF";
   color noTradeColor = inNoTrade ? clrRed : clrLime;
   CreateLabel(panelName + "12", x, y + lineHeight*12, "NoTradeZone: " + noTradeStr, noTradeColor);
   
   // Switch hour info (show tiered hours and hard block)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string switchInfo = StringFormat("R@%d R2@%d Block@%04d (Now:%d)", InpRelaxSwitchHour, InpRelax2Hour, InpHardBlockAfterHHMM, dt.hour);
   CreateLabel(panelName + "13", x, y + lineHeight*13, switchInfo, clrGray);
   
   // Cancel counters - Top 3 (sorted by count)
   string top3Str = GetTop3CancelReasons();
   CreateLabel(panelName + "14", x, y + lineHeight*14, "Top3: " + top3Str, clrGray);
   
   // Total cancel count today
   int totalCancels = 0;
   for(int i = 0; i < CANCEL_COUNT; i++) totalCancels += g_cancelCounters[i];
   CreateLabel(panelName + "15", x, y + lineHeight*15, StringFormat("TotalCancels: %d", totalCancels), clrGray);
}

//+------------------------------------------------------------------+
//| Get top 3 cancel reasons as string                                 |
//+------------------------------------------------------------------+
string GetTop3CancelReasons()
{
   // Sort cancel counters
   int sortedIdx[];
   int sortedCounts[];
   ArrayResize(sortedIdx, CANCEL_COUNT);
   ArrayResize(sortedCounts, CANCEL_COUNT);
   
   for(int i = 0; i < CANCEL_COUNT; i++)
   {
      sortedIdx[i] = i;
      sortedCounts[i] = g_cancelCounters[i];
   }
   
   // Simple bubble sort by count descending
   for(int i = 0; i < CANCEL_COUNT - 1; i++)
   {
      for(int j = i + 1; j < CANCEL_COUNT; j++)
      {
         if(sortedCounts[j] > sortedCounts[i])
         {
            int tmpIdx = sortedIdx[i];
            int tmpCnt = sortedCounts[i];
            sortedIdx[i] = sortedIdx[j];
            sortedCounts[i] = sortedCounts[j];
            sortedIdx[j] = tmpIdx;
            sortedCounts[j] = tmpCnt;
         }
      }
   }
   
   // Build top 3 string
   string result = "";
   for(int i = 0; i < 3 && i < CANCEL_COUNT; i++)
   {
      if(sortedCounts[i] > 0)
      {
         if(result != "") result += " ";
         result += StringFormat("%s=%d", GetCancelReasonName((ENUM_CANCEL_REASON)sortedIdx[i]), sortedCounts[i]);
      }
   }
   
   if(result == "") result = "-";
   return result;
}

//+------------------------------------------------------------------+
//| Create text label                                                  |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Get state as string                                                |
//+------------------------------------------------------------------+
string GetStateString()
{
   switch(g_state)
   {
      case STATE_WAIT_SWEEP:   return "WAIT_SWEEP";
      case STATE_WAIT_CHOCH:   return "WAIT_CHOCH";
      case STATE_WAIT_RETRACE: return "WAIT_RETRACE";
      case STATE_PLACE_ORDER:  return "PLACE_ORDER";
      case STATE_MANAGE_TRADE: return "MANAGE_TRADE";
      case STATE_COOLDOWN:     return "COOLDOWN";
      default:                 return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
