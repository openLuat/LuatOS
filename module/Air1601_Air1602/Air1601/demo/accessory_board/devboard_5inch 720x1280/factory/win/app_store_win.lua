--[[
@module app_store_win
@summary 应用市场窗口
@version 1.0.4
@date 2026.04.14
@author 江访
@usage
本文件为应用市场窗口的UI实现，遵循无状态设计原则，核心功能为：
1. 提供应用市场的用户界面，包括分类选择、排序、搜索、分页显示
2. 通过exapp模块获取应用列表和已安装应用信息
3. 处理用户操作（安装、卸载、更新应用）并发布相应消息
4. 订阅exapp模块的消息更新UI状态

本文件不维护任何应用数据状态，所有数据实时从exapp模块查询。
所有用户操作通过发布以下消息触发：
1. APP_STORE_GET_LIST  - 请求获取应用列表（携带category, sort, page, size, query）
2. APP_STORE_INSTALL   - 安装应用
3. APP_STORE_UNINSTALL - 卸载应用
4. APP_STORE_UPDATE    - 更新应用

订阅的消息包括：
1. APP_STORE_LIST_UPDATED      - 应用列表更新
2. APP_STORE_INSTALLED_UPDATED - 已安装应用更新
3. APP_STORE_PROGRESS          - 下载安装进度
4. APP_STORE_ACTION_DONE       - 应用操作完成
5. APP_STORE_ERROR             - 错误信息
6. APP_STORE_ICON_READY        - 图标下载完成

设计原则：
1. 无状态设计
2. 纯查询模式
3. 消息驱动
4. 及时刷新
]]

local win_id = nil
local main_container = nil
local search_input = nil
local search_keyboard = nil
local sort_select = nil
local category_btns = {}
local current_category = "全部"
local current_sort = "recommend"
local apps_container = nil
local apps_grid = nil
local page_label = nil
local prev_btn = nil
local next_btn = nil

-- 布局参数
local top_h, sort_h, side_w, app_area_h, page_btn_h, grid_area_h = 0, 0, 0, 0, 0, 0
local search_bg_w, search_bg_h = 0, 0
local sort_bar_w = 0
local apps_container_w, apps_container_h = 0, 0
local apps_grid_w, apps_grid_h = 0, 0
local page_bar_w = 0

local grid_margin = 8
local card_w, card_h = 0, 0
local grid_cols = 1
local icon_size = 0
local title_font_size = 0
local desc_font_size = 0
local button_font_size = 0
local info_font_size = 0
local max_desc_lines = 2  -- 描述最大行数，动态计算

-- 按钮自适应参数
local card_btn_height = 32
local card_btn_bottom_margin = 8
local vertical_padding = 12 
local current_page = 1
local total_pages = 0
local page_limit = 10
local has_more = false
local current_query = ""

-- 只保存UI状态，不保存业务数据
local local_installed_ids = {}

-- 使用颜色
local COLOR_PRIMARY = 0x2196F3
local COLOR_PRIMARY_DARK = 0x0B5E9E
local COLOR_ACCENT = 0xFF9800
local COLOR_BG = 0xF5F5F5
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x212121
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER = 0xE0E0E0

local categories = { "全部", "已安装", "通信","工具", "游戏", "工业", "健康" }
local pending_icon_updates = {}

-- 进度对话框相关
local progress_dialog = nil
local progress_bar = nil
local progress_label = nil

