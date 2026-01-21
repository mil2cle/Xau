//+------------------------------------------------------------------+
//|                    SMC_Scalp_Martingale_XAUUSD_iux.mq5           |
//|                    SMC Scalping Bot v1.0                         |
//|                    For DEMO Account Only - XAUUSD.iux            |
//+------------------------------------------------------------------+
#property copyright "SMC Scalping Bot v1.0"
#property link      ""
#property version   "1.00"
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

//=== INPUT PARAMETERS ===
input group "=== Symbol & Timeframe ==="
input string   InpSymbol            = "XAUUSD.iux";    // Symbol
input ENUM_TIMEFRAMES InpBiasTF     = PERIOD_M15;     // Bias Timeframe
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M5;      // Entry Timeframe

input group "=== SMC Parameters ==="
input int      InpSwingK            = 2;              // Swing lookback (fractal)
input int      InpEqThresholdPoints = 80;             // EQH/EQL threshold (points)
input int      InpReclaimMaxBars    = 2;              // Reclaim max bars after sweep
input int      InpSweepBreakPoints  = 30;             // Min sweep break (points)
input int      InpConfirmMaxBars    = 6;              // CHOCH confirm max bars
input int      InpEntryTimeoutBars  = 10;             // Entry timeout bars

input group "=== SL/TP Parameters ==="
input int      InpSLBufferPoints    = 40;             // SL buffer min (points)
input double   InpPartialClosePercent = 50.0;         // Partial close % at TP1/1R

input group "=== Risk Guardrails ==="
input int      InpSpreadMax         = 30;             // Max spread (points)
input int      InpCooldownBars      = 3;              // Cooldown bars after close
input int      InpMaxTradesPerDay   = 6;              // Max trades per day
input int      InpMaxConsecLosses   = 3;              // Max consecutive losses
input double   InpDailyLossLimitPct = 2.0;            // Daily loss limit (%)

input group "=== Time Filter ==="
input string   InpTradeStart        = "14:00";        // Trade start time (server)
input string   InpTradeEnd          = "23:30";        // Trade end time (server)

input group "=== Martingale ==="
input ENUM_MARTINGALE_MODE InpMartingaleMode = MART_AFTER_LOSS; // Martingale mode
input double   InpBaseLot           = 0.01;           // Base lot
input double   InpMartMultiplier    = 2.0;            // Martingale multiplier
input int      InpMartMaxLevel      = 3;              // Max martingale level
input double   InpLotCapMax         = 0.08;           // Max lot cap

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

