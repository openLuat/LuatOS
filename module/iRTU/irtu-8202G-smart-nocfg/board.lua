--[[
@module  board
@summary 板级自适应模块（单固件多型号：识别硬件型号 + 输出板级配置 profile）
@version 1.0
@date    2026.09.16
@usage
本模块是"板级差异"的唯一真相源：业务/驱动层只读 profile，禁止出现板型名字判断。

设计要点（依据合宙官网口径）：
1. 型号判定主判据 = hmeta.model()（官网明确：不要用 rtos.bsp() 判断具体模组型号，
   rtos.bsp() 返回值粒度不一致，Air780E/EP/EPV 固定返回 EC618）；
   rtos.bsp() 仅作交叉校验与兜底。
2. board.init() 必须在 T0 同步窗口执行（main.lua 中 fskv.init() 之后、其它 require 之前）：
   内部禁止 sys.wait / i2c / uart / gpio.setup 等阻塞或外设操作，否则会推迟 profile 生效时间，
   导致 require 期求值的模块（如 config.HARDWARE_PINS、utils/tools.lua 的 LED_PINS）读到错误引脚。
3. 能力用 impl 声明、缺失用 nil/"none" 表达；模块必须能处理缺失（不得崩溃）。
4. 识别失败兜底为 unknown：全局禁用外设能力，仅保定位+上报主链路，并提示用 fskv board_force 排障。

对外接口：
  board.init()              识别并构建 profile（幂等，可重复调用）
  board.profile             当前板级配置表（init 后有效）
  board.id                  板型标识 "8202" / "8201G" / "8201H" / "unknown"
  board.source              判定来源："force" / "hmeta" / "bsp" / "fallback"
  board.describe()          生成启动日志文本（板型 + 全部生效引脚）
  board.report()            打印启动日志
]]

local board = {}

-- 板型标识常量（供外部比较，禁止在业务层散落字面量）
board.ID_8202    = "8202"     -- Air8202（主控 Air780EGG，当前基线板）
board.ID_8201G   = "8201G"    -- Air8201G（主控 Air780EGH）
board.ID_8201H   = "8201H"    -- Air8201H（主控 Air780EHM）
board.ID_UNKNOWN = "unknown"  -- 识别失败

-- 传感器驱动实现标识
local GS_EXVIB    = "exvib"      -- DA221（8202）
local GS_DA267    = "exs_da267"  -- DA267（8201G / 8201H）
local GS_NONE     = "none"

-- 充电源实现标识
local CHG_YHM     = "yhm"   -- YHM2712A 阶段读（CMD 单总线）
local CHG_VBUS    = "vbus"  -- VBUS 电平检测（无充电 IC 通讯）
local CHG_NONE    = "none"

-- 电压源实现标识
local VOLT_ADC0   = "adc0"           -- 外部 ADC0 + 硬件分压（8201G / 8201H）
local VOLT_VBAT   = "vbat_internal"  -- 模组内部 VBAT 通道（8202 现状，M2 评估切换）

-- 低压截止动作
local CUT_SHIP    = "ship_mode"  -- YHM2712A 船运模式（断电池 FET）
local CUT_SHUT    = "shutdown"   -- pm.shutdown()
local CUT_NONE    = "none"

--[[
AGPIOWU0 的两种用法（依据合宙官网《GPIO/AGPIO/AGPIOWU/WAKEUP》，管脚表 2025-11-28）：

AGPIOWU0 / AGPIOWU1 / AGPIOWU2 分别对应物理管脚 GPIO20 / GPIO21 / GPIO22，
**同一个物理脚，gpio.setup() 第一个参数的类型决定它属于哪个模式**：
  · 填 GPIO 号(20)      → 作 AGPIO：有中断，但**低功耗(mode1)/PSM+(mode3) 下不响应中断、不可作唤醒源**
  · 填 gpio.WAKEUP3     → 作 WAKEUP：**有中断 + 可在休眠下唤醒模块**
因此 G-Sensor 震动中断若落在 GPIO20 上，应优先用 gpio.WAKEUP3 句柄以获得休眠唤醒能力。
（gpio.WAKEUP3 常量缺失时回退为 GPIO20：中断仍可用，仅失去休眠唤醒，不静默失败。）
]]
-- 官方常量，不做数字兜底：本平台实测 gpio.WAKEUP3 = 42（唤醒句柄，与普通 GPIO 号不同体系）。
-- 若某 BSP 未提供该常量，int_pin 为 nil，gsensor 会自动降级为轮询判定，不会崩。
local AGPIOWU0_AS_WAKEUP = gpio.WAKEUP3

