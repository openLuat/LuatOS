--[[
@module  platform_loader
@summary 平台检测与项目配置加载器（触摸显示偏移测试精简版 · factory_new 初始化方式）
@version 2.0
@date    2026.09.22
@author  江访

=== 执行流程 ===

require 即执行，按以下顺序：
  1. 编译清单：require (...) 声明所有需要打包进固件的配置文件和驱动（编译系统静态分析用）
  2. 平台检测：hmeta.model() → 识别芯片型号 → 设 _G.model_str / _G.is_pc
  3. PROJECT 映射：长命名 "Engine_Air1602_5inch_720x1280_002_V000" → 短文件名 "eng_1602_5i_v2"
  4. 配置加载：require(cfg_name) → 返回配置 table → 存入 _G.project_config
  5. PC 适配：模拟器环境补充 mobile.* 桩函数
  6. 引脚初始化：遍历 config.pins，逐条调用 pins.setup(pin, func)
  7. 供电上电：按 config.power_on 时序设置 GPIO 电平（与 factory_new 工厂工程一致）

=== 与 factory_new 工厂工程 platform_loader 的差异 ===

本工程只做显示/触摸偏移测试，编译清单和业务加载中去掉了网络、AirCloud、
设置上报等业务模块，只保留：配置文件 + LCD/TP 驱动 + 供电/引脚初始化。
PROJECT 映射表与 factory_new 一致（含 8603 十型号 / 8605 四型号 / 8607 三型号 /
8601·8602 的 WiFi·4G 拆分型号），并补挂了 factory_new 遗漏的
EVB_Air8101B_5inch_480x854_000_V010 → evb_8101b_5i_v1（配置文件存在但未映射）。

上电序列末尾会置 _G.__power_on_done 并发布 POWER_ON_DONE：
main.lua 以此门控 LCD/触摸初始化，避免外设电源未稳就初始化 GT911 导致触摸失灵。

=== 关键设计（factory_new · display 底层初始化） ===

- RGB 屏统一走 lcd_display_rgb 驱动：内部 display.init("custom", ...) 一次完成
  SPI IC 寄存器序列（custom_cmds）+ RGB 接口时序 + FrameBuffer 分配；
  需要 SPI 初始化的面板 IC（如 ST7701S）由配置文件通过 ic_init 回调提供寄存器序列

- 短文件名映射（PROJECT_MAP）：LuatOS 文件系统限制文件名 ≤24 字节，长 PROJECT 名
  必须映射到短名。命名格式: {eng|evb|cor}_{芯片简写}_{尺寸简写}_{版本简写}

- 三级回退策略（容错设计）：
  第一级：PROJECT_MAP 命中 → require 配置文件 → 返回 table
  第二级：配置文件 require 返回非 table → PC 配置（根据 PROJECT 名推断分辨率）
  第三级：PROJECT_MAP 未命中 → PC配置

- require 编译清单：头部 require (...) 不是给运行时用的，是给编译系统静态分析用的。
  编译系统扫描这些 require 语句决定哪些 .lua 文件打包进固件。
]]

-- ==================== 编译清单（编译系统静态分析，运行时不执行） ====================
-- 新增驱动或配置文件时在此加一行，编译系统会自动打包对应 .lua 文件。
-- 包进永不调用的函数：顶层 require 会在点亮屏幕前把全部配置表读进内存（40+ 个 table，
-- 占脚本区 RAM 且拖慢启动）；函数体内的静态 require 编译系统文本扫描同样能扫到
-- （与 factory_new 的 _compile_manifest 同一机制）。