-------------------------------------------------------------------------------
-- 布局计算
------------------------------------------------------------------------------
local function calc_layout()
    -- 响应式断点定义
    local screen_width_breakpoints = {480, 720, 1024}
    local screen_height_breakpoints = {480, 600, 800, 854, 1280}

    -- 字体大小优化：更平缓的缩放曲线，增加最大最小值限制
    local base_font = math.floor(screen_h / 40)
    -- 限制基础字体范围在14-24之间
    base_font = math.max(14, math.min(24, base_font))

    -- 各组件独立缩放系数
    title_font_size = math.max(16, math.min(26, base_font))
    desc_font_size = math.max(14, math.min(22, base_font - 2))
    button_font_size = math.max(12, math.min(20, base_font - 2))
    info_font_size = button_font_size

    -- 图标大小优化：基于屏幕高度和方向综合计算
    if is_landscape then
        -- 横向屏幕：较小图标
        icon_size = math.max(40, math.min(70, math.floor(screen_h / 16)))
    else
        -- 纵向屏幕：适中图标
        icon_size = math.max(40, math.min(70, math.floor(screen_h / 14)))
    end

    -- 区域比例优化：根据屏幕方向调整比例系数
    if is_landscape then
        -- 横向屏幕：适当减少顶部和排序栏高度，优化侧边栏宽度
        top_h = math.floor(screen_h * 0.08)  -- 从0.1降低到0.08
        sort_h = math.floor(screen_h * 0.06)  -- 从0.08降低到0.06
        side_w = math.floor(screen_w * 0.16)  -- 从0.18降低到0.16
    else
        -- 纵向屏幕：微调比例
        top_h = math.floor(screen_h * 0.08)
        sort_h = math.floor(screen_h * 0.06)
        side_w = math.floor(screen_w * 0.2)   -- 从0.22降低到0.2
    end

    -- 分页栏高度优化：基于屏幕高度的比例，增加限制
    page_btn_h = math.max(40, math.min(60, math.floor(screen_h * 0.065)))

    app_area_h = screen_h - top_h - sort_h
    grid_area_h = app_area_h - page_btn_h - grid_margin * 2

    search_bg_w = screen_w - 2 * grid_margin - 70 - 50
    search_bg_h = math.floor(top_h * 0.7)
    sort_bar_w = screen_w
    apps_container_w = screen_w - side_w
    apps_container_h = app_area_h
    apps_grid_w = apps_container_w - 2 * grid_margin
    apps_grid_h = grid_area_h
    page_bar_w = apps_container_w

    -- 网格布局优化：动态调整最小卡片宽度基于屏幕宽度
    local min_card_w
    if is_landscape then
        -- 横向屏幕：卡片可以稍宽一些
        min_card_w = math.max(150, math.floor(screen_w * 0.18))
    else
        -- 纵向屏幕：卡片稍窄以增加列数
        min_card_w = math.max(150, math.floor(screen_w * 0.30))
    end
    -- 限制最小卡片宽度范围
    min_card_w = math.max(150, math.min(280, min_card_w))

    grid_cols = math.max(1, math.floor(apps_grid_w / min_card_w))
    
    -- 基于屏幕宽度的智能列数限制
    if screen_w < 480 then
        -- 超小屏幕：最多2列
        grid_cols = math.min(2, grid_cols)
    elseif screen_w < 720 then
        -- 小屏幕：最多3列
        grid_cols = math.min(3, grid_cols)
    else
        -- 大屏幕：最多4列
        grid_cols = math.min(4, grid_cols)
    end
    
    -- 特殊处理：480×800/854竖屏保持单列布局（用户反馈显示3个应用正好）
    if screen_w == 480 and not is_landscape and (screen_h == 800 or screen_h == 854) then
        grid_cols = 1
    end

    card_w = math.floor((apps_grid_w - (grid_cols + 1) * grid_margin) / grid_cols)

    -- 按钮高度优化：动态调整基于屏幕高度，确保最小可点击区域
    card_btn_height = math.max(36, math.min(50, math.floor(screen_h / 18)))

    -- 卡片内容布局优化：动态计算描述行数基于可用高度
    local title_height = title_font_size + 4
    local info_line_height = info_font_size + 4
    local desc_line_height = desc_font_size + 4
    local desc_lines = 2

    -- 计算卡片基础高度（不含描述）
    local base_card_h = math.max(icon_size, title_height + info_line_height) + card_btn_height + card_btn_bottom_margin + vertical_padding
    local available_height_for_desc = grid_area_h - base_card_h - grid_margin * 2

    -- 根据可用高度调整描述行数
    if available_height_for_desc >= desc_line_height * 2 then
        desc_lines = 2
    elseif available_height_for_desc >= desc_line_height then
        desc_lines = 1
    else
        desc_lines = 0
    end

    local desc_height = desc_font_size * desc_lines + (desc_lines > 0 and 8 or 0)
    card_h = math.floor(base_card_h + desc_height)

    local rows_per_page = math.max(1, math.floor(grid_area_h / (card_h + grid_margin)))
    page_limit = grid_cols * rows_per_page

    -- 更新全局变量
    max_desc_lines = desc_lines

    log.info("app_store_win", "layout", screen_w, screen_h, is_landscape, grid_cols, card_w, card_h, "btn_h", card_btn_height, "min_card_w", min_card_w, "desc_lines", desc_lines)
