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
-- All variable and function names now use full readable names.
-- Layout variables defined in calc_layout().
-- Message callbacks: on_list_updated, on_installed_updated, on_progress, on_action_done, on_error, on_icon_ready
-- Containers: main_container, app_content_area, app_grid
-- State: current_category, current_sort, current_page, total_pages, has_more, current_query

local window_id = nil
local main_container = nil
local search_input = nil
local search_keyboard = nil
local sort_select = nil
local category_buttons = {}
local current_category = "全部"
local current_sort = "recommend"
local app_content_area = nil
local app_grid = nil
local page_label = nil
local prev_button = nil
local next_button = nil

-- 布局参数
local top_height, sort_height, sidebar_width, available_area_height, pagination_bar_height, grid_area_height = 0, 0, 0, 0, 0, 0
local search_box_width, search_box_height = 0, 0
local sort_bar_width = 0
local app_content_width, app_content_height = 0, 0
local app_grid_width, app_grid_height = 0, 0
local page_bar_width = 0
local sort_by = 0

local grid_margin = 8
local card_width, card_height = 0, 0
local grid_columns = 1
local icon_size = 0
local title_font_size = 0
local description_font_size = 0
local button_font_size = math.floor(16 * (_G.density_scale or 1))
local info_font_size = 0
local max_description_lines = 2 -- 描述最大行数，动态计算

-- 按钮自适应参数
local card_button_height = math.floor(32 * (_G.density_scale or 1.0))
local card_button_bottom_margin = 8
local current_page = 1
local total_pages = 0
local page_limit = 10
local has_more = false
local current_query = ""

-- 只保存UI状态，不保存业务数据
local local_installed_info = {}

-- 使用颜色
local COLOR_PRIMARY = 0x007AFF
local COLOR_PRIMARY_DARK = 0x0056B3
local COLOR_ACCENT = 0xFF9800
local COLOR_BG = 0xF5F5F5
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER = 0xE0E0E0
local COLOR_WHITE = 0xFFFFFF
local COLOR_DANGER = 0xE63946

local categories = { "全部", "已安装", "通信", "工具", "游戏", "工业", "健康" }
local pending_icon_updates = {}

-- 进度对话框相关
local progress_dialog = nil
local progress_bar = nil
local progress_label = nil

