--[[
@module  platform_loader
@summary 平台检测与项目配置加载器（从 main.lua 中抽离）
@version 1.0
@date    2026.05.22
@author  江访

=== 执行流程 ===

require 即执行，按以下顺序：
  1. 编译清单：require (...) 声明所有需要打包进固件的模块（编译系统静态分析用）
  2. 平台检测：hmeta.model() → 识别芯片型号 → 设 _G.model_str / _G.is_pc
  3. PROJECT 映射：长命名 "Engine_Air1602_5inch_720x1280_002_V000" → 短文件名 "eng_1602_5i_v2"
  4. 配置加载：require(cfg_name) → 返回配置 table → 存入 _G.project_config
  5. PC 适配：模拟器环境补充 mobile.* 桩函数、设置默认网卡为 ETH0
  6. 引脚初始化：遍历 config.pins，逐条调用 pins.setup(pin, func)

=== 关键设计 ===

- 短文件名映射（PROJECT_MAP）：LuatOS 文件系统限制文件名 ≤24 字节，长 PROJECT 名（如 "Engine_Air1602_5inch_720x1280_002_V000" 42 字节）
  必须映射到短名（如 "eng_1602_5i_v2" 15 字节）。命名格式: {eng|evb|cor}_{芯片简写}_{尺寸简写}_{版本简写}

- 三级回退策略（容错设计）：
  第一级：PROJECT_MAP 命中 → require 配置文件 → 返回 table
  第二级：配置文件 require 返回非 table → PC 配置（根据 PROJECT 名推断分辨率）
  第三级：PROJECT_MAP 未命中 → PC配置

- require 编译清单：头部 require (...) 不是给运行时用的，是给编译系统静态分析用的。
  编译系统扫描这些 require 语句决定哪些 .lua 文件打包进固件。
]]

-- ==================== 编译清单（编译系统静态分析，运行时无害） ====================
-- 新增驱动或配置文件时在此加一行，编译系统会自动打包对应 .lua 文件

-- 所有配置文件（pcall 保证缺失不崩溃，正编固件会全部打包）
require ("eng_8000w_4i_v0")   -- Air8000W 4寸
require ("eng_1602_5i_v2")    -- Air1602 5寸 V002
require ("eng_1602_5i_v3")    -- Air1602 5寸 V003 (NAND)
require ("eng_1602_7i_v0")    -- Air1602 7寸
require ("eng_1602_10i_v0")   -- Air1602 10.1寸
require ("evb_8101_10i_v1")   -- Air8101 EVB 10.1寸
require ("evb_8101b_5i_v1")    -- Air8101 EVB 5寸
require ("pc_default")        -- PC 模拟器回退

-- 所有 LCD 驱动（按屏幕 IC 型号分类）
require ("lcd_st7796")        -- SPI ST7796 (3.5/4寸 320×480)
require ("lcd_nv3052c_5in")   -- RGB NV3052C (5寸 720×1280)
require ("lcd_st7701s_5in")   -- RGB ST7701S (5寸 480×854)
require ("lcd_hx8282_10in")   -- RGB HX8282 (10.1寸 1024×600)
require ("lcd_custom_7in")    -- 7寸通用 RGB (1024×600)
require ("lcd_custom_10in")   -- 10寸通用 RGB (Air160x 时序)
require ("lcd_custom_evb_10in") -- 10寸通用 RGB (EVB 时序)

-- TP 驱动（统一用 GT911，仅引脚参数不同）
require ("tp_gt911")

