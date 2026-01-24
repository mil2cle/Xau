# Changelog v3.5 - Trailing Stop + Smart BE + Exit Classification

## Release Date: 2025-01-24

## New Features

### 1. Trailing Stop (3 Modes)
- **TRAIL_ATR**: ATR-based trailing distance
- **TRAIL_SWING**: Swing high/low based
- **TRAIL_FIXED**: Fixed points

**Input Parameters:**
```
InpUseTrailingStop    = true      // Enable trailing stop
InpTrailMode          = TRAIL_ATR // Trailing mode
InpTrailStartR        = 0.6       // Start trailing at 0.6R profit
InpTrailAfterTP1Only  = true      // Trail only after TP1 partial
InpTrailATRPeriod     = 14        // ATR period
InpTrailATRMul        = 0.8       // ATR multiplier
InpTrailFixedPoints   = 250       // Fixed distance
InpTrailSwingLookback = 2         // Swing lookback
InpTrailMinStepPoints = 30        // Min improvement to modify
InpTrailCooldownSec   = 30        // Cooldown between modifications
InpDisableMartWhenTrailing = true // Disable martingale when trailing
```

### 2. Smart BE (Lock Profit)
- Move SL to lock profit when reaching threshold

**Input Parameters:**
```
InpUseSmartBE         = true      // Enable smart BE
InpBEStartR           = 0.4       // Move SL to BE at 0.4R
InpBELockR            = 0.05      // Lock 5% of risk
InpBEOffsetPoints     = 25        // Extra offset for spread
```

### 3. Exit Classification
- **EXIT_SL_LOSS**: SL hit with actual loss (profit < 0)
- **EXIT_BE_OR_TRAIL**: SL hit but profit >= 0 (BE or trailed)
- **EXIT_TP**: Take profit hit
- **EXIT_MANUAL**: Manual close or other

### 4. MFE/MAE Tracking
- Track Max Favorable Excursion (MFE)
- Track Max Adverse Excursion (MAE)
- Log in R multiples for analysis

## Log Examples

### Entry Log
```
[TRAIL_INIT] entryPrice=2650.50 sl=2648.00 initialRiskPts=250
```

### Trailing Log
```
[TRAIL] type=BUY profitR=0.85 oldSL=2650.60 newSL=2652.20 dist=180 mode=TRAIL_ATR
[TRAIL_SKIP] reason=cooldown
```

### Smart BE Log
```
[SMART_BE] type=BUY profitR=0.45 oldSL=2648.00 newSL=2650.60 lockR=0.05 offset=25
```

### Exit Log
```
[EXIT] class=EXIT_BE_OR_TRAIL reason=3 profit=0.50 MFE=180(0.72R) MAE=50(0.20R) maxProfitR=0.72
```

## Daily Summary Output
```
=== DAILY SUMMARY ===
Trades executed: 5
Daily PnL: 12.50

--- Exit Classification (Today) ---
  SL_LOSS hits: 1 (loss sum: -8.50)
  BE/Trail stops: 2 (profit sum: 3.00)
  TP hits: 2

--- Trailing/BE (Today) ---
  Trail moves: 8
  BE moves: 3
  Trail attempted: 45
  Trail skip (cooldown): 20
  Trail skip (min_step): 15
  Trail skip (broker): 2
```

## Final Summary Output
```
--- Exit Classification (All Time) ---
  SL_LOSS hits: 15 (loss sum: -120.00)
  BE/Trail stops: 42 (profit sum: 85.00)
  TP hits: 35

--- Trailing/BE (All Time) ---
  Trail moves: 85
  BE moves: 28
```

## Acceptance Tests
- [ ] Backtest 7 days + 1 month (1-min OHLC)
- [ ] Trail moves > 0
- [ ] BE moves > 0
- [ ] Exit classification shows SL_LOSS vs BE_OR_TRAIL separation
- [ ] MFE/MAE logged correctly
- [ ] Visual test: price reaches 0.6R → trailing starts