--[[
板级配置表（三套 profile）

字段失效语义：nil 表示该型号不具备此资源；driver 层须判空处理。
单位约定：电压 mV，时间 ms/s，频率 Hz，电阻为数值比（只用比值）。
标注：【码】= 已由当前工程源码证实；【待实测】= 需上板/看图纸确认（见 docs/多型号兼容/03 §8 M0）
]]
local PROFILES = {

    -- ================= Air8202（主控 Air780EGG，当前基线板） =================
    [board.ID_8202] = {
        id  = board.ID_8202,
        soc = "Air780EGG",

        led = {
            net_pin = 26,      -- 【码】config.HARDWARE_PINS.GREEN_LED（网络/状态指示）
            chg_pin = 27,      -- 【码】config.HARDWARE_PINS.YELLOW_LED（充电指示）
            active  = 1,
            style   = "green_yellow",
        },

        gnss = {
            volgpio = nil,     -- 【码】现网走 pm.power(pm.GPS, ...)；是否需显式 GPIO 使能待实测
            uart    = 2,       -- 【码】modules/exgnss.lua uart_id=2
            baud    = 115200,  -- 【码】
        },

        voltage = {
            impl      = VOLT_VBAT, -- M1 保持现状；M2 评估统一改 ADC0（需先确认该板 ADC0 是否接电池分压）
            adc_ch    = 0,
            range     = "min",     -- 符号名，M2 解析为 adc.ADC_RANGE_1_2 / min
            r_up      = 1000,
            r_down    = 300,
            offset_mv = 0,
            sample_n  = 3,
        },

        charger = {
            impl          = CHG_YHM,
            cmd_pin       = 25,    -- 【码】config.CHARGE_CONFIG.CMD_PIN
            vbus_pin      = nil,
            vbus_polarity = nil,
            stage_capable = true,  -- 可读充电阶段/充满
            cutoff        = { impl = CUT_SHIP },
            enable        = true,
            float_mv      = 4200,  -- 【码】config.CHARGE_CONFIG.FLOAT_VOLTAGE_MV
            cap_mah       = 2000,  -- 【码】config.CHARGE_CONFIG.CAP_BATTERY_MAH
        },

        gsensor = {
            impl      = GS_EXVIB,
            i2c_id    = 1,            -- 【码】lib/exvib.lua L121-125（780 系列走 I2C1）
            addr      = 0x27,         -- 【码】lib/exvib.lua L126
            -- 【码】原 modules/sensors/gsensor.lua L19 硬编码。
            -- 8202(EGG) 上 WAKEUP2 = USIM_DET(PIN79) 被**内部固定占用**作内置 G-Sensor 振动中断输入，
            -- 外部不可再用（合宙官网 EGP/EGG/EGH 内部占用表）→ 故 G-Sensor 用 WAKEUP2、
            -- SIM 检测只能改用 WAKEUP0；两者分属不同引脚，无冲突。
            int_pin   = gpio.WAKEUP2,
            -- AGPIO3（GPIO23）= Vref：EGP/EGG 上兼作 G-Sensor 供电，
            -- ⚠️ 必须保持默认输出高，否则 I2C1 初始化失败（内置 G-Sensor 挂 I2C1 / 地址 0x27）
            power_pin = 23,           -- 【码】lib/exvib.lua L231（780 分支，库内自行设置）
            range_g   = 2,
            -- 注意：exvib 的 read_xyz 直接返回硬件 12bit 原始值（基线标度），
            --       不参与 raw_per_g 归一化；此处不配置 raw_per_g。
        },

        wdt = {
            impl     = "air153c",
            feed_pin = 24,         -- 【码】config.WDT_CONFIG.FEED_PIN
            interval = 180,        -- 【码】config.WDT_CONFIG.FEED_INTERVAL
            enable   = true,
        },

        -- SIM 卡槽在位检测（热插拔）
        -- 各型号 SIM0 检测脚（硬件确认）：8202 = WAKEUP0 / 8201G = WAKEUP2 / 8201H = WAKEUP2
        -- 与 G-Sensor 震动中断脚（8202 = WAKEUP2 / 8201G = AGPIOWU0(WAKEUP3) / 8201H = WAKEUP0）互不冲突
        --
        -- · SIM 供电（硬件确认）：三型号 SIM0 均走 PIN14 的 USIM_VDD，**由底层自动控制，脚本不介入**；
        --   mobile.simid() 切卡时底层自行完成该路电源上下电与重新搜网，本工程无需任何供电控制代码。
        -- · 检测脚上下拉：sim_slot 默认用**内部上拉**（profile 可用 sim.det_pull 覆盖）。
        --   ⚠️ 外部上拉禁止接 VDD_EXT / 普通 GPIO（官网《SIM 卡电路设计》《GPIO 设计说明》）：
        --      休眠时 VDD_EXT 会间歇输出百 ms 级高脉冲，会把 WAKEUP 拉出中断 → **设备无法休眠**；
        --      若硬件确需外部上拉，请改用 VRef(AGPIO23)。
        sim = {
            detect_enable  = true,          -- 8202 为双卡槽硬件（SIM0/SIM1），启用 SIM0 在位检测
            det_pin        = gpio.WAKEUP0,  -- SIM0 在位检测脚
            -- 极性：检测脚经上拉电阻拉高，插卡时卡座检测开关对地闭合 → **低电平 = 在位**
            -- 硬件依据：8202 检测脚经 R339 10k 上拉至 VREF；8201G/H 经 100k / 10K 上拉至 V_BCKP
            present_level  = 0,             -- 低电平 = SIM0 在位
            boot_default   = 1,             -- 检测不可用时的默认卡槽（原行为：固定 SIM1）
            debounce_ms    = 500,           -- 官方热插拔示例防抖 500ms
            fly_off_ms     = 1000,          -- 退出飞行模式后的稳定等待
            fly_on_ms      = 1000,          -- 进入飞行模式后的稳定等待
            switch_wait_ms = 3000,          -- 官方要求：切卡后延时再读卡槽
        },
    },

    -- ================= Air8201G（主控 Air780EGH） =================
    [board.ID_8201G] = {
        id  = board.ID_8201G,
        soc = "Air780EGH",

        led = {
            net_pin = 12,      -- 红灯（网络/状态指示）
            chg_pin = 1,       -- 蓝灯（充电指示）
            active  = 1,
            style   = "red_blue",
        },

        gnss = {
            volgpio = 21,      -- 内置 GNSS，使能脚 GPIO21
            uart    = 2,
            baud    = 115200,
        },

        voltage = {
            impl      = VOLT_ADC0,
            adc_ch    = 0,     -- ADC0（Pin9）+ 1M/300K 分压 → ×4.3333
            range     = "min",
            r_up      = 1000,
            r_down    = 300,
            offset_mv = 0,     -- 【待实测】产测口径曾用 +140mV，需万用表标定
            sample_n  = 3,
        },

        charger = {
            impl          = CHG_VBUS, -- U16 无 CMD、CHRG 未接主控 → 改 VBUS 电平检测
            cmd_pin       = nil,
            -- 官方语义常量 gpio.VBUS（等价 gpio.WAKEUP1，本平台实测同为 40）
            vbus_pin      = gpio.VBUS or gpio.WAKEUP1, -- 【待实测】极性需实机标定
            vbus_polarity = "high",
            stage_capable = false,    -- 拿不到阶段与充满 → LED 降级为"充电中亮/未充灭"
            cutoff        = { impl = CUT_SHUT }, -- 无 YHM2712A → 无船运模式
            enable        = false,    -- 无软件可配充电 IC
            float_mv      = nil,
            cap_mah       = nil,
        },

        gsensor = {
            impl      = GS_DA267,
            i2c_id    = 1,     -- I2C1（Pin66 SDA / Pin67 SCL）
            -- ★★ I2C1 外部上拉源 = GPIO28（AGPIO8 / 模组 PIN78）
            -- 原理图：I2C1_SDA / I2C1_SCL 的 10k 上拉电阻（R16 / R17）由 GPIO28 供电/使能。
            -- ⚠️ 不打开 → SDA/SCL 无上拉 → **整条总线无任何器件应答**。
            --    实机已复现：i2c.scan 全地址"传输超时"、DA267 芯片ID 校验失败。
            --    通信前必须先把它拉高（驱动见 modules/sensors/gsensor.lua 的 drv.setup 第①步）。
            -- 注：仅 8201G 如此；8201H 的 AGPIO8 用作 UART1_RXD，8202 用模组内置 G-Sensor（上拉在模组内）。
            i2c_pullup_pin = 28,
            addr      = 0x26,  -- exs_da267 默认地址
            -- 【硬件确认】DA267 INTN → AGPIOWU0（物理管脚 GPIO20）
            -- 用 gpio.WAKEUP3 句柄（非数字 20）：同一物理脚，作 WAKEUP 才具备休眠唤醒能力
            int_pin   = AGPIOWU0_AS_WAKEUP,
            -- AGPIO4（GPIO24）：AGPIO 休眠可保持电平，适合做外设使能脚；
            -- 注意 AGPIO 全组总驱动电流 ≤5mA，且上下拉电阻不可过小（AGPIOWU 需 100K 级）
            power_pin = 24,
            -- ★★ I2C1 总线上**全部**支撑脚 —— 开机即全部拉高（2026-09-17 用户指示）
            -- 动机：I2C1 上不止一个器件，**任一器件未上电，其 ESD 保护二极管就会把
            --   SDA/SCL 钳在低位** → 主控只看到"传输超时"(-13) 而不是 NACK，
            --   且上拉再强也无用。这与实机现象完全吻合。
            -- 依据：
            --   · 28 = AGPIO8 / PIN78     → I2C1 的 10k 外部上拉（R16/R17）使能
            --                               【已实机验证：不使能则全地址超时】
            --   · 23 = VREF / PIN99 (=AGPIO3) → 传感器块供电 + VREF【图/同族】
            --        05 文档 8202 段原文：「PIN99 GPIO23 兼作 G-Sensor 供电 + VREF，
            --        必须保持默认输出高（否则 I2C1 初始化失败）」；
            --        且 8202 的 profile 就是 `gsensor.power_pin = 23`
            --        （lib/exvib.lua:231 注释"gsensor 开关"）→ 同源证据 ✅
            --   · 24 = AGPIO4 / V_BCKP     → 传感器与 SIM_CD 上拉供电【图/同族】
            -- ⚠️ 本清单只做"拉高"；断电复位只动 power_pin(24)，**不会**拉低 23/28
            --    （避免扰动 VREF 这类参考/供电源）。
            -- [[ 官方依据（Air8201G DA267 示例，module/Air8201/demo/gsensor/da267_app.lua L76-81）：
            --      gpio.setup(POWER_PIN, 1)  -- GPIO24: DA267供电
            --      if HARDWARE_ENV == "G" then
            --          gpio.setup(28, 1)    -- Air8201G: 开启I2C1总线上拉
            --          gpio.setup(26, 1)    -- Air8201G: 开启I2C1外围供电   ★
            --      end
            --   → 8201G 的 I2C1 支撑脚**官方明确为三只**：24 / 28 / 26。
            --     本工程此前漏了 **26（I2C1 外围供电）** —— 这正是"sensor 未上电时
            --     其 ESD 二极管钳住总线、表现为间歇性传输异常"的成因。
            -- 注：23（VREF/PIN99）官方示例未列，但 BSP 出厂已配为 output 1
            --     （实机日志 `bsp_bus_init io gpio23 output 1`），一并拉高无害，保留。
            support_pins = { 24, 28, 26, 23 },   -- 24=DA267供电 28=总线上拉 26=I2C1外围供电 23=VREF
            -- ★ 引脚角色（2026-09-18 用户确认，权威口径）：
            --   · **GPIO24 = G-Sensor 供电，接 V_BCKP**（经负载开关由 GPIO24 门控）
            --     → `power_pin = 24` ✅ 正确。05 文档「V_BCKP 由 GPIO24 控制供电」原判定正确。
            --   · **本板无外接看门狗（无 Air153C）** → `wdt.impl = "none"` ✅ 正确。
            --     ⚠️ config.lua:120 那句「AGPIO24 → NPN → WTDOG」是 **8202 的接线**，
            --        不可外推到 8201G（我曾据此误判，2026-09-17~18，已纠正）。
            --   · GPIO23 = VREF/PIN99（AGPIO3）：BSP 出厂即配 `output 1`（`bsp_bus_init`），
            --     传感器块供电/VREF → 一并拉高。
            --   · GPIO28 = AGPIO8/PIN78：I2C1 的 10k 外部上拉（R16/R17）使能【已实机验证】。
            -- 断电重上电已启用：GPIO24 就是传感器电源，切断 200ms 是"器件失电/闩锁后
            -- ESD 钳位总线"这类故障的正解；30s 限流 + 关机时间短，对 V_BCKP 影响可接受。
            power_cycle_recover = true,
            range_g   = 2,
            -- 归一化到 8202 基线标度（TLV 1301/1303 的 12bit 原始值口径；原 1293/1295）：
            -- exs_da267 内部灵敏度为 32768/range（2g→16384），与 DA221 口径（2g→1024）相差 16 倍，
            -- 若不归一化，同一物理加速度在 8201G/H 与 8202 上会上报不同数值，平台侧解读失真。
            -- 【待标定】水平静置读 Z 轴，令 1g 对应 1024，据此微调本值（见 docs/多型号兼容/03 §13）。
            raw_per_g = 1024,
            -- 无中断引脚时的轮询判定阈值（合加速度偏离 1g 超过该值视为震动）
            motion_threshold_g = 0.18,
        },

        wdt = {
            impl    = "none",  -- 官表未列硬件看门狗
            enable  = false,
        },

        -- SIM 卡槽在位检测：SIM0 检测脚 = 官方语义常量 gpio.USIM_DET
        -- （等价 gpio.WAKEUP2，本平台实测同为 41；与 G-Sensor 中断脚 GPIO20 不冲突）
        sim = {
            detect_enable  = true,
            det_pin        = gpio.USIM_DET or gpio.WAKEUP2,
            -- 极性：**低电平 = 在位**（上拉 + 卡座检测开关对地）。
            -- 实测依据（2026-09-17）：卡插在 SIM0 时该脚稳定读到 0，
            -- 原写 1 导致每次开机都被判成"SIM0 拔出"而切到 SIM1。
            present_level  = 0,
            -- 检测脚不可读时的兜底卡槽：本板实体卡插在 SIM0（2026-09-17 实机确认），
            -- 原为 1(SIM1) 系沿用 8202 双卡槽的历史默认值，在 8201G 上会导致"插卡不识别"。
            boot_default   = 0,
            debounce_ms    = 500,
            fly_off_ms     = 1000,
            fly_on_ms      = 1000,
            switch_wait_ms = 3000,
        },
    },

    -- ================= Air8201H（主控 Air780EHM） =================
    [board.ID_8201H] = {
        id  = board.ID_8201H,
        soc = "Air780EHM",

        led = {
            net_pin = 12,      -- 红灯
            chg_pin = 1,       -- 蓝灯
            active  = 1,
            style   = "red_blue",
        },

        gnss = {
            volgpio = 25,      -- 外置 GNSS 芯片，使能脚 GPIO25
            uart    = 2,
            baud    = 115200,
        },

        voltage = {
            impl      = VOLT_ADC0,
            adc_ch    = 0,     -- ADC0（Pin9）+ 1M/300K 分压 → ×4.3333
            range     = "min",
            r_up      = 1000,
            r_down    = 300,
            offset_mv = 0,     -- 【待实测】
            sample_n  = 3,
        },

        charger = {
            impl          = CHG_YHM,  -- YHM2712A（U1），与 8202 同款同用法
            cmd_pin       = 27,       -- 【用户确认+原理图】CHARG_CMD → GPIO27
            vbus_pin      = nil,
            vbus_polarity = nil,
            stage_capable = true,
            cutoff        = { impl = CUT_SHIP },
            enable        = true,
            float_mv      = 4200,
            cap_mah       = 2000,
        },

        gsensor = {
            impl      = GS_DA267,
            i2c_id    = 1,     -- I2C1（Pin83 SDA / Pin85 SCL）
            addr      = 0x26,  -- exs_da267 默认地址
            -- 【硬件确认】DA267 INTN → WAKEUP0（WAKEUP 类，本身即支持休眠唤醒）
            int_pin   = gpio.WAKEUP0,
            -- AGPIO4（GPIO24）：休眠可保持电平；AGPIO 全组总电流 ≤5mA
            power_pin = 24,    -- 传感器/电平上拉使能脚（官方库不管理，需适配层设置）
            range_g   = 2,
            -- 归一化到 8202 基线标度（同 8201G，详见 8201G 段说明与 03 文档 R-11）
            raw_per_g = 1024,  -- 【待标定】水平静置读 Z 轴，令 1g→1024
            motion_threshold_g = 0.18,
        },

        wdt = {
            impl   = "none",
            enable = false,
        },

        -- SIM 卡槽在位检测：SIM0 检测脚 = 官方语义常量 gpio.USIM_DET（等价 gpio.WAKEUP2）
        -- （与 G-Sensor 中断脚 WAKEUP0 不冲突）
        sim = {
            detect_enable  = true,
            det_pin        = gpio.USIM_DET or gpio.WAKEUP2,
            -- 极性：低电平 = 在位（同 8201G，硬件结构一致：【待实测】确认为准）
            present_level  = 0,
            boot_default   = 1,
            debounce_ms    = 500,
            fly_off_ms     = 1000,
            fly_on_ms      = 1000,
            switch_wait_ms = 3000,
        },
    },
}

-- ==================== 模块内部状态 ====================

-- unknown 兜底 profile：全局禁用外设能力，仅保定位+上报主链路
local function build_unknown_profile()
    return {
        id  = board.ID_UNKNOWN,
        soc = nil,
        led = { net_pin = nil, chg_pin = nil, active = 1, style = "none" },
        gnss = { volgpio = nil, uart = 2, baud = 115200 },
        voltage = { impl = VOLT_VBAT, adc_ch = 0, range = "min",
                    r_up = 1000, r_down = 300, offset_mv = 0, sample_n = 3 },
        charger = { impl = CHG_NONE, cmd_pin = nil, vbus_pin = nil, vbus_polarity = nil,
                    stage_capable = false, cutoff = { impl = CUT_NONE },
                    enable = false, float_mv = nil, cap_mah = nil },
        gsensor = { impl = GS_NONE, i2c_id = 1, addr = 0x26, int_pin = nil,
                    power_pin = nil, range_g = 2, raw_per_g = 1024, motion_threshold_g = 0.18 },
        wdt = { impl = "none", enable = false },
        -- 识别失败时不确定板级接法 → 不启用卡检测，沿用原固定 SIM1 行为
        sim = { detect_enable = false, det_pin = nil, present_level = 1, boot_default = 1,
                debounce_ms = 500, fly_off_ms = 1000, fly_on_ms = 1000, switch_wait_ms = 3000 },
    }
end

-- 注：三型号的 "SIM0 在位检测脚" 与 "G-Sensor 震动中断脚" 按硬件确认分属不同引脚
-- （8202: WAKEUP0 / WAKEUP2；8201G: WAKEUP2 / GPIO20；8201H: WAKEUP2 / WAKEUP0），
-- 因此**不需要引脚冲突仲裁**——各模块各用各的脚即可。

-- 浅拷贝两层（profile 只读使用，避免外部误改静态表）
local function dup_profile(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local sub = {}
            for k2, v2 in pairs(v) do
                sub[k2] = type(v2) == "table" and dup_profile(v2) or v2
            end
            out[k] = sub
        else
            out[k] = v
        end
    end
    return out
end

-- 读取 fskv 强制指定板型（现场排障用），fskv 未就绪时安全返回 nil
local function read_force()
    if not fskv or not fskv.get then return nil end
    local ok, v = pcall(fskv.get, "board_force")
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

-- 从型号字符串中提取板型标识（按后缀匹配）
-- 【权威口径】8202 实际装机主控为 **Air780EGG**（用户确认）。
--   Air8202G 原理图（V1，2026-08-19）的模组符号仍写 `AIR780EGP`，属**图纸未更新**，不作为判据。
-- 【兼容别名】EGP 分支保留为兜底：官方明确「Air780EGP / EGG / EGH 硬件管脚完全一致」，
--   PIN79(WAKEUP2)/PIN99(GPIO23)/PIN66-67(I2C1) 的内部占用在 EGP 与 EGG 上完全相同（均内置 G-Sensor），
--   故万一某批次 hmeta 返回 EGP，复用 8202 板级配置不会出错；
--   ⚠️ 若无此别名而落入 unknown：外设全禁 + **Air153C 看门狗不再喂狗** → 240s 超时复位循环。
local function match_id(s)
    if type(s) ~= "string" or s == "" then return nil end
    s = s:upper()
    if s:find("EGG", 1, true) then return board.ID_8202 end   -- 8202 实际装机
    if s:find("EGH", 1, true) then return board.ID_8201G end
    if s:find("EHM", 1, true) then return board.ID_8201H end
    if s:find("EGP", 1, true) then return board.ID_8202 end   -- 兼容别名（原理图旧符号）
    return nil
end

-- ==================== 型号判据源（hmeta / rtos 均为核心库，直接调用） ====================
-- 不做"库是否存在 / 是否支持"的判断：hmeta、rtos 都是 LuatOS 核心库，固件必然提供。
-- 这里只处理官方语义上"值可能取不到"的情况：
--   · hmeta.model() / hmeta.chip()：识别不出时官方返回 nil
--   · rtos.bsp()：官网明确其粒度不一致；本 BSP 下 luat_os_bsp() 返回空（实测 2026-09-17）
--   · rtos.firmware()：与 rtos.bsp() 同源，尾段含型号
--
-- ⚠️ 历史教训（已修复）：曾用 type(hmeta) == "table" 判断核心库是否存在，而实测
--    **type(hmeta) == "userdata"** —— 核心库的注册形式不保证是普通 table，这个硬判
--    把完全可用的 hmeta 误判成"不存在"→ 识别失败 → unknown → SIM/LED/电池/看门狗全禁。
--    → 结论：核心库直接调用，不要做存在性或类型判断。

-- hmeta.model()：官网指定的精确型号识别 API（★ 主判据）
local function read_model()
    local m = hmeta.model()
    if type(m) == "string" and m ~= "" then return m end
    return nil
end

-- hmeta.chip()：原始芯片型号（辅助判据）
local function read_chip()
    local m = hmeta.chip()
    if type(m) == "string" and m ~= "" then return m end
    return nil
end

-- rtos.bsp()：BSP 名（粒度不一致，仅兜底）
local function read_bsp()
    local b = rtos.bsp()
    if type(b) == "string" and b ~= "" then return b end
    return nil
end

-- rtos.firmware()：形如 "LuatOS-SoC_V2052_Air780EGH"
local function read_firmware()
    local s = rtos.firmware()
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

-- 构建期兜底板型（取 main.lua 顶部的 BOARD_DEFAULT 常量）
-- 用途：本固件若缺少型号自报能力（hmeta 库未编入 / rtos.bsp 返回空），用它显式指定，
--       避免静默落入 unknown 导致"能开机但功能全废"（SIM 检测/LED/电池/看门狗全关）。
-- 取值必须命中 PROFILES 键（"8202"/"8201G"/"8201H"）；nil = 不兜底。
local function read_default()
    local d = BOARD_DEFAULT
    if type(d) == "string" and d ~= "" and PROFILES[d] then return d end
    return nil
end

--[[
识别板型（纯字符串判定，无任何外设 I/O）

判据源按可信度依次尝试，命中即止；全部不可用才落 unknown：
  1) fskv board_force    人工覆盖（现场排障）
  2) hmeta.model()       官网指定的精确型号 API（★主判据）
  3) hmeta.chip()        原始芯片型号（辅助）
  4) rtos.bsp()          BSP 名（官网明确粒度不一致，仅兜底）
  5) rtos.firmware()     形如 "LuatOS-SoC_V2052_Air780EGH"（第二兜底，尾段含型号）
  6) BOARD_DEFAULT       构建期显式指定（★固件无自报能力时的唯一出路）

