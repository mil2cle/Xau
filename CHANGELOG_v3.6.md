# CHANGELOG v3.6

## Version 3.6 (2026-01-24)

### Major Changes

#### 1. Trailing Stop System - Complete Rewrite
- **Fixed trailing stop not working** - Completely rewrote `ManageTrailingStop()` function
- **Three trailing modes**: TRAIL_ATR, TRAIL_SWING, TRAIL_FIXED
- **Proper activation conditions**:
  - After TP1 partial close (when `g_tp1PartialClosed = true`)
  - OR when profit reaches `InpTrailStartR` × R (default 1.0R)
- **Cooldown system**: `InpTrailCooldownSec` (default 30s) prevents spam modifications
- **Min step requirement**: `InpTrailMinStepPoints` (default 30 pts) ensures meaningful moves
- **Broker constraint respect**: Checks SYMBOL_TRADE_STOPS_LEVEL and freeze level
- **Diagnostic counters**: 
  - `g_trailAttemptedToday`, `g_trailMoveCountToday`
  - `g_trailSkipCooldown`, `g_trailSkipMinStep`, `g_trailSkipBroker`

#### 2. Smart Breakeven (BE) System
- **Lock-R option**: `InpBELockR` (default 0.4R) - locks profit at 0.4R instead of just breakeven
- **BE trigger**: When profit reaches `InpBEProfitPoints` (default 80 pts)
- **Separate counter**: `g_beMoveCountToday` tracks BE moves separately from trail moves

#### 3. Exit Classification - SL_LOSS vs BE/Trail
- **EXIT_SL_LOSS**: Actual loss (profit < -$0.50) - **COUNTED in guardrail**
- **EXIT_BE_OR_TRAIL**: SL hit but profit >= 0 - **NOT counted in guardrail**
- **EXIT_TP**: Take profit hit
- **EXIT_MANUAL**: Other reasons
- **Separate tracking**:
  - `g_slLossHitsToday` / `g_totalSlLossHits`
  - `g_beOrTrailStopsToday` / `g_totalBeOrTrailStops`
  - `g_slLossProfitSum` / `g_trailStopProfitSum`

#### 4. Auto Tune Entry Filters
- **InpAutoRelaxNoTrade** (default true): Auto-relax mode after 2 hours no trade
- **InpAutoRelaxHours** (default 2): Hours without trade before auto-relax
- **Progression**: STRICT → RELAX → RELAX2
- **Resets to STRICT**: On new trade or daily reset

### Input Parameters (New/Changed)

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpTrailMode | TRAIL_ATR | Trailing mode: ATR/SWING/FIXED |
| InpTrailStartR | 1.0 | R-multiple to start trailing |
| InpTrailATRMult | 1.5 | ATR multiplier for trail distance |
| InpTrailSwingLookback | 20 | Bars for swing detection |
| InpTrailFixedPoints | 100 | Fixed trail distance in points |
| InpTrailCooldownSec | 30 | Seconds between trail modifications |
| InpTrailMinStepPoints | 30 | Min improvement to modify SL |
| InpBELockR | 0.4 | R-multiple to lock at BE (0=exact BE) |
| InpAutoRelaxNoTrade | true | Auto-relax when no trades |
| InpAutoRelaxHours | 2 | Hours before auto-relax |

### Summary Output Enhancements

#### Daily Summary
```
--- Exit Classification (Today) ---
  SL_LOSS hits: X (loss sum: -$Y)
  BE/Trail stops: X (profit sum: +$Y)
  TP hits: X

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
  BE/Trail stops: X (profit sum: +$Y)
  TP hits: X

--- Trailing/BE (All Time) ---
  Trail moves: X
  BE moves: X

--- Core Bottleneck Analysis ---
  NO_SWEEP: count, avg_dist, avg_need, suggestion
  CHOCH_TIMEOUT: count, avg_waited, avg_max_bars, suggestion
  PRIMARY BOTTLENECK: identification + recommended action
```

### Bug Fixes
- Fixed compile errors from v3.51
- Fixed trailing stop not activating after TP1 partial close
- Fixed exit classification not properly separating SL_LOSS from BE/Trail
- Fixed guardrail counting BE stops as losses

### Testing Checklist
- [ ] Compile without errors
- [ ] Backtest 7 days (1-min OHLC)
- [ ] Backtest 1 month (1-min OHLC)
- [ ] Verify `trail_moved > 0` in summary
- [ ] Verify SL_LOSS vs BE/Trail separation
- [ ] Verify guardrail only counts SL_LOSS
- [ ] Verify auto-relax triggers after 2 hours no trade

---

## Previous Versions

### v3.51
- Visual debug overlay
- Bottleneck analysis (no_sweep, choch_timeout)
- Cancel markers on chart

### v3.5
- TP1 partial close + TP2 final target
- Initial trailing stop implementation
- Exit classification framework

### v3.4
- Strategy Change B implementation
- Partial close system
- BE/Lock-R option