end

local function update_page_display()
    if not page_label then return end
    local text = tostring(current_page)
    if total_pages > 0 then
        text = text .. "/" .. total_pages
    else
        text = text .. "/?"
    end
    page_label:set_text(text)
end

-------------------------------------------------------------------------------
-- 进度对话框
-------------------------------------------------------------------------------
local function close_progress_dialog()
    if progress_dialog then
        progress_dialog:destroy()
        progress_dialog = nil
        progress_bar = nil
        progress_label = nil
    end
end

local function show_progress_dialog(app_name)
    close_progress_dialog()
    local mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0x000000,
        color_opacity = 180,
    })
    local dialog_w = math.min(400, screen_w - 80)
    local dialog_h = 160
    local dialog_x = (screen_w - dialog_w) / 2
    local dialog_y = (screen_h - dialog_h) / 2
    local dialog = airui.container({
        parent = mask,
        x = dialog_x,
        y = dialog_y,
        w = dialog_w,
        h = dialog_h,
        color = COLOR_CARD,
        radius = 16,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    airui.label({
        parent = dialog,
        x = 20,
        y = 20,
        w = dialog_w - 40,
        h = 30,
        text = "正在安装 " .. (app_name or ""),
        font_size = title_font_size,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    local bar = airui.bar({
        parent = dialog,
        x = 20,
        y = 70,
        w = dialog_w - 40,
        h = 20,
        min = 0,
        max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 10
    })
    local text_label = airui.label({
        parent = dialog,
        x = 20,
        y = 105,
        w = dialog_w - 40,
        h = 24,
        text = "准备下载...",
        font_size = desc_font_size,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    progress_dialog = mask
    progress_bar = bar
    progress_label = text_label
end

local function show_success_toast(action, app_name)
    local msg = ""
    if action == "install" then
        msg = (app_name or "应用") .. " 安装完成"
    elseif action == "uninstall" then
        msg = (app_name or "应用") .. " 卸载完成"
    elseif action == "update" then
        msg = (app_name or "应用") .. " 更新完成"
    else
        msg = "操作完成"
    end
    local toast = airui.msgbox({
        title = "提示",
        text = msg,
        buttons = { "确定" },
        timeout = 1000,
        on_action = function(self, label)
            if label == "确定" then
                self:hide()
            end
            self:destroy()
        end
    })
    toast:show()
end

-------------------------------------------------------------------------------
-- 图标更新
-------------------------------------------------------------------------------
local function on_icon_ready(aid, local_path)
    local entry = pending_icon_updates[aid]
    if entry and entry.image_component then
        -- 尝试安全地调用方法，避免访问已销毁组件的错误
        local ok, err = pcall(function()
            entry.image_component:set_src(local_path)
        end)
        if not ok then
            log.warn("app_store_win", "设置图标失败，组件可能已销毁:", err)
        end
    end
    pending_icon_updates[aid] = nil
end

-------------------------------------------------------------------------------
-- UI 创建（顶部栏、排序栏、分类侧边栏、内容区、分页栏）
-------------------------------------------------------------------------------
local function create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h, color = COLOR_BG, parent = airui.screen
    })

    -- 顶部栏
    local top_bar = airui.container({
        parent = main_container, x = 0, y = 0, w = screen_w, h = top_h, color = COLOR_CARD
    })
    airui.button({
        parent = top_bar,
        x = 8,
        y = math.floor((top_h - 36) / 2),
        w = 40,
        h = 36,
        text = "←",
        font_size = 24,
        style = { bg_color = 0xEEEEEE, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = 18, border_width = 1, border_color = COLOR_DIVIDER, pad = 0 },
        on_click = function()
            if win_id then
                exapp.init()
                exwin.return_idle()
            end
        end
    })

    local search_bg = airui.container({
        parent = top_bar,
        x = 54,
        y = math.floor((top_h - search_bg_h) / 2),
        w = search_bg_w,
        h = search_bg_h,
        color = 0xEEEEEE,
        radius = 24,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    search_keyboard = airui.keyboard({ mode = "text", auto_hide = true, preview = true, preview_height = 40, w = screen_w, h = 200, bg_color = COLOR_CARD })
    search_input = airui.textarea({
        parent = search_bg,
        x = 16,
        y = 4,
        w = search_bg_w - 32,
        h = search_bg_h - 8,
        placeholder = "搜索应用...",
        font_size = button_font_size,
        color = COLOR_TEXT,
        keyboard = search_keyboard
    })
    airui.button({
        parent = top_bar,
        x = search_bg_w + 54 + grid_margin,
        y = math.floor((top_h - 40) / 2),
        w = 60,
        h = 40,
        text = "搜索",
        font_size = button_font_size,
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = 0xFFFFFF, radius = 20, border_width = 0, pad = 8 },
        on_click = function()
            local q = (search_input and search_input:get_text()) or ""
            current_query = q or ""
            current_page = 1
            sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
        end
    })

    -- 排序栏
    local sort_bar = airui.container({ parent = main_container, x = 0, y = top_h, w = sort_bar_w, h = sort_h, color = COLOR_CARD })
    airui.label({ parent = sort_bar, x = 16, y = 10, w = 50, h = sort_h - 10, text = "排序:", font_size = math.max(14, button_font_size - 2), color = COLOR_TEXT_SECONDARY })
    sort_select = airui.dropdown({
        parent = sort_bar,
        x = 70,
        y = math.floor((sort_h - 36) / 2),
        w = 150,
        h = 36,
        options = { "推荐", "序号", "上传时间(旧)", "上传时间(新)", "热度", "下载量", "更新优先" },
        default_index = 0,
        style = { bg_color = 0xFFFFFF, border_color = COLOR_DIVIDER, radius = 18 },
        on_change = function(self, idx, value)
            local sort_map = { "recommend", "idAsc", "timeAsc", "timeDesc", "hot", "downloads", "updatePriority" }
            current_sort = sort_map[idx + 1] or "recommend"
            current_page = 1
            sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
        end
    })
    airui.button({
        parent = sort_bar,
        x = screen_w - 80,
        y = math.floor((sort_h - 36) / 2),
        w = 70,
        h = 36,
        text = "刷新",
        font_size = button_font_size,
        style = { bg_color = 0xEEEEEE, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = 18, border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function()
            current_page = 1
            sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
        end
    })

    -- 分类侧边栏
    local category_sidebar = airui.container({ parent = main_container, x = 0, y = top_h + sort_h, w = side_w, h = app_area_h, color = COLOR_CARD })
    local cat_y = 16
    local cat_height = math.max(36, math.min(50, math.floor(screen_h / 20)))
    local cat_width = side_w - 20
    for i, cat in ipairs(categories) do
        local btn = airui.button({
            parent = category_sidebar,
            x = 10,
            y = cat_y,
            w = cat_width,
            h = cat_height,
            text = cat,
            font_size = button_font_size,
            style = {
                bg_color = (cat == current_category) and COLOR_PRIMARY or 0xFFFFFF,
                pressed_bg_color = COLOR_PRIMARY_DARK,
                text_color = (cat == current_category) and 0xFFFFFF or COLOR_TEXT,
                radius = 24,
                border_width = 1,
                border_color = COLOR_DIVIDER,
                pad = 0
            },
            on_click = function()
                if current_category == cat then return end
                current_category = cat
                for idx, btn_obj in ipairs(category_btns) do
                    local active = (categories[idx] == cat)
                    btn_obj:set_style({ bg_color = active and COLOR_PRIMARY or 0xFFFFFF, text_color = active and 0xFFFFFF or COLOR_TEXT })
                end
                current_page = 1
                sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
            end
        })
        category_btns[i] = btn
        cat_y = cat_y + cat_height + 8
    end

    -- 右侧内容区
    apps_container = airui.container({ parent = main_container, x = side_w, y = top_h + sort_h, w = apps_container_w, h = apps_container_h - page_btn_h, color = COLOR_BG })
    apps_grid = airui.container({ parent = apps_container, x = grid_margin, y = grid_margin, w = apps_grid_w, h = apps_grid_h, color = COLOR_BG })

    -- 分页栏
    local page_bar = airui.container({ parent = main_container, x = side_w, y = screen_h - page_btn_h, w = screen_w - side_w, h = page_btn_h, color = COLOR_CARD })
    local prev_btn_x = 16
    local prev_btn_w = 70
    local next_btn_w = 70
    local next_btn_x = page_bar_w - 86
    local label_x = prev_btn_x + prev_btn_w + 4

    prev_btn = airui.button({
        parent = page_bar,
        x = prev_btn_x,
        y = 5,
        w = prev_btn_w,
        h = 40,
        text = "上一页",
        font_size = math.max(14, button_font_size - 4),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = 0xFFFFFF, radius = 20, border_width = 0 },
        on_click = function()
            if current_page > 1 then
                current_page = current_page - 1
                sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
                update_page_display()
            end
        end
    })
    next_btn = airui.button({
        parent = page_bar,
        x = next_btn_x,
        y = 5,
        w = next_btn_w,
        h = 40,
        text = "下一页",
        font_size = math.max(14, button_font_size - 4),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = 0xFFFFFF, radius = 20, border_width = 0 },
        on_click = function()
            if has_more then
                current_page = current_page + 1
                sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
                update_page_display()
            end
        end
    })
    page_label = airui.label({
        parent = page_bar,
        x = label_x,
        y = 14,
        w = screen_w - side_w - next_btn_w * 2 - 40,
        h = 30,
        text = "1/?",
        font_size = button_font_size,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-------------------------------------------------------------------------------
-- 渲染应用卡片（新布局：名称 → 信息行 → 描述 → 按钮）
-------------------------------------------------------------------------------
local function render_apps(apps, more)
    has_more = more
    update_page_display()

    -- 清理 pending_icon_updates 中可能已销毁的 image 组件引用
    for aid, entry in pairs(pending_icon_updates) do
        -- 虽然我们不能直接检查组件是否已销毁，但可以先清空表
        -- 这样就不会尝试更新已销毁的组件
        pending_icon_updates[aid] = nil
    end

    if apps_grid then apps_grid:destroy() end

    local rows_needed = math.ceil(#apps / grid_cols)
    local new_grid_h = math.max(grid_area_h, rows_needed * (card_h + grid_margin) + grid_margin + 10)
    apps_grid = airui.container({
        parent = apps_container,
        x = grid_margin,
        y = grid_margin,
        w = apps_grid_w,
        h = new_grid_h,
        color = COLOR_BG
    })

    local installed_apps = exapp.list_installed()
    local btn_height = card_btn_height
    local btn_bottom_margin = card_btn_bottom_margin
    local btn_y = card_h - btn_height - btn_bottom_margin

    for idx, app in ipairs(apps) do
        local lid = local_installed_ids[tostring(app.aid)]
        if lid then app.installed = true end

        local col = (idx - 1) % grid_cols
        local row = math.floor((idx - 1) / grid_cols)
        local x = col * (card_w + grid_margin) + grid_margin
        local y = row * (card_h + grid_margin) + grid_margin

        local card = airui.container({
            parent = apps_grid,
            x = x, y = y, w = card_w, h = card_h,
            color = COLOR_CARD,
            radius = 16,
            border_width = 1,
            border_color = COLOR_DIVIDER
        })

        -- 图标
        local icon_src = nil
        local need_async = false
        if app.icon_path and io.exists(app.icon_path) then
            icon_src = app.icon_path
        elseif app.icon and app.icon ~= "" then
            icon_src = exapp.get_icon_path(app.aid, app.icon)
            if icon_src and io.exists(icon_src) then
            else
                icon_src = "/luadb/img.png"
                need_async = true
            end
        else
            icon_src = "/luadb/img.png"
        end

        local icon_img = airui.image({
            parent = card, x = 12, y = 12, w = icon_size, h = icon_size, src = icon_src
        })
        if need_async then
            pending_icon_updates[app.aid] = { image_component = icon_img }
        end

        -- 应用名称
        local name_y = 15
        airui.label({
            parent = card,
            x = icon_size + 20,
            y = name_y,
            w = card_w - icon_size - 28,
            h = title_font_size + 4,
            text = app.title or app.name or "未知",
            font_size = title_font_size,
            color = COLOR_TEXT
        })

        -- 信息行：大小和下载量（格式：XXKB | ↓ xx次）
        local info_y = name_y + title_font_size + 6
        local size_text = (app.origin_size_kb and app.origin_size_kb ~= "") and (app.origin_size_kb .. "KB") or "未知"
        local download_text = (app.total_downloads and tostring(app.total_downloads)) or "0"
        local info_text = string.format("%s | ↓ %s次", size_text, download_text)
        airui.label({
            parent = card,
            x = icon_size + 20,
            y = info_y,
            w = card_w - icon_size - 28,
            h = info_font_size + 4,
            text = info_text,
            font_size = info_font_size,
            color = COLOR_TEXT_SECONDARY
        })

        -- 应用描述（动态行数）
        if max_desc_lines > 0 then
            local desc_y = info_y + info_font_size + 8
            local desc_height = desc_font_size * max_desc_lines + (max_desc_lines > 1 and 2 or 0)
            airui.label({
                parent = card,
                x = 12,
                y = desc_y,
                w = card_w - 24,
                h = desc_height,
                text = app.desc or "",
                font_size = desc_font_size,
                color = COLOR_TEXT_SECONDARY
            })
        end

        -- 按钮（安装/更新/卸载）
        if app.installed then
            if app.has_update then
                local btn_w = math.min(70, (card_w - 36) / 2)
                airui.button({
                    parent = card,
                    x = 12,
                    y = btn_y,
                    w = btn_w,
                    h = btn_height,
                    text = "更新",
                    font_size = button_font_size,
                    style = { bg_color = COLOR_ACCENT, pressed_bg_color = 0xE68900, text_color = 0xFFFFFF, radius = 16, border_width = 0 },
                    on_click = function()
                        local msgbox = airui.msgbox({
                            title = "确认更新",
                            text = "是否更新应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, label)
                                if label == "确定" then
                                    show_progress_dialog(app.title or app.name)
                                    sys.publish("APP_STORE_UPDATE", tostring(app.aid), app.url, app.title or app.name,
                                        current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msgbox:show()
                    end
                })
                airui.button({
                    parent = card,
                    x = 12 + btn_w + 12,
                    y = btn_y,
                    w = btn_w,
                    h = btn_height,
                    text = "卸载",
                    font_size = button_font_size,
                    style = { bg_color = 0xF44336, pressed_bg_color = 0xD32F2F, text_color = 0xFFFFFF, radius = 16, border_width = 0 },
                    on_click = function()
                        local msgbox = airui.msgbox({
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, label)
                                if label == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msgbox:show()
                    end
                })
            else
                local btn_w = math.min(80, card_w - 24)
                airui.button({
                    parent = card,
                    x = 12,
                    y = btn_y,
                    w = btn_w,
                    h = btn_height,
                    text = "卸载",
                    font_size = button_font_size,
                    style = { bg_color = 0xF44336, pressed_bg_color = 0xD32F2F, text_color = 0xFFFFFF, radius = 16, border_width = 0 },
                    on_click = function()
                        local msgbox = airui.msgbox({
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, label)
                                if label == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msgbox:show()
                    end
                })
            end
        else
            local btn_w = math.min(80, card_w - 24)
            airui.button({
                parent = card,
                x = 12,
                y = btn_y,
                w = btn_w,
                h = btn_height,
                text = "安装",
                font_size = button_font_size,
                style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = 0xFFFFFF, radius = 16, border_width = 0 },
                on_click = function()
                    local msgbox = airui.msgbox({
                        title = "确认安装",
                        text = "是否安装应用 " .. (app.title or app.name) .. "？",
                        buttons = { "确定", "取消" },
                        on_action = function(self, label)
                            if label == "确定" then
                                show_progress_dialog(app.title or app.name)
                                sys.publish("APP_STORE_INSTALL", tostring(app.aid), app.url, app.title or app.name,
                                    current_category, current_sort)
                            end
                            self:hide()
                        end
                    })
                    msgbox:show()
                end
            })
        end
    end
end

-------------------------------------------------------------------------------
-- 消息回调
-------------------------------------------------------------------------------
local function on_installed_updated(new_installed)
    for aid, _ in pairs(new_installed) do
        local_installed_ids[aid] = true
    end
end

local function on_list_updated(apps, page_info)
    local has_more_now = false
    local total_pages_now = current_page
    local total_now = 0
    if type(page_info) == "table" then
        if type(page_info.page) == 'number' then
            current_page = page_info.page
        end
        if type(page_info.total_pages) == 'number' then
            total_pages_now = page_info.total_pages
        elseif type(page_info.pages) == 'number' then
            total_pages_now = page_info.pages
        end
        if type(page_info.total) == 'number' then
            total_now = page_info.total
        end
        if page_info.has_more ~= nil then
            has_more_now = (page_info.has_more == true)
        else
            has_more_now = (current_page < total_pages_now)
        end
    end

    has_more = has_more_now
    if type(total_pages_now) ~= "number" then
        total_pages_now = 1
    end
    total_pages = math.max(total_pages_now, 1)
    update_page_display()

    local installed_apps = exapp.list_installed()

    for _, app in ipairs(apps) do
        local aid = tostring(app.aid)
        local cached = local_installed_ids[aid]
        if cached ~= nil then
            app.installed = cached
            if cached and installed_apps[aid] then
                local info = installed_apps[aid]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            end
        else
            if installed_apps[aid] then
                app.installed = true
                local info = installed_apps[aid]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            else
                app.installed = false
            end
        end
    end
    render_apps(apps, has_more)
end

local function on_progress(aid, percent, status_text)
    if progress_bar and progress_label then
        progress_bar:set_value(percent)
        progress_label:set_text(status_text or string.format("下载进度 %d%%", percent))
        if percent >= 100 then
            progress_label:set_text("解压完成，请稍候...")
        end
    end
end

local function on_action_done(aid, action, success)
    close_progress_dialog()

    if success then
        local app_name = nil
        local installed_apps = exapp.list_installed()
        if installed_apps[aid] then
            app_name = installed_apps[aid].cn_name or installed_apps[aid].name
        end

        local apps, more = exapp.get_current_list()
        if apps then
            local idx = nil
            for i, app in ipairs(apps) do
                if tostring(app.aid) == aid then
                    idx = i
                    break
                end
            end

            if idx then
                if action == "install" then
                    apps[idx].installed = true
                    apps[idx].has_update = false
                elseif action == "update" then
                    apps[idx].has_update = false
                    apps[idx].installed = true
                elseif action == "uninstall" then
                    apps[idx].installed = false
                end
            end

            render_apps(apps, more)
        end

        show_success_toast(action, app_name)

        local key = tostring(aid)
        if action == "install" and success then
            local_installed_ids[key] = true
        elseif action == "uninstall" and success then
            local_installed_ids[key] = false
        end
    end
end

local function on_error(msg)
    close_progress_dialog()
    local msgbox = airui.msgbox({
        title = "错误",
        text = msg,
        buttons = { "确定" },
        on_action = function(self, label) self:hide() end
    })
    msgbox:show()
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    calc_layout()
    create_ui()

    sys.subscribe("APP_STORE_LIST_UPDATED", on_list_updated)
    sys.subscribe("APP_STORE_PROGRESS", on_progress)
    sys.subscribe("APP_STORE_ERROR", on_error)
    sys.subscribe("APP_STORE_ACTION_DONE", on_action_done)
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    sys.subscribe("APP_STORE_ICON_READY", on_icon_ready)

    sys.publish("APP_STORE_SYNC_INSTALLED")
    sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
end

local function on_destroy()
    sys.unsubscribe("APP_STORE_LIST_UPDATED", on_list_updated)
    sys.unsubscribe("APP_STORE_PROGRESS", on_progress)
    sys.unsubscribe("APP_STORE_ERROR", on_error)
    sys.unsubscribe("APP_STORE_ACTION_DONE", on_action_done)
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    sys.unsubscribe("APP_STORE_ICON_READY", on_icon_ready)

    close_progress_dialog()
    if search_keyboard then search_keyboard:destroy() end
    if main_container then main_container:destroy() end
end

local function on_get_focus()
    local apps, more = exapp.get_current_list()
    if apps then
        render_apps(apps, more)
    end
end

local function on_lose_focus()
    local_installed_ids = {}
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_APP_STORE_WIN", open_handler)