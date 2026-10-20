--[[
@module  board
@summary 板级配置（Air8203 工业模组专用，单一产品线，不兼容 8201/8202）
@version 0.1  （框架版，待上板标定）
@date    2026.09.28

=== 设计原则 ===
本套软件**只服务 Air8203 硬件**，不做 8201/8202 兼容。因此 board.lua 的职责比
8202G 项目收窄：不再"猜测这是哪块板"，而是"确认为 8203 的哪个子型号"。

=== Air8203 子型号矩阵（依据【官网-8203 产品页】） ===
Air8203 共 12 个子型号，两个维度区分：

  维度一：主控模组（决定 GPIO 编号体系 / 是否支持音频 / 面向地区）
    H 系列 → Air780EHM   （国内）
    V 系列 → Air780EHV   （国内，**唯一支持 Mic/Speaker 音频**）
    U 系列 → Air780EHU   （海外）
    N 系列 → Air780EHN   （海外）

  维度二：板载收发器接法（决定对外 485_A/485_B 两个端子是什么）
    1 → 隔离式 RS485
    2 → 非隔离 RS485
    3 → UART3（3.3V TTL，直接引出）

  → 12 款：Air8203H1/H2/H3、V1/V2/V3、U1/U2/U3、N1/N2/N3
  （官网表格中 H3 一行印作 "Air8780H3"，系官方笔误，按 Air8203H3 理解）

=== ★ 本文件当前完成度 ===
V 系列（Air780EHV）的引脚已由 **Air8203 V1.0 原理图**（官网公开
Air8203_V1_20260909_2100.pdf，9 页，主控符号 U15 = AIR780EHV）逐脚核对，
标【图】。
H/U/N 三个系列的模组管脚编号**尚未核对**（EHM/EHU/EHN 的 PIN 编号与 EHV 有差异），
凡未核对处一律标【待核】，并在 profile 中留 nil —— 绝不用 EHV 的编号硬套。

=== 证据标记约定 ===
  【图】  = Air8203 V1.0 原理图直接读出，可信
  【官网】= 合宙官网文档明文规定
  【待核】= 需核对原理图图形/实物万用表，当前**不可用于生产**
  【待标定】= 需上板实测标定数值（分压比、极性等）

对外接口（与 8202G 项目保持一致，业务层零改动）：
  board.init()        识别子型号并构建 profile（幂等，T0 同步窗口，无阻塞）
  board.profile       当前板级配置表
  board.id            子型号标识 "8203V1" / "8203H2" / ... / "unknown"
  board.series        主控系列 "H" / "V" / "U" / "N"
  board.variant       收发器接法 "iso485" / "rs485" / "uart"
  board.source        判定来源 "force" / "hmeta" / "rtos" / "default" / "fallback"
  board.describe()    启动日志文本
  board.report()      打印启动日志
]]

local board = {}

-- ==================== 型号标识常量 ====================
board.SERIES_H = "H"   -- Air780EHM
board.SERIES_V = "V"   -- Air780EHV（唯一带音频）
board.SERIES_U = "U"   -- Air780EHU
board.SERIES_N = "N"   -- Air780EHN
board.ID_UNKNOWN = "unknown"

-- 收发器接法
board.VAR_ISO485 = "iso485"  -- 隔离式 485（CA-IS2092A）
board.VAR_RS485  = "rs485"   -- 非隔离 485（SIT3485E）
board.VAR_UART   = "uart"    -- UART3 TTL 直出

-- 传感器驱动实现
local GS_DA267 = "exs_da267"   -- 【图】U500，I2C 加速度计，与 GNSS 共挂 I2C1
local GS_NONE  = "none"

-- 充电源实现（★ 8203 无 YHM2712A，也没有任何充电 IC 单总线通信）
local CHG_TP4066 = "tp4066"  -- TP4066 线性充电 IC：无通信口，仅 CHRG/STDBY 两状态脚
local CHG_NONE   = "none"

-- 看门狗实现（★ 8203 无 Air153C，由 BLE 芯片 MS1631C 兼任）
local WDT_BLE = "ble_ms1631c"
local WDT_NONE = "none"

-- 电压源实现
local VOLT_ADC = "adc"           -- 外部 ADC + 板级分压
local VOLT_VBAT = "vbat_internal" -- 模组内部 VBAT 通道

