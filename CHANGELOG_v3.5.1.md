# Changelog v3.5.1 - Visual Debug + Bottleneck Analysis

## สรุปการเปลี่ยนแปลง

### 1. Visual Debug Overlay
- **InpDebugVisual** (default: true) - แสดง debug panel บนกราฟ
- **InpDebugPrint** (default: true) - พิมพ์ debug log
- **InpDebugLogThrottleSec** (default: 60) - ความถี่ในการพิมพ์ log

**Debug Panel แสดง:**
- State ปัจจุบัน (WAIT_SWEEP, WAIT_CHOCH, etc.)
- Mode (STRICT, RELAX, RELAX2)
- Bias (BULLISH, BEARISH, NONE)
- Nearest Swing Level และระยะห่าง
- Sweep Break Points ที่ต้องการ
- CHOCH bars waited / max bars

### 2. Sweep/CHoCH Soft Relax Parameters
```
InpSweepRelaxMultiplier = 0.8    // ลด sweep threshold 20% ใน RELAX modes
InpSweepMinPoints = 30           // Minimum sweep break points
InpChochMaxBarsStrict = 12       // STRICT mode CHOCH timeout
InpChochMaxBarsRelax = 18        // RELAX mode CHOCH timeout
InpChochMaxBarsRelax2 = 24       // RELAX2 mode CHOCH timeout
```

### 3. Bottleneck Analysis
**RecordCancel() เพิ่ม context:**
- no_sweep: บันทึก dist_to_swing, need_break, dist_less_than_need
- choch_timeout: บันทึก bars_waited, max_bars_allowed

**Final Summary แสดง:**
```
--- Core Bottleneck Analysis (All Time) ---
  NO_SWEEP:
    count: 1234
    avg_dist_to_swing: 45.2 pts
    avg_need_break: 60.0 pts
    dist_less_than_need: 890 (72.1%)
    SUGGESTION: Consider reducing SweepBreakPoints or SweepRelaxMultiplier

  CHOCH_TIMEOUT:
    count: 567
    avg_bars_waited: 17.8
    avg_max_bars_allowed: 18.0
    SUGGESTION: Consider increasing ChochMaxBars

  PRIMARY BOTTLENECK: no_sweep - price not reaching swing levels
    Try: Lower SweepBreakPoints, lower SweepRelaxMultiplier, or enable more liquidity sources
```

### 4. Cancel Marker
- ปัก marker บนกราฟเมื่อ cancel (ถ้า InpDebugVisual = true)
- สี: แดง = no_sweep, ส้ม = choch_timeout, เทา = อื่นๆ

## Input Parameters ใหม่

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpDebugVisual | true | แสดง debug panel |
| InpDebugPrint | true | พิมพ์ debug log |
| InpDebugLogThrottleSec | 60 | ความถี่ log (วินาที) |
| InpSweepRelaxMultiplier | 0.8 | ลด sweep threshold ใน RELAX |
| InpSweepMinPoints | 30 | Min sweep break points |
| InpChochMaxBarsStrict | 12 | STRICT CHOCH timeout |
| InpChochMaxBarsRelax | 18 | RELAX CHOCH timeout |
| InpChochMaxBarsRelax2 | 24 | RELAX2 CHOCH timeout |

## วิธีใช้งาน

1. **ดู Debug Panel** - เปิด InpDebugVisual = true
2. **ดู Log** - เปิด InpDebugPrint = true
3. **วิเคราะห์ Bottleneck** - ดู Final Summary หลัง backtest

## Acceptance Tests

- [ ] Compile ใน MT5 (ไม่มี error)
- [ ] Debug panel แสดงบนกราฟ
- [ ] Cancel markers ปักบนกราฟ
- [ ] Final Summary แสดง Bottleneck Analysis
- [ ] Suggestion ถูกต้องตาม data