-------------------------------------------------------------------------------
-- 布局计算
------------------------------------------------------------------------------
local function calc_layout()
    -- 框架布局：从模板线性缩放
    -- 竖屏模板 480x854: top=68, sort=51, side=96, pagination_bar_height=55
    -- 横屏模板 854x480: top=38, sort=28, side=136, pagination_bar_height=40
    if is_landscape then
        local sy = screen_h / 480
        top_height = math.floor(38 * sy)
        sort_height = math.floor(28 * sy)
        sidebar_width = math.floor(136 * screen_w / 854)
        pagination_bar_height = math.floor(40 * sy)
    else
        local sy = screen_h / 854
        top_height = math.floor(68 * sy)
        sort_height = math.floor(51 * sy)
        sidebar_width = math.floor(96 * screen_w / 480)
        pagination_bar_height = math.floor(55 * sy)
    end
    sidebar_width = math.max(64, math.min(260, sidebar_width))
    sort_height = math.max(26, sort_height)
    pagination_bar_height = math.max(28, math.min(60, pagination_bar_height))

    -- 字体大小（全部 ≥ 14）
    local bf = math.floor(screen_h / 40 * _G.density_scale)
    bf = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(24 * _G.density_scale), bf))
    title_font_size = math.max(math.floor(16 * _G.density_scale), math.min(math.floor(26 * _G.density_scale), bf))
    description_font_size = math.max(math.floor(14 * _G.density_scale),
        math.min(math.floor(22 * _G.density_scale), bf - math.floor(2 * _G.density_scale)))
    button_font_size = math.max(math.floor(14 * _G.density_scale),
        math.min(math.floor(20 * _G.density_scale), bf - math.floor(2 * _G.density_scale)))
    info_font_size = button_font_size

    -- 图标大小
    if is_landscape then
        icon_size = math.max(math.floor(40 * _G.density_scale),
            math.min(math.floor(70 * _G.density_scale), math.floor(screen_h / 16 * _G.density_scale)))
    else
        icon_size = math.max(math.floor(40 * _G.density_scale),
            math.min(math.floor(70 * _G.density_scale), math.floor(screen_h / 14 * _G.density_scale)))
    end
    if screen_h < 360 then
        icon_size = math.max(math.floor(32 * _G.density_scale),
            math.min(math.floor(50 * _G.density_scale), math.floor(screen_h / 12 * _G.density_scale)))
    end

    -- 区域尺寸
    available_area_height = screen_h - top_height - sort_height
    grid_area_height = available_area_height - pagination_bar_height - grid_margin * 2

    search_box_width = screen_w - 2 * grid_margin - 70 - 50
    search_box_height = math.max(32, math.min(math.floor(top_height * 0.72), top_height - 10))
    sort_bar_width = screen_w
    app_content_width = screen_w - sidebar_width
    app_content_height = available_area_height
    app_grid_width = app_content_width - 2 * grid_margin
    app_grid_height = grid_area_height
    page_bar_width = app_content_width

    -- 网格列数（动态计算，最小卡片宽度乘以 density_scale 适配高密度屏）
    local mcw
    if is_landscape then
        mcw = math.max(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.18 * _G.density_scale))
    else
        mcw = math.max(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.30 * _G.density_scale))
    end
    mcw = math.max(math.floor(150 * _G.density_scale), math.min(math.floor(280 * _G.density_scale), mcw))

    grid_columns = math.max(1, math.floor(app_grid_width / mcw))

    if screen_w < 480 then
        grid_columns = math.min(2, grid_columns)
    elseif screen_w < 720 then
        grid_columns = math.min(3, grid_columns)
    elseif screen_w < 1800 then
        grid_columns = math.min(4, grid_columns)
    else
        grid_columns = math.min(5, grid_columns)
    end

    if screen_w <= 480 and not is_landscape then
        grid_columns = 1
    end

    card_width = math.floor((app_grid_width - (grid_columns + 1) * grid_margin) / grid_columns)

    -- 卡片按钮高度
    if screen_h < 360 then
        card_button_height = math.max(math.floor(28 * _G.density_scale),
            math.min(math.floor(40 * _G.density_scale), math.floor(screen_h / 14 * _G.density_scale)))
    else
        card_button_height = math.max(math.floor(36 * _G.density_scale),
            math.min(math.floor(50 * _G.density_scale), math.floor(screen_h / 18 * _G.density_scale)))
    end

    -- 卡片高度与描述行数
    local tlh = title_font_size + 4
    local ilh = info_font_size + 4
    local dlh = description_font_size + 4
    local desc_lines = 2

    local vpe = (screen_h < 400) and 8 or 12
    local bch = math.max(icon_size, tlh + ilh) + card_button_height + card_button_bottom_margin +
        vpe
    local ahd = grid_area_height - bch - grid_margin * 2

    if ahd >= dlh * 2 then
        desc_lines = 2
    elseif ahd >= dlh then
        desc_lines = 1
    else
        desc_lines = 0
    end

    local dh = description_font_size * desc_lines + (desc_lines > 0 and 8 or 0)
    card_height = math.floor(bch + dh)

    -- 确保卡片高度足够容纳内部布局：描述 + 间距 + 按钮
    local ioy = 15 + title_font_size + 6
    local dsy = ioy + info_font_size + 8
    local rh = dsy + dh + 4 + card_button_height + card_button_bottom_margin
    card_height = math.max(card_height, math.floor(rh))

    local rpp = math.max(1, math.floor(grid_area_height / (card_height + grid_margin)))
    page_limit = grid_columns * rpp

    max_description_lines = desc_lines