-- 低压截止动作（8203 是"电池 + 外电共用"场景，且无 YHM2712A 船运模式）
local CUT_SHUT = "shutdown"
local CUT_NONE = "none"

--[[
板级配置表（三套 profile + 变体叠加）

★ 引脚来源说明（Air8203 V1.0 原理图，主控 U15 = AIR780EHV）：
   原理图第 1 页给出 EHV 全部管脚编号，以下直接引用。

【已实证的关键结论】
 · 主控        = Air780EHV（V 系列）
 · GNSS        = AIR510W（U510），**外置 GNSS 模组，纯 NMEA 输出，不支持二次开发**
                 （【官网-faq 2026-09-15】原文：Air510W 属于单 GNSS 模块，不支持二次开发，只输出 NMEA 数据）
 · BLE         = MS1631C-3D10A（U461），**兼作硬件看门狗**：
                 主控不按时喂它 → 它拉高 → 三极管反相 → 拉低主控 RESET_N 复位
 · 加速度计    = U500（12 脚 I2C 器件：SDA/VDDIO/INT1/VDD/GND/GNDIO/SCL）
 · I2C1 总线   = **GNSS 与加速度计共用**（PIN66 SDA / PIN67 SCL），R250/R251 4.7K 上拉
 · RS485       = 非隔离 SIT3485E（U245）或 隔离 CA-IS2092A（U491），**方向脚 = GPIO1**
 · 音频        = AW8733 功放（U480），使能 PA_EN = GPIO26（仅 V 系列有）
 · 充电 IC     = **TP4066**（U222），非 YHM2712A；无单总线通信能力
 · 电源        = 5-36V_VIN → JWH5103 DC-DC → 4.5V → JW7809-3.3 → VDD_3.3
 · 电池路径    = AO3407（Q220）P-MOS 路径管理
 · 对外接口    = J100(10PIN) + J101(5PIN)，经三极管做数字隔离
                 GPIO22M/WAKEUP2M（中断输入，湿接点，高电平触发）
                 GPIO28M/GPIO38M（输出，主控高 → 端子低）
]]

