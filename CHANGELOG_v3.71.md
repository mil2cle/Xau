# CHANGELOG v3.71

## Version 3.71 (2026-01-24)

### สรุปการเปลี่ยนแปลงหลัก

#### 1. TP1 เป็น Milestone + Run to TP2
**ปัญหาเดิม:** EA ตั้ง TP = TP1 ทำให้ปิดไม้เร็วเกินไป ไม่ได้ run to TP2

**แก้ไข:**
- ตอน PlaceOrder ตั้ง `tp = g_tp2Price` (ถ้ามี) แทน `g_tp1Price`
- TP1 กลายเป็น **milestone** สำหรับ:
  - Partial close (ถ้า volume มากพอ)
  - ย้าย SL ไป BE
  - เปิดใช้งาน trailing stop
- ถ้า volume น้อยเกินไปสำหรับ partial close:
  - ไม่ partial แต่ set flags ให้เหมือนผ่าน TP1
  - `g_tp1PartialDone = true`
  - `g_beStageDone = true`
  - ย้าย SL ไป BE และคง TP ไว้ที่ TP2

#### 2. แก้ PnL Tracking (Total PnL = 0 bug)
**ปัญหาเดิม:** `CheckTradeResult()` หยิบ deal ล่าสุดมั่วๆ ทำให้ PnL เพี้ยน

**แก้ไข:**
- ย้าย PnL tracking ไปที่ `OnTradeTransaction()`
- ตรวจสอบ `DEAL_ENTRY_OUT` หรือ `DEAL_ENTRY_OUT_BY` เท่านั้น
- ตรวจสอบ magic number ก่อนอัปเดต
- คำนวณ: `profit + commission + swap`
- Log ชัดเจน: `[PNL_UPDATE] deal=X profit=X comm=X swap=X total=X dailyPnL=X`

#### 3. Risk-Based Lot Sizing (ใหม่)
**เพิ่มใหม่:**
```
InpUseRiskBasedLot   = true    // ใช้ risk-based lot sizing (แนะนำ)
InpRiskPerTradePct   = 1.0     // Risk ต่อไม้ (% ของ equity)
```

**วิธีคำนวณ:**
```
riskMoney = equity * InpRiskPerTradePct / 100
slDistancePoints = |entryPrice - slPrice| / Point
pointValue = tickValue / tickSize * Point
lot = riskMoney / (slDistancePoints * pointValue)
```

#### 4. ปรับ Default ลดความเสี่ยง
| Parameter | ค่าเดิม | ค่าใหม่ | เหตุผล |
|-----------|---------|---------|--------|
| InpMartingaleMode | MART_AFTER_LOSS | **MART_DISABLED** | ปิด martingale = ลด DD |
| InpMartMaxLevel | 3 | **0** | ไม่มี level = ไม่เพิ่ม lot |
| InpMartMultiplier | 2.0 | **1.5** | ถ้าเปิดใช้ ให้ conservative |
| InpUseRecoveryTP | true | **false** | ปิด recovery TP = ลด DD |
| InpLotCapMax | 0.08 | **0.05** | จำกัด lot สูงสุด |

---

## ค่า Input แนะนำสำหรับทุน $100 (Low DD)

### Lot Sizing
```
InpUseRiskBasedLot   = true    // ใช้ risk-based
InpRiskPerTradePct   = 1.0     // Risk 1% = $1 ต่อไม้
InpBaseLot           = 0.01    // Fallback ถ้า risk-based ไม่ทำงาน
InpLotCapMax         = 0.02    // จำกัดไม่เกิน 0.02 lot
```

### Martingale (ปิด)
```
InpMartingaleMode    = MART_DISABLED  // ปิด
InpMartMaxLevel      = 0              // ไม่มี level
```

### Recovery TP (ปิด)
```
InpUseRecoveryTP     = false   // ปิด
```

### Risk Guardrails
```
InpMaxSLHitsPerDay   = 2       // หยุดหลัง SL 2 ครั้ง
InpStopTradingOnSLHits = true  // หยุดจริงๆ
InpDailyLossLimitPct = 3.0     // หยุดเมื่อขาดทุน 3% = $3
InpMaxConsecLosses   = 2       // หยุดหลังขาดทุนติดต่อกัน 2 ครั้ง
```

### Target Trades
```
InpTargetTradesPerDay = 2      // เป้า 2 ไม้/วัน
InpMaxTradesPerDay    = 3      // สูงสุด 3 ไม้/วัน
```

### คาดการณ์ DD
- **Risk per trade:** 1% = $1
- **Max SL hits/day:** 2 = $2 max loss/day
- **Daily loss limit:** 3% = $3 max loss/day
- **Expected max DD:** ~5-10% ในสภาวะปกติ

---

## Acceptance Test Checklist
- [ ] Compile ไม่มี error
- [ ] TP ตั้งที่ TP2 (ไม่ใช่ TP1)
- [ ] TP1 milestone ทำงาน (partial close + BE)
- [ ] PnL tracking ถูกต้อง (ไม่เป็น 0)
- [ ] Risk-based lot คำนวณถูกต้อง
- [ ] Martingale ปิดโดย default

---

## Previous Versions

### v3.7
- 2-Stage BE + Trailing Stop
- Exit Classification: SL_LOSS/BE_STOP/TRAIL_STOP
- SL Source Tracking

### v3.6
- Initial trailing stop implementation
- Visual debug overlay
