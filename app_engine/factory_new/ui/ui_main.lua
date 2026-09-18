--[[
@module  ui_main
@summary UI 主模块，负责加载所有 UI 页面并启动硬件初始化序列
@version 3.1
@date    2026.09.16
@author  江访

=== 执行流程 ===

  1. require 所有 UI 页面模块 → 注册窗口
  2. init_ui_task 协程：
     a. lcd_drv.init()         → LCD + AirUI 初始化
     b. tp_drv.init()          → GT911 触摸初始化
     c. lcd_drv.backlight_on() → 开启背光
     d. OPEN_WELCOME_WIN       → welcome_win 播放 MJPG 开机动画
     e. OPEN_IDLE_WIN          → welcome_win 播完后发布，进入桌面

  消息流: OPEN_WELCOME_WIN → (welcome_win 播视频) → OPEN_IDLE_WIN → idle_win

  注: 「应用工厂 / AI 助手」两个窗口**不无条件 require** —— 它们常驻约占 1024KB，
  只在 config 的 features.app_factory / features.ai_chat 打开时才加载（见文件末尾）。
  这两个窗口必须与整机配置保持一致：idle_win 只看 project_config 就渲染入口图标，
  窗口若不加载，点击就只是 publish 到一个没有订阅者的事件，
  表现正是「图标能显示、点进去没反应」。
]]

-- ==================== 加载所有 UI 页面模块 ====================
require "ui_theme_themes"   -- 主题预设注册（必须在所有页面之前：决定启动配色）
require "welcome_win"       -- 开机欢迎页（播放 MJPG 动画）
require "idle_win"          -- 桌面/待机页
require "wifi_list_win"     -- WiFi 列表页
require "settings_win"      -- 设置主页
require "settings_auto_win" -- 后装APP自启动设置页
require "settings_theme_win"-- 主题风格选择页
require "app_store_win"     -- 应用商店
require "file_manager_win"  -- 文件管理

-- ==================== 按功能开关加载可选窗口 ====================
--[[必须与 config 的 features / ui 开关保持一致。

idle_win 的入口图标只判断 project_config（features.app_factory / ai_chat），
与「窗口模块是否被 require」完全解耦 —— 所以只要 config 打开了功能，
图标就会显示；而窗口模块若没加载，它内部的 sys.subscribe("OPEN_xxx_WIN")
就从未执行，点击时 sys.publish 找不到订阅者，表现为「图标能显示但点不进去」。

反过来，这两个窗口常驻约占 1024KB，小屏机型 LuaDB 拮据（800×480 只有 1024KB），
不能无条件 require。用 features 门控可以两头兼顾：
不启用该功能的机型一个字节都不多付，启用该功能的机型入口才真正可用。]]
local _feat = (_G.project_config or {}).features or {}

if _feat.app_factory then
    require "factory_win"       -- 应用工厂（订阅 OPEN_APP_FACTORY_WIN）
    -- 不加载 factory_rec_win：全工程无人 publish OPEN_FACTORY_REC_WIN，
    -- 它是被 v4.2 整合版 factory_win（录音/生成/安装都在一页）取代后的孤儿文件
end

if _feat.ai_chat then
    require "llm_chat_win"      -- AI 助手聊天窗口（订阅 OPEN_AI_CHAT_WIN）
end

-- ==================== 硬件初始化协程 ====================
local function init_ui_task()
    -- 主题恢复重试：ui_theme_themes 被 require 时 fskv 很可能还没挂载完，
    -- 这里（app_main 已跑完）再读一次，保证用户保存的主题开机不丢。
    -- 此时还没有任何页面构建，直接改令牌即可，无需通知页面重建。
    require("ui_theme").restore()

    lcd_drv.init()
    tp_drv.init()
    lcd_drv.backlight_on()
    sys.publish("OPEN_WELCOME_WIN")
end

sys.taskInit(init_ui_task)