local function _compile_manifest()
-- 所有配置文件（与 factory_new 工厂工程一致：≥800×480 / 480×854 型号）
-- 注：config/eng_8601_7i_v0.lua、config/eng_8602_9i_v0.lua 已被 factory_new 拆分为
--     WiFi / 4G 两个出货型号（2026.10.14），本工程沿用拆分后的配置，这两个旧文件
--     保留在磁盘上仅作参考，不再打包、不再被 PROJECT_MAP 引用。
require ("pc_default")        -- PC 模拟器回退
require ("eng_1602_5i_v2")    -- Air1602 5寸 720×1280 NV3052C
require ("eng_1602_5i_v3")    -- Air1602 5寸 720×1280 NV3052C + NAND
require ("eng_1602_5i_v5")    -- Air1602 5寸 480×854 ST7701S + NAND
require ("eng_1602_7i_v0")    -- Air1602 7寸 1024×600
require ("eng_1602_7i_v4")    -- Air1602 7寸 1024×600 + NAND
require ("eng_1602_9i_v09421")    -- Air1602 9寸 1024×600
require ("eng_1602_10i_v0")       -- Air1602 10寸 1024×600
require ("eng_1602_10i_v10421")   -- Air1602 10寸 1024×600
require ("eng_8601_7i_wifi")     -- Air8601 7寸 1024×600 HX8282 + Airlink UART WiFi(6205)（WiFi 版）
require ("eng_8601_7i_4g")       -- Air8601 7寸 1024×600 HX8282 + Airlink UART 4G(780ER2)（4G 版）
require ("eng_8602_9i_wifi")     -- Air8602 9寸 1024×600 HX8282 + Airlink UART WiFi(6205)（WiFi 版）
require ("eng_8602_9i_4g")       -- Air8602 9寸 1024×600 HX8282 + Airlink UART 4G(780ER2)（4G 版）
require ("eng_8603w1_10i_v0")    -- Air8603W1 10寸 1024×600 + WiFi(6205) + 隔离485(UART1) + UVC(UART2) + Air1103语音
require ("eng_8603w2_10i_v0")    -- Air8603W2 10寸 1024×600 + WiFi(6205) + 非隔离485(UART1) + UVC(UART2)
require ("eng_8603w3_10i_v0")    -- Air8603W3 10寸 1024×600 + WiFi(6205) + 隔离485(UART1/UART2) + UVC(USB)
require ("eng_8603w4_10i_v0")    -- Air8603W4 10寸 1024×600 + WiFi(6205) + 非隔离485(UART1) + 隔离485(UART2) + UVC(USB)
require ("eng_8603w5_10i_v0")    -- Air8603W5 10寸 1024×600 + WiFi(6205) + TTL串口(UART1) + 隔离485(UART2) + UVC(USB)
require ("eng_8603m1_10i_v0")    -- Air8603M1 10寸 1024×600 + 4G(780ER2) + 隔离485(UART1) + UVC(UART2) + Air1103语音
require ("eng_8603m2_10i_v0")    -- Air8603M2 10寸 1024×600 + 4G(780ER2) + 非隔离485(UART1) + UVC(UART2)
require ("eng_8603m3_10i_v0")    -- Air8603M3 10寸 1024×600 + 4G(780ER2) + 隔离485(UART1/UART2) + UVC(USB)
require ("eng_8603m4_10i_v0")    -- Air8603M4 10寸 1024×600 + 4G(780ER2) + 非隔离485(UART1) + 隔离485(UART2) + UVC(USB)
require ("eng_8603m5_10i_v0")    -- Air8603M5 10寸 1024×600 + 4G(780ER2) + TTL串口(UART1) + 隔离485(UART2) + UVC(USB)
require ("eng_8605_10i_v0")      -- Air8605 10寸 1024×600 + 4G(780ER2) + 非隔离485(UART1) + UVC + SD（无 Air1103）
require ("eng_8605w_10i_v0")     -- Air8605W 10寸 1024×600 + WiFi(6205) + Air1103语音 + NAND + UVC + 隔离485
require ("eng_8605m_10i_v0")     -- Air8605M 10寸 1024×600 + 4G(780ER2) + Air1103语音 + NAND + UVC + 隔离485
require ("eng_8605b_10i_v0")     -- Air8605B 10寸 1024×600 + 4G(780ER2) + NAND + UVC + 双隔离485(UART1/UART6)
require ("eng_8607_10i_v0")      -- Air8607 10寸 1024×600 + PWM背光 + 喇叭(HT6873) + SD（无网络）
require ("eng_8607a_10i_v0")     -- Air8607A 10寸 1024×600 + PWM背光 + 喇叭(HT6873) + UVC（无 SD/网络）
require ("eng_8607w_10i_v0")     -- Air8607W 10寸 1024×600 + WiFi(601S,SPI5) + 非隔离485 + 人脸识别摄像头 + SD
require ("evb_8101_5i_v0")       -- Air8101 5寸 800×480 H050IWV
require ("evb_8101_7i_v0")       -- Air8101 7寸 1024×600
require ("evb_8101_9i_v0")       -- Air8101 9寸 1024×600
require ("evb_8101_10i_v0")      -- Air8101 10寸 1024×600
require ("evb_8101b_5i_v1")      -- Air8101B 5寸 480×854 ST7701S
require ("evb_8101b_5i_v2")      -- Air8101B 5寸 480×854 GC9503
require ("evb_1601_5i_v11")      -- Air1601 5寸 800×480
require ("evb_1601_7i_v11")      -- Air1601 7寸 1024×600
require ("evb_1601_7i_v12")      -- Air1601 7寸 1024×600
require ("evb_1601_10i_v11")     -- Air1601 10寸 1024×600

