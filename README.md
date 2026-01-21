# SMC Scalping Bot v1.0 - XAUUSD.iux

## สำหรับบัญชี DEMO เท่านั้น

EA นี้ออกแบบมาสำหรับการเทรดทองคำ (XAUUSD.iux) บน MetaTrader 5 โดยใช้หลักการ Smart Money Concepts (SMC) พร้อมระบบ Martingale และ Risk Guardrails

---

## คุณสมบัติหลัก

### 1. SMC Logic (Deterministic)
- **Swing Detection**: ใช้ Fractal method (k=2) หา Swing High/Low
- **Liquidity Levels**: PDH/PDL, Session High/Low, EQH/EQL, Swing levels
- **Sweep Detection**: ตรวจจับ liquidity grab ที่ wick ทะลุแล้ว close กลับ
- **CHOCH (Change of Character)**: ยืนยันการเปลี่ยนทิศทางด้วย Close price
- **Zone Building**: FVG (Fair Value Gap) และ OB (Order Block)

### 2. Bias System
- **M15 Bias**: กำหนดทิศทางหลักจาก timeframe M15
- **M5 Entry**: หา entry point จาก timeframe M5

### 3. Risk Guardrails (ป้องกันความเสี่ยง)
- Spread limit: 30 points (0.30)
- Cooldown: 3 bars หลังปิด order
- Max trades/day: 6
- Max consecutive losses: 3
- Daily loss limit: 2%
- ห้ามเปิด order ซ้อน

### 4. Martingale System
- Mode: AFTER_LOSS (default)
- Base lot: 0.01
- Multiplier: 2.0x
- Max level: 3
- Lot cap: 0.08

### 5. Logging (CSV)
- `SMC_trades.csv`: บันทึกทุก trade
- `SMC_setups.csv`: บันทึกทุก setup (แม้ไม่เข้า)

### 6. Visual Debug
- เส้น liquidity levels (PDH/PDL, Session H/L)
- กรอบ FVG/OB zones
- Panel แสดงสถานะ

---

## วิธีติดตั้ง

### ขั้นตอนที่ 1: คัดลอกไฟล์
1. คัดลอกไฟล์ `SMC_Scalp_Martingale_XAUUSD_iux.mq5` ไปยัง:
   ```
   [MT5 Data Folder]\MQL5\Experts\
   ```
2. หา Data Folder: เปิด MT5 → File → Open Data Folder

### ขั้นตอนที่ 2: Compile
1. เปิด MetaEditor (กด F4 ใน MT5)
2. เปิดไฟล์ EA
3. กด Compile (F7)
4. ตรวจสอบว่าไม่มี error

### ขั้นตอนที่ 3: แนบ EA กับ Chart
1. เปิด chart XAUUSD.iux timeframe M5
2. ลาก EA จาก Navigator ไปวางบน chart
3. ตั้งค่า input parameters ตามต้องการ
4. เปิด Allow Algo Trading

---

## Input Parameters

### Symbol & Timeframe
| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpSymbol | XAUUSD.iux | Symbol ที่ใช้เทรด |
| InpBiasTF | M15 | Timeframe สำหรับ Bias |
| InpEntryTF | M5 | Timeframe สำหรับ Entry |

### SMC Parameters
| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpSwingK | 2 | Fractal lookback |
| InpEqThresholdPoints | 80 | EQH/EQL threshold (points) |
| InpReclaimMaxBars | 2 | Max bars สำหรับ reclaim |
| InpSweepBreakPoints | 30 | Min sweep break (points) |
| InpConfirmMaxBars | 6 | Max bars รอ CHOCH |
| InpEntryTimeoutBars | 10 | Timeout รอเข้า zone |

### Risk Guardrails
| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpSpreadMax | 30 | Max spread (points) |
| InpCooldownBars | 3 | Cooldown หลังปิด |
| InpMaxTradesPerDay | 6 | Max trades/day |
| InpMaxConsecLosses | 3 | Max consecutive losses |
| InpDailyLossLimitPct | 2.0 | Daily loss limit (%) |

### Time Filter
| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpTradeStart | 14:00 | เวลาเริ่มเทรด (server) |
| InpTradeEnd | 23:30 | เวลาหยุดเทรด (server) |

### Martingale
| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpMartingaleMode | AFTER_LOSS | Mode: OFF/AFTER_LOSS/SCALE_IN |
| InpBaseLot | 0.01 | Lot เริ่มต้น |
| InpMartMultiplier | 2.0 | ตัวคูณ Martingale |
| InpMartMaxLevel | 3 | Max level |
| InpLotCapMax | 0.08 | Lot สูงสุด |

---

## วิธีทดสอบใน Strategy Tester

1. เปิด Strategy Tester (Ctrl+R)
2. เลือก:
   - Expert: SMC_Scalp_Martingale_XAUUSD_iux
   - Symbol: XAUUSD.iux
   - Period: M5
   - Modeling: Every tick based on real ticks (แนะนำ)
   - Date: เลือกช่วงเวลาที่ต้องการ
3. กด Start