// Martingale
int            g_martLevel = 0;
double         g_currentLot = 0;

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

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(Symbol() != InpSymbol)
   {
      Print("Warning: EA designed for ", InpSymbol, " but attached to ", Symbol());
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(123456);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize lot
   g_currentLot = InpBaseLot;
   
   // Initialize daily tracking
   ResetDailyCounters();
   
   // Initialize logging
   if(InpEnableLogging)
   {
      InitLogging();
   }
   
   // Set timer for periodic updates
   EventSetTimer(1);
   
   // Initial calculations
   CalculateLiquidityLevels();
   
   Print("SMC Scalping Bot v1.0 initialized on ", InpSymbol);
   Print("Bias TF: ", EnumToString(InpBiasTF), " | Entry TF: ", EnumToString(InpEntryTF));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Close log files
   if(g_tradesFileHandle != INVALID_HANDLE)
      FileClose(g_tradesFileHandle);
   if(g_setupsFileHandle != INVALID_HANDLE)
      FileClose(g_setupsFileHandle);
   
   // Remove visual objects
   ObjectsDeleteAll(0, g_objPrefix);
   
   Print("SMC Scalping Bot deinitialized. Reason: ", reason);
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
   // Check for new day
   CheckNewDay();
   
   // Update liquidity levels periodically
   static datetime lastLiqUpdate = 0;
   if(TimeCurrent() - lastLiqUpdate > 60)
   {
      CalculateLiquidityLevels();
      lastLiqUpdate = TimeCurrent();
   }
   
   // Draw visuals
   if(InpShowLiquidity)
      DrawLiquidityLevels();
   
   // Check if we have open position
   if(PositionSelect(InpSymbol))
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
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // A deal was added - check if it's ours
      if(trans.symbol == InpSymbol)
      {
         // Will be handled in ManageTrade
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
   
   int k = InpSwingK;
   
   for(int i = k; i < lookback - k; i++)
   {
      double high_i = iHigh(InpSymbol, tf, i);
      double low_i = iLow(InpSymbol, tf, i);
      
      bool isSwingHigh = true;
      bool isSwingLow = true;
      
      for(int j = 1; j <= k; j++)
      {
         if(high_i <= iHigh(InpSymbol, tf, i - j) || high_i <= iHigh(InpSymbol, tf, i + j))
            isSwingHigh = false;
         if(low_i >= iLow(InpSymbol, tf, i - j) || low_i >= iLow(InpSymbol, tf, i + j))
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
   g_pdh = iHigh(InpSymbol, PERIOD_D1, 1);
   g_pdl = iLow(InpSymbol, PERIOD_D1, 1);
   
   // Session High/Low (current day)
   CalculateSessionHighLow();
   
   // EQH/EQL
   CalculateEqualHighsLows();
   
   // Store swing levels
   DetectSwings(InpEntryTF, g_m5SwingHighs, g_m5SwingLows, g_m5SwingHighBars, g_m5SwingLowBars, 100);
   DetectSwings(InpBiasTF, g_m15SwingHighs, g_m15SwingLows, g_m15SwingHighBars, g_m15SwingLowBars, 100);
}

//+------------------------------------------------------------------+
//| Calculate session high/low                                         |
//+------------------------------------------------------------------+
void CalculateSessionHighLow()
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   g_sessionHigh = 0;
   g_sessionLow = DBL_MAX;
   
   int bars = iBars(InpSymbol, InpEntryTF);
   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(InpSymbol, InpEntryTF, i);
      if(barTime < dayStart)
         break;
      
      double high = iHigh(InpSymbol, InpEntryTF, i);
      double low = iLow(InpSymbol, InpEntryTF, i);
      
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
   
   if(g_bias == BIAS_NONE)
   {
      LogSetup("WAIT_SWEEP", "nobias", g_bias, false, false, ZONE_NONE, 0, 0, 0);
      return;
   }
   
   double sweepBreak = MathMax(InpSweepBreakPoints, (int)MathCeil(2 * GetSpreadPoints())) * _Point;
   
   // Check for sweep based on bias
   if(g_bias == BIAS_BULLISH)
   {
      // Look for sweep down (liquidity grab below)
      if(CheckSweepDown(sweepBreak))
      {
         g_sweepType = SWEEP_BULLISH;
         g_state = STATE_WAIT_CHOCH;
         Print("Sweep DOWN detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ")");
      }
   }
   else if(g_bias == BIAS_BEARISH)
   {
      // Look for sweep up (liquidity grab above)
      if(CheckSweepUp(sweepBreak))
      {
         g_sweepType = SWEEP_BEARISH;
         g_state = STATE_WAIT_CHOCH;
         Print("Sweep UP detected at ", g_sweepLevel, " (", EnumToString(g_sweepLiqType), ")");
      }
   }
}

//+------------------------------------------------------------------+
//| Check for sweep down (below liquidity)                             |
//+------------------------------------------------------------------+
bool CheckSweepDown(double sweepBreak)
{
   // Check liquidity levels: PDL, Session Low, EQL, Swing Lows
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
      double high = iHigh(InpSymbol, InpEntryTF, bar);
      double low = iLow(InpSymbol, InpEntryTF, bar);
      double close = iClose(InpSymbol, InpEntryTF, bar);
      
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
//| Look for Change of Character                                       |
//+------------------------------------------------------------------+
void LookForChoCH()
{
   // Check timeout
   int barsSinceSweep = g_sweepBar;
   if(barsSinceSweep > InpConfirmMaxBars)
   {
      LogSetup("WAIT_CHOCH", "timeout", g_bias, true, false, ZONE_NONE, 0, 0, 0);
      ResetSetup();
      return;
   }
   
   int minorSwingBar;
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      // After sweep down, look for bullish CHOCH (close above minor swing high)
      double minorSwingHigh = GetLatestMinorSwingHigh(InpEntryTF, minorSwingBar);
      
      if(minorSwingHigh > 0 && minorSwingBar > 0)
      {
         double close = iClose(InpSymbol, InpEntryTF, 0);
         if(close > minorSwingHigh)
         {
            g_chochLevel = minorSwingHigh;
            g_chochBar = 0;
            g_state = STATE_WAIT_RETRACE;
            
            // Build zones
            BuildZones(true);
            
            Print("Bullish CHOCH confirmed at ", g_chochLevel);
         }
      }
   }
   else if(g_sweepType == SWEEP_BEARISH)
   {
      // After sweep up, look for bearish CHOCH (close below minor swing low)
      double minorSwingLow = GetLatestMinorSwingLow(InpEntryTF, minorSwingBar);
      
      if(minorSwingLow > 0 && minorSwingBar > 0)
      {
         double close = iClose(InpSymbol, InpEntryTF, 0);
         if(close < minorSwingLow)
         {
            g_chochLevel = minorSwingLow;
            g_chochBar = 0;
            g_state = STATE_WAIT_RETRACE;
            
            // Build zones
            BuildZones(false);
            
            Print("Bearish CHOCH confirmed at ", g_chochLevel);
         }
      }
   }
   
   g_sweepBar++;
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
      double high1 = iHigh(InpSymbol, InpEntryTF, i);
      double low1 = iLow(InpSymbol, InpEntryTF, i);
      double high3 = iHigh(InpSymbol, InpEntryTF, i + 2);
      double low3 = iLow(InpSymbol, InpEntryTF, i + 2);
      
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
      double open_i = iOpen(InpSymbol, InpEntryTF, i);
      double close_i = iClose(InpSymbol, InpEntryTF, i);
      double high_i = iHigh(InpSymbol, InpEntryTF, i);
      double low_i = iLow(InpSymbol, InpEntryTF, i);
      
      if(isBullish)
      {
         // Bullish OB = bearish candle before impulse up
         if(close_i < open_i)
         {
            // Check if next candle is bullish impulse
            double close_next = iClose(InpSymbol, InpEntryTF, i - 1);
            double open_next = iOpen(InpSymbol, InpEntryTF, i - 1);
            
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
            double close_next = iClose(InpSymbol, InpEntryTF, i - 1);
            double open_next = iOpen(InpSymbol, InpEntryTF, i - 1);
            
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
   // Check timeout
   g_zoneBar++;
   if(g_zoneBar > InpEntryTimeoutBars)
   {
      LogSetup("WAIT_RETRACE", "timeout", g_bias, true, true, g_zoneType, g_zoneLow, g_zoneHigh, 0);
      ResetSetup();
      return;
   }
   
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   
   // Check if price is in zone
   if(g_sweepType == SWEEP_BULLISH)
   {
      // For long: price should retrace down into zone
      if(bid <= g_zoneHigh && bid >= g_zoneLow)
      {
         g_state = STATE_PLACE_ORDER;
         Print("Price retraced into zone for LONG entry");
      }
   }
   else if(g_sweepType == SWEEP_BEARISH)
   {
      // For short: price should retrace up into zone
      if(ask >= g_zoneLow && ask <= g_zoneHigh)
      {
         g_state = STATE_PLACE_ORDER;
         Print("Price retraced into zone for SHORT entry");
      }
   }
}

//+------------------------------------------------------------------+
//| Place order                                                        |
//+------------------------------------------------------------------+
void PlaceOrder()
{
   // Final risk check
   if(!PassRiskChecks())
   {
      ResetSetup();
      return;
   }
   
   // Calculate SL/TP
   CalculateSLTP();
   
   // Get current lot based on martingale
   g_currentLot = CalculateLot();
   
   double price, sl, tp;
   ENUM_ORDER_TYPE orderType;
   
   if(g_sweepType == SWEEP_BULLISH)
   {
      orderType = ORDER_TYPE_BUY;
      price = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
      sl = g_slPrice;
      tp = g_tp1Price;
   }
   else
   {
      orderType = ORDER_TYPE_SELL;
      price = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
      sl = g_slPrice;
      tp = g_tp1Price;
   }
   
   // Normalize prices
   price = NormalizeDouble(price, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   string comment = StringFormat("SMC_%s_L%d", 
                                 g_sweepType == SWEEP_BULLISH ? "LONG" : "SHORT",
                                 g_martLevel);
   
   if(trade.PositionOpen(InpSymbol, orderType, g_currentLot, price, sl, tp, comment))
   {
      g_currentTicket = trade.ResultOrder();
      g_entryPrice = price;
      g_partialClosed = false;
      g_tradesToday++;
      g_state = STATE_MANAGE_TRADE;
      
      Print("Order placed: ", EnumToString(orderType), " Lot: ", g_currentLot, 
            " Entry: ", price, " SL: ", sl, " TP1: ", tp);
      
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
      
      // TP2: further liquidity
      g_tp2Price = GetFurtherLiquidity(true);
   }
   else
   {
      // Short: SL above sweep high
      double sweepHigh = GetSweepExtreme(true);
      g_slPrice = sweepHigh + slBuffer;
      
      // TP1: nearest opposite liquidity
      g_tp1Price = GetNearestOppositeLiquidity(false);
      
      // TP2: further liquidity
      g_tp2Price = GetFurtherLiquidity(false);
   }
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
         double h = iHigh(InpSymbol, InpEntryTF, i);
         if(h > extreme) extreme = h;
      }
      else
      {
         double l = iLow(InpSymbol, InpEntryTF, i);
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
   double currentPrice = SymbolInfoDouble(InpSymbol, isLong ? SYMBOL_ASK : SYMBOL_BID);
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
//| Manage open trade                                                  |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!PositionSelect(InpSymbol))
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
   
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(InpSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   
   double riskPoints = MathAbs(posOpenPrice - posSL);
   double profitPoints = MathAbs(currentPrice - posOpenPrice);
   
   // Check for partial close at TP1 or 1R
   if(!g_partialClosed)
   {
      bool atTP1 = false;
      bool at1R = profitPoints >= riskPoints;
      
      if(posType == POSITION_TYPE_BUY)
         atTP1 = currentPrice >= g_tp1Price;
      else
         atTP1 = currentPrice <= g_tp1Price;
      
      if(atTP1 || at1R)
      {
         // Partial close
         double closeVolume = NormalizeDouble(posVolume * InpPartialClosePercent / 100.0, 2);
         if(closeVolume >= 0.01)
         {
            if(trade.PositionClosePartial(InpSymbol, closeVolume))
            {
               g_partialClosed = true;
               
               // Move SL to BE + spread
               double spreadPoints = GetSpreadPoints();
               double newSL;
               
               if(posType == POSITION_TYPE_BUY)
                  newSL = posOpenPrice + spreadPoints * _Point;
               else
                  newSL = posOpenPrice - spreadPoints * _Point;
               
               trade.PositionModify(InpSymbol, newSL, g_tp2Price);
               
               Print("Partial close done. New SL: ", newSL, " New TP: ", g_tp2Price);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check trade result after close                                     |
//+------------------------------------------------------------------+
void CheckTradeResult()
{
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
      g_consecLosses = 0;
      g_martLevel = 0;
      g_currentLot = InpBaseLot;
   }
   else if(totalPnL < 0)
   {
      result = "lose";
      g_consecLosses++;
      
      // Martingale adjustment
      if(InpMartingaleMode == MART_AFTER_LOSS && g_martLevel < InpMartMaxLevel)
      {
         g_martLevel++;
      }
   }
   else
   {
      result = "breakeven";
   }
   
   // Log trade
   LogTrade(result, totalPnL);
   
   Print("Trade closed: ", result, " PnL: ", totalPnL, " Consec losses: ", g_consecLosses);
}

//=== RISK MANAGEMENT ===
//+------------------------------------------------------------------+
//| Check all risk conditions                                          |
//+------------------------------------------------------------------+
bool PassRiskChecks()
{
   // Time filter
   if(!IsWithinTradingHours())
   {
      return false;
   }
   
   // Spread check
   double spreadPoints = GetSpreadPoints();
   if(spreadPoints > InpSpreadMax)
   {
      return false;
   }
   
   // Max trades per day
   if(g_tradesToday >= InpMaxTradesPerDay)
   {
      return false;
   }
   
   // Consecutive losses
   if(g_consecLosses >= InpMaxConsecLosses)
   {
      return false;
   }
   
   // Daily loss limit
   double dailyLossLimit = g_dailyStartEquity * InpDailyLossLimitPct / 100.0;
   if(g_dailyPnL <= -dailyLossLimit)
   {
      return false;
   }
   
   // No overlapping positions
   if(PositionSelect(InpSymbol))
   {
      return false;
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
//| Get bias from M15                                                  |
//+------------------------------------------------------------------+
ENUM_BIAS GetBias()
{
   int barIndex;
   double close = iClose(InpSymbol, InpBiasTF, 0);
   
   double minorSwingHigh = GetLatestMinorSwingHigh(InpBiasTF, barIndex);
   double minorSwingLow = GetLatestMinorSwingLow(InpBiasTF, barIndex);
   
   if(minorSwingHigh > 0 && close > minorSwingHigh)
      return BIAS_BULLISH;
   
   if(minorSwingLow > 0 && close < minorSwingLow)
      return BIAS_BEARISH;
   
   return BIAS_NONE;
}

//+------------------------------------------------------------------+
//| Calculate lot size with martingale                                 |
//+------------------------------------------------------------------+
double CalculateLot()
{
   double lot = InpBaseLot;
   
   if(InpMartingaleMode == MART_AFTER_LOSS && g_martLevel > 0)
   {
      lot = InpBaseLot * MathPow(InpMartMultiplier, g_martLevel);
   }
   
   // Apply cap
   lot = MathMin(lot, InpLotCapMax);
   
   // Normalize
   double minLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   
   return NormalizeDouble(lot, 2);
}

//=== UTILITY FUNCTIONS ===
//+------------------------------------------------------------------+
//| Get spread in points                                               |
//+------------------------------------------------------------------+
double GetSpreadPoints()
{
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   return (ask - bid) / _Point;
}

//+------------------------------------------------------------------+
//| Get ATR value                                                      |
//+------------------------------------------------------------------+
double GetATR(int period)
{
   int handle = iATR(InpSymbol, InpEntryTF, period);
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
   g_tradesToday = 0;
   g_consecLosses = 0;
   g_dailyPnL = 0;
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_martLevel = 0;
   g_currentLot = InpBaseLot;
   
   Print("Daily counters reset. Start equity: ", g_dailyStartEquity);
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
         if(orderInfo.Symbol() == InpSymbol)
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
      InpSymbol,
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
   datetime startTime = iTime(InpSymbol, PERIOD_D1, 1);
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
   datetime startTime = iTime(InpSymbol, InpEntryTF, g_zoneBar + 5);
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
   for(int i = 0; i < 10; i++)
   {
      ObjectDelete(0, panelName + IntegerToString(i));
   }
   
   int x = 10, y = 30, lineHeight = 18;
   color textColor = clrWhite;
   
   // Panel background
   string bgName = panelName + "BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 5);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 5);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 200);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, lineHeight * 9);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // Create labels
   CreateLabel(panelName + "0", x, y, "SMC Scalp Bot v1.0", textColor);
   CreateLabel(panelName + "1", x, y + lineHeight, "State: " + GetStateString(), textColor);
   CreateLabel(panelName + "2", x, y + lineHeight*2, "Bias: " + EnumToString(g_bias), textColor);
   CreateLabel(panelName + "3", x, y + lineHeight*3, StringFormat("Spread: %.1f pts", GetSpreadPoints()), 
               GetSpreadPoints() > InpSpreadMax ? clrRed : textColor);
   CreateLabel(panelName + "4", x, y + lineHeight*4, StringFormat("Trades: %d/%d", g_tradesToday, InpMaxTradesPerDay), textColor);
   CreateLabel(panelName + "5", x, y + lineHeight*5, StringFormat("Losses: %d/%d", g_consecLosses, InpMaxConsecLosses), 
               g_consecLosses >= InpMaxConsecLosses ? clrRed : textColor);
   CreateLabel(panelName + "6", x, y + lineHeight*6, StringFormat("Mart Lvl: %d", g_martLevel), textColor);
   
   double dailyPct = (g_dailyStartEquity > 0) ? (g_dailyPnL / g_dailyStartEquity * 100) : 0;
   CreateLabel(panelName + "7", x, y + lineHeight*7, StringFormat("Daily PnL: %.2f%%", dailyPct), 
               dailyPct < 0 ? clrRed : clrLime);
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