-- LCD/TP 驱动（factory_new · display 底层初始化）
require ("lcd_display_rgb")   -- RGB 屏统一驱动（内部走 display.init）
require ("lcd_st7701s_5in")   -- ST7701S IC 初始化序列（作为 ic_init 回调被配置文件引用）
require ("tp_gt911")          -- GT911 触摸（统一）
end

-- ==================== 1. 平台检测 ====================
-- hmeta.model() 返回芯片型号字符串（如 "Air1602_A10"），不可用则回退到 rtos.bsp()
local ok, _model = pcall(hmeta.model)
if not ok or not _model then _model = rtos.bsp() end
_G.model_str = tostring(_model or "")

-- PC 模拟器检测：hmeta.model 在 PC 上会报错，model_str 为空或 "PC"
_G.is_pc = (not ok) or (_G.model_str == "PC") or (_G.model_str == "")

-- ==================== 2. PROJECT 长名 → 短文件名映射 ====================
-- 短名格式: {eng|evb|cor}_{芯片简写}_{尺寸简写}_{版本简写}，目标 ≤24 字节
-- eng = Engine 引擎主机, evb = EVB turnkey 开发板, cor = Core 核心板
-- 与 factory_new 工厂工程一致（≥800×480 / 480×854）
local PROJECT_MAP = {
    -- Engine 引擎主机系列（已实现）
    ["Engine_Air1602_5inch_720x1280_002_V000"]     = "eng_1602_5i_v2",
    ["Engine_Air1602_7inch_1024x600_000_V000"]     = "eng_1602_7i_v0",
    ["Engine_Air1602_10inch1_1024x600_001_V000"]   = "eng_1602_10i_v0",
    ["Engine_Air1602_5inch_720x1280_003_V000"]     = "eng_1602_5i_v3",
    ["Engine_Air1602_5inch_480x854_005_V000"]      = "eng_1602_5i_v5",
    ["Engine_Air1602_7inch_1024x600_004_V000"]     = "eng_1602_7i_v4",
    ["Engine_Air1602_AirLCD_1090_09421_V000"]     = "eng_1602_9i_v09421",
    ["Engine_Air1602_AirLCD_1100_10421_V000"]     = "eng_1602_10i_v10421",
    ["Engine_Air8601_7inch_1024x600_010_WiFi_V000"] = "eng_8601_7i_wifi",
    ["Engine_Air8601_7inch_1024x600_010_4G_V000"]   = "eng_8601_7i_4g",
    ["Engine_Air8602_9inch_1024x600_010_WiFi_V000"] = "eng_8602_9i_wifi",
    ["Engine_Air8602_9inch_1024x600_010_4G_V000"]   = "eng_8602_9i_4g",
    ["Engine_Air8603W1_10inch_1024x600_000_WiFi_V000"] = "eng_8603w1_10i_v0",
    ["Engine_Air8603W2_10inch_1024x600_000_WiFi_V000"] = "eng_8603w2_10i_v0",
    ["Engine_Air8603W3_10inch_1024x600_000_WiFi_V000"] = "eng_8603w3_10i_v0",
    ["Engine_Air8603W4_10inch_1024x600_000_WiFi_V000"] = "eng_8603w4_10i_v0",
    ["Engine_Air8603W5_10inch_1024x600_000_WiFi_V000"] = "eng_8603w5_10i_v0",
    ["Engine_Air8603M1_10inch_1024x600_000_4G_V000"]   = "eng_8603m1_10i_v0",
    ["Engine_Air8603M2_10inch_1024x600_000_4G_V000"]   = "eng_8603m2_10i_v0",
    ["Engine_Air8603M3_10inch_1024x600_000_4G_V000"]   = "eng_8603m3_10i_v0",
    ["Engine_Air8603M4_10inch_1024x600_000_4G_V000"]   = "eng_8603m4_10i_v0",
    ["Engine_Air8603M5_10inch_1024x600_000_4G_V000"]   = "eng_8603m5_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_4G_V000"]     = "eng_8605_10i_v0",
    ["Engine_Air8605W_10inch_1024x600_000_WiFi_V000"]  = "eng_8605w_10i_v0",
    ["Engine_Air8605M_10inch_1024x600_000_4G_V000"]    = "eng_8605m_10i_v0",
    ["Engine_Air8605B_10inch_1024x600_000_4G_V000"]    = "eng_8605b_10i_v0",
    ["Engine_Air8607_10inch_1024x600_000_V000"]        = "eng_8607_10i_v0",
    ["Engine_Air8607A_10inch_1024x600_000_V000"]       = "eng_8607a_10i_v0",
    ["Engine_Air8607W_10inch_1024x600_000_V000"]       = "eng_8607w_10i_v0",
    -- 别名：改名前的旧 PROJECT 名（与 factory_new 一致）
    -- 8601 / 8602 拆分前只有单一配置文件 eng_8601_7i_v0 / eng_8602_9i_v0，
    -- 现统一落到 WiFi 版（同一底板电阻切换，仅 features/network/ui 不同，屏幕与触摸参数完全一致）
    ["Engine_Air8601_7inch_1024x600_010_V000"]        = "eng_8601_7i_wifi",
    ["Engine_Air8602_9inch_1024x600_010_V000"]        = "eng_8602_9i_wifi",
    -- 8603 改名前的全功能旧名（W 系列落 W1，M 系列落 M1）
    ["Engine_Air8603W_10inch_1024x600_000_V000"]      = "eng_8603w1_10i_v0",
    ["Engine_Air8603W_10inch_1024x600_000_WiFi_V000"] = "eng_8603w1_10i_v0",
    ["Engine_Air8603M_10inch_1024x600_000_V000"]      = "eng_8603m1_10i_v0",
    ["Engine_Air8603M1_10inch_1024x600_000_V000"]     = "eng_8603m1_10i_v0",
    -- 8605 旧名（WiFi 版已并入 8605W，8605B 由双网改 4G 单网）
    ["Engine_Air8605_10inch_1024x600_000_V000"]       = "eng_8605_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_WiFi_V000"]  = "eng_8605w_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_WIFI_V000"]  = "eng_8605w_10i_v0",
    ["Engine_Air8605B_10inch_1024x600_000_V000"]      = "eng_8605b_10i_v0",
    -- EVB turnkey 开发板系列（已实现）
    ["EVB_Air8101_AirLCD_1020_000_V020"]            = "evb_8101_5i_v0",
    ["EVB_Air8101_AirLCD_1090_000_V020"]            = "evb_8101_9i_v0",
    ["EVB_Air8101_AirLCD_1100_000_V020"]            = "evb_8101_10i_v0",
    ["EVB_Air8101_AirLCD_1070_000_V020"]            = "evb_8101_7i_v0",
    ["EVB_Air8101B_5inch_480x854_000_V010"]        = "evb_8101b_5i_v1",   -- factory_new 的 PROJECT_MAP 漏挂了此型号，本工程补上
    ["EVB_Air8101B_5inch_480x854_000_V020"]        = "evb_8101b_5i_v2",
    ["EVB_Air1601_5inch_800x480_000_V011"]      = "evb_1601_5i_v11",
    ["EVB_Air1601_7inch_1024x600_000_V011"]     = "evb_1601_7i_v11",
    ["EVB_Air1601_7inch_1024x600_000_V012"]     = "evb_1601_7i_v12",
    ["EVB_Air1601_10inch1_1024x600_000_V011"]   = "evb_1601_10i_v11",
}