-- 带路径前缀的模块（不在 config/ 或 drv/ 下，需完整 require 路径）
require ("net_init")

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
local PROJECT_MAP = {
    -- Engine 引擎主机系列（已实现）
    ["Engine_Air8000W_4inch_320x480_000_V000"]     = "eng_8000w_4i_v0",
    ["Engine_Air1602_5inch_720x1280_002_V000"]     = "eng_1602_5i_v2",
    ["Engine_Air1602_7inch_1024x600_000_V000"]     = "eng_1602_7i_v0",
    ["Engine_Air1602_10inch1_1024x600_001_V000"]   = "eng_1602_10i_v0",
    ["Engine_Air1602_5inch_720x1280_003_V000"]     = "eng_1602_5i_v3",
    -- EVB turnkey 开发板系列（已实现）
    ["EVB_Air8101_10inch1_1024x600_000_V010"]      = "evb_8101_10i_v1",
    ["EVB_Air8101_5inch_800x480_000_V010"]         = "evb_8101b_5i_v1",
    -- 以下映射已预留，配置文件待实现
    -- ["EVB_Air1601_10inch1_1024x600_000_V011"]   = "evb_1601_10i_v11",
    -- ["EVB_Air1601_7inch_1024x600_000_V011"]     = "evb_1601_7i_v11",
    -- ["EVB_Air1601_5inch_800x480_000_V011"]      = "evb_1601_5i_v11",
    -- ["EVB_Air8000A_3inch5_480x320_000_V020"]    = "evb_8000a_35i_v2",
    -- ["EVB_Air780EGG_3inch5_480x320_000_V014"]   = "evb_780eg_35i_v14",
    -- ["EVB_Air780EHV_3inch5_480x320_000_V014"]   = "evb_780ehv_35i_v14",
    -- ["EVB_Air780EHU_3inch5_480x320_000_V014"]   = "evb_780ehu_35i_v14",
    -- ["EVB_Air780EHM_3inch5_480x320_000_V014"]   = "evb_780ehm_35i_v14",
    ["EVB_Air8101B_5inch_480x854_000_V010"]        = "evb_8101b_5i_v1",
    -- ["EVB_Air8101_10inch1_1024x600_000_V010_b"] = "evb_8101_10i_v1b",
    -- Core 核心板系列（待实现）
    -- ["Core_Air780EGG_3inch5_480x320_000_V020"]  = "cor_780eg_35i_v2",
    -- ["Core_Air780EHU_3inch5_480x320_000_V020"]  = "cor_780ehu_35i_v2",
    -- ["Core_Air780EHN_3inch5_480x320_000_V020"]  = "cor_780ehn_35i_v2",
    -- ["Core_Air8000A_3inch5_480x320_000_V040"]   = "cor_8000a_35i_v4",
    -- ["Core_Air8000W_3inch5_480x320_000_V040"]   = "cor_8000w_35i_v4",
    -- ["Core_Air8000D_3inch5_480x320_000_V040"]   = "cor_8000d_35i_v4",
    -- ["Core_Air8000DB_3inch5_480x320_000_V040"]  = "cor_8000db_35i_v4",
    -- ["Core_Air8000U_3inch5_480x320_000_V040"]   = "cor_8000u_35i_v4",
    -- ["Core_Air8000N_3inch5_480x320_000_V040"]   = "cor_8000n_35i_v4",
}

-- ==================== 3. 加载项目配置 ====================

