--[[
@module  platform_loader
@summary 平台检测与项目配置加载器（从 main.lua 中抽离）
@version 1.0
@date    2026.05.22
@author  江访

=== 执行流程 ===

require 即执行，按以下顺序：
  1. 编译清单：包进永不调用的 _compile_manifest()，仅供编译系统文本扫描打包，运行时不执行
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

- require 编译清单：不是给运行时用的，是给编译系统文本扫描用的。
  编译系统扫描这些 require 语句决定哪些 .lua 文件打包进固件；
  包进永不调用的函数后运行时不执行，动态 require（变量名）扫不到的文件才必须登记。
]]

-- ==================== 编译清单（编译系统文本扫描，运行时不执行） ====================
-- 新增驱动或配置文件时在此加一行，编译系统会自动打包对应 .lua 文件。
-- 包进永不调用的函数：这些 require 若在顶层执行，会在点亮屏幕前把全部配置 +
-- 整条网络库链（≈400ms）加载进启动关键路径；函数体内的静态 require 编译系统
-- 文本扫描同样能扫到（与 app_main / ui_main 的函数体 require 同一机制）。

-- 编译清单：≥800×480 分辨率的配置/驱动（编译系统静态分析）
local function _compile_manifest()
require ("pc_default")            -- PC 模拟器回退

