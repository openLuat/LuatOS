--[[
@module  ui_main
@summary UI 主模块，负责加载所有 UI 页面并启动硬件初始化序列
@version 3.0
@date    2026.08.04
@author  江访

=== 执行流程 ===

require 即执行，以下按顺序发生：

  1. require LCD/TP 驱动模块 → 加载驱动代码（不自动初始化）
  2. require 所有 UI 页面模块 → 每个模块内部通过 sys.subscribe("OPEN_xxx_WIN", ...) 注册窗口
  3. sys.taskInit(init_ui_task) → 创建独立协程执行硬件初始化（不阻塞 sys.run() 事件循环启动）
  4. init_ui_task 协程内：
     a. lcd_drv.init()         → LCD 硬件初始化（lcd.init + 厂商寄存器）
     b. lcd_drv.airui_init()   → AirUI 引擎 + 字体 + 密度缩放
     c. tp_drv.init()          → GT911 触摸驱动 + AirUI 触摸绑定
     d. open_idle_win()        → 打开首页
     e. sys.wait(100)          → 等待 100ms 让首页渲染完成，避免白屏闪烁
     f. lcd_drv.backlight_on() → 开启背光 PWM，屏幕正常显示

对齐工厂引擎 app_engine 的 ui_main.lua 初始化时序：
LCD → TP → 打开页面 → 等待渲染 → 背光。无 DISPLAY_READY / BACKLIGHT_ON 消息。
]]

-- ==================== 共享主题 + 加载驱动模块（不自动初始化） ====================
require "theme"
local lcd_drv = require "lcd_st6201_43in"
local tp_drv  = require "tp_gt911"

-- ==================== 加载所有 UI 页面模块（注册窗口，不立即显示） ====================
require "idle_win"
require "network_win"
require "wifi_win"
require "rs485_win"
require "rs232_win"
require "di_win"
require "do_win"
require "buzzer_win"
require "led_win"
require "watchdog_win"
require "reload_win"
require "flash_win"
require "sysinfo_win"

-- ==================== 硬件初始化协程（LCD → AirUI → TP → 首页 → 背光） ====================
local function init_ui_task()
    -- 步骤1: LCD 硬件初始化（lcd.init + 厂商寄存器序列）
    local ok = lcd_drv.init()
    if not ok then
        log.error("ui_main", "LCD 初始化失败，中止")
        return
    end

    -- 步骤2: AirUI 引擎 + 字体 + 密度缩放
    ok = lcd_drv.airui_init()
    if not ok then
        log.error("ui_main", "AirUI 初始化失败，中止")
        return
    end

    -- 步骤3: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤4: 打开首页
    sys.publish("OPEN_IDLE_WIN")

    -- 步骤5: 等待首页渲染完成（避免背光提前亮导致白屏）
    sys.wait(100)

    -- 步骤6: 打开背光
    lcd_drv.backlight_on()
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task)
