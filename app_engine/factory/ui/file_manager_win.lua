--[[
@module  file_manager_win
@summary 文件管理窗口模块，包含设备列表页和目录浏览页
@version 1.1
@date    2026.06.02
@author  江访

设计原则：
1. 两级视图：设备列表 → 目录浏览（在同一窗口内切换）
2. 文件夹可展开/折叠，点击文件选中，顶部按钮操作
3. 纯 AirUI 容器表示，无图标图片
4. 所有跨节前向函数引用通过 view table 运行时解析
   （LuatOS bytecode 编译器可能 upvalue 捕获快照而非动态查找）
]]

local file_manager_app = require "file_manager_app"

local window_id = nil
local main_container = nil

-- 视图状态
local current_view = nil              -- "device_list" | "directory"
local current_mount_point = nil
local current_sub_path = nil
local tree_nodes = {}
local selected_path = nil
local selected_name = nil
local selected_is_dir = false

-- 多选模式
local multi_select_mode = false
local selected_paths = {}     -- { [path] = true }
local selected_count = 0

-- 剪贴板状态显示
local clipboard_info = nil    -- { mode = "copy"/"cut", count = N }

-- 设备列表容器
local device_list_container = nil
local device_items = {}

-- 目录视图容器
local directory_container = nil
local directory_content = nil
local action_bar = nil
local dir_titlebar_label = nil
local dir_titlebar_bg = nil
local dir_selected_bar = nil
local delete_button = nil

-- 目录内容行
local dir_item_rows = {}

-- 对话框
local dialog_overlay = nil
local input_dialog = nil
local input_textarea = nil
local input_callback = nil
local input_title = nil
local input_keyboard = nil
local confirm_dialog = nil
local confirm_callback = nil
local create_dialog = nil

-- 布局
local screen_w, screen_h = 480, 800
local margin = 10
local card_w = 460
local card_h = 70
local card_spacing = 12
local titlebar_h = 0
local action_bar_h = 0
local row_h = 0
local indent_w = 24

-- 颜色
local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946
local COLOR_WARNING        = 0xF0A020
local COLOR_FOLDER         = 0x007AFF
local COLOR_FILE           = 0x333333
local COLOR_SELECTED_BG    = 0xE3F2FD
local COLOR_SELECTED_TITLE = 0xE3F2FD

-- 所有需要运行时绑定的函数存于此表（解决 LuatOS bytecode 前向引用问题）
local view = {}

-- ==================== 工具函数 ====================

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    card_w = screen_w - 2 * margin
    card_h = math.max(48, math.floor(screen_h * 0.09))
    card_spacing = math.floor(screen_h * 0.015)

    local density = _G.density_scale or 1.0
    titlebar_h = math.floor(60 * density)
    action_bar_h = math.floor(50 * density)
    row_h = math.floor(44 * density)
    indent_w = math.floor(24 * density)
end

-- ==================== 树结构管理 ====================

local function get_full_path(sub_path)
    local base = current_mount_point .. "app_store"
    if sub_path == "" then return base end
    return base .. "/" .. sub_path
end

local function expand_node(full_path, depth)
    local node = tree_nodes[full_path]
    if not node then return end
    if node.expanded then return end

    local ret, items = file_manager_app.list_directory(full_path)
    if not ret then return end

    local dirs = {}
    local files = {}
    for _, item in ipairs(items) do
        if item.type == 1 then
            table.insert(dirs, item)
        else
            table.insert(files, item)
        end
    end
    table.sort(dirs, function(a, b) return a.name < b.name end)
    table.sort(files, function(a, b) return a.name < b.name end)

    local children = {}
    for _, item in ipairs(dirs) do
        local child_path = full_path .. "/" .. item.name
        tree_nodes[child_path] = {
            name = item.name,
            type = 1,
            size = 0,
            children = {},
            expanded = false,
            depth = depth + 1,
        }
        table.insert(children, child_path)
    end
    for _, item in ipairs(files) do
        local child_path = full_path .. "/" .. item.name
        tree_nodes[child_path] = {
            name = item.name,
            type = 0,
            size = tonumber(item.size) or 0,
            children = {},
            expanded = false,
            depth = depth + 1,
        }
        table.insert(children, child_path)
    end

    node.children = children
    node.expanded = true
end

local function collapse_node(full_path)
    local node = tree_nodes[full_path]
    if not node then return end
    if not node.expanded then return end

    for _, child_path in ipairs(node.children) do
        collapse_node(child_path)
        tree_nodes[child_path] = nil
    end
    node.children = {}
    node.expanded = false