背景（2026-09-17 上机实测，Air780EGH 固件 V2052）：
  该固件未编入 hmeta Lua 库（hmeta 全局为 nil），且 luat_os_bsp() 返回空
  → 2~5 全部失效。C 层 luat_hmeta_model_name() 实际可用（pins 库日志已证明其能
  正确取得 "Air780EGH"），但全 SDK 仅 hmeta 一个 Lua 入口，缺少该库即无从读取。
  ⚠️ 因此该固件下"型号自适应"不可达，必须靠 BOARD_DEFAULT 兜底。

@return string|nil 板型标识
@return string 判定来源："force"/"hmeta"/"chip"/"bsp"/"firmware"/"default"/"fallback"
]]
local function resolve_id()
    -- 1) 人工覆盖优先（现场排障）
    local force = read_force()
    if force and PROFILES[force] then
        return force, "force"
    end

    -- 2~5) 字符串判据源，按可信度排列
    local sources = {
        { name = "hmeta.model",   src = "hmeta",    get = read_model },
        { name = "hmeta.chip",    src = "chip",     get = read_chip },
        { name = "rtos.bsp",      src = "bsp",      get = read_bsp },
        { name = "rtos.firmware", src = "firmware", get = read_firmware },
    }

    local hit_id, hit_src
    local conflicts = {}
    for _, s in ipairs(sources) do
        local v = s.get()
        if v then
            local id = match_id(v)
            if id then
                if not hit_id then
                    hit_id, hit_src = id, s.src
                elseif id ~= hit_id then
                    -- 多源不一致：以最高优先级源为准，但必须告警（可能是 BSP 自报串异常）
                    conflicts[#conflicts + 1] = string.format("%s=%s→%s", s.name, v, id)
                end
            end
        end
    end

    if hit_id then
        if #conflicts > 0 then
            log.warn("board", "型号判据源不一致，采用最高优先级结果:",
                hit_src, hit_id, "| 其它:", table.concat(conflicts, " "))
        end
        return hit_id, hit_src
    end

    -- 6) 构建期兜底
    local def = read_default()
    if def then return def, "default" end

    return nil, "fallback"
