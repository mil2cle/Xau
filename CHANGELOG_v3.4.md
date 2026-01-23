# SMC Scalping Bot v3.4 - Strategy Change B

## สรุปการเปลี่ยนแปลง

**เป้าหมาย:** หยุดปิด position ที่ TP1 (nearest liquidity) เร็วเกินไป โดยเปลี่ยนไปใช้ TP2 (further target) แทน และจัดการ TP1 เป็น partial close + BE move

---

## A) Order Placement Changes (Critical)

### 1. CalculateSLTP() - เพิ่ม TP2 Fallback
- ยังคงคำนวณ `g_tp1Price` และ `g_tp2Price` เหมือนเดิม
- **เพิ่ม TP2 Fallback:** ถ้า TP2 ไม่พบหรือใกล้ TP1 เกินไป จะใช้ fallback = entry +/- max(InpMinTPPoints, 200) points
- **เพิ่ม TP2 Clamp:** จำกัด TP2 ไม่เกิน InpMaxTPPoints

### 2. PlaceOrder() - เปลี่ยน TP เป็น TP2
- **เดิม:** `tp = g_tp1Price`
- **ใหม่:** `tp = InpUseBrokerTP ? g_tp2Price : 0`
- รองรับ option `InpUseBrokerTP=false` สำหรับไม่ตั้ง TP (manage manually)

### 3. Debug Log on Entry
```
[ENTRY] BUY entry=2650.50 sl=2648.00 tp1=2652.00 tp2=2655.00 slPts=250 tp1Pts=150 tp2Pts=450 spreadPts=35.0 mode=MODE_STRICT
```

---

## B) Partial Close at TP1 (Trade Management)

### New Input Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpUseTP1PartialClose` | true | Enable partial close at TP1 |
| `InpTP1CloseFraction` | 0.50 | Fraction to close at TP1 (50%) |
| `InpMoveSLToBEOnTP1` | true | Move SL to BE after TP1 partial close |
| `InpBEOffsetPoints` | 5 | BE offset points (+ for profit buffer) |
| `InpTP1TriggerBufferPoints` | 1 | TP1 trigger buffer (allow slightly before/after) |
| `InpMinPartialLots` | 0.01 | Min partial close lots |

### ManageTrade() Logic
1. ถ้า position เปิดอยู่ และ `g_tp1Done=false` และราคาถึง TP1:
   - คำนวณ `closeVolume = NormalizeVolume(posVolume * InpTP1CloseFraction)`
   - ถ้า volume valid → Execute partial close
   - หลัง partial close สำเร็จ:
     - `g_tp1Done = true`
     - ถ้า `InpMoveSLToBEOnTP1`:
       - `newSL = entryPrice +/- (InpBEOffsetPoints * _Point)`
       - ตรวจสอบ broker stop level และ freeze level
       - Modify SL ด้วย `trade.PositionModify()`
   - **TP ยังคงอยู่ที่ TP2** (ไม่เปลี่ยน)

### Throttle Log
```
[TP1] Partial close SUCCESS: closed=0.01 remaining=0.01
[TP1] SL moved to BE: newSL=2650.55 (BE+5 pts) tp2_remains=2655.00
```

---

## C) Broker/Platform Constraints

### New Helper Functions
1. **NormalizeVolume(double volume)**
   - Respect `SYMBOL_VOLUME_MIN` และ `SYMBOL_VOLUME_STEP`
   - Round to volume step
   - Clamp to min/max

2. **CanModifyStopLevel(double price, double newSL, long posType)**
   - Check `SYMBOL_TRADE_STOPS_LEVEL`
   - Check `SYMBOL_TRADE_FREEZE_LEVEL`
   - Return false ถ้าไม่สามารถ modify ได้

---

## D) Backtest Diagnostics

### New Counters (Daily + All Time)
| Counter | Description |
|---------|-------------|
| `g_tp1PartialTriggeredCount` | จำนวนครั้งที่ partial close ที่ TP1 สำเร็จ |
| `g_tp1PartialFailedCount` | จำนวนครั้งที่ partial close ล้มเหลว |
| `g_beMovedCount` | จำนวนครั้งที่ move SL to BE สำเร็จ |
| `g_lastTP1FailReason` | เหตุผลล่าสุดที่ partial close ล้มเหลว |

### Daily Summary Output
```
=== DAILY SUMMARY ===
--- TP1 Partial Close (Today) ---
  TP1 partial triggered: 5
  TP1 partial failed: 1 (last reason: invalid_volume)
  BE moved: 5
```

### Final Summary Output
```
--- TP1 Partial Close (All Time) ---
  TP1 partial triggered: 45
  TP1 partial failed: 3
  BE moved: 42
  Success rate: 93.8%
```

---

## E) Functions Modified

| Function | Changes |
|----------|---------|
| `CalculateSLTP()` | Added TP2 fallback and clamp |
| `PlaceOrder()` | Changed TP from TP1 to TP2, added detailed entry log, reset TP1 tracking |
| `ManageTrade()` | Added TP1 partial close logic with BE move |
| `DailyResetIfNeeded()` | Added TP1 counters reset |
| `PrintDailySummary()` | Added TP1 diagnostics |
| `PrintFinalSummary()` | Added TP1 diagnostics (all time) |

### New Functions
| Function | Description |
|----------|-------------|
| `NormalizeVolume()` | Normalize volume to broker constraints |
| `CanModifyStopLevel()` | Check if SL modification respects broker constraints |

---

## Acceptance Test Checklist

- [ ] Run 7 days + 1 month 1-min OHLC
- [ ] Verify trades no longer close immediately at TP1
- [ ] Partial closes happen at TP1 (counter > 0)
- [ ] Remaining position can reach TP2 or exit via SL/management
- [ ] Run 14 days real ticks if available
- [ ] Screenshot/log proving:
  1. Entry TP is set to TP2
  2. Partial close at TP1
  3. SL moved to BE after TP1
