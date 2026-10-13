--[[
@module  prod_ui_main
@summary 产测模式 UI 主模块，负责加载产测页面并启动硬件初始化序列
@version 1.0
@date    2026.10.08
@author  江访

@usage
require 即执行，以下按顺序发生：

  1. require LCD/TP 驱动模块 → 加载驱动代码（不自动初始化）
  2. require 所有产测 UI 页面模块 → 每个模块内部通过 sys.subscribe("OPEN_PROD_xxx_WIN", ...) 注册窗口
  3. sys.taskInit(init_ui_task) → 创建独立协程执行硬件初始化（不阻塞 sys.run() 事件循环启动）
  4. init_ui_task 协程内（与业务模式 ui_main 同一套「引擎主机」启动范式）：
     a. lcd_drv.init()                 → LCD 硬件初始化（lcd.init + 厂商寄存器）
     b. lcd_drv.airui_init()           → AirUI 引擎 + 字体 + 密度缩放
     c. OPEN_BOOT_WIN                  → 显示开机画面（全屏深色底 + LOGO）
     d. sys.wait(100) + backlight_on() → LOGO 首帧上屏后开背光（链头点亮屏幕）
     e. tp_drv.init()                  → GT911 触摸驱动 + AirUI 触摸绑定
     f. BOOT_INIT_DONE                 → 开机画面收尾 → 打开产测首页 → 关闭自己（无白屏）

模式隔离：本文件仅在产测模式（test_done 未置位）被 prod_test 加载；
业务模式的 UI 编排在 ui_main.lua，两者页面文件与消息名互不干扰。

=== 本次 UI 优化说明 ===
各产测页面已迁移到新设计系统 ui_theme（480×272 深色玻璃态），
本文件仍 require "theme"（向后兼容桥接层），用于设置全局 T 并提供按键音兜底。
]]

-- ==================== 共享主题 + 加载驱动模块（不自动初始化） ====================
require "theme"
local lcd_drv = require "lcd_st6201_43in"
local tp_drv  = require "tp_gt911"

-- ==================== 加载所有产测 UI 页面模块（注册窗口，不立即显示） ====================
require "boot_win"       -- 开机画面（LOGO 启动页，最先显示，两模式共用）
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

-- ==================== 硬件初始化协程（LCD → AirUI → LOGO → 背光 → TP → 首页） ====================
-- 与业务模式 ui_main 采用同一套「引擎主机」启动范式：链头点亮屏幕，先 LOGO 后开背光。
local function init_ui_task()
    -- 步骤1: LCD 硬件初始化（lcd.init + 厂商寄存器序列；内含 clear，背光未开不可见）
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

    -- 步骤3: 显示开机画面（全屏深色底 + LOGO），并指定收尾后进入产测首页
    sys.publish("OPEN_BOOT_WIN", "OPEN_PROD_IDLE_WIN")

    -- 步骤4: 等 LOGO 首帧刷上屏再开背光（避免看到清屏过程与首帧黑屏）
    sys.wait(100)
    lcd_drv.backlight_on()

    -- 步骤5: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤6: 通知开机画面收尾 → 由 boot_win 打开产测首页并关闭自己
    _G.__boot_init_done = true
    sys.publish("BOOT_INIT_DONE")

    -- 步骤7: 兜底——开机画面因异常未收尾（极端情况）时，确保首页仍会打开。
    --        prod_idle_win 有单实例保护，重复 OPEN_PROD_IDLE_WIN 不会重复建窗。
    --        等待时长必须 > boot_win 的 MIN_SHOW_MS(1800)，理由同业务模式 ui_main。
    sys.wait(4000)
    if not _G.__boot_finished then
        log.warn("prod_ui_main", "开机画面未收尾，兜底打开产测首页")
        sys.publish("OPEN_PROD_IDLE_WIN")
    end
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task)