--[[
加载 PROJECT 对应的硬件/功能/UI 配置
@param project string  PROJECT 长名
@return table  配置表 { name, chip, baseboard, pins, hw={lcd,tp}, features, ui }
@logic
  1. PC 模拟 → 内联配置（lcd_st7796 + ETH0 网卡）
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
        return {
            name = "PC", chip = "PC", baseboard = "PC", pins = {},
            hw = {
                lcd = { model = "lcd_st7796", params = { port = lcd.HWID_0, pin_rst = 36, direction = 0, w = 320, h = 480 }, need_buffer = false, screen_size = 4.0, font = { size = 14 }, backlight = { pwm_ch = 0, pwm_freq = 1000 } },
                tp  = { model = "tp_gt911", params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0 } },
            },
            features = {
                net_4g = false, wifi = true, ethernet = true, buzzer = false,
                speaker = false, mic = false, sd_card = false, nand_flash = false,
                gnss = false, bluetooth = false, can = false, rs485 = false,
                usb_camera = false, spi_camera = false, i2c_sensor = false,
            },
            ui = {
                show_4g_icon = false, show_wifi_icon = true,
                show_buzzer_settings = false, show_brightness_slider = true,
                show_ethernet_settings = false, show_storage_settings = true,
                show_camera_preview = false, show_sensor_panel = false,
            },
        }
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
    function mobile.imei() return "pc_simulator" end

    local w, h, sz, need_buf, fs = 320, 480, 4.0, false, 14
    local _, _, rw, rh = project:find("(%d+)x(%d+)")   -- 正则提取 "720x1280"
    if rw and rh then w, h = tonumber(rw), tonumber(rh) end
    if project:find("7inch") then sz = 7.0 elseif project:find("10inch") then sz = 10.0 end
    if w > 480 then need_buf, fs = true, 20 end         -- 高分辨率屏需要帧缓冲 + 大字体

    return {
        name = "PC", chip = "PC", baseboard = "PC", pins = {},
        hw = {
            lcd = { model = "lcd_st7796", params = { port = lcd.HWID_0, pin_rst = 36, direction = 0, w = w, h = h }, need_buffer = need_buf, screen_size = sz, font = { size = fs }, backlight = { pwm_ch = 0, pwm_freq = 1000 } },
            tp  = { model = "tp_gt911", params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0 } },
        },
        features = {
            net_4g = false, wifi = true, ethernet = true, buzzer = false,
            speaker = false, mic = false, sd_card = false, nand_flash = false,
            gnss = false, bluetooth = false, can = false, rs485 = false,
            usb_camera = false, spi_camera = false, i2c_sensor = false,
        },
        ui = {
            show_4g_icon = false, show_wifi_icon = true,
            show_buzzer_settings = false, show_brightness_slider = true,
            show_ethernet_settings = false, show_storage_settings = true,
            show_camera_preview = false, show_sensor_panel = false,
        },
    }
end

-- 全局存储配置，后续所有模块通过 _G.project_config 读取硬件/功能/UI 参数
_G.project_config = load_project_config(_G.PROJECT)

-- ==================== 4. PC 运行时适配 ====================
-- 在 PC 模拟器上补充真机才有的 mobile 模块桩函数，避免 require 时报 nil
if _G.is_pc then
    _G.model_str = "PC"
    _G.project_config.chip = "PC"
    _G.project_config.features.net_4g = false          -- PC 无 4G 硬件
    socket.dft(socket.ETH0)
    _G.mobile = {}
    function mobile.imei() return "pc_simulator" end    -- FOTA 等需要 IMEI 的场景
    function mobile.csq() return 99 end                  -- 信号强度满格（状态栏显示用）
    function mobile.simPin() return false end            -- 无 SIM 卡
    function mobile.setAuto() end                        -- 空操作
    function mobile.flymode() end                        -- 空操作
    log.info("platform_loader", "PC 模拟器模式，默认网卡=ETH0，4G 已禁用")
end

-- ==================== 5. 配置引脚（底板决定接线） ====================
-- 引脚配置由底板决定，不在驱动中硬编码。逐条调用 pins.setup 设置引脚功能
-- 对应设计文档 阶段 2.1 PIN_CFG
local config = _G.project_config
if config.pins and pins then
    for _, p in ipairs(config.pins) do
        pcall(pins.setup, p.pin, p.func)                -- pcall 防止单条引脚配置失败阻塞整体
    end
    log.info("platform_loader", "引脚配置完成, 数量:", #config.pins)
end

-- ==================== 6. GPIO 供电上电（底板决定） ====================
-- 对应设计文档 阶段 2.2 POWER_ON：设置 GPIO 方向/电平，控制外设供电
-- power_on 格式: { pin=GPIO编号, dir=0输出/1输入, level=0低/1高, [delay=延时ms] }
-- 例: Airlink WiFi 模组上电 → GPIO55 拉低 50ms → 拉高 120ms
-- 使用 sys.taskInit 创建协程执行 sys.wait，避免阻塞主线程
if config.power_on then
    sys.taskInit(function()
        for _, step in ipairs(config.power_on) do
            gpio.setup(step.pin, step.dir)
            gpio.set(step.pin, step.level)
            if step.delay then
                sys.wait(step.delay)
            end
        end
        log.info("platform_loader", "POWER_ON 完成, 步骤数:", #config.power_on)
    end)
end