-- 各系列共用的底板定义（同一块 PCBA，仅主控不同）
-- 拆成 base + 系列增量，避免 12 份重复表
local function build_profile(series, variant, over)
    local p = {
        id      = "8203" .. series .. (variant == board.VAR_ISO485 and "1"
                    or variant == board.VAR_RS485 and "2" or "3"),
        series  = series,
        variant = variant,

        -- ==================== IO 电压域 ====================
        -- 【待核】Air780EHM/EHU/EHN 的 IO 电平档。EHV 原理图第 1 页图注明确
        --   「LTE模组默认IO电平3.3V」，且 8203 对外客户端 IO 支持 3.3V 与 5V 版本
        --   （原理图第 2 页图注），故当前按 3.3V 域处理，不调用 pm.ioVol()。
        --   ⚠️ 若后续某子型号改用 1.8V 域器件，必须在此填 io_volt_mv = 1800，
        --      由 board.init() 在**任何 gpio/i2c/uart 动作之前**下发（同 8202G 教训）。
        io_volt_mv = nil,

        -- ==================== 指示灯 ====================
        -- 8203 仍是双灯：网络灯 + 充电灯
        -- · 网络灯 LED240：【图】第 4 页，网络名 [1]GPIO27 → 主控 PIN16
        -- · 充电灯 LED202：【图】第 3 页，接在 TP4066 充电电路侧（CHRG/STDBY 网络），
        --   并**未见到**接到主控的网络名 → 【待核】极性/是否主控可编程
        --   → 若确认为硬件直驱（充电 IC 自己点亮），则 chg_pin = nil，
        --     tools 的充电灯状态机自动跳过该灯（不得崩溃）
        led = {
            net_pin = 27,      -- 【图】PIN16 GPIO27 · 网络灯 LED240
            chg_pin = nil,     -- 【待核】PIN? · 充电灯 LED202（疑似 TP4066 直驱）
            active  = 1,
            style   = "net_only",  -- 单灯可编程 + 充电灯硬件直驱
        },

        -- ==================== GNSS（AIR510W） ====================
        -- 【图】U510 = AIR510W；【官网-faq】纯 NMEA 输出模组，不支持二次开发
        -- ★【已确认 2026-09-28】硬件串口接的是 **UART2**，波特率 **115200**
        --   依据：官方 demo（D:\LUATOS\LuatOS\module\Air780EHM_Air780EHV_Air780EGH\
        --         demo\gnss\Air780EHM_Air780EHV+510W\single）的 readme 原文
        --         「接的是串口2，默认波特率115200」，demo 的 exgnss.setup 亦传 uart=2
        -- 使能：ON_OFF（U510 第 7 脚）——【待核】本板该脚接主控哪个 GPIO
        --   ⚠️ demo 用的是 GPIO21，那是**开发板接线**，不可照搬到 8203（AGENTS §1.1）
        -- 复位：RESET_GNSS = GPIO25 【图】PIN106 CAN_RXD/GPIO25
        -- 1PPS：图注「Air780EHV用WAKEUP6，其他用GPIO20」→ 待核该图注指向 1PPS 还是 G-Sensor INT
        gnss = {
            model    = "Air510W",     -- 【图】
            uart     = 2,             -- ★【已确认】UART2（demo readme：接的是串口2）
            baud     = 115200,        -- ★【已确认】demo readme：默认波特率115200
            volgpio  = nil,           -- 【待核】ON_OFF 使能脚（若板上是常开则 nil）
            reset_pin = 25,           -- 【图】PIN106 GPIO25 = RESET_GNSS
            pps_pin  = nil,           -- 【待核】1PPS → WAKEUP6(PIN75) 或 GPIO20
            i2c_id   = 1,             -- 【图】AIR510W 的 SDA/SCL 挂 I2C1
            cold_start_s = 35,        -- 【官网-Air510W】冷启动 <35s
            hot_start_s  = 1,         -- 【官网-Air510W】热启动 <1s
        },

        -- ==================== 加速度计（U500） ====================
        -- 【图】U500 12 脚 I2C 器件，挂 I2C1（与 GNSS 共总线），R250/R251 4.7K 上拉
        -- 中断 INT1 → 【待核】WAKEUP6 或 GPIO20（同 GNSS 1PPS 的二选一图注）
        -- 地址/型号：【待核】芯片丝印与 ID 寄存器，疑似 DA267 同族（0x26）
        -- ⚠️ 与 8201G 不同：本板 **无 GPIO28 上拉使能脚、无独立传感器供电脚**
        --    （上拉是常接的 4.7K 电阻），因此不需要 support_pins 机制。
        gsensor = {
            impl      = GS_DA267,
            i2c_id    = 1,       -- 【图】I2C1（PIN66 SDA / PIN67 SCL）
            addr      = 0x26,    -- 【待核】芯片地址
            int_pin   = nil,     -- 【待核】WAKEUP6(PIN75) 或 GPIO20
            power_pin = nil,     -- 【图】无独立供电控制脚
            support_pins = nil,  -- 【图】无支撑脚（上拉为常接电阻）
            range_g   = 2,
            raw_per_g = 1024,    -- 【待标定】1g → 1024 LSB（沿用 8202 协议基线）
            motion_threshold_g = 0.18,
        },

        -- ==================== 电池电压 ====================
        -- 【图】主控引出 ADC0(PIN9) / ADC1(PIN96) / ADC2(PIN77) / ADC3(PIN76)
        -- 【待核】电池分压落在哪个 ADC 通道、分压比多少
        voltage = {
            impl      = VOLT_ADC,  -- 【待核】若走模组内部 VBAT 通道则改 VOLT_VBAT
            adc_ch    = nil,       -- 【待核】
            range     = "min",
            r_up      = nil,       -- 【待核】分压上电阻
            r_down    = nil,       -- 【待核】分压下电阻
            offset_mv = 0,         -- 【待标定】
            sample_n  = 3,
        },

        -- ==================== 充电（TP4066） ====================
        -- ★ 与 8202/8201 的根本差异：**官方根本没有可通信的充电 IC**
        --   TP4066 只有 CHRG(7)/STDBY(6) 两个开漏状态脚，原理图中它们驱动充电灯 LED202，
        --   未见接入主控 GPIO。
        --   → 拿不到电压/电流/阶段，只能靠"电池电压是否在爬升"判断是否在充电。
        charger = {
            impl          = CHG_TP4066,
            cmd_pin       = nil,      -- 【图】无单总线 CMD（非 YHM2712A）
            vbus_pin      = nil,      -- 【待核】是否有 VBUS/CHG_DET 检测（EHV PIN75 = CHG_DET/WAKEUP6）
            vbus_polarity = nil,
            stage_capable = false,    -- 【图】无法读充电阶段
            cutoff        = { impl = CUT_SHUT },  -- 【图】无船运模式 → 只能软件关机
            enable        = false,    -- 【图】无软件可配充电参数
            float_mv      = nil,
            cap_mah       = nil,
        },

        -- ==================== 硬件看门狗（★ 由 BLE 芯片兼任） ====================
        -- 【图】第 6 页图注原文：「当主控不按时喂 MS1631C 时，拉高该信号，
        --       通过三极管反向后，拉低主控 RESET_N 复位」
        -- → Air8203 **没有 Air153C**，看门狗职责在 BLE 芯片上。
        -- 【待核】喂狗的物理形式（专用 GPIO 脉冲 还是 串口 AT 心跳），以及超时时长
        -- ⚠️ 这是 P0 项：不喂狗 = 设备周期复位；喂错脚 = 复位循环。
        wdt = {
            impl     = WDT_BLE,
            chip     = "MS1631C",   -- 【图】U461 MS1631C-3D10A
            feed_pin = nil,         -- 【待核】喂狗信号脚
            interval = nil,         -- 【待核】超时时长
            enable   = false,       -- 【待核】确认机制后再置 true
        },

        -- ==================== BLE（MS1631C） ====================
        -- 【图】第 6 页图注给出三条硬功能：
        --   ① 主控发 AT 指令给 MS1631C 无响应时，拉低 RESET_BLE 可复位它
        --   ② 主控进低功耗时，BLE 与手机保持连接
        --   ③ 蓝牙连接断开或收到数据时，通过 BLE_WAKEUP0 唤醒主控
        --   ④ 主控不按时喂它 → 复位主控（见 wdt）
        ble = {
            chip        = "MS1631C-3D10A",  -- 【图】
            uart        = nil,       -- 【待核】BLE 所在 UART 号
            baud        = nil,       -- 【待核】
            reset_pin   = nil,       -- 【待核】RESET_BLE 脚
            wakeup_pin  = nil,       -- 【待核】BLE_WAKEUP0（BLE→主控唤醒）
            ant_ipcx    = true,      -- 【图】J460 IPEX 一代 / J461 陶瓷 1608 可选
            apn_role    = true,      -- 【官网】出海外时可用它配置 APN
        },

        -- ==================== RS485 / UART 对外口 ====================
        -- 【图】第 2 页（非隔离）：U245 = SIT3485E，RE#/DE 由 **GPIO1** 控制
        --      （网络名 [1,9] GPIO1 出现两次 = RE#/DE 并接）
        -- 【图】第 9 页（隔离）：U491 = CA-IS2092A，3.3V 由 U490 LP5907 供给
        -- 【待核】数据脚落在哪个 UART；隔离版的 DE 控制脚
        rs485 = {
            variant   = variant,
            dir_pin   = 1,         -- 【图】非隔离版方向脚 = GPIO1（PIN22 PWM0/GPIO1）
            dir_active_high = nil, -- 【待核】发送时应置高还是低（视 RE#/DE 接法）
            uart      = nil,       -- 【待核】485 数据所在 UART
            baud      = nil,       -- 【待核】默认波特率
            iso_power_pin = nil,   -- 【待核】隔离版隔离电源使能（若有）
        },

        -- ==================== 对外数字 IO（J100/J101，经三极管隔离） ====================
        -- 【官网-8203 产品页】原文：
        --   GPIO22M  中断输入，湿接点，高电平触发 GPIO22 中断
        --   WAKEUP2M 中断输入，湿接点，高电平触发 WAKEUP2 中断
        --   GPIO38M  输出；GPIO38 输出高时 GPIO38M 为低；反之亦然
        --   GPIO28M  输出；GPIO28 输出高时 GPIO28M 为低；反之亦然
        --   补充：GPIO38 在低功耗下无法保持高；GPIO28 为 AGPIO，低功耗下可保持
        dio = {
            di_int_pins = { 22, nil },   -- 【官网】GPIO22M；WAKEUP2 语义名待映射
            do_pins     = { 28, 38 },    -- 【官网】GPIO28M（AGPIO，休眠可保持）/ GPIO38M（休眠不可保持）
            do_invert   = true,          -- 【官网】主控输出高 → 端子为低
        },

        -- ==================== 音频（仅 V 系列） ====================
        -- 【图】U480 = AW8733 功放，PA_EN = GPIO26（PIN25 CAN_TXD/GPIO26）
        --       MIC_P/MIC_N = PIN3/PIN4，SPK_P/SPK_N = PIN5/PIN6（模组内置 codec）
        -- 【官网】仅国内版本（Air780EHV）支持 Mic 收音与 Speaker 播放
        audio = {
            supported   = (series == board.SERIES_V),
            pa_en_pin   = (series == board.SERIES_V) and 26 or nil,  -- 【图】GPIO26/PA_EN
            mic_channel = 1,
            spk_channel = 1,
        },

        -- ==================== SIM ====================
        -- ★【已确认 2026-09-28】只支持**单卡 SIM0**，且卡座的 CD（在位检测）脚**没有接**：
        --   · 不做在位检测（detect_enable=false），不做双卡切换
        --   · 固定使用 SIM0（boot_default=0）
        --   · 网络注册看护外移：上电 30s 未注册 → 进出一次飞行模式，
        --     连续 3 次仍失败 → 每半小时再试（见 net_guard.lua）
        -- 【图】SIM200 卡座；USIM_VDD/RST/CLK/DATA = PIN11~14
        sim = {
            detect_enable  = false,          -- ★ 单卡 + CD 未接 → 不检测
            det_pin        = nil,            -- ★ CD 脚未接（PIN79 的 USIM_DET 语义本板不可用）
            present_level  = nil,            -- 不适用（检测已关闭）
            boot_default   = 0,              -- ★ 固定 SIM0
            debounce_ms    = 500,
            fly_off_ms     = 1000,
            fly_on_ms      = 1000,
            switch_wait_ms = 3000,
        },

        -- ==================== 模组能力 ====================
        -- 【官网】8203 V1.0 原理图第 1 页图注：「LTE模组默认IO电平3.3V」
        -- 【待核】GNSS/加速度计/BLE 混挂的 I2C1 在 V 系列上是否为 3.3V 域
        soc = nil,   -- 由 board.init() 按 series 填入
    }

    -- 覆盖项（供个别系列微调，例如 H/U/N 的引脚编号差异）
    if over then
        for k, v in pairs(over) do p[k] = v end
    end
    return p