end

local function flatten_tree(root_path)
    local result = {}

    local function walk(node_path)
        local node = tree_nodes[node_path]
        if not node then return end
        table.insert(result, node_path)
        if node.expanded then
            for _, child_path in ipairs(node.children) do
                walk(child_path)
            end
        end
    end

    walk(root_path)
    return result
end

-- ==================== 目录视图 ====================

local function has_any_selection()
    return (selected_path ~= nil) or (selected_count > 0)
end

local function clear_directory_content()
    for _, row in ipairs(dir_item_rows) do
        if row.ref then row.ref:destroy() end
    end
    dir_item_rows = {}
end

local function update_clipboard_display()
    local info = file_manager_app.clipboard_get()
    if info and #info > 1 then
        clipboard_info = nil
    end
    if view.render_directory then view.render_directory() end
end

-- 放在 render_directory 之前定义，供其引用
local function on_item_click(node_path)
    local node = tree_nodes[node_path]
    if not node then return end

    if multi_select_mode then
        -- 多选模式：toggle 选中项
        if selected_paths[node_path] then
            selected_paths[node_path] = nil
            selected_count = selected_count - 1
        else
            selected_paths[node_path] = true
            selected_count = selected_count + 1
        end
    elseif node.type == 1 then
        -- 文件夹：选中 + 展开/折叠
        if selected_path == node_path then
            -- 已选中：toggle 展开/折叠
            if node.expanded then
                collapse_node(node_path)
            else
                expand_node(node_path, node.depth)
            end
            -- 折叠后取消选中
            if not node.expanded then
                selected_path = nil
                selected_name = nil
                selected_is_dir = false
            end
        else
            -- 首次点击：选中并展开
            selected_path = node_path
            selected_name = node.name
            selected_is_dir = true
            if not node.expanded then
                expand_node(node_path, node.depth)
            end
        end
    else
        -- 文件：单选 toggle
        if selected_path == node_path then
            selected_path = nil
            selected_name = nil
            selected_is_dir = false
        else
            selected_path = node_path
            selected_name = node.name
            selected_is_dir = false
        end
    end

    local display_path = current_mount_point .. "app_store"
    if current_sub_path ~= "" then
        display_path = display_path .. "/" .. current_sub_path
    end
    if multi_select_mode and selected_count > 0 then
        display_path = display_path .. "  [已选:" .. selected_count .. "]"
    elseif selected_path and selected_name then
        display_path = display_path .. "  [" .. selected_name .. "]"
    end
    if dir_titlebar_label then
        dir_titlebar_label:set_text(display_path)
    end

    if view.render_directory then view.render_directory() end
end

local function deselect_all()
    selected_path = nil
    selected_name = nil
    selected_is_dir = false
    selected_paths = {}
    selected_count = 0
end

local function deselect_item()
    deselect_all()
    local display_path = current_mount_point .. "app_store"
    if current_sub_path ~= "" then
        display_path = display_path .. "/" .. current_sub_path
    end
    if dir_titlebar_label then
        dir_titlebar_label:set_text(display_path)
    end
    if view.render_directory then view.render_directory() end
end

local function refresh_directory()
    local root_path = get_full_path(current_sub_path)
    if tree_nodes[root_path] then
        if tree_nodes[root_path].expanded then
            collapse_node(root_path)
        end
    end
    deselect_item()
    if view.render_directory then view.render_directory() end
end