### Tips สำหรับ Backtesting
- ใช้ข้อมูล tick จริงเพื่อความแม่นยำ
- ทดสอบช่วงเวลาที่หลากหลาย
- สังเกต drawdown และ win rate

---

## State Machine Flow

```
WAIT_SWEEP → WAIT_CHOCH → WAIT_RETRACE → PLACE_ORDER → MANAGE_TRADE → COOLDOWN
     ↑                                                                    |
     └────────────────────────────────────────────────────────────────────┘
```

### สถานะแต่ละขั้น:
1. **WAIT_SWEEP**: รอ liquidity sweep
2. **WAIT_CHOCH**: รอ Change of Character
3. **WAIT_RETRACE**: รอราคา retrace เข้า zone
4. **PLACE_ORDER**: วาง order
5. **MANAGE_TRADE**: จัดการ position (partial close, move SL)
6. **COOLDOWN**: พักหลังปิด order

---

## ข้อควรระวัง

### สำหรับ DEMO เท่านั้น
⚠️ **EA นี้ออกแบบสำหรับทดสอบบนบัญชี DEMO เท่านั้น**

### ความเสี่ยงที่ต้องทราบ:
1. **Martingale Risk**: แม้จะมี level limit แต่ยังมีความเสี่ยงสูง
2. **Spread Sensitivity**: ช่วง spread สูงอาจทำให้ไม่เข้าเทรด
3. **Slippage**: ราคาจริงอาจต่างจากที่คาดหวัง
4. **Market Conditions**: SMC ทำงานได้ดีในตลาดที่มี liquidity

### สิ่งที่ยังไม่ได้ทำ (v1.0):
- [ ] AI Filter สำหรับกรอง setup
- [ ] SCALE_IN Martingale mode (เป็น stub)
- [ ] MFE/MAE tracking ใน log
- [ ] Multi-symbol support
- [ ] News filter

---

## โครงสร้างฟังก์ชัน

```
├── OnInit()              # Initialize EA
├── OnDeinit()            # Cleanup
├── OnTick()              # Main logic
├── OnTimer()             # Panel update
│
├── SMC Core
│   ├── DetectSwings()        # หา Swing High/Low
│   ├── CalculateLiquidityLevels()
│   ├── CalculateEqualHighsLows()
│   ├── LookForSweep()        # ตรวจจับ Sweep
│   ├── LookForChoCH()        # ตรวจจับ CHOCH
│   ├── BuildZones()          # สร้าง FVG/OB
│   ├── FindFVG()
│   └── FindOB()
│
├── Entry & Trade
│   ├── LookForRetrace()      # รอ entry
│   ├── PlaceOrder()          # วาง order
│   ├── CalculateSLTP()       # คำนวณ SL/TP
│   └── ManageTrade()         # จัดการ position
│
├── Risk Management
│   ├── PassRiskChecks()      # ตรวจสอบ risk
│   ├── IsWithinTradingHours()
│   ├── GetBias()             # หา M15 bias
│   └── CalculateLot()        # คำนวณ lot + martingale
│
├── Logging
│   ├── InitLogging()
│   ├── LogTrade()
│   └── LogSetup()
│
└── Visual
    ├── DrawLiquidityLevels()
    ├── DrawZone()
    └── UpdatePanel()
```

---

## Log Files

### trades.csv
บันทึกทุก trade ที่เปิด/ปิด:
- timestamp_open, timestamp_close
- symbol, direction, lot
- entry, sl, tp1, tp2
- spread_points, sl_buffer_points
- setup_type, sweep_level_type
- result, r_multiple
- martingale_level

### setups.csv
บันทึกทุก setup (แม้ไม่เข้าเทรด):
- timestamp, state_reached
- reason_cancel (timeout/spread/nobias)
- bias, sweep_detected, choch_detected
- zone_type, zone_price_range
- distance_to_tp1_points

---

## การปรับแต่ง

### ปรับความเสี่ยง:
- ลด `InpBaseLot` สำหรับความเสี่ยงต่ำ
- ลด `InpMartMaxLevel` หรือปิด Martingale
- เพิ่ม `InpDailyLossLimitPct` สำหรับ buffer มากขึ้น

### ปรับความถี่:
- ขยาย `InpTradeStart/End` สำหรับเทรดนานขึ้น
- ลด `InpCooldownBars` สำหรับเทรดถี่ขึ้น

### ปรับ SMC Logic:
- เพิ่ม `InpSwingK` สำหรับ swing ที่ใหญ่กว่า
- ปรับ `InpSweepBreakPoints` ตาม volatility

---

## License & Disclaimer

**ใช้สำหรับการศึกษาและทดสอบบนบัญชี DEMO เท่านั้น**

ผู้พัฒนาไม่รับผิดชอบต่อความเสียหายใดๆ ที่เกิดจากการใช้งาน EA นี้ การเทรดมีความเสี่ยง โปรดศึกษาและทดสอบอย่างละเอียดก่อนใช้งานจริง

---

## Version History

### v1.0 (Initial Release)
- SMC Logic: Sweep + CHOCH + FVG/OB
- M15 Bias + M5 Entry
- Risk Guardrails
- Martingale AFTER_LOSS
- CSV Logging
- Visual Debug Panel
