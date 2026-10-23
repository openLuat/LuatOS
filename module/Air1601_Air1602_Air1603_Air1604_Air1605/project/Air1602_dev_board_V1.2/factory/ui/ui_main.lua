--[[
@module  ui_main
@summary UI 窗口聚合入口：core() 核心窗口批 + optional() 可选窗口批（boot_ui 分批调用）
@version 4.0
@date    2026.10.16
@author  江访

=== 执行流程 ===

boot_ui 在 logo 展示期间分批调用本模块的两个函数：

  core()     核心窗口批（进桌面前完成）：
    ui_theme_themes → idle_win → video_win → wifi_list_win → settings_win
    → settings_auto_win → settings_theme_win → app_store_win → file_manager_win
    （settings_win 级联全部设置子页，wifi_list_win 级联 connect/detail）

  optional() 可选窗口批（optional_task 协程调用，features 门控）：
    factory_win / llm_chat_win / cloud_disk_win / file_transfer_win

  消息流: boot_ui 画 logo → 核心批完成 → OPEN_IDLE_WIN → idle_win

=== 关键约束 ===

1. ui_theme_themes 必须第一个加载（决定启动配色，require 时即 restore）
2. 可选窗口必须与 app_main.optional 的业务层成对、同门控加载——
   idle_win 入口图标只看 project_config，窗口没加载时点击只是 publish 到空订阅，
   表现为「图标能显示、点进去没反应」
3. welcome_win 已删除：logo 由 boot_ui 裸 airui 形状绘制，核心批完成直接进桌面
]]

local M = {}

-- ==================== 核心窗口批：进桌面前完成 ====================
function M.core()
    require "ui_theme_themes"   -- 主题预设注册（必须最先：决定启动配色）
    require "idle_win"          -- 桌面/待机页
    require "video_win"         -- 全屏播放页（布局驱动：有播放器区域就有入口按钮，无门控）
    require "wifi_list_win"     -- WiFi 列表页（级联 wifi_connect_win / wifi_detail_win）
    require "settings_win"      -- 设置主页（级联全部设置子页）
    require "settings_auto_win" -- 后装APP自启动设置页
    require "settings_theme_win"-- 主题风格选择页
    require "app_store_win"     -- 应用商店
    require "file_manager_win"  -- 文件管理
end

-- ==================== 可选窗口批：features 门控，与业务层成对 ====================
function M.optional()
    local _feat = (_G.project_config or {}).features or {}

    -- 门控条件必须与 app_main.optional 对应业务层完全一致
    if _feat.app_factory then
        require "factory_win"       -- 应用工厂（订阅 OPEN_APP_FACTORY_WIN）
        -- 不加载 factory_rec_win：被 v4.2 整合版 factory_win 取代后的孤儿文件
    end

    if _feat.ai_chat then
        require "llm_chat_win"      -- AI 助手聊天窗口（订阅 OPEN_AI_CHAT_WIN）
    end

    if _feat.cloud_disk then
        require "cloud_disk_win"    -- 合宙网盘窗口（订阅 OPEN_CLOUD_DISK_WIN）
    end

    if _feat.file_transfer then
        require "file_transfer_win" -- 文件传输窗口（订阅 OPEN_FILE_TRANSFER_WIN）
    end
end

return M