view.render_directory = function()
    if not directory_content then return end

    clear_directory_content()

    local root_path = get_full_path(current_sub_path)

    if not tree_nodes[root_path] then
        tree_nodes[root_path] = {
            name = "app_store",
            type = 1,
            size = 0,
            children = {},
            expanded = false,
            depth = 0,
        }
    end
    expand_node(root_path, 0)

    local visible = flatten_tree(root_path)
    local density = _G.density_scale or 1.0
    local font_size = math.floor(18 * density)

    -- use a factory to bind node_path per-iteration (Lua closure captures loop variable)
    local function create_row(node_path, node, px, pw, y, density)
        local bg_color = COLOR_BG
        if selected_paths[node_path] or node_path == selected_path then
            bg_color = COLOR_SELECTED_BG
        end
        return airui.container({
            parent = directory_content,
            x = 0, y = y,
            w = card_w, h = row_h,
            color = bg_color,
            on_click = function()
                on_item_click(node_path)
            end,
        })
    end

    local y = 0
    for _, node_path in ipairs(visible) do
        if node_path ~= root_path then
            local node = tree_nodes[node_path]
            if not node then goto continue end

            local node_depth = node.depth
            local px = (node_depth - 1) * indent_w + margin
            local pw = card_w - px - math.floor(50 * density)

            local row = create_row(node_path, node, px, pw, y, density)

            local name_color = (node.type == 1) and COLOR_FOLDER or COLOR_FILE
            -- 文件名 label：左侧对齐
            airui.label({
                parent = row,
                x = px, y = math.floor(8 * density),
                w = pw, h = row_h - math.floor(16 * density),
                text = node.name,
                font_size = font_size,
                color = name_color,
                align = airui.TEXT_ALIGN_LEFT,
            })

            -- 文件大小 label：右侧显示 KB，保留 1 位小数
            local size_str = ""
            if node.type == 0 then
                local kb = (node.size or 0) / 1024
                if kb < 0.1 then
                    size_str = "<0.1 KB"
                elseif kb >= 1024 then
                    size_str = string.format("%.1f MB", kb / 1024)
                else
                    size_str = string.format("%.1f KB", kb)
                end
            end
            airui.label({
                parent = row,
                x = card_w - math.floor(130 * density),
                y = math.floor(8 * density),
                w = math.floor(80 * density),
                h = row_h - math.floor(16 * density),
                text = size_str,
                font_size = math.floor(13 * density),
                color = COLOR_TEXT_SECONDARY,
                align = airui.TEXT_ALIGN_RIGHT,
            })

            if node.type == 1 then
                local marker = node.expanded and "V" or ">"
                airui.label({
                    parent = row,
                    x = card_w - math.floor(50 * density),
                    y = math.floor(8 * density),
                    w = math.floor(30 * density),
                    h = row_h - math.floor(16 * density),
                    text = marker,
                    font_size = math.floor(16 * density),
                    color = COLOR_TEXT_SECONDARY,
                    align = airui.TEXT_ALIGN_CENTER,
                })
            end

            table.insert(dir_item_rows, { ref = row, path = node_path, name = node.name, is_dir = (node.type == 1) })
            y = y + row_h
        end
        ::continue::
    end
end

