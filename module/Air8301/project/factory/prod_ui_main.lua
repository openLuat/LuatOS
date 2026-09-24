--[[
@module  prod_ui_main
@summary 产测模式 UI 主模块，负责加载产测页面并启动硬件初始化序列
@version 1.0
@date    2026.09.24
@usage
require 即执行，以下按顺序发生：

  1. require LCD/TP 驱动模块 → 加载驱动代码（不自动初始化）
  2. require 所有产测 UI 页面模块 → 每个模块内部通过 sys.subscribe("OPEN_PROD_xxx_WIN", ...) 注册窗口
  3. sys.taskInit(init_ui_task) → 创建独立协程执行硬件初始化（不阻塞 sys.run() 事件循环启动）
  4. init_ui_task 协程内：
     a. lcd_drv.init()         → LCD 硬件初始化（lcd.init + 厂商寄存器）
     b. lcd_drv.airui_init()   → AirUI 引擎 + 字体 + 密度缩放
     c. tp_drv.init()          → GT911 触摸驱动 + AirUI 触摸绑定
     d. open_idle_win()        → 打开产测首页
     e. sys.wait(100)          → 等待首页渲染完成，避免白屏闪烁
     f. lcd_drv.backlight_on() → 开启背光 PWM，屏幕正常显示

模式隔离：本文件仅在产测模式（test_done 未置位）被 prod_test 加载；
业务模式的 UI 编排在 ui_main.lua，两者页面文件与消息名互不干扰。
]]

-- ==================== 共享主题 + 加载驱动模块（不自动初始化） ====================
require "theme"
local lcd_drv = require "lcd_st6201_43in"
local tp_drv  = require "tp_gt911"

-- ==================== 加载所有产测 UI 页面模块（注册窗口，不立即显示） ====================
require "prod_idle_win"
require "prod_network_win"
require "prod_wifi_win"
require "prod_rs485_win"
require "prod_rs232_win"
require "prod_di_win"
require "prod_do_win"
require "prod_buzzer_win"
require "prod_led_win"
require "prod_watchdog_win"
require "prod_reload_win"
require "prod_flash_win"
require "prod_sysinfo_win"

-- ==================== 硬件初始化协程（LCD → AirUI → TP → 首页 → 背光） ====================
local function init_ui_task()
    -- 步骤1: LCD 硬件初始化（lcd.init + 厂商寄存器序列）
    local ok = lcd_drv.init()
    if not ok then
        log.error("prod_ui_main", "LCD 初始化失败，中止")
        return
    end

    -- 步骤2: AirUI 引擎 + 字体 + 密度缩放
    ok = lcd_drv.airui_init()
    if not ok then
        log.error("prod_ui_main", "AirUI 初始化失败，中止")
        return
    end

    -- 步骤3: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤4: 打开产测首页
    sys.publish("OPEN_PROD_IDLE_WIN")

    -- 步骤5: 等待首页渲染完成（避免背光提前亮导致白屏）
    sys.wait(100)

    -- 步骤6: 打开背光
    lcd_drv.backlight_on()
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task)