end

local function update_page_label()
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
    local msk = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0x000000,
        color_opacity = 180,
    })
    local dlw = math.min(400, screen_w - 80)
    local dlh = 160
    local dlx = (screen_w - dlw) / 2
    local dly = (screen_h - dlh) / 2
    local dlg = airui.container({
        parent = msk,
        x = dlx,
        y = dly,
        w = dlw,
        h = dlh,
        color = COLOR_CARD,
        radius = 16,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    airui.label({
        parent = dlg,
        x = 20,
        y = 20,
        w = dlw - 40,
        h = 30,
        text = "正在安装 " .. (app_name or ""),
        font_size = title_font_size,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    local bar = airui.bar({
        parent = dlg,
        x = 20,
        y = 70,
        w = dlw - 40,
        h = 20,
        min = 0,
        max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 10
    })
    local tl = airui.label({
        parent = dlg,
        x = 20,
        y = 105,
        w = dlw - 40,
        h = 24,
        text = "准备下载...",
        font_size = description_font_size,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    progress_dialog = msk
    progress_bar = bar
    progress_label = tl
end

local function show_status_toast(action, app_name)
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
    local toast_msg = airui.msgbox({
        w = math.floor(screen_w * 0.7),
        h = math.floor(screen_h * 0.25),
        style = { text_font_size = button_font_size },
	title = "提示",
        text = msg,
        buttons = { "确定" },
        timeout = 1000,
        on_action = function(self, btn_label)
            if btn_label == "确定" then
                self:hide()
            end
            self:destroy()
        end
    })
    toast_msg:show()
end

-------------------------------------------------------------------------------
-- 图标更新
-------------------------------------------------------------------------------
local function on_icon_ready(app_id, icon_path)
    local entry = pending_icon_updates[app_id]
    if entry and entry.image_component then
        entry.image_component:set_src(icon_path)
    end
    pending_icon_updates[app_id] = nil
end

-------------------------------------------------------------------------------
-- UI 创建（顶部栏、排序栏、分类侧边栏、内容区、分页栏）
-------------------------------------------------------------------------------
local function create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h, color = COLOR_BG, parent = airui.screen
    })

    -- 顶部栏
    local tb = airui.container({
        parent = main_container, x = 0, y = 0, w = screen_w, h = top_height, color = COLOR_CARD
    })
    -- 按钮高度：小屏用 38 上限，大屏按宽度比例放大
    local tih = math.floor(top_height * 0.82)
    if screen_w <= 480 then
        tih = math.min(38, tih)
    else
        tih = math.max(math.floor(screen_w * 0.06), tih)
    end
    tih = math.min(tih, top_height - 4)
    local tiy = math.floor((top_height - tih) / 2)
    local tir = math.floor(tih / 2)
    airui.button({
        parent = tb,
        x = 8,
        y = tiy,
        w = tih,
        h = tih,
        text = "←",
        font_size = math.min(math.floor(24 * _G.density_scale), math.floor((tih - 4) * _G.density_scale)),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = tir, border_width = 1, border_color = COLOR_DIVIDER, pad = 0 },
        on_click = function()
            if window_id then
                exwin.close(window_id)
            end
        end
    })

    local search_btn_w = math.max(60, math.floor(button_font_size * 2.5))
    -- 大屏按宽度比例放大搜索按钮
    if screen_w > 480 then
        search_btn_w = math.max(search_btn_w, math.floor(screen_w * 0.10))
    end
    local sbwe = screen_w - tih - 12 - search_btn_w - 8
    local sbhe = math.min(tih, search_box_height)
    local sbg = airui.container({
        parent = tb,
        x = tih + 12,
        y = tiy,
        w = sbwe,
        h = sbhe,
        color = COLOR_DIVIDER,
        radius = tir,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    -- 搜索框内容跟踪变量（避免焦点切换后 get_text 回滚到旧值）
    local search_text = ""
    local function sync_search_text()
        local t = (search_input and search_input:get_text()) or ""
        search_text = t
    end
    local function publish_get_list()
        sync_search_text()
        current_query = search_text
        sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
    end

    search_keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = screen_w,
        h = 200,
        bg_color = COLOR_CARD,
        on_commit = function(self)
            sync_search_text()
            self:hide()
        end,
    })
    search_input = airui.textarea({
        parent = sbg,
        x = 8,
        y = 2,
        w = sbwe - 16,
        h = sbhe - 4,
        placeholder = "搜索应用...",
        font_size = button_font_size,
        color = COLOR_TEXT,
        keyboard = search_keyboard
    })
    local sbnw = math.min(search_btn_w, screen_w - tih - 12 - sbwe - 8)
    airui.button({
        parent = tb,
        x = tih + 12 + sbwe + 4,
        y = tiy,
        w = sbnw,
        h = tih,
        text = "搜索",
        font_size = button_font_size,
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = tir, border_width = 0, pad = 4 },
        on_click = function()
            if search_keyboard then search_keyboard:hide() end
            current_page = 1
            publish_get_list()
        end
    })

    -- 排序栏
    local srb = airui.container({
        parent = main_container,
        x = 0,
        y = top_height,
        w = sort_bar_width,
        h = sort_height,
        color = COLOR_CARD
    })
    local stbh = math.floor(sort_height * 0.85)
    if screen_w <= 480 then
        stbh = math.min(36, stbh)
    else
        stbh = math.max(math.floor(screen_w * 0.06), stbh)
    end
    stbh = math.min(stbh, sort_height - 4)
    local stbr = math.floor(stbh / 2)
    sort_by = math.floor((sort_height - stbh) / 2)
    local sddx = math.floor(12 * _G.density_scale)
    local sort_dd_max = math.max(150, math.floor(150 * _G.density_scale))
    local sddw = math.min(sort_dd_max, math.floor((screen_w - sddx - 90) * 0.65))
    local srfx = sddx + sddw + 20
    if srfx + 70 > screen_w then
        sddw = math.floor(screen_w - sddx - 90)
        srfx = sddx + sddw + 10
    end
    sort_select = airui.dropdown({
        parent = srb,
        x = sddx,
        y = sort_by,
        w = sddw,
        h = stbh,
        options = { "推荐", "序号", "上传时间(旧)", "上传时间(新)", "热度", "下载量", "更新优先" },
        default_index = 0,
        style = { bg_color = COLOR_CARD, border_color = COLOR_DIVIDER, radius = stbr },
        on_change = function(self, idx, option_value)
            local sort_map = { "recommend", "idAsc", "timeAsc", "timeDesc", "hot", "downloads", "updatePriority" }
            current_sort = sort_map[idx + 1] or "recommend"
            current_page = 1
            publish_get_list()
        end
    })
    airui.button({
        parent = srb,
        x = math.max(srfx, screen_w - 78),
        y = sort_by,
        w = math.min(math.max(70, math.floor(button_font_size * 3)), screen_w - math.max(srfx, screen_w - 78) - 4),
        h = stbh,
        text = "刷新",
        font_size = button_font_size,
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = stbr, border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function()
            current_page = 1
            publish_get_list()
        end
    })

    -- 分类侧边栏
    local csb = airui.container({
        parent = main_container,
        x = 0,
        y = top_height + sort_height,
        w = sidebar_width,
        h = available_area_height,
        color = COLOR_CARD
    })
    local cy = 16
    local cth = math.max(36, math.min(50, math.floor(screen_h / 20)))
    local ctr = math.min(24, math.floor(cth / 2))
    local ctw = sidebar_width - 20
    for i, cat in ipairs(categories) do
        local btn = airui.button({
            parent = csb,
            x = 10,
            y = cy,
            w = ctw,
            h = cth,
            text = cat,
            font_size = button_font_size,
            style = {
                bg_color = (cat == current_category) and COLOR_PRIMARY or COLOR_CARD,
                pressed_bg_color = COLOR_PRIMARY_DARK,
                text_color = (cat == current_category) and COLOR_WHITE or COLOR_TEXT,
                radius = ctr,
                border_width = 1,
                border_color = COLOR_DIVIDER,
                pad = 0
            },
            on_click = function()
                if current_category == cat then return end
                current_category = cat
                for cat_idx, button_obj in ipairs(category_buttons) do
                    local is_active = (categories[cat_idx] == cat)
                    button_obj:set_style({
                        bg_color = is_active and COLOR_PRIMARY or COLOR_CARD,
                        text_color = is_active and COLOR_WHITE or COLOR_TEXT
                    })
                end
                current_page = 1
                publish_get_list()
            end
        })
        category_buttons[i] = btn
        cy = cy + cth + 8
    end

    -- 右侧内容区
    app_content_area = airui.container({
        parent = main_container,
        x = sidebar_width,
        y = top_height + sort_height,
        w = app_content_width,
        h = app_content_height - pagination_bar_height,
        color = COLOR_BG,
        scrollable = true,
    })
    app_grid = airui.container({
        parent = app_content_area,
        x = grid_margin,
        y = grid_margin,
        w = app_grid_width,
        h = app_grid_height,
        color = COLOR_BG
    })

    -- 分页栏
    local pbhe = pagination_bar_height
    local pgb = airui.container({
        parent = main_container,
        x = sidebar_width,
        y = screen_h - pagination_bar_height,
        w = screen_w - sidebar_width,
        h = pagination_bar_height,
        color = COLOR_CARD
    })
    local pag_btn_w = math.max(70, math.floor(button_font_size * 3))
    local pvx = 16
    local pvw = pag_btn_w
    local nxw = pag_btn_w
    local nxx = page_bar_width - pag_btn_w - 16
    local lx = pvx + pvw + 4

    local pnbh = math.min(40, math.floor(pagination_bar_height * 0.8))
    local pnby = math.floor((pagination_bar_height - pnbh) / 2)
    local pnr = math.floor(pnbh / 2)

    prev_button = airui.button({
        parent = pgb,
        x = pvx,
        y = pnby,
        w = pvw,
        h = pnbh,
        text = "上一页",
        font_size = math.max(math.floor(14 * _G.density_scale), button_font_size - math.floor(4 * _G.density_scale)),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = pnr, border_width = 0 },
        on_click = function()
            if current_page > 1 then
                current_page = current_page - 1
                publish_get_list()
                update_page_label()
            end
        end
    })
    next_button = airui.button({
        parent = pgb,
        x = nxx,
        y = pnby,
        w = nxw,
        h = pnbh,
        text = "下一页",
        font_size = math.max(math.floor(14 * _G.density_scale), button_font_size - math.floor(4 * _G.density_scale)),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = pnr, border_width = 0 },
        on_click = function()
            if has_more then
                current_page = current_page + 1
                publish_get_list()
                update_page_label()
            end
        end
    })
    page_label = airui.label({
        parent = pgb,
        x = lx,
        y = math.floor((pagination_bar_height - 30) / 2),
        w = screen_w - sidebar_width - nxw * 2 - 40,
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
local function render_apps(apps, has_more_pages)
    has_more = has_more_pages
    update_page_label()

    if app_grid then app_grid:destroy() end

    -- 空列表时显示提示（避免切换分类后残留旧数据）
    if #apps == 0 then
        app_grid = airui.container({
            parent = app_content_area,
            x = grid_margin,
            y = grid_margin,
            w = app_grid_width,
            h = grid_area_height,
            color = COLOR_BG
        })
        local empty_text = (current_category == "已安装") and "暂未安装应用" or "暂无应用"
        airui.label({
            parent = app_grid,
            x = 0, y = math.floor(grid_area_height / 2) - 30,
            w = app_grid_width, h = 60,
            text = empty_text,
            font_size = 18,
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })
        update_page_label()
        return
    end

    local row_count = math.ceil(#apps / grid_columns)
    local needed_grid_height = math.max(grid_area_height, row_count * (card_height + grid_margin) + grid_margin + 10)
    app_grid = airui.container({
        parent = app_content_area,
        x = grid_margin,
        y = grid_margin,
        w = app_grid_width,
        h = needed_grid_height,
        color = COLOR_BG
    })

    local ia = exapp.list_installed()
    local bh = card_button_height
    local bbm = card_button_bottom_margin
    local by = card_height - bh - bbm

    for idx, app in ipairs(apps) do
        local installed_flag = local_installed_info[tostring(app.aid)]
        if installed_flag then app.installed = true end

        local col = (idx - 1) % grid_columns
        local row = math.floor((idx - 1) / grid_columns)
        local x = col * (card_width + grid_margin) + grid_margin
        local y = row * (card_height + grid_margin) + grid_margin

        local card = airui.container({
            parent = app_grid,
            x = x,
            y = y,
            w = card_width,
            h = card_height,
            color = COLOR_CARD,
            radius = 16,
            border_width = 1,
            border_color = COLOR_DIVIDER
        })

        -- 图标
        local isc = "/luadb/img.png"
        if app.icon_path and io.exists(app.icon_path) then
            isc = app.icon_path
        end

        airui.image({
            parent = card, x = 12, y = 12, w = icon_size, h = icon_size, src = isc
        })

        -- 应用名称
        local ny = 15
        airui.label({
            parent = card,
            x = icon_size + 20,
            y = ny,
            w = card_width - icon_size - 28,
            h = title_font_size + 4,
            text = app.title or app.name or "未知",
            font_size = title_font_size,
            color = COLOR_TEXT
        })

        -- 信息行：大小和下载量（格式：XXKB | ↓ xx次）
        local ioy = ny + title_font_size + 6
        local osz = tonumber(app.origin_size_kb) or 0
        local szt = (osz > 0) and (math.floor(osz) .. "KB") or "未知"
        local tdl = tonumber(app.total_downloads) or 0
        local dlt = (tdl > 0) and tostring(math.floor(tdl)) or "0"
        local ift = string.format("%s | ↓ %s次", szt, dlt)
        airui.label({
            parent = card,
            x = icon_size + 20,
            y = ioy,
            w = card_width - icon_size - 28,
            h = info_font_size + 4,
            text = ift,
            font_size = info_font_size,
            color = COLOR_TEXT_SECONDARY
        })

        -- 应用描述（动态行数）
        if max_description_lines > 0 then
            local dsy = ioy + info_font_size + 8
            local dh = description_font_size * max_description_lines + (max_description_lines > 1 and 2 or 0)
            airui.label({
                parent = card,
                x = 12,
                y = dsy,
                w = card_width - 24,
                h = dh,
                text = app.desc or "",
                font_size = description_font_size,
                color = COLOR_TEXT_SECONDARY
            })
        end

        -- 按钮（安装/更新/卸载）
        if app.installed then
            if app.has_update then
                local bw = math.min(70, (card_width - 36) / 2)
                airui.button({
                    parent = card,
                    x = 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "更新",
                    font_size = button_font_size,
                    style = { bg_color = COLOR_ACCENT, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local msg_box = airui.msgbox({
                            w = math.floor(screen_w * 0.78),
                            h = math.floor(screen_h * 0.28),
                            style = { text_font_size = button_font_size },
                            title = "确认更新",
                            text = "是否更新应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, btn_label)
                                if btn_label == "确定" then
                                    show_progress_dialog(app.title or app.name)
                                    sys.publish("APP_STORE_UPDATE", tostring(app.aid), app.url, app.title or app.name, current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msg_box:show()
                    end
                })
                airui.button({
                    parent = card,
                    x = 12 + bw + 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "卸载",
                    font_size = button_font_size,
                    style = { bg_color = COLOR_DANGER, pressed_bg_color = COLOR_DANGER, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local msg_box = airui.msgbox({
                            w = math.floor(screen_w * 0.78),
                            h = math.floor(screen_h * 0.28),
                            style = { text_font_size = button_font_size },
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, btn_label)
                                if btn_label == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msg_box:show()
                    end
                })
            else
                local bw = math.min(80, card_width - 24)
                airui.button({
                    parent = card,
                    x = 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "卸载",
                    font_size = button_font_size,
                    style = { bg_color = COLOR_DANGER, pressed_bg_color = COLOR_DANGER, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local msg_box = airui.msgbox({
                            w = math.floor(screen_w * 0.78),
                            h = math.floor(screen_h * 0.28),
                            style = { text_font_size = button_font_size },
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, btn_label)
                                if btn_label == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), current_category, current_sort)
                                end
                                self:hide()
                            end
                        })
                        msg_box:show()
                    end
                })
            end
        else
            local bw = math.min(80, card_width - 24)
            airui.button({
                parent = card,
                x = 12,
                y = by,
                w = bw,
                h = bh,
                text = "安装",
                font_size = button_font_size,
                style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                on_click = function()
                    local msg_box = airui.msgbox({
                        w = math.floor(screen_w * 0.78),
                        h = math.floor(screen_h * 0.28),
                        style = { text_font_size = button_font_size },
                        title ="确认安装",
                        text = "是否安装应用 " .. (app.title or app.name) .. "？",
                        buttons = { "确定", "取消" },
                        on_action = function(self, btn_label)
                            if btn_label == "确定" then
                                show_progress_dialog(app.title or app.name)
                                sys.publish("APP_STORE_INSTALL", tostring(app.aid), app.url, app.title or app.name, current_category, current_sort)
                            end
                            self:hide()
                        end
                    })
                    msg_box:show()
                end
            })
        end
    end
end

-------------------------------------------------------------------------------
-- 消息回调
-------------------------------------------------------------------------------
local function on_installed_updated(new_installed)
    for app_id_str, _ in pairs(new_installed) do
        local_installed_info[app_id_str] = true
    end
end

local function on_list_updated(apps, page_info)
    local hn = false
    local tn = current_page
    local tl = 0
    if type(page_info) == "table" then
        if type(page_info.page) == 'number' then
            current_page = page_info.page
        end
        if type(page_info.total_pages) == 'number' then
            tn = page_info.total_pages
        elseif type(page_info.total_pages) == 'number' then
            tn = page_info.total_pages
        end
        if type(page_info.total) == 'number' then
            tl = page_info.total
        end
        if page_info.has_more ~= nil then
            hn = (page_info.has_more == true)
        else
            hn = (current_page < tn)
        end
    end

    has_more = hn
    if type(tn) ~= "number" then
        tn = 1
    end
    total_pages = math.max(tn, 1)
    update_page_label()

    local ia = exapp.list_installed()

    for _, app in ipairs(apps) do
        local app_id_str = tostring(app.aid)
        local cached_status = local_installed_info[app_id_str]
        if cached_status ~= nil then
            app.installed = cached_status
            if cached_status and ia[app_id_str] then
                local info = ia[app_id_str]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            end
        else
            if ia[app_id_str] then
                app.installed = true
                local info = ia[app_id_str]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            else
                app.installed = false
            end
        end
    end
    if current_category == "已安装" then
        local filtered = {}
        for _, app in ipairs(apps) do
            if app.installed then
                table.insert(filtered, app)
            end
        end
        if #filtered == 0 then
            render_apps({}, false)
            return
        end
        apps = filtered
        -- 以实际已安装数量计算分页，而非服务端返回的 total
        local ia = exapp.list_installed()
        local installed_cnt = 0
        for _ in pairs(ia) do installed_cnt = installed_cnt + 1 end
        total_pages = math.max(1, math.ceil(installed_cnt / page_limit))
        has_more = (current_page < total_pages)
    end
    render_apps(apps, has_more)
end

local function on_progress(app_id, download_percent, status_text)
    if progress_bar and progress_label then
        progress_bar:set_value(download_percent)
        progress_label:set_text(status_text or string.format("下载进度 %d%%", download_percent))
        if download_percent >= 100 then
            progress_label:set_text("解压完成，请稍候...")
        end
    end
end

local function on_action_done(app_id, action, success)
    close_progress_dialog()

    if success then
        local app_name = nil
        local ia = exapp.list_installed()
        if ia[app_id] then
            app_name = ia[app_id].cn_name or ia[app_id].name
        end

        local apps, more = exapp.get_current_list()
        if apps then
            local app_index = nil
            for i, app in ipairs(apps) do
                if tostring(app.aid) == app_id then
                    app_index = i
                    break
                end
            end

            if app_index then
                if action == "install" then
                    apps[app_index].installed = true
                    apps[app_index].has_update = false
                elseif action == "update" then
                    apps[app_index].has_update = false
                    apps[app_index].installed = true
                elseif action == "uninstall" then
                    apps[app_index].installed = false
                end
            end

            if current_category == "已安装" then
                local filtered = {}
                for _, app in ipairs(apps) do
                    if app.installed then
                        table.insert(filtered, app)
                    end
                end
                if #filtered > 0 then
                    render_apps(filtered, false)
                else
                    render_apps({}, false)
                end
            else
                render_apps(apps, more)
            end
        end

        show_status_toast(action, app_name)

        local key = tostring(app_id)
        if action == "install" and success then
            local_installed_info[key] = true
        elseif action == "uninstall" and success then
            local_installed_info[key] = false
        end

        -- 卸载后调整分页：如果当前页已空且非首页，回退一页
        if action == "uninstall" and success then
            if current_category == "已安装" then
                local ia = exapp.list_installed()
                local installed_cnt = 0
                for _ in pairs(ia) do installed_cnt = installed_cnt + 1 end
                total_pages = math.max(1, math.ceil(installed_cnt / page_limit))
                if current_page > total_pages then
                    current_page = total_pages
                end
                has_more = current_page < total_pages
            end
            update_page_label()
        end

        -- 后台用当前页码重新请求服务端数据，不跳回第1页
        sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
    end
end

local function on_error(error_msg)
    close_progress_dialog()
    local msg_box = airui.msgbox({
        w = math.floor(screen_w * 0.78),
        h = math.floor(screen_h * 0.28),
        style = { text_font_size = button_font_size },
        title = "错误",
        text = error_msg,
        buttons = { "确定" },
        on_action = function(self, btn_label) self:hide() end
    })
    msg_box:show()
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
    -- 立即请求列表（网络已就绪时马上加载）
    sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
    -- 网络未就绪时等IP_READY后再重试一次（避免首次进入需手动刷新）
    sys.taskInit(function()
        local ok = sys.waitUntil("IP_READY", 30000)
        if ok then
            sys.publish("APP_STORE_GET_LIST", current_category, current_sort, current_page, page_limit, current_query)
        end
    end)
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
        if current_category == "已安装" then
            local ia = exapp.list_installed()
            local filtered = {}
            for _, app in ipairs(apps) do
                local app_id_str = tostring(app.aid)
                if ia[app_id_str] then
                    app.installed = true
                    table.insert(filtered, app)
                end
            end
            if #filtered == 0 then
                return
            end
            render_apps(filtered, false)
        else
            render_apps(apps, more)
        end
    end
end

local function on_lose_focus()
    local_installed_info = {}
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_APP_STORE_WIN", open_handler)