-- Engine 引擎主机系列
require ("eng_8603w1_10i_v0")      -- Air8603W1 10寸 1024×600 + Airlink UART WiFi(6205) + 隔离RS485(UART1) + UVC(UART2控制串口) + 喇叭(HT6873) + SD（WiFi）
require ("eng_8603w2_10i_v0")      -- Air8603W2 10寸 1024×600 + Airlink UART WiFi(6205) + 非隔离RS485(UART1) + UVC(UART2控制串口) + 喇叭(HT6873) + SD（WiFi）
require ("eng_8603w3_10i_v0")      -- Air8603W3 10寸 1024×600 + Airlink UART WiFi(6205) + 隔离RS485(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（WiFi）
require ("eng_8603w4_10i_v0")      -- Air8603W4 10寸 1024×600 + Airlink UART WiFi(6205) + 非隔离RS485(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（WiFi）
require ("eng_8603w5_10i_v0")      -- Air8603W5 10寸 1024×600 + Airlink UART WiFi(6205) + TTL串口(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（WiFi）
require ("eng_8603m1_10i_v0")      -- Air8603M1 10寸 1024×600 + Airlink UART 4G(780ER2) + 隔离RS485(UART1) + UVC(UART2控制串口) + 喇叭(HT6873) + SD（4G）
require ("eng_8603m2_10i_v0")      -- Air8603M2 10寸 1024×600 + Airlink UART 4G(780ER2) + 非隔离RS485(UART1) + UVC(UART2控制串口) + 喇叭(HT6873) + SD（4G）
require ("eng_8603m3_10i_v0")      -- Air8603M3 10寸 1024×600 + Airlink UART 4G(780ER2) + 隔离RS485(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（4G）
require ("eng_8603m4_10i_v0")      -- Air8603M4 10寸 1024×600 + Airlink UART 4G(780ER2) + 非隔离RS485(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（4G）
require ("eng_8603m5_10i_v0")      -- Air8603M5 10寸 1024×600 + Airlink UART 4G(780ER2) + TTL串口(UART1) + 隔离RS485(UART2) + 喇叭(HT6873) + SD（4G）



-- 驱动
require ("lcd_display_rgb")       -- RGB display 统一驱动
require ("tp_gt911")              -- GT911 触摸（统一）
require ("periph_loader")         -- 外设预留框架（config.peripherals，require 无副作用）
require ("periph_uvc")            -- UVC 摄像头外设（纯供电开关，数据流走 UVC 预览页）
require ("periph_rs485")          -- RS485 外设（多路，DE 方向 + 供电引用计数）
require ("periph_uart")           -- 通用串口外设（收发计数 + 环形缓冲）
require ("periph_audio")          -- 录音播放外设（Air1103 等语音芯片，config.hw.audio + type=audio）

-- 业务模块
require ("net_manager")           -- 统一网络管理器
require ("net_init")
require ("aircloud_app")          -- AirCloud 通用数据上报（能力探测型，有接口就采）
require ("settings_report_win")   -- AirCloud 上报设置页（配 features.aircloud 使用）
-- 应用工厂 / AI 聊天体积大，800×480 脚本区 1024KB 先不打包
end


--[[app_main / ui_main 等聚合入口 **不登记** 在本清单：它们由 boot_ui 源码内的
函数体静态 require 文本扫描打包（与 features 门控里的 require "llm_chat" 同一机制）。
清单内只放「动态 require（变量名）扫不到」的文件——各机型配置、驱动、外设框架。]]

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
    -- Engine 引擎主机系列（已实现，≥800×480）
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
    ["Engine_Air8605_10inch_1024x600_000_4G_V000"]  = "eng_8605_10i_v0",
    ["Engine_Air8605W_10inch_1024x600_000_WiFi_V000"] = "eng_8605w_10i_v0",
    ["Engine_Air8605M_10inch_1024x600_000_4G_V000"]  = "eng_8605m_10i_v0",
    ["Engine_Air8605B_10inch_1024x600_000_4G_V000"]  = "eng_8605b_10i_v0",
    ["Engine_Air8607_10inch_1024x600_000_V000"]   = "eng_8607_10i_v0",
    ["Engine_Air8607A_10inch_1024x600_000_V000"]  = "eng_8607a_10i_v0",
    -- 别名：改名前的旧 PROJECT 名与大小写变体，避免填错时静默回退 PC 配置
    --（回退后桌面没有「功能测试」图标，硬件配置也全丢，日志会打「未找到 PROJECT 映射」）
    -- 8605 系列的旧名指向各自的后继型号：8605 由 WiFi+4G 双网改回 4G 单网并补 _4G 后缀，
    -- 8605 WiFi 版已并入 8605W，8605B 由双网改 4G 单网
    -- 8603 系列旧名：改名前只有全功能版 W1 / M1，统一落到同串口划分的 W1 / M1
    ["Engine_Air8603W_10inch_1024x600_000_V000"]      = "eng_8603w1_10i_v0",
    ["Engine_Air8603W_10inch_1024x600_000_WiFi_V000"] = "eng_8603w1_10i_v0",
    ["Engine_Air8603M_10inch_1024x600_000_V000"]      = "eng_8603m1_10i_v0",
    ["Engine_Air8603M1_10inch_1024x600_000_V000"]     = "eng_8603m1_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_V000"]      = "eng_8605_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_WiFi_V000"] = "eng_8605w_10i_v0",
    ["Engine_Air8605_10inch_1024x600_000_WIFI_V000"] = "eng_8605w_10i_v0",
    ["Engine_Air8605B_10inch_1024x600_000_V000"]     = "eng_8605b_10i_v0",
    -- EVB turnkey 开发板系列（已实现，≥800×480）
    ["EVB_Air8101_AirLCD_1020_000_V020"]            = "evb_8101_5i_v0",
    ["EVB_Air8101_AirLCD_1090_000_V020"]            = "evb_8101_9i_v0",
    ["EVB_Air8101_AirLCD_1100_000_V020"]            = "evb_8101_10i_v0",
    ["EVB_Air8101_AirLCD_1070_000_V020"]            = "evb_8101_7i_v0",
    ["EVB_Air8101B_5inch_480x854_000_V020"]        = "evb_8101b_5i_v2",
    ["EVB_Air1601_10inch1_1024x600_000_V011"]   = "evb_1601_10i_v11",
    ["EVB_Air1601_7inch_1024x600_000_V011"]     = "evb_1601_7i_v11",
    ["EVB_Air1601_7inch_1024x600_000_V012"]     = "evb_1601_7i_v12",
    ["EVB_Air1601_5inch_800x480_000_V011"]      = "evb_1601_5i_v11",
}

-- ==================== 3. 加载项目配置 ====================

--[[
加载 PROJECT 对应的硬件/功能/UI 配置
@param project string  PROJECT 长名
@return table  配置表 { name, chip, baseboard, pins, hw={lcd,tp}, features, ui }
@logic
  1. PC 模拟 → 内联配置（lcd_display_rgb + ETH0 网卡）
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
                lcd = { model = "lcd_display_rgb", params = { pin_rst = 36, w = 320, h = 480 }, need_buffer = false, screen_size = 4.0, font = { size = 14 }, backlight = { pwm_ch = 0, pwm_freq = 1000 } },
                tp  = { model = "tp_gt911", params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0 } },
            },
            features = {
                ethernet = true,
            },
            ui = {
                show_brightness_slider = true,
                show_storage_settings = true,
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

    local w, h, sz, need_buf, fs = 800, 480, 5.0, true, 20
    local _, _, rw, rh = project:find("(%d+)x(%d+)")   -- 正则提取 "720x1280"
    if rw and rh then w, h = tonumber(rw), tonumber(rh) end
    if project:find("7inch") then sz = 7.0 elseif project:find("10inch") then sz = 10.0 end
    if w > 480 then need_buf, fs = true, 20 end         -- 高分辨率屏需要帧缓冲 + 大字体

    return {
        name = "PC", chip = "PC", baseboard = "PC", pins = {},
        hw = {
            lcd = { model = "lcd_display_rgb", params = { pin_rst = 36, w = w, h = h }, need_buffer = need_buf, screen_size = sz, font = { size = fs }, backlight = { pwm_ch = 0, pwm_freq = 1000 } },
            tp  = { model = "tp_gt911", params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0 } },
        },
        features = {
            wifi = true, ethernet = true,
        },
        ui = {
            show_wifi_icon = true,
            show_brightness_slider = true,
            show_storage_settings = true,
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
-- power_on 格式: { pin=GPIO编号, level=0低/1高, [delay=延时ms], [dir=兼容旧字段] }
-- 例: Airlink WiFi 模组上电 → GPIO55 拉低 50ms → 拉高 120ms
-- 使用 sys.taskInit 创建协程执行 sys.wait，避免阻塞主线程
--
-- 电平直接写进 gpio.setup 第 2 参：gpio.setup(pin, mode) 里 0/1 都是输出模式、
-- 数字即初始电平（luat_lib_gpio.c l_gpio_setup，nil 才是输入）。不能再拿 dir 当初始电平
-- 先配成低再靠 gpio.set 纠正 —— set 不生效时引脚就停在低电平上。dir 只在 level 缺省时兜底。
-- 每步独立 pcall 并打印回读值：单条引脚失败不能中断后面的上电步骤，失败也必须看得见。
--
-- 完成标记：整个序列（含各步 delay 的电源稳定时间）跑完后置 _G.__power_on_done
-- 并发布 POWER_ON_DONE。boot_ui 以此为门再初始化触摸 —— I2C 总线上未上电的
-- 设备会钳住 SDA/SCL，GT911 也会因电源未稳而软失败（触摸"完全失灵"）。
if config.power_on then
    sys.taskInit(function()
        -- 背光 PWM 上电前先压灭：PWM 引脚默认高电平，上电瞬间 BL 即被拉高点亮，
        -- 与 backlight_on 的延时表无关 → 背光提前亮。故上电序列一开始就用 0 占空比
        -- 压住 PWM 背光通道，等 boot_ui 首帧后 backlight_on 再点亮。
        -- 仅 PWM 背光板（backlight.pwm_ch 存在）需要；GPIO 背光板由 pin_bl 压低延后，无需此步。
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
    end)
else
    -- 无上电序列的板子视为立即就绪（boot_ui 以 _G.__power_on_done 为门）
    _G.__power_on_done = true
end