view.build_directory_view = function()
    if directory_container then
        directory_container:destroy()
        directory_container = nil
    end

    update_screen_size()

    local density = _G.density_scale or 1.0
    local display_path = current_mount_point .. "app_store"
    if current_sub_path ~= "" then
        display_path = display_path .. "/" .. current_sub_path
    end

    -- 主容器
    directory_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    -- 标题栏：不随选中变色，始终蓝色
    dir_titlebar_bg = airui.container({
        parent = directory_container,
        x = 0, y = 0, w = screen_w, h = titlebar_h,
        color = COLOR_PRIMARY,
    })

    local back_btn = airui.container({
        parent = dir_titlebar_bg,
        x = math.floor(10 * density), y = math.floor(10 * density),
        w = math.floor(50 * density), h = math.floor(40 * density),
        color = COLOR_PRIMARY,
        on_click = function()
            current_view = "device_list"
            selected_path = nil
            selected_name = nil
            selected_is_dir = false
            dir_item_rows = {}
            tree_nodes = {}
            directory_container:destroy()
            directory_container = nil
            if device_list_container then
                clear_directory_content()
            end
            if view.build_device_list then view.build_device_list() end
        end,
    })
    airui.label({
        parent = back_btn,
        x = 0, y = math.floor(5 * density),
        w = math.floor(50 * density), h = math.floor(30 * density),
        text = "<", font_size = math.floor(28 * density),
        color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER,
    })

    dir_titlebar_label = airui.label({
        parent = dir_titlebar_bg,
        x = math.floor(60 * density), y = math.floor(5 * density),
        w = screen_w - math.floor(120 * density), h = math.floor(22 * density),
        text = display_path, font_size = math.floor(18 * density),
        color = COLOR_WHITE, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 选中状态显示在标题栏第二行（浅蓝条）
    local selected_bar = airui.container({
        parent = dir_titlebar_bg,
        x = 0, y = titlebar_h - math.floor(4 * density),
        w = screen_w, h = math.floor(4 * density),
        color = COLOR_PRIMARY,
    })
    dir_selected_bar = selected_bar

    -- 先计算操作栏所有尺寸，再创建容器（确保高度正确，子元素可见）
    local btn_gap = math.floor(8 * density)
    local btn_w = math.floor((card_w - margin * 2 - btn_gap * 2) / 3)
    local btn_font_size = math.floor(15 * density)
    local btn_h = math.floor(36 * density)
    local btn_row_gap = math.floor(4 * density)
    local row1_y = math.floor(4 * density)
    local row2_y = row1_y + btn_h + btn_row_gap
    local total_btn_h = (btn_h + btn_row_gap) * 2
    action_bar_h = total_btn_h + math.floor(8 * density)

    -- 操作栏容器（用已算好的正确高度创建）
    if action_bar then action_bar:destroy() end
    action_bar = airui.container({
        parent = directory_container,
        x = margin, y = titlebar_h + math.floor(4 * density),
        w = card_w, h = action_bar_h,
        color = COLOR_BG,
    })

    -- 操作栏：6 个按钮分两行（每行 3 个），按钮间距均匀分布
    -- 第一行：多选 | 新建 | 删除
    -- 第二行：复制 | 剪切 | 粘贴

    local function mk_btn(parent, x, y, text, style, on_click)
        airui.button({
            parent = parent, x = x, y = y, w = btn_w, h = btn_h,
            text = text, font_size = btn_font_size,
            style = style,
            on_click = on_click,
        })
    end

    local btn_style_active = { bg_color = COLOR_PRIMARY, pressed_bg_color = 0x0056B3, text_color = COLOR_WHITE, radius = 8, border_width = 0 }
    local btn_style_danger = { bg_color = COLOR_DANGER, pressed_bg_color = 0xB71C1C, text_color = COLOR_WHITE, radius = 8, border_width = 0 }
    local btn_style_warning= { bg_color = COLOR_WARNING, pressed_bg_color = 0xD4891A, text_color = COLOR_WHITE, radius = 8, border_width = 0 }
    local btn_style_gray   = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_TEXT, radius = 8, border_width = 0 }

    -- 第一行
    mk_btn(action_bar, margin, row1_y, multi_select_mode and "退出多选" or "多选", btn_style_active, function()
        multi_select_mode = not multi_select_mode
        deselect_all()
        -- 重建整个目录浏览视图以刷新按钮文本
        if view.build_directory_view then view.build_directory_view() end
    end)
    mk_btn(action_bar, margin + btn_w + btn_gap, row1_y, "新建", btn_style_warning, function()
        if view.show_create_dialog then view.show_create_dialog() end
    end)
    mk_btn(action_bar, margin + (btn_w + btn_gap) * 2, row1_y, "删除", btn_style_danger, function()
        local paths_to_delete = {}
        if multi_select_mode then
            for p, _ in pairs(selected_paths) do
                table.insert(paths_to_delete, p)
            end
        elseif selected_path then
            table.insert(paths_to_delete, selected_path)
        end
        if #paths_to_delete == 0 then return end
        local msg = "确定删除 " .. #paths_to_delete .. " 个项目吗？"
        if view.show_confirm_dialog then
            view.show_confirm_dialog("删除确认", msg, function()
                for _, p in ipairs(paths_to_delete) do
                    local node = tree_nodes[p]
                    local is_dir = node and (node.type == 1)
                    file_manager_app.delete_path(p, is_dir)
                end
                deselect_all()
                refresh_directory()
            end)
        end
    end)

    -- 第二行
    mk_btn(action_bar, margin, row2_y, "复制", btn_style_active, function()
        local items = {}
        if multi_select_mode then
            for p, _ in pairs(selected_paths) do
                local node = tree_nodes[p]
                if node then
                    table.insert(items, { path = p, is_dir = (node.type == 1), name = node.name })
                end
            end
        elseif selected_path then
            local node = tree_nodes[selected_path]
            if node then
                table.insert(items, { path = selected_path, is_dir = (node.type == 1), name = node.name })
            end
        end
        if #items == 0 then
            log.info("file_manager", "copy: no selection")
            return
        end
        log.info("file_manager", "copy items", #items, "src", items[1].path, "name", items[1].name)
        file_manager_app.clipboard_set(items, "copy")
        log.info("file_manager", "copied", #items, "items")
        deselect_all()
        if view.render_directory then view.render_directory() end
    end)

    mk_btn(action_bar, margin + btn_w + btn_gap, row2_y, "剪切", btn_style_active, function()
        local items = {}
        if multi_select_mode then
            for p, _ in pairs(selected_paths) do
                local node = tree_nodes[p]
                if node then
                    table.insert(items, { path = p, is_dir = (node.type == 1), name = node.name })
                end
            end
        elseif selected_path then
            local node = tree_nodes[selected_path]
            if node then
                table.insert(items, { path = selected_path, is_dir = (node.type == 1), name = node.name })
            end
        end
        if #items == 0 then
            log.info("file_manager", "cut: no selection")
            return
        end
        log.info("file_manager", "cut items", #items, "src", items[1].path, "name", items[1].name)
        file_manager_app.clipboard_set(items, "cut")
        log.info("file_manager", "cut", #items, "items")
        -- 剪切：选中项变灰标记
        for _, item in ipairs(items) do
            selected_paths[item.path] = "cut"  -- mark as cut
        end
        if view.render_directory then view.render_directory() end
    end)

    mk_btn(action_bar, margin + (btn_w + btn_gap) * 2, row2_y, "粘贴", btn_style_active, function()
        local clip_items, clip_mode = file_manager_app.clipboard_get()
        if not clip_items or #clip_items == 0 then
            log.info("file_manager", "paste clipboard empty")
            return
        end
        -- 若选中了文件夹且与当前浏览目录不同，则粘贴到选中目录内
        local dst_dir = get_full_path(current_sub_path)
        if selected_is_dir and selected_path and selected_path ~= dst_dir then
            dst_dir = selected_path
        end
        log.info("file_manager", "paste dst_dir", dst_dir, "current_sub_path", current_sub_path or "(nil)", "selected_is_dir", selected_is_dir, "selected_path", selected_path or "(nil)")
        for _, item in ipairs(clip_items) do
            local dst_path = dst_dir .. "/" .. item.name
            log.info("file_manager", "paste src", item.path, "dst", dst_path, "is_dir", item.is_dir)
            if dst_path == item.path then
                log.warn("file_manager", "paste skip, same path", dst_path)
                goto paste_continue
            end
            log.info("file_manager", "paste copy begin", item.path, "->", dst_path)
            file_manager_app.copy_path(item.path, dst_path, item.is_dir)
            if clip_mode == "cut" then
                log.info("file_manager", "paste delete src (cut)", item.path)
                file_manager_app.delete_path(item.path, item.is_dir)
            end
            ::paste_continue::
        end
        file_manager_app.clipboard_clear()
        deselect_all()
        refresh_directory()
    end)

    -- 可滚动内容区（依赖 action_bar_h）
    if directory_content then directory_content:destroy() end
    directory_content = airui.container({
        parent = directory_container,
        x = margin, y = titlebar_h + action_bar_h + math.floor(4 * density),
        w = card_w, h = screen_h - titlebar_h - action_bar_h - math.floor(8 * density),
        color = COLOR_BG, scrollable = true,
    })

    if view.render_directory then view.render_directory() end
end

-- ==================== 设备列表视图 ====================

local function clear_device_list()
    for _, item in ipairs(device_items) do
        if item.ref then item.ref:destroy() end
    end
    device_items = {}
end

view.build_device_list = function()
    clear_device_list()
    if directory_container then
        directory_container:destroy()
        directory_container = nil
    end

    update_screen_size()

    -- 主容器（复用或创建）
    if not main_container then
        main_container = airui.container({
            parent = airui.screen,
            x = 0, y = 0, w = screen_w, h = screen_h,
            color = COLOR_BG,
        })
    end

    if device_list_container then
        device_list_container:destroy()
    end

    device_list_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    local density = _G.density_scale or 1.0
    local tb = airui.container({
        parent = device_list_container,
        x = 0, y = 0, w = screen_w, h = titlebar_h,
        color = COLOR_PRIMARY,
    })
    local back_btn = airui.container({
        parent = tb,
        x = math.floor(10 * density), y = math.floor(10 * density),
        w = math.floor(50 * density), h = math.floor(40 * density),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(window_id) end,
    })
    airui.label({
        parent = back_btn,
        x = 0, y = math.floor(5 * density),
        w = math.floor(50 * density), h = math.floor(30 * density),
        text = "<", font_size = math.floor(28 * density),
        color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = tb,
        x = math.floor(60 * density), y = math.floor(10 * density),
        w = screen_w - math.floor(120 * density), h = math.floor(40 * density),
        text = "文件管理", font_size = math.floor(32 * density),
        color = COLOR_WHITE, align = airui.TEXT_ALIGN_LEFT,
    })

    local scroll_area = airui.container({
        parent = device_list_container,
        x = 0, y = titlebar_h, w = screen_w, h = screen_h - titlebar_h,
        color = COLOR_BG, scrollable = true,
    })

    local mount_points = file_manager_app.get_mount_points()

    if #mount_points == 0 then
        airui.label({
            parent = scroll_area,
            x = margin, y = margin + math.floor(20 * density),
            w = card_w, h = math.floor(30 * density),
            text = "没有可用的存储设备", font_size = math.floor(18 * density),
            color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    local y = margin
    for _, dev in ipairs(mount_points) do
        local card = airui.container({
            parent = scroll_area,
            x = margin, y = y,
            w = card_w, h = card_h,
            color = COLOR_CARD, radius = 8,
            on_click = function()
                current_view = "directory"
                current_mount_point = dev.mount_point
                current_sub_path = ""
                selected_path = nil
                selected_name = nil
                selected_is_dir = false
                dir_item_rows = {}
                tree_nodes = {}
                if device_list_container then device_list_container:destroy() end
                device_list_container = nil
                if view.build_directory_view then view.build_directory_view() end
            end,
        })
        local label_h = math.floor(30 * density)
        local label_y = math.floor((card_h - label_h) / 2)
        airui.label({
            parent = card,
            x = math.floor(20 * density), y = label_y,
            w = card_w - math.floor(80 * density), h = label_h,
            text = dev.label, font_size = math.floor(22 * density),
            color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = card,
            x = card_w - math.floor(50 * density), y = label_y,
            w = math.floor(30 * density), h = label_h,
            text = ">", font_size = math.floor(22 * density),
            color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER,
        })

        table.insert(device_items, { ref = card, label = dev.label, mount_point = dev.mount_point })
        y = y + card_h + card_spacing
    end
end

-- ==================== 输入对话框 ====================

local function hide_input_dialog()
    if input_keyboard then
        input_keyboard:hide()
        input_keyboard:destroy()
        input_keyboard = nil
    end
    if dialog_overlay then
        dialog_overlay:destroy()
        dialog_overlay = nil
    end
    input_dialog = nil
    input_callback = nil
    input_textarea = nil
end

view.show_input_dialog = function(title, callback)
    hide_input_dialog()
    input_callback = callback
    input_title = title
    update_screen_size()

    local density = _G.density_scale or 1.0
    local btn_w = math.floor(90 * density)
    local btn_h = math.floor(40 * density)

    -- 输入框居中，稍靠上以免键盘遮挡
    local dialog_w = math.floor(screen_w * 0.85)
    local dialog_h = math.floor(140 * density)
    local dialog_x = math.floor((screen_w - dialog_w) / 2)
    local dialog_y = math.floor(screen_h * 0.2)

    -- 先创建键盘实例
    input_keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(screen_h * 0.35),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    dialog_overlay = airui.container({
        parent = main_container,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 40,
        on_click = function() hide_input_dialog() end,
    })

    input_dialog = airui.container({
        parent = dialog_overlay,
        x = dialog_x, y = dialog_y,
        w = dialog_w, h = dialog_h,
        color = COLOR_CARD, radius = 12,
    })

    -- 标题
    airui.label({
        parent = input_dialog,
        x = math.floor(16 * density), y = math.floor(10 * density),
        w = dialog_w - math.floor(32 * density), h = math.floor(24 * density),
        text = title, font_size = math.floor(18 * density),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 输入框
    local input_w = dialog_w - math.floor(32 * density)
    local input_h = math.floor(40 * density)
    input_textarea = airui.textarea({
        parent = input_dialog,
        x = math.floor(16 * density), y = math.floor(42 * density),
        w = input_w, h = input_h,
        placeholder = "请输入名称，勿用 / \\ : * ? \" < > |",
        font_size = math.floor(16 * density),
        color = COLOR_TEXT,
        keyboard = input_keyboard,
    })

    -- 确认/取消按钮居中在对话框底部
    local btn_y = dialog_h - btn_h - math.floor(8 * density)
    local btn_gap_h = math.floor(16 * density)
    local two_btn_w = btn_w * 2 + btn_gap_h
    local btn_start_x = math.floor((dialog_w - two_btn_w) / 2)

    airui.button({
        parent = input_dialog,
        x = btn_start_x, y = btn_y, w = btn_w, h = btn_h,
        text = "取消", font_size = math.floor(16 * density),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_TEXT, radius = 8, border_width = 0 },
        on_click = function() hide_input_dialog() end,
    })

    airui.button({
        parent = input_dialog,
        x = btn_start_x + btn_w + btn_gap_h,
        y = btn_y, w = btn_w, h = btn_h,
        text = "确认", font_size = math.floor(16 * density),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = 0x0056B3, text_color = COLOR_WHITE, radius = 8, border_width = 0 },
        on_click = function()
            if input_textarea and input_callback then
                local text = input_textarea:get_text()
                -- 去除首尾空白
                if text then text = text:match("^%s*(.-)%s*$") end
                if text and #text > 0 then
                    local cb = input_callback
                    hide_input_dialog()
                    cb(text)
                end
            end
        end,
    })

end

-- ==================== 确认对话框 ====================

-- ==================== 新建选择对话框 ====================

local function hide_create_dialog()
    if dialog_overlay then
        dialog_overlay:destroy()
        dialog_overlay = nil
    end
    create_dialog = nil
end

-- 命名合法性校验：非空、不含非法字符（/ \ : * ? " < > |）
local function validate_name(name)
    if not name or #name == 0 then
        return false, "名称不能为空"
    end
    local illegal = { ["/"]=true, ["\\"]=true, [":"]=true, ["*"]=true, ["?"]=true, ['"']=true, ["<"]=true, [">"]=true, ["|"]=true }
    for ch in name:gmatch(".") do
        if illegal[ch] then
            return false, "名称包含非法字符: " .. ch
        end
    end
    return true, nil
end

view.show_create_dialog = function()
    hide_create_dialog()
    update_screen_size()

    local density = _G.density_scale or 1.0
    local dialog_w = math.floor(screen_w * 0.75)
    local dialog_h = math.floor(160 * density)
    local dialog_x = math.floor((screen_w - dialog_w) / 2)
    local dialog_y = math.floor((screen_h - dialog_h) / 2)

    dialog_overlay = airui.container({
        parent = main_container,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 40,
        on_click = function() hide_create_dialog() end,
    })

    create_dialog = airui.container({
        parent = dialog_overlay,
        x = dialog_x, y = dialog_y,
        w = dialog_w, h = dialog_h,
        color = COLOR_CARD, radius = 12,
    })

    -- 标题
    airui.label({
        parent = create_dialog,
        x = math.floor(16 * density), y = math.floor(16 * density),
        w = dialog_w - math.floor(32 * density), h = math.floor(26 * density),
        text = "新建", font_size = math.floor(20 * density),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER,
    })

    -- 提示文字
    airui.label({
        parent = create_dialog,
        x = math.floor(16 * density), y = math.floor(52 * density),
        w = dialog_w - math.floor(32 * density), h = math.floor(24 * density),
        text = "请选择新建类型：", font_size = math.floor(16 * density),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER,
    })

    -- 两个大按钮：文件夹（黄色）| 文件（黄色）
    local btn_w = math.floor((dialog_w - math.floor(48 * density)) / 2)
    local btn_h = math.floor(46 * density)
    local btn_y = math.floor(88 * density)
    local btn_x_folder = math.floor(16 * density)
    local btn_x_file   = btn_x_folder + btn_w + math.floor(16 * density)

    -- 文件夹按钮（黄色）
    local local_folder_cb = function()
        local cb = function(name)
            local ok, err = validate_name(name)
            if not ok then
                log.warn("file_manager", "invalid folder name", err)
                return
            end
            -- 若选中了文件夹且与当前浏览目录不同，则在选中目录内创建
            local parent_path = get_full_path(current_sub_path)
            if selected_is_dir and selected_path and selected_path ~= parent_path then
                parent_path = selected_path
            end
            local path = parent_path .. "/" .. name
            file_manager_app.create_directory(path)
            refresh_directory()
        end
        hide_create_dialog()
        if view.show_input_dialog then
            view.show_input_dialog("新建文件夹", cb)
        end
    end
    view.pending_folder_callback = local_folder_cb

    airui.button({
        parent = create_dialog,
        x = btn_x_folder, y = btn_y,
        w = btn_w, h = btn_h,
        text = "文件夹", font_size = math.floor(18 * density),
        style = { bg_color = COLOR_WARNING, pressed_bg_color = 0xD4891A, text_color = COLOR_WHITE, radius = 8, border_width = 0 },
        on_click = local_folder_cb,
    })

    -- 文件按钮（黄色）
    local local_file_cb = function()
        local cb = function(name)
            local ok, err = validate_name(name)
            if not ok then
                log.warn("file_manager", "invalid file name", err)
                return
            end
            -- 若选中了文件夹则在选中目录内创建，否则在当前浏览目录下创建
            local parent_path = get_full_path(current_sub_path)
            if selected_is_dir and selected_path and tree_nodes[selected_path] then
                parent_path = selected_path
            end
            local path = parent_path .. "/" .. name
            file_manager_app.create_file(path)
            refresh_directory()
        end
        hide_create_dialog()
        if view.show_input_dialog then
            view.show_input_dialog("新建文件", cb)
        end
    end
    view.pending_file_callback = local_file_cb

    airui.button({
        parent = create_dialog,
        x = btn_x_file, y = btn_y,
        w = btn_w, h = btn_h,
        text = "文件", font_size = math.floor(18 * density),
        style = { bg_color = COLOR_WARNING, pressed_bg_color = 0xD4891A, text_color = COLOR_WHITE, radius = 8, border_width = 0 },
        on_click = local_file_cb,
    })
end

local function hide_confirm_dialog()
    if dialog_overlay then
        dialog_overlay:destroy()
        dialog_overlay = nil
    end
    confirm_dialog = nil
    confirm_callback = nil
    view.pending_confirm_callback = nil
end

view.show_confirm_dialog = function(title, message, callback)
    hide_confirm_dialog()
    -- 同时存 view 表和局部：view 表生命周期不受 hide_confirm_dialog 影响
    view.pending_confirm_callback = callback
    confirm_callback = callback

    local density = _G.density_scale or 1.0
    local dialog_w = math.floor(screen_w * 0.8)
    local dialog_h = math.floor(160 * density)
    local dialog_x = math.floor((screen_w - dialog_w) / 2)
    local dialog_y = math.floor((screen_h - dialog_h) / 2)

    dialog_overlay = airui.container({
        parent = main_container,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 40,
        on_click = function() hide_confirm_dialog() end,
    })

    confirm_dialog = airui.container({
        parent = dialog_overlay,
        x = dialog_x, y = dialog_y,
        w = dialog_w, h = dialog_h,
        color = COLOR_CARD, radius = 12,
    })

    airui.label({
        parent = confirm_dialog,
        x = math.floor(16 * density), y = math.floor(14 * density),
        w = dialog_w - math.floor(32 * density), h = math.floor(26 * density),
        text = title, font_size = math.floor(20 * density),
        color = COLOR_DANGER, align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = confirm_dialog,
        x = math.floor(16 * density), y = math.floor(48 * density),
        w = dialog_w - math.floor(32 * density), h = math.floor(32 * density),
        text = message, font_size = math.floor(16 * density),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER,
    })

    local btn_w = math.floor(80 * density)
    local btn_h = math.floor(36 * density)
    local btn_y = math.floor(105 * density)

    airui.button({
        parent = confirm_dialog,
        x = math.floor((dialog_w / 2) - btn_w - math.floor(10 * density)), y = btn_y,
        w = btn_w, h = btn_h,
        text = "取消", font_size = math.floor(16 * density),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_TEXT, radius = 8, border_width = 0 },
        on_click = function() hide_confirm_dialog() end,
    })

    airui.button({
        parent = confirm_dialog,
        x = math.floor((dialog_w / 2) + math.floor(10 * density)), y = btn_y,
        w = btn_w, h = btn_h,
        text = "确认", font_size = math.floor(16 * density),
        style = { bg_color = COLOR_DANGER, pressed_bg_color = 0xB71C1C, text_color = COLOR_WHITE, radius = 8, border_width = 0 },
        on_click = function()
            local cb = view.pending_confirm_callback
            hide_confirm_dialog()
            if cb then cb() end
        end,
    })
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    update_screen_size()

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    current_view = "device_list"
    if view.build_device_list then view.build_device_list() end
end

local function on_destroy()
    clear_device_list()
    clear_directory_content()
    hide_input_dialog()
    hide_confirm_dialog()
    hide_create_dialog()

    if directory_container then
        directory_container:destroy()
        directory_container = nil
    end
    if device_list_container then
        device_list_container:destroy()
        device_list_container = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    window_id = nil
    current_view = nil
    current_mount_point = nil
    current_sub_path = nil
    tree_nodes = {}
    selected_path = nil
    selected_name = nil
    selected_is_dir = false
    dir_item_rows = {}
    device_items = {}
    dir_titlebar_label = nil
    dir_titlebar_bg = nil
    delete_button = nil
    directory_content = nil
    action_bar = nil
    create_dialog = nil
    input_keyboard = nil
end

local function on_get_focus() end
local function on_lose_focus() end

-- ==================== 事件注册 ====================

local function open_handler()
    window_id = exwin.open({
        on_create    = on_create,
        on_destroy   = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_FILE_MANAGER_WIN", open_handler)
