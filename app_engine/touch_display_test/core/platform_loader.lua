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
PROJECT 映射表与 factory_new 一致，并补挂了 factory_new 遗漏的
EVB_Air8101B_5inch_480x854_000_V010 → evb_8101b_5i_v1（配置文件存在但未映射）。

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

-- ==================== 编译清单（编译系统静态分析，运行时无害） ====================
-- 新增驱动或配置文件时在此加一行，编译系统会自动打包对应 .lua 文件

-- 所有配置文件（与 factory_new 工厂工程一致：≥800×480 / 480×854 型号）
require ("pc_default")        -- PC 模拟器回退
require ("eng_1602_5i_v2")    -- Air1602 5寸 720×1280 NV3052C
require ("eng_1602_5i_v3")    -- Air1602 5寸 720×1280 NV3052C + NAND
require ("eng_1602_5i_v5")    -- Air1602 5寸 480×854 ST7701S + NAND
require ("eng_1602_7i_v0")    -- Air1602 7寸 1024×600
require ("eng_1602_7i_v4")    -- Air1602 7寸 1024×600 + NAND
require ("eng_1602_9i_v09421")    -- Air1602 9寸 1024×600
require ("eng_1602_10i_v0")       -- Air1602 10寸 1024×600
require ("eng_1602_10i_v10421")   -- Air1602 10寸 1024×600
require ("eng_8601_7i_v0")       -- Air8601 7寸 1024×600
require ("eng_8602_9i_v0")       -- Air8602 9寸 1024×600
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
    ["Engine_Air8601_7inch_1024x600_010_V000"]    = "eng_8601_7i_v0",
    ["Engine_Air8602_9inch_1024x600_010_V000"]    = "eng_8602_9i_v0",
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
-- power_on 格式: { pin=GPIO编号, dir=0输出/1输入, level=0低/1高, [delay=延时ms] }
-- 例: Airlink WiFi 模组上电 → GPIO 拉低/拉高保持，LCD/TP/触摸供电使能等
-- 步骤间带 delay 时使用 sys.wait，不阻塞主线程

--[[
供电上电协程函数，按 config.power_on 时序逐条设置 GPIO 方向和电平
@param 无
@return 无（协程函数，内部使用 sys.wait）
]]
local function power_on_task_func()
    local steps = _G.project_config.power_on
    for _, step in ipairs(steps) do
        gpio.setup(step.pin, step.dir)
        gpio.set(step.pin, step.level)
        if step.delay then
            sys.wait(step.delay)
        end
    end
    log.info("platform_loader", "POWER_ON 完成, 步骤数:", #steps)
end

if config.power_on then
    sys.taskInit(power_on_task_func)
end