end

-- ==================== 三套主控系列 profile ====================
local PROFILES = {}

-- V 系列：Air780EHV —— 唯一已由原理图逐脚核对的系列
PROFILES[board.SERIES_V] = build_profile(board.SERIES_V, nil)
PROFILES[board.SERIES_V].soc = "Air780EHV"

-- H 系列：Air780EHM —— 引脚编号体系与 EHV 不同，**必须重新核对原理图后再填**
PROFILES[board.SERIES_H] = build_profile(board.SERIES_H, nil)
PROFILES[board.SERIES_H].soc = "Air780EHM"
-- 【待核】以下字段在 H 系列上大概率不同，确认前保持 nil：
PROFILES[board.SERIES_H].led.net_pin      = nil
PROFILES[board.SERIES_H].gnss.reset_pin   = nil
PROFILES[board.SERIES_H].rs485.dir_pin    = nil
PROFILES[board.SERIES_H].audio.pa_en_pin  = nil
PROFILES[board.SERIES_H].audio.supported  = false  -- 【官网】音频仅国内版（EHV）实现

-- U 系列：Air780EHU —— 海外版，同样待核
PROFILES[board.SERIES_U] = build_profile(board.SERIES_U, nil)
PROFILES[board.SERIES_U].soc = "Air780EHU"
PROFILES[board.SERIES_U].led.net_pin     = nil
PROFILES[board.SERIES_U].gnss.reset_pin  = nil
PROFILES[board.SERIES_U].rs485.dir_pin   = nil
PROFILES[board.SERIES_U].audio.pa_en_pin = nil
PROFILES[board.SERIES_U].audio.supported = false

