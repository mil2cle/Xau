# CHANGELOG v3.7

## Version 3.7 (2026-01-24)

### Major Changes - 2-Stage BE + Trailing Stop System

#### 1. New Input Parameters (Spec v3.7)
```
=== 2-Stage BE + Trailing Stop ===
InpEnableTrailing     = true    // Enable trailing stop system
InpBEStartR           = 0.6     // Stage A: Move SL to BE at this R profit
InpBEOffsetPoints     = 25      // BE offset for spread/commission (points)
InpTrailStartR        = 1.0     // Stage B: Start ATR trailing at this R profit
InpTrailATRPeriod     = 14      // ATR period for trailing
InpTrailATRMult       = 1.8     // ATR multiplier for trail distance
InpTrailMinStepPoints = 25      // Min improvement to modify SL (points)
InpTrailCooldownSec   = 30      // Cooldown between SL modifications (sec)
InpTrailUseTP1Gate    = true    // Trail requires TP1 partial OR BEStartR reached
InpBEProfitEpsMoney   = 0.50    // Profit threshold for BE_STOP classification ($)
```

#### 2. Stage A: BE Move
- **Trigger**: When profit R >= `InpBEStartR` (default 0.6R)
- **New SL**: `entry + (spread + InpBEOffsetPoints) * Point`
- **Rules**:
  - Tighten only (newSL must be better than current SL)
  - Respects broker constraints (SYMBOL_TRADE_STOPS_LEVEL, freeze level)
  - Sets `g_lastSLSource = SL_SRC_BE`
- **Counter**: `g_beMoveCountToday++`

#### 3. Stage B: ATR Trailing
- **Trigger**: When profit R >= `InpTrailStartR` (default 1.0R)
- **Gate**: If `InpTrailUseTP1Gate = true`, requires TP1 partial done OR BE stage done
- **New SL**: `currentPrice - ATR * InpTrailATRMult - spreadBuffer`
- **Rules**:
  - Tighten only
  - Min step: `InpTrailMinStepPoints` (25 pts)
  - Cooldown: `InpTrailCooldownSec` (30 sec)
  - Respects broker constraints
  - Sets `g_lastSLSource = SL_SRC_TRAIL`
- **Counters**: 
  - `g_trailAttemptedToday++` (every attempt)
  - `g_trailMoveCountToday++` (successful moves)
  - `g_trailSkipCooldown++`, `g_trailSkipMinStep++`, `g_trailSkipBroker++` (skips)

#### 4. Exit Classification (3 Types)
| Exit Type | Condition | Guardrail |
|-----------|-----------|-----------|
| **SL_LOSS** | profit < -InpBEProfitEpsMoney | ✅ Counts |
| **BE_STOP** | profit >= -InpBEProfitEpsMoney | ❌ Does NOT count |
| **TRAIL_STOP** | g_lastSLSource == SL_SRC_TRAIL && profit > 0 | ❌ Does NOT count |
| **TP** | DEAL_REASON_TP | ❌ Does NOT count |

#### 5. SL Source Tracking
```cpp
enum ENUM_SL_SOURCE {
   SL_SRC_INITIAL,  // Original SL from entry
   SL_SRC_BE,       // SL moved to BE
   SL_SRC_TRAIL     // SL moved by trailing
};

// Tracking variables
g_lastSLSource      // Current SL source
g_lastModifiedSL    // Last modified SL price
g_lastSLModifyTime  // Last SL modify timestamp
```

#### 6. NormalizeVolumeToStep Function
- Uses `SYMBOL_VOLUME_STEP` and `SYMBOL_VOLUME_MIN`
- Floors to step to avoid broker rejection
- Counter: `g_tp1PartialSkippedMinVol++` when partial close skipped

### Summary Output (Spec v3.7)

#### Daily Summary
```
--- Exit Classification (Today) ---
  SL_LOSS hits: X (loss sum: -$Y)
  BE_STOP hits: X (profit sum: +$Y)
  TRAIL_STOP hits: X (profit sum: +$Y)
  TP hits: X
  Guardrail SL Hits: X/Y (only SL_LOSS counts)

--- Trailing/BE (Today) ---
  Trail moves: X
  BE moves: X
  Trail attempted: X
  Trail skip (cooldown): X
  Trail skip (min_step): X
  Trail skip (broker): X
```

#### Final Summary
```
--- Exit Classification (All Time) ---
  SL_LOSS hits: X (loss sum: -$Y)
  BE_STOP hits: X (profit sum: +$Y)
  TRAIL_STOP hits: X (profit sum: +$Y)
  TP hits: X

--- Trailing/BE (All Time) ---
  BE moves: X
  Trail moves: X
  Trail attempted: X
  Trail skips (cooldown/min_step/broker): X/X/X
```

### Acceptance Test Checklist
- [ ] Compile without errors in MT5
- [ ] Backtest 7 days (1-min OHLC)
- [ ] Backtest 1 month (1-min OHLC)
- [ ] Verify `trail_attempted_count > 0`
- [ ] Verify `trail_moves_count > 0`
- [ ] Verify `BE_STOP > 0` or `TRAIL_STOP > 0`
- [ ] Verify SL_LOSS does NOT include BE/Trail stops
- [ ] Verify guardrail only counts SL_LOSS
- [ ] Visual test: SL moves BE → Trail correctly

### Logging (Spec v3.7)
```
[ENTRY] entry=X sl=X tp1=X tp2=X riskPts=X tp1Pts=X tp2Pts=X spread=X mode=X
[BE_MOVE] type=BUY/SELL R=0.6 oldSL=X newSL=X source=BE reason=R>=0.6
[TRAIL] R=1.0 ATR=X oldSL=X newSL=X source=TRAIL result=move
[TRAIL_SKIP] reason=cooldown/min_step/stops_level
[EXIT] classify=SL_LOSS/BE_STOP/TRAIL_STOP/TP profit=X slSource=X
```

---

## Previous Versions

### v3.6
- Initial trailing stop implementation
- Exit classification (SL_LOSS vs BE_OR_TRAIL)
- Visual debug overlay

### v3.51
- Bottleneck analysis
- Cancel markers on chart

### v3.5
- TP1 partial close + TP2 final target
- Smart BE with Lock-R option
