--[[
@module  ui_main
@summary UI 主模块，负责加载所有 UI 页面并启动硬件初始化序列
@version 1.0
@date    2026.03.26
@author  江访

=== 执行流程 ===

require 即执行，以下按顺序发生：

  1. require 所有 UI 页面模块 → 每个模块内部通过 sys.subscribe("OPEN_xxx_WIN", ...) 注册窗口
  2. sys.taskInit(init_ui_task) → 创建独立协程执行硬件初始化（不阻塞 require 返回）
  3. init_ui_task 协程内：
     a. lcd_drv.init()    → 调 LCD 驱动 init(params) → 成功后调 AirUI init + 字体 + 密度计算
     b. tp_drv.init()     → 调 GT911 驱动 init(params) → 成功后 airui.device_bind_touch 绑定
     c. sys.publish("OPEN_WELCOME_WIN") → 打开欢迎页（首次启动的引导界面）
     d. sys.wait(100)     → 等待 100ms 让欢迎页渲染完成，避免白屏闪烁
     e. lcd_drv.backlight_on() → 开启背光 PWM，屏幕正常显示

=== 关键设计决策 ===

1. 页面模块与窗口注册分离：require 只注册窗口（subscribe），不创建窗口（open）。
   窗口由用户交互或事件触发打开（如点击设置按钮 → publish OPEN_SETTINGS_WIN）

2. 背光延迟开启：如果背光在 LCD 初始化后立即打开，用户会看到未初始化的白屏。
   等待 100ms 让 AirUI 首帧渲染完成后再亮屏，体验更好

3. lcd_drv / tp_drv 由 lcd_common.lua 在阶段3构建：ui_main 不关心具体用了哪个 LCD/TP 型号，
   只调用统一的 .init() / .backlight_on() 接口
]]

-- ==================== 加载所有 UI 页面模块（注册窗口，不立即显示） ====================
-- 每个模块内部通过 sys.subscribe("OPEN_xxx_WIN", handler) 注册窗口打开回调
require "welcome_win"       -- 欢迎页（开机引导）
require "idle_win"          -- 桌面/待机页（状态栏图标 + 功能入口）
require "wifi_list_win"     -- WiFi 列表页（扫描/连接/断开）
require "settings_win"      -- 设置主页（功能入口列表：WiFi/显示/存储/关于...）
require "app_store_win"     -- 应用商店页（浏览/搜索/下载 exapp 应用）
require "speedtest_win"     -- 测速页（延迟/下载/上传结果显示）

-- ==================== 硬件初始化协程（LCD → TP → 欢迎页 → 背光） ====================
local function init_ui_task()
    -- 步骤1: LCD 初始化（包含 AirUI 初始化、字体加载、密度缩放计算）
    lcd_drv.init()

    -- 步骤2: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤3: 打开欢迎界面（引导用户进入系统）
    sys.publish("OPEN_WELCOME_WIN")

    -- 步骤4: 等待欢迎界面渲染完成（避免背光提前亮导致白屏）
    sys.wait(100)

    -- 步骤5: 打开背光
    lcd_drv.backlight_on()
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task)