-- N 系列：Air780EHN —— 海外版，同样待核
PROFILES[board.SERIES_N] = build_profile(board.SERIES_N, nil)
PROFILES[board.SERIES_N].soc = "Air780EHN"
PROFILES[board.SERIES_N].led.net_pin     = nil
PROFILES[board.SERIES_N].gnss.reset_pin  = nil
PROFILES[board.SERIES_N].rs485.dir_pin   = nil
PROFILES[board.SERIES_N].audio.pa_en_pin = nil
PROFILES[board.SERIES_N].audio.supported = false

-- ==================== unknown 兜底 profile ====================
-- 识别失败：禁用全部外设能力，仅保留"联网 + 上报"主链路，并显式告警。
-- 与 8202G 的经验一致：宁可功能全禁并报错，也不能猜错引脚把外设打死。
local function build_unknown_profile()
    return {
        id = board.ID_UNKNOWN, series = nil, variant = nil, soc = nil,
        io_volt_mv = nil,
        led = { net_pin = nil, chg_pin = nil, active = 1, style = "none" },
        gnss = { model = nil, uart = nil, baud = nil, volgpio = nil, reset_pin = nil,
                 pps_pin = nil, i2c_id = 1, cold_start_s = 35, hot_start_s = 1 },
        gsensor = { impl = GS_NONE, i2c_id = 1, addr = 0x26, int_pin = nil,
                    power_pin = nil, support_pins = nil, range_g = 2,
                    raw_per_g = 1024, motion_threshold_g = 0.18 },
        voltage = { impl = VOLT_VBAT, adc_ch = 0, range = "min",
                    r_up = nil, r_down = nil, offset_mv = 0, sample_n = 3 },
        charger = { impl = CHG_NONE, cmd_pin = nil, vbus_pin = nil, vbus_polarity = nil,
                    stage_capable = false, cutoff = { impl = CUT_NONE },
                    enable = false, float_mv = nil, cap_mah = nil },
        wdt  = { impl = WDT_NONE, chip = nil, feed_pin = nil, interval = nil, enable = false },
        ble  = { chip = nil, uart = nil, baud = nil, reset_pin = nil, wakeup_pin = nil },
        rs485 = { variant = nil, dir_pin = nil, dir_active_high = nil, uart = nil, baud = nil },
        dio  = { di_int_pins = {}, do_pins = {}, do_invert = true },
        audio = { supported = false, pa_en_pin = nil },
        sim = { detect_enable = false, det_pin = nil, present_level = 1,
                boot_default = 0, debounce_ms = 500, fly_off_ms = 1000,
                fly_on_ms = 1000, switch_wait_ms = 3000 },
    }