-- ==================== 3. 加载项目配置 ====================

--[[
生成 PC 模拟器/未命中映射时使用的回退配置（lcd_display_rgb + GT911）
@param number w  模拟屏幕宽度
@param number h  模拟屏幕高度
@param number sz 模拟屏幕尺寸（英寸），仅用于密度计算
@param boolean need_buf  是否需要帧缓冲
@param number fs  字体大小
@return table  配置表 { name, chip, pins, hw={lcd,tp} }
]]
local function make_pc_config(w, h, sz, need_buf, fs)
    return {
        name = "PC", chip = "PC", baseboard = "PC", pins = {},
        hw = {
            lcd = { model = "lcd_display_rgb", params = { port = lcd.HWID_0, pin_rst = 36, direction = 0, w = w, h = h }, need_buffer = need_buf, screen_size = sz, font = { size = fs }, backlight = { pwm_ch = 0, pwm_freq = 1000 } },
            tp  = { model = "tp_gt911", params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0 } },
        },
    }
end

--[[
加载 PROJECT 对应的硬件配置
@param string project  PROJECT 长名
@return table  配置表 { name, chip, baseboard, pins, power_on, hw={lcd,tp}, ... }
@logic
  1. PC 模拟 → 内联配置
  2. PROJECT_MAP 命中 → require 配置文件 → 返回 table
  3. 失败 → 回退：根据 PROJECT 长名推断分辨率的 PC 配置
]]
local function load_project_config(project)
    -- PC 模拟器：直接返回内联配置，避免依赖文件系统
    if project == "PC" or project:find("^PC") then
        _G.model_str = "PC"
        socket.dft(socket.ETH0)                        -- PC 模拟器用 ETH0 网卡
        _G.mobile = {}                                  -- 补充 mobile 模块桩
        function mobile.imei() return "pc_simulator" end
        return make_pc_config(800, 480, 5.0, true, 20)
    end

    -- 正常路径：PROJECT_MAP 查找 → require 配置文件
    local cfg_name = PROJECT_MAP[project]
    if cfg_name then
        local cfg = require(cfg_name)
        -- require 返回配置文件 return 的 table（不是 boolean）
        if type(cfg) == "table" then
            log.info("platform_loader", "配置加载成功:", cfg_name, "<-", project)
            return cfg
        end
        log.warn("platform_loader", "配置文件加载失败:", cfg_name, "，回退到 PC 模拟")
    else
        log.warn("platform_loader", "未找到 PROJECT 映射:", project, "，回退到 PC 模拟")
    end

    -- 最终回退：生成 PC 配置
    -- 从 PROJECT 名中提取分辨率信息（如 "720x1280"），用于模拟器窗口大小
    _G.model_str = "PC"
    socket.dft(socket.ETH0)
    _G.mobile = {}
    function mobile.imei() return "pc_simulator" end    -- 触摸测试不需要 IMEI，保留桩避免缺模块

    local w, h, sz, need_buf, fs = 800, 480, 5.0, true, 20
    local _, _, rw, rh = project:find("(%d+)x(%d+)")   -- 正则提取 "720x1280"
    if rw and rh then w, h = tonumber(rw), tonumber(rh) end
    if project:find("7inch") then sz = 7.0 elseif project:find("10inch") then sz = 10.0 end

    return make_pc_config(w, h, sz, need_buf, fs)