end

--[[
板型识别并构建 profile（幂等）

约束：必须在 T0 同步窗口调用，内部禁止 sys.wait / i2c / uart / gpio.setup。
]]
function board.init()
    if board.profile then return board.profile end

    local id, source = resolve_id()
    board.source = source

    if id then
        board.id = id
        board.profile = dup_profile(PROFILES[id])
        if source == "default" then
            -- 构建期兜底生效：本固件不具备型号自报能力，换型号必须改 BOARD_DEFAULT 并重烧
            log.error("board", "型号自报失败（hmeta 库缺失 / rtos 不可用），已按构建期 BOARD_DEFAULT=",
                id, "兜底。⚠️ 本固件无型号自适应能力，切勿直接烧到其它型号板。")
        end
    else
        board.id = board.ID_UNKNOWN
        board.profile = build_unknown_profile()
        log.error("board", "板型识别失败（型号自报不可用）",
            "hmeta.model=", tostring(read_model()),
            "rtos.bsp=", tostring(read_bsp()),
            "rtos.firmware=", tostring(read_firmware()),
            "→ 已禁用外设能力。补救：① main.lua 设 BOARD_DEFAULT；② fskv board_force 覆盖")
    end

    board.report()
    return board.profile
end

--[[
生成启动日志文本（板型 + 全部生效引脚），便于现场核对
@return string
]]
function board.describe()
    local p = board.profile
    if not p then return "[board] 未初始化" end

    local led = p.led or {}
    local gnss = p.gnss or {}
    local volt = p.voltage or {}
    local chg = p.charger or {}
    local gs = p.gsensor or {}
    local wdt = p.wdt or {}

    local lines = {}
    lines[#lines + 1] = string.format(
        "[board] 板型识别: id=%s soc=%s source=%s", tostring(p.id), tostring(p.soc), tostring(board.source))
    lines[#lines + 1] = string.format(
        "[board] LED: net=%s chg=%s style=%s",
        tostring(led.net_pin), tostring(led.chg_pin), tostring(led.style))
    lines[#lines + 1] = string.format(
        "[board] GNSS: volgpio=%s uart=%s baud=%s",
        tostring(gnss.volgpio), tostring(gnss.uart), tostring(gnss.baud))
    lines[#lines + 1] = string.format(
        "[board] 电池电压源: %s(adc_ch=%s, range=%s, 分压=%s/%s, offset=%smV, n=%s)",
        tostring(volt.impl), tostring(volt.adc_ch), tostring(volt.range),
        tostring(volt.r_up), tostring(volt.r_down), tostring(volt.offset_mv), tostring(volt.sample_n))
    lines[#lines + 1] = string.format(
        "[board] 充电源: %s(cmd=%s vbus=%s 极性=%s 阶段可读=%s) 低压动作=%s",
        tostring(chg.impl), tostring(chg.cmd_pin), tostring(chg.vbus_pin),
        tostring(chg.vbus_polarity), tostring(chg.stage_capable),
        tostring(chg.cutoff and chg.cutoff.impl))
    lines[#lines + 1] = string.format(
        "[board] 加速度计: %s(i2c%s addr=0x%02X int=%s 供电=%s range=%sg raw_per_g=%s)",
        tostring(gs.impl), tostring(gs.i2c_id), tonumber(gs.addr) or 0,
        tostring(gs.int_pin), tostring(gs.power_pin), tostring(gs.range_g),
        tostring(gs.raw_per_g))
    -- 支撑脚清单：I2C 使用前必须全部拉高的板级引脚（上拉源 / 器件供电 / 外围供电 …）。
    -- 显式打印，避免后续再按"某个脚是干什么的"去猜测 —— 曾因此在 24/23/26 上绕了弯路。
    lines[#lines + 1] = string.format("[board] I2C1 支撑脚: %s",
        (type(gs.support_pins) == "table") and table.concat(gs.support_pins, ",")
            or "无(回退为 上拉源+供电)")
    lines[#lines + 1] = string.format(
        "[board] 硬件看门狗: %s(feed=%s 周期=%ss)",
        tostring(wdt.impl), tostring(wdt.feed_pin), tostring(wdt.interval))

    local sim = p.sim or {}
    lines[#lines + 1] = string.format(
        "[board] SIM 在位检测: %s(pin=%s 在位电平=%s 默认卡槽=SIM%s)",
        sim.detect_enable and "启用" or "关闭",
        tostring(sim.det_pin), tostring(sim.present_level), tostring(sim.boot_default))

    -- 判据源读数（现场排障：一次开机即知型号自报通路是否正常）
    lines[#lines + 1] = string.format(
        "[board] 判据源: hmeta.model=%s hmeta.chip=%s | rtos.bsp=%s rtos.firmware=%s | force=%s default=%s",
        tostring(read_model()), tostring(read_chip()),
        tostring(read_bsp()), tostring(read_firmware()),
        tostring(read_force()), tostring(read_default()))

    return table.concat(lines, "\n")
end

-- 打印启动日志（init 内部已调用；也可手动再打一次）
function board.report()
    log.info("board", "\n" .. board.describe())
end

return board