end

-- ==================== 内部工具 ====================

-- 深拷贝（profile 只读使用）
local function dup(t)
    local o = {}
    for k, v in pairs(t) do
        o[k] = (type(v) == "table") and dup(v) or v
    end
    return o
end

-- fskv 强制覆盖（现场排障）：board_force = "V1" / "H2" / "U3" ...
local function read_force()
    if not fskv or not fskv.get then return nil end
    local ok, v = pcall(fskv.get, "board_force")
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

--[[
从型号字符串提取主控系列。

★ 主判据 = hmeta.model()（【官网】明确不要用 rtos.bsp() 判具体型号，粒度不一致）
   Air780EHM → H    Air780EHV → V    Air780EHU → U    Air780EHN → N
   兼容别名：个别固件可能自报 Air780EPM（与 EHM 硬件完全一致，【官网】原文明示）
             → 按 H 系列处理
]]
local function match_series(s)
    if type(s) ~= "string" or s == "" then return nil end
    local u = s:upper()
    if u:find("EHV", 1, true) then return board.SERIES_V end
    if u:find("EHM", 1, true) then return board.SERIES_H end
    if u:find("EPM", 1, true) then return board.SERIES_H end  -- 与 EHM 硬件一致
    if u:find("EHU", 1, true) then return board.SERIES_U end
    if u:find("EHN", 1, true) then return board.SERIES_N end
    return nil
end

-- 解析变体："V1" → {series="V", variant=iso485}
local function match_variant(s)
    if type(s) ~= "string" or s == "" then return nil, nil end
    local u = s:upper():gsub("%s", "")
    -- 允许 "8203V1" / "V1" / "V-1" 等写法
    local letter, num = u:match("([HVUN])[%-]?([123])$")
    if not letter then return nil, nil end
    local variant = (num == "1") and board.VAR_ISO485
                 or (num == "2") and board.VAR_RS485
                 or board.VAR_UART
    return letter, variant
end

-- 判据源（hmeta / rtos 为核心库，直接调用，不做存在性判断 —— 与 8202G 教训一致）
local function read_model()
    local m = hmeta.model()
    if type(m) == "string" and m ~= "" then return m end
    return nil
end
local function read_chip()
    local m = hmeta.chip()
    if type(m) == "string" and m ~= "" then return m end
    return nil
end
local function read_bsp()
    local b = rtos.bsp()
    if type(b) == "string" and b ~= "" then return b end
    return nil