end

-- 全局存储配置，后续所有模块通过 _G.project_config 读取硬件参数
_G.project_config = load_project_config(_G.PROJECT)

-- ==================== 4. PC 运行时适配 ====================
-- 在 PC 模拟器上补充真机才有的 mobile 模块桩函数，避免 require 时报 nil
if _G.is_pc then
    _G.model_str = "PC"
    _G.project_config.chip = "PC"
    socket.dft(socket.ETH0)
    _G.mobile = {}
    function mobile.imei() return "pc_simulator" end
end

-- ==================== 5. 配置引脚（底板决定接线） ====================
-- 引脚配置由底板决定，不在驱动中硬编码。逐条调用 pins.setup 设置引脚功能
-- 与 factory_new 工厂工程完全一致，保证供电和接线行为不变
local config = _G.project_config
if config.pins and pins then
    for _, p in ipairs(config.pins) do
        pcall(pins.setup, p.pin, p.func)                -- pcall 防止单条引脚配置失败阻塞整体
    end
    log.info("platform_loader", "引脚配置完成, 数量:", #config.pins)
end

-- ==================== 6. GPIO 供电上电（底板决定） ====================
-- power_on 格式: { pin=GPIO编号, level=0低/1高, [delay=延时ms], [dir=兼容旧字段] }
-- 例: Airlink WiFi 模组上电 → GPIO 拉低/拉高保持，LCD/TP/触摸供电使能等
-- 步骤间带 delay 时使用 sys.wait，不阻塞主线程
--
-- 电平直接写进 gpio.setup 第 2 参：gpio.setup(pin, mode) 里 0/1 都是输出模式、
-- 数字即初始电平。不能拿 dir 当初始电平再靠 gpio.set 纠正 —— set 前引脚已停在
-- 错误电平上（如 WIFI_EN 要求拉低，setup(pin,1) 会先给一个高脉冲）。
--
-- 完成标记：整条序列（含各步 delay 的电源稳定时间）跑完后置 _G.__power_on_done
-- 并发布 POWER_ON_DONE。main.lua 以此为门再初始化 LCD/触摸 —— I2C 总线上未上电的
-- 设备会钳住 SDA/SCL，GT911 也会因电源未稳而软失败（触摸"完全失灵"）。
--
--[[
供电上电协程函数，按 config.power_on 时序逐条设置 GPIO 电平
@param 无
@return 无（协程函数，内部使用 sys.wait）
]]
local function power_on_task_func()
    -- 背光 PWM 上电前先压灭：PWM 引脚默认高电平，上电瞬间 BL 即被拉高点亮，
    -- 会抢在测试界面首帧之前亮屏（白屏/残影）。仅 PWM 背光板需要这一步。
    local bl = config.hw and config.hw.lcd and config.hw.lcd.backlight
    if bl and bl.pwm_ch then
        pcall(pwm.setup, bl.pwm_ch, bl.pwm_freq or 1000, 0)  -- 占空比 0 = 熄灭
        pcall(pwm.start, bl.pwm_ch)
        log.info("platform_loader", "背光 PWM", bl.pwm_ch, "上电即压灭(占空比0)")
    end

    local bad = 0
    for i, step in ipairs(config.power_on) do
        -- level 是目标电平，缺省时按旧字段 dir 兜底
        local level = step.level
        if level == nil then level = step.dir end
        if step.pin and level ~= nil then
            -- setup 直接给目标电平，再 set 一次兜底；两边都失败才计失败
            local ok1 = pcall(gpio.setup, step.pin, level)
            local ok2 = pcall(gpio.set, step.pin, level)
            if ok1 and ok2 then
                local ok3, rd = pcall(gpio.get, step.pin)
                log.info("platform_loader", "POWER_ON", i, "GPIO" .. tostring(step.pin),
                         level == 1 and "高" or "低", ok3 and ("回读 " .. tostring(rd)) or "回读失败")
            else
                bad = bad + 1
                log.warn("platform_loader", "POWER_ON 引脚设置失败", i,
                         tostring(step.pin), tostring(level))
            end
        end
        if step.delay then
            sys.wait(step.delay)
        end
    end
    log.info("platform_loader", "POWER_ON 完成, 步骤数:", #config.power_on, "失败:", bad)
    _G.__power_on_done = true
    sys.publish("POWER_ON_DONE")
end

if config.power_on and #config.power_on > 0 then
    sys.taskInit(power_on_task_func)
else
    -- 无上电序列的板子视为立即就绪（main.lua 以 _G.__power_on_done 为门）
    _G.__power_on_done = true
end
