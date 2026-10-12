--[[
@module  ui_main
@summary UI 主模块，负责加载所有 UI 页面并启动硬件初始化序列（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

=== 执行流程 ===

require 即执行，以下按顺序发生：

  1. require LCD/TP 驱动模块 → 加载驱动代码（不自动初始化）
  2. require 所有 UI 页面模块 → 每个模块内部通过 sys.subscribe("OPEN_xxx_WIN", ...) 注册窗口
  3. sys.taskInit(init_ui_task) → 创建独立协程执行硬件初始化（不阻塞 sys.run() 事件循环启动）
  4. init_ui_task 协程内（对齐工厂引擎 boot_ui 的启动范式）：
     a. lcd_drv.init()                 → LCD 硬件初始化（lcd.init + 厂商寄存器）
     b. lcd_drv.airui_init()           → AirUI 引擎 + 字体 + 密度缩放
     c. OPEN_BOOT_WIN                  → 显示开机画面（全屏深色底 + LOGO）
     d. sys.wait(100) + backlight_on() → LOGO 首帧上屏后开背光（链头点亮屏幕）
     e. tp_drv.init()                  → GT911 触摸驱动 + AirUI 触摸绑定
     f. BOOT_INIT_DONE                 → 开机画面收尾 → 打开首页 → 关闭自己（无白屏）

「点亮屏幕」由链尾提到链头：黑屏时间只剩固件启动 + display init 的固定开销，
触摸初始化与首页构建和 LOGO 展示并行，整机启动总时长不增加。

=== 本次 UI 优化说明（v3.0 界面范式重构·全部推广） ===
界面范式由「14 项图标总菜单」改为「仪表盘 + 底部 Dock 四分区导航」：
  主页 idle_win → 时间与天气仪表盘（时间/日期/天气/设备状态）
  通信 comm_win → 通信通道磁贴；IO io_win → IO 磁贴；系统 sys_win → 系统磁贴。
设计系统 ui_theme 提供 shell/statusbar/dock/stat_card/tile 等骨架与组件；
本文件仍 require "theme"（向后兼容桥接层），用于设置全局 T 并提供按键音兜底。
]]

-- ==================== 共享主题 + 加载驱动模块（不自动初始化） ====================
require "theme"
local lcd_drv = require "lcd_st6201_43in"
local tp_drv  = require "tp_gt911"

-- ==================== 加载所有 UI 页面模块（注册窗口，不立即显示） ====================
require "boot_win"       -- 开机画面（LOGO 启动页，最先显示）
require "idle_win"       -- 主页（时间与天气仪表盘）
require "weather_set_win" -- 城市设置（主页天气卡城市名点击进入）
require "comm_win"       -- 通信分区页（蜂窝/WiFi/RS485/以太网/Modbus）
require "io_win"         -- IO 分区页（DI/DO/继电器/蜂鸣器/状态灯）
require "sys_win"        -- 系统分区页（看门狗/Flash/系统信息/远程升级/RELOAD）
require "network_win"    -- 网络状态
require "multi_net_win"  -- 多网融合（网卡优先级配置）
require "wifi_win"       -- WiFi
require "rs485_win"      -- RS485 通讯监视
require "relay_win"      -- 继电器控制
require "modbus_win"     -- Modbus 寄存器监视
require "di_win"         -- DI 输入
require "do_win"         -- DO 输出
require "buzzer_win"     -- 蜂鸣器
require "led_win"        -- 状态灯
require "watchdog_win"   -- 看门狗
require "flash_win"      -- Flash 存储
require "sysinfo_win"    -- 系统信息
require "reload_win"     -- RELOAD 按键
require "fota_win"       -- 远程升级

-- ==================== 硬件初始化协程（LCD → AirUI → LOGO → 背光 → TP → 首页） ====================
-- 对齐工厂引擎 boot_ui 的启动范式：把「点亮屏幕」从初始化链尾提到链头。
-- 用户在固件启动后最先看到的是 LOGO 开机画面；触摸初始化与首页构建和 LOGO 展示并行，
-- 整机启动总时长不变（只是把原本的黑屏时间换成了 LOGO 展示）。
local function init_ui_task()
    -- 步骤1: LCD 硬件初始化（lcd.init + 厂商寄存器序列；内含 clear，背光未开不可见）
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

    -- 步骤3: 显示开机画面（全屏深色底 + LOGO），并指定收尾后进入业务首页
    sys.publish("OPEN_BOOT_WIN", "OPEN_IDLE_WIN")

    -- 步骤4: 等 LOGO 首帧刷上屏再开背光（避免看到清屏过程与首帧黑屏）
    sys.wait(100)
    lcd_drv.backlight_on()

    -- 步骤5: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤6: 通知开机画面收尾 → 由 boot_win 打开业务首页并关闭自己
    _G.__boot_init_done = true
    sys.publish("BOOT_INIT_DONE")

    -- 步骤7: 兜底——开机画面因异常未收尾（极端情况）时，确保首页仍会打开。
    --        idle_win 有单实例保护，重复 OPEN_IDLE_WIN 不会重复建窗。
    --        等待时长必须 > boot_win 的 MIN_SHOW_MS(1800)：否则会在"开机画面最短停留"
    --        未满足前抢先打开首页，把 LOGO 页顶掉（表现为开机画面一闪而过）。
    sys.wait(4000)
    if not _G.__boot_finished then
        log.warn("ui_main", "开机画面未收尾，兜底打开业务首页")
        sys.publish("OPEN_IDLE_WIN")
    end
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task)