end
local function read_firmware()
    local s = rtos.firmware()
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

--[[
判定主控系列。
优先级：fskv board_force > hmeta.model > hmeta.chip > rtos.bsp > rtos.firmware
        > 构建期 BOARD_DEFAULT
]]
local function resolve_series()
    -- 1) 强制覆盖
    local f = read_force()
    if f then
        local s, v = match_variant(f)
        if s and PROFILES[s] then return s, v, "force" end
    end

    -- 2~5) 字符串判据源
    local sources = {
        { src = "hmeta",    get = read_model },
        { src = "chip",     get = read_chip },
        { src = "bsp",      get = read_bsp },
        { src = "firmware", get = read_firmware },
    }
    for _, s in ipairs(sources) do
        local v = s.get()
        if v then
            local series = match_series(v)
            if series then return series, nil, s.src end
        end
    end

    -- 6) 构建期兜底
    local d = BOARD_DEFAULT
    if type(d) == "string" and d ~= "" then
        local s, v = match_variant(d)
        if s and PROFILES[s] then return s, v, "default" end
    end

    return nil, nil, "fallback"
end

--[[
解析收发器变体。优先级：
  1) fskv board_force 里带的数字后缀（如 "V1"）—— 现场排障用，最高优先
  2) 构建期常量 BOARD_VARIANT（1=隔离485 / 2=非隔离485 / 3=UART，也接受 "2"/"V2" 写法）
  3) 默认非隔离 485
说明：8203 的子型号靠"板载收发器接法"区分，而这一点主控无法自报 → 只能靠构建期指定。
]]
local function resolve_variant(series, forced)
    if forced then return forced end

    local v = BOARD_VARIANT
    local n
    if type(v) == "number" then
        n = tostring(math.floor(v))
    elseif type(v) == "string" and v ~= "" then
        n = v:sub(-1)
    end
    if n == "1" then return board.VAR_ISO485 end
    if n == "2" then return board.VAR_RS485  end
    if n == "3" then return board.VAR_UART   end

    return board.VAR_RS485  -- 默认按最常见的非隔离 485 处理
end

-- ==================== 对外接口 ====================

--[[
识别板型并构建 profile（幂等，T0 同步窗口，禁止阻塞/外设 I/O）

★ 与 8202G 的差异：本板**不需要** IO 电压域下发与管脚复用下发（原理图已固定 3.3V 域、
  且 I2C1 上拉为常接 4.7K 电阻，无需软件使能）。若后续实测发现某系列需要，再按
  8202G 的 apply_io_volt / apply_pinmux 模式补上 —— 但同样必须在**任何 gpio/i2c/uart
  动作之前**执行，这是不可妥协的时序约束。
]]
function board.init()
    if board.profile then return board.profile end

    local series, variant_forced, source = resolve_series()
    board.source = source

    if not series then
        board.id = board.ID_UNKNOWN
        board.series, board.variant = nil, nil
        board.profile = build_unknown_profile()
        log.error("board", "8203 板型识别失败（型号自报不可用）",
            "hmeta.model=", tostring(read_model()),
            "rtos.bsp=", tostring(read_bsp()),
            "rtos.firmware=", tostring(read_firmware()),
            "→ 已禁用全部外设能力。补救：① main.lua 设 BOARD_DEFAULT；② fskv board_force")
        return board.profile
    end

    local variant = resolve_variant(series, variant_forced)
    board.series  = series
    board.variant = variant
    board.profile = dup(PROFILES[series])
    board.profile.variant = variant
    board.profile.rs485.variant = variant

    -- id 形如 "8203V2"
    board.id = "8203" .. series .. (
        variant == board.VAR_ISO485 and "1" or
        variant == board.VAR_RS485  and "2" or "3")

    if source == "default" then
        log.error("board", "型号自报失败，已按构建期 BOARD_DEFAULT=", series,
            " 兜底。⚠️ 该固件无型号自适应能力，切勿烧到其它系列板。")
    end

    if variant_forced then
        log.warn("board", "收发器变体由 board_force 强制指定:", variant)
    end

    board.report()
    return board.profile
end

--[[
生成启动日志文本（全部生效引脚，便于现场核对）
]]
function board.describe()
    local p = board.profile
    if not p then return "[board] 未初始化" end

    local g  = p.gnss or {}
    local gs = p.gsensor or {}
    local v  = p.voltage or {}
    local c  = p.charger or {}
    local w  = p.wdt or {}
    local b  = p.ble or {}
    local r  = p.rs485 or {}
    local s  = p.sim or {}

    local L = {}
    L[#L+1] = string.format("[board] 型号: id=%s series=%s soc=%s variant=%s source=%s",
        tostring(p.id), tostring(p.series), tostring(p.soc), tostring(p.variant), tostring(board.source))
    L[#L+1] = string.format("[board] IO 电压域: %s",
        p.io_volt_mv and (p.io_volt_mv .. "mV") or "沿用固件默认（原理图已固定 3.3V）")
    L[#L+1] = string.format("[board] 指示灯: net=%s chg=%s style=%s",
        tostring(p.led.net_pin), tostring(p.led.chg_pin), tostring(p.led.style))
    L[#L+1] = string.format("[board] GNSS: %s uart=%s baud=%s reset=%s pps=%s i2c=%s（冷启<%ss 热启<%ss）",
        tostring(g.model), tostring(g.uart), tostring(g.baud), tostring(g.reset_pin),
        tostring(g.pps_pin), tostring(g.i2c_id), tostring(g.cold_start_s), tostring(g.hot_start_s))
    L[#L+1] = string.format("[board] 加速度计: %s i2c%s addr=0x%02X int=%s power=%s range=%sg raw_per_g=%s",
        tostring(gs.impl), tostring(gs.i2c_id), tonumber(gs.addr) or 0,
        tostring(gs.int_pin), tostring(gs.power_pin), tostring(gs.range_g), tostring(gs.raw_per_g))
    L[#L+1] = string.format("[board] 电池电压: %s ch=%s 分压=%s/%s offset=%smV n=%s",
        tostring(v.impl), tostring(v.adc_ch), tostring(v.r_up), tostring(v.r_down),
        tostring(v.offset_mv), tostring(v.sample_n))
    L[#L+1] = string.format("[board] 充电: %s cmd=%s vbus=%s 阶段可读=%s 低压动作=%s",
        tostring(c.impl), tostring(c.cmd_pin), tostring(c.vbus_pin),
        tostring(c.stage_capable), tostring(c.cutoff and c.cutoff.impl))
    L[#L+1] = string.format("[board] 看门狗: %s chip=%s feed=%s 周期=%s enable=%s",
        tostring(w.impl), tostring(w.chip), tostring(w.feed_pin),
        tostring(w.interval), tostring(w.enable))
    L[#L+1] = string.format("[board] BLE: %s uart=%s baud=%s reset=%s wakeup=%s",
        tostring(b.chip), tostring(b.uart), tostring(b.baud),
        tostring(b.reset_pin), tostring(b.wakeup_pin))
    L[#L+1] = string.format("[board] 485/UART: variant=%s dir_pin=%s uart=%s baud=%s",
        tostring(r.variant), tostring(r.dir_pin), tostring(r.uart), tostring(r.baud))
    L[#L+1] = string.format("[board] 对外 DIO: DI=%s DO=%s 取反=%s",
        (type(p.dio.di_int_pins) == "table") and table.concat(p.dio.di_int_pins, ",") or "-",
        (type(p.dio.do_pins) == "table") and table.concat(p.dio.do_pins, ",") or "-",
        tostring(p.dio.do_invert))
    L[#L+1] = string.format("[board] 音频: supported=%s pa_en=%s",
        tostring(p.audio.supported), tostring(p.audio.pa_en_pin))
    L[#L+1] = string.format("[board] SIM: 检测=%s pin=%s 在位电平=%s 默认卡槽=%s",
        s.detect_enable and "启用" or "关闭", tostring(s.det_pin),
        tostring(s.present_level), tostring(s.boot_default))
    L[#L+1] = string.format("[board] 判据源: model=%s chip=%s bsp=%s fw=%s force=%s default=%s",
        tostring(read_model()), tostring(read_chip()), tostring(read_bsp()),
        tostring(read_firmware()), tostring(read_force()), tostring(BOARD_DEFAULT))

    return table.concat(L, "\n")
end

function board.report()
    log.info("board", "\n" .. board.describe())
end

-- 便捷判定：业务层用这些函数代替散落的 series 字面量比较
function board.is_series(x)  return board.series == x end
function board.has_audio()   return board.profile and board.profile.audio.supported == true end
function board.is_iso485()   return board.variant == board.VAR_ISO485 end

return board
