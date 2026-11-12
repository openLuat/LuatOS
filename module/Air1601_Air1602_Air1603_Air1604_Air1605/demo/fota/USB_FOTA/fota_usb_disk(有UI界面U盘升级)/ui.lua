--[[
@module  ui
@summary U盘FOTA升级(有UI界面版) 三个页面：待机页 / 升级包选择页 / 升级进度页 + 结果弹窗
@version 1.0
@date    2026.11.11
@author  谌程
@usage
-- 页面结构（1024x600）：
--   待机页  : 顶栏标题+当前版本, 中央"请插入升级U盘"卡片, 底部提示
--   选择页  : 树形文件浏览器(仿电脑资源管理器) -- 根节点=升级U盘, 点文件夹展开/收起,
--             子项缩进, 文件夹/文件用容器画的图标, 内容超出可滚动, 仅*.bin可选为升级包
--   进度页  : 文件名 + 阶段文字 + 进度条 + 百分比 + 字节数 + 警告提示
--   结果弹窗: airui.msgbox（成功/失败/二次确认; 必须显式传w/h, 否则文本区太窄一字一行竖排）
--
-- 事件约定（与 fota_usb_disk_ui.lua 对接）：
--   订阅 UDISK_LIST(dir,items)  -- 挂载成功/进入文件夹/返回, 重建浏览器并弹出选择页
--   订阅 UDISK_REMOVED          -- U盘拔出, 回待机页
--   订阅 FOTA_PROGRESS(done,total,text) -- 升级进度
--   订阅 FOTA_RESULT(ok,msg)    -- 升级结果, 失败回选择页
--   发布 UDISK_LIST_REQ(dir)    -- 展开文件夹时请求核心列目录(懒加载, 只列用到的层)
--   发布 UDISK_RESCAN           -- 用户点"刷新": 回到根目录重新扫描
--   发布 UDISK_CLOSE            -- 用户点右上角✕, 核心unmount并回待机页
--   发布 FOTA_UPGRADE_START(path) -- 用户二次确认后, 通知业务核心开始升级
--
-- 列表行的做法参考 module/Air8607/demo/play_hzv_sd/file_list.lua：
--   一行一个 airui.button, 所有行共用一个点击回调, 按按钮文字反查序号；
--   选中态用每行右侧隐藏的"已选"角标(set_hidden切换), 不依赖运行时改样式
]]

local conf = require "conf"
local C = conf.ui

local W, H = conf.screen.w, conf.screen.h

local M = {}

-- 控件引用
local R = {}
-- U盘文件树（仿电脑资源管理器, 树形展开收起; UDISK_LIST 逐层填充）
-- 节点结构: {name, path, is_dir, size, expanded, loaded, children}
local root_node = nil     -- 根节点 = 升级U盘
local view_root = nil     -- 当前浏览的目录节点(点文件夹行进入后变化, 点"返回上一级"回退)
local sel_item = nil      -- 当前选中的升级包节点(必须是*.bin文件), nil=未选
local pending_path = nil  -- 正在列目录的节点路径(展开中提示)

-- ==================== 小工具 ====================

-- 把动作挪出事件回调上下文执行；定时器创建失败时直接执行，避免"点了没反应"
-- （写法与 module/Air8607/demo/servo_drv/code/ui.lua 一致）
local function defer(fn)
    local ok, id = pcall(sys.timerStart, function()
        local ok2, err = pcall(fn)
        if not ok2 then log.error("ui", "defer error", tostring(err)) end
    end, 10)
    if not ok or not id or id == 0 then
        local ok3, err3 = pcall(fn)
        if not ok3 then log.error("ui", "defer inline error", tostring(err3)) end
    end
end

-- 字节数格式化
local function fmt_size(n)
    n = n or 0
    if n >= 1024 * 1024 then
        return string.format("%.2f MB", n / 1024 / 1024)
    elseif n >= 1024 then
        return string.format("%.1f KB", n / 1024)
    else
        return tostring(n) .. " B"
    end
end

-- 便捷构造函数
local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or 20,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function button(parent, x, y, w, h, text, size, bg, fg, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = bg or C.panel2,
            pressed_bg_color = bg or C.panel2,   -- 按下不变色, 避免按下瞬间闪白
            text_color = fg or C.ink,
            radius = 8, border_width = 0,
        },
        on_click = on_click,
    })
end

local function card(parent, x, y, w, h, color)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel, radius = 12, border_width = 0,
    })
end

-- 页面切换（三个全屏容器互相 set_hidden）
local function show_page(name)
    if R.idle     then R.idle:set_hidden(name ~= "idle")     end
    if R.select   then R.select:set_hidden(name ~= "select") end
    if R.progress then R.progress:set_hidden(name ~= "progress") end
    log.info("ui", "切换页面", name)
end

-- ==================== 待机页 ====================
local function build_idle()
    R.idle = airui.container({ x = 0, y = 0, w = W, h = H, color = C.bg })

    -- 顶栏
    card(R.idle, 0, 0, W, 72, C.panel)
    label(R.idle, 24, 18, 400, 40, "U盘固件升级", 26)
    label(R.idle, W - 400, 24, 376, 30,
        "当前版本: " .. tostring(_G.PROJECT or "?") .. " " .. tostring(_G.VERSION or "?"),
        16, C.ink2, airui.TEXT_ALIGN_RIGHT)

    -- 中央卡片
    local cw, ch = 700, 220
    local cx, cy = (W - cw) / 2, 170
    card(R.idle, cx, cy, cw, ch)
    label(R.idle, cx, cy + 55, cw, 40, "请插入升级 U 盘", 26, C.ink, airui.TEXT_ALIGN_CENTER)
    label(R.idle, cx, cy + 120, cw, 30,
        "插入后自动扫描U盘根目录的固件包 ( *" .. conf.usb.suffix .. ", FAT32 )",
        16, C.ink2, airui.TEXT_ALIGN_CENTER)

    -- 底部提示
    label(R.idle, 24, H - 50, W - 48, 26,
        "提示: USB已切换为主机模式, 日志请接UART串口查看; 升级过程中请勿断电",
        16, C.ink3)
end

-- ==================== 选择页 ====================

-- 是否可选为升级包（conf.usb.suffix 规则, 大小写不敏感）
local function is_bin(name)
    local s = conf.usb.suffix
    return #name > #s and name:lower():sub(-#s) == s
end

-- Windows 垃圾临时文件(浏览器里不显示): Office打开文档生成的 ~$xx.docx 等桶文件
local function is_junk(name)
    if name:sub(1, 2) == "~$" then return true end
    local lower = name:lower()
    if lower == "thumbs.db" or lower == "desktop.ini" or lower == ".ds_store" then return true end
    return false
end

-- ==================== 树形文件浏览器（仿电脑资源管理器）====================
-- 做法参考 module/Air8603/factory/ui/file_manager_win.lua:
--   纯 AirUI 容器画图标(无图片资源), 行=container(on_click), scrollable=true 自带滚动条

-- 建一个空根节点(未加载)
local function new_root()
    return {
        name = "升级U盘", path = conf.usb.mount,
        is_dir = true, size = 0,
        expanded = false, loaded = false, children = nil,
    }
end

-- 按路径在树里找节点(DFS)
local function find_node(node, path)
    if not node then return nil end
    if node.path == path then return node end
    if node.children then
        for i = 1, #node.children do
            local hit = find_node(node.children[i], path)
            if hit then return hit end
        end
    end
    return nil
end

-- 把已展开的节点摊平成渲染行(最多max行, 防超深/超多占内存)
local function flatten(node, depth, out, max)
    if #out >= max then return end
    out[#out + 1] = { node = node, depth = depth }
    if node.is_dir and node.expanded and node.children then
        for i = 1, #node.children do
            flatten(node.children[i], depth + 1, out, max)
            if #out >= max then return end
        end
    end
end

-- 前向声明: render_tree 的行闭包里要调点击函数, 点击函数里又要调 render_tree
local render_tree
local on_node_click   -- 点*.bin行: 选中升级包
local on_node_toggle  -- 点箭头: 原地展开/收起(树形)
local on_node_enter   -- 点文件夹行: 进入该目录(列表切到该层)

-- 清掉旧列表（destroy 会连带子控件）
local function clear_list()
    if R.list_box then
        R.list_box:destroy()
        R.list_box = nil
    end
end

-- 文件夹图标: 黄色标签页+主体(纯容器拼; hzfont没有emoji字形, 不能用unicode图标)
local function draw_folder_icon(parent, x, y)
    airui.container({ parent = parent, x = x, y = y + 2, w = 14, h = 6, color = 0xC8922A, radius = 1, border_width = 0 })
    airui.container({ parent = parent, x = x, y = y + 7, w = 28, h = 15, color = 0xE8B339, radius = 3, border_width = 0 })
end

-- 文件图标: 单个纸张容器(可选的*.bin用绿色, 其他文件用灰色)
-- 不再画三行"文字"线: 每行省3个控件, 滚动时每帧绘制量更小更顺滑
local function draw_file_icon(parent, x, y, selectable)
    local c = selectable and 0x4CAF50 or 0x8A94A6
    airui.container({ parent = parent, x = x + 4, y = y + 1, w = 20, h = 22, color = c, radius = 2, border_width = 0 })
end

render_tree = function()
    clear_list()
    if not R.select then return end

    local area_y = 88
    local area_h = H - area_y - 84
    local lw = W - 48

    -- scrollable=true: 行数超出高度时容器自带滚动条, 同电脑下拉效果
    R.list_box = airui.container({
        parent = R.select, x = 24, y = area_y, w = lw, h = area_h,
        color = C.panel, scrollable = true,
    })

    local ROW_H = 52

    -- 进入过子目录时, 顶部给一行"返回上一级"(factory文件管理器的".."行同款交互)
    local y0 = 0
    if view_root and view_root ~= root_node then
        button(R.list_box, 0, 0, lw, ROW_H, "返回上一级", 18, C.panel2, C.ink, function()
            if view_root and view_root.parent then
                view_root = view_root.parent
                render_tree()
            end
        end)
        y0 = ROW_H + 4
    end

    local rows = {}
    local top = view_root or root_node
    if top then flatten(top, 0, rows, 200) end

    for i = 1, #rows do
        local node, depth = rows[i].node, rows[i].depth
        local y = y0 + (i - 1) * ROW_H
        local is_on = (sel_item ~= nil) and (node.path == sel_item.path) and not node.is_dir
        local row_bg = is_on and C.accent or C.row

        -- 行底座用 airui.button(不用 container.on_click): 本固件实测 container 的 on_click
        -- 在 scrollable 容器里触摸无响应, 而 button 行点击可靠(上一版逐层进入已验证)
        -- 每行独立闭包捕获node, 不用文字反查(重名也不怕)
        local base_cb = nil
        if node.is_dir then
            base_cb = function() on_node_enter(node) end        -- 点文件夹行 = 进入
        elseif is_bin(node.name) then
            base_cb = function() on_node_click(node) end        -- 点*.bin行 = 选中
        end
        -- 可点行(文件夹/*.bin)用button底座保证点击可靠; 不可点行用container底座
        -- (纯显示无点击判定, 减少滚动手势判定开销, 滑动更顺)
        local row
        if base_cb then
            row = button(R.list_box, 0, y, lw, ROW_H, " ", 16, row_bg, C.ink, base_cb)
        else
            row = airui.container({
                parent = R.list_box, x = 0, y = y, w = lw, h = ROW_H,
                color = row_bg, radius = 8, border_width = 0,
            })
        end

        local indent = 10 + depth * 36
        local iy = math.floor((ROW_H - 26) / 2)

        if node.is_dir then
            -- 箭头是独立小按钮叠在行上: 点箭头=原地展开/收起(树形下标), 点行其余区域=进入
            -- (两种操作并存; 箭头用ASCII, 实测hzfont没有▶▼字形, 会显示成方框)
            button(row, indent, 0, 48, ROW_H, node.expanded and "v" or ">", 20,
                row_bg, C.ink2, function() on_node_toggle(node) end)
            draw_folder_icon(row, indent + 56, iy)
            label(row, indent + 96, math.floor((ROW_H - 23) / 2), lw - indent - 220, 23,
                node.name, 20, C.ink)
            if node.expanded and not node.loaded then
                label(row, lw - 140, math.floor((ROW_H - 20) / 2), 120, 20,
                    (node.path == pending_path) and "打开中..." or "(空目录)", 16, C.ink3,
                    airui.TEXT_ALIGN_RIGHT)
            end
        else
            local selectable = is_bin(node.name)
            draw_file_icon(row, indent, iy, selectable)
            label(row, indent + 40, math.floor((ROW_H - 23) / 2), lw - indent - 200, 23,
                node.name .. "  (" .. fmt_size(node.size) .. ")", 20,
                selectable and C.ink or C.ink2)
            if is_on then
                label(row, lw - 110, math.floor((ROW_H - 24) / 2), 90, 24,
                    "已选", 20, 0xFFFFFF, airui.TEXT_ALIGN_RIGHT)
            end
        end
    end

    if R.count_label then
        R.count_label:set_text("点箭头展开/收起 | 点文件夹进入 | 点*" .. conf.usb.suffix .. "选中 | 内容多时可上下滑动")
    end
end

-- 点箭头: 原地展开/收起(树形浏览, 首次展开向核心要目录, 懒加载)
on_node_toggle = function(node)
    if node.expanded then
        node.expanded = false
        render_tree()
    else
        node.expanded = true
        if node.loaded then
            render_tree()
        else
            pending_path = node.path
            if R.count_label then R.count_label:set_text("正在打开 " .. node.name .. " ...") end
            sys.publish("UDISK_LIST_REQ", node.path)
        end
    end
end

-- 点文件夹行: 进入该目录 -- 列表切到该层(顶部出现"返回上一级"), 同时树上也展开
on_node_enter = function(node)
    log.info("ui", "进入文件夹", node.path)
    view_root = node
    node.expanded = true
    if node.loaded then
        render_tree()
    else
        pending_path = node.path
        render_tree()  -- 先画出该层骨架(打开中...), 目录到了再填内容
        if R.count_label then R.count_label:set_text("正在打开 " .. node.name .. " ...") end
        sys.publish("UDISK_LIST_REQ", node.path)
    end
end

-- 点*.bin行: 选中升级包; 其他文件不可选仅日志
on_node_click = function(node)
    sel_item = node
    log.info("ui", "选中升级包", node.name)
    render_tree()
end

-- 收到 UDISK_LIST: 挂到树的对应节点下并重画(挂载成功/展开文件夹/手动刷新 共用)
sys.subscribe("UDISK_LIST", function(dir, list)
    defer(function()
        list = list or {}
        local node = root_node and find_node(root_node, dir) or nil
        if node then
            node.loaded = true
            node.expanded = true
            node.children = {}
            local n = 0
            for i = 1, #list do
                if not is_junk(list[i].name) then  -- 滤掉 ~$xxx / Thumbs.db 等垃圾文件
                    n = n + 1
                    node.children[n] = {
                        name = list[i].name, path = list[i].path,
                        is_dir = list[i].is_dir, size = list[i].size or 0,
                        expanded = false, loaded = false, children = nil,
                        parent = node,   -- "返回上一级"靠它回溯
                    }
                end
            end
        end
        pending_path = nil
        render_tree()
        show_page("select")
    end)
end)

-- 长文件名截尾显示(弹窗一行放不下)
local function short_name(n)
    if #n <= 40 then return n end
    return "..." .. n:sub(-40)
end

-- 长文本中间截断: 保头保尾(进度页文件名用, 两端都可见)
local function mid_trunc(s, max)
    if #s <= max then return s end
    local keep = max - 3
    local head = math.floor(keep * 0.45)
    local tail = keep - head
    return s:sub(1, head) .. "..." .. s:sub(-tail)
end

-- "确认升级"点击: 未选提示 / 二次确认弹窗
-- 注意: airui.msgbox 必须显式传 w/h, 否则默认文本区太窄, 中文一字一行竖排
local function on_confirm_click()
    defer(function()
        if not sel_item then
            local m = airui.msgbox({
                w = 520, h = 200, style = { text_font_size = 20 },
                title = "提示",
                text = "请先在列表中点选一个 *" .. conf.usb.suffix .. " 升级包",
                buttons = { "确定" },
                on_action = function(s, l) s:hide() end,
            })
            m:show()
            return
        end
        local item = sel_item
        local m = airui.msgbox({
            w = 640, h = 260, style = { text_font_size = 20 },
            title = "确认升级",
            text = "确定使用以下升级包吗?\n" .. short_name(item.name) .. " (" .. fmt_size(item.size) .. ")\n升级过程中请勿断电",
            buttons = { "取消", "确定" },
            on_action = function(s, l)
                if l == "确定" then
                    log.info("ui", "确认升级", item.path)
                    sys.publish("FOTA_UPGRADE_START", item.path)
                    M.show_progress_page(item)
                end
                s:hide()
            end,
        })
        m:show()
    end)
end

local function build_select()
    R.select = airui.container({ x = 0, y = 0, w = W, h = H, color = C.bg })
    R.select:set_hidden(true)

    -- 顶栏: 标题 + [刷新] + ✕(最右); 树形目录自带层级, 不需要返回键和路径条
    card(R.select, 0, 0, W, 72, C.panel)
    label(R.select, 24, 18, 400, 40, "选择升级包", 26)
    -- 右上角: [刷新](收起全部并重新扫描根目录) + ✕(最右, 点✕回待机页, 核心unmount)
    button(R.select, W - 24 - 96 - 64, 18, 96, 36, "刷新", 16, C.panel2, C.ink, function()
        log.info("ui", "手动刷新: 重建文件树并重新扫描U盘根目录")
        root_node = new_root()
        view_root = nil
        sel_item = nil
        sys.publish("UDISK_RESCAN")
    end)
    -- 关闭按钮: 用字母X(hzfont没有✕ U+2715字形, 会画成空方框)
    button(R.select, W - 24 - 56, 14, 56, 44, "X", 22, C.danger, 0xFFFFFF, function()
        log.info("ui", "关闭选择页: unmount并回待机页, 重新插拔U盘可再次进入")
        sys.publish("UDISK_CLOSE")
        show_page("idle")
    end)

    -- 树形文件列表区(容器由 render_tree 动态创建, scrollable自带滚动)
    R.list_box = nil
    root_node = new_root()
    view_root = nil

    -- 底部操作条(无取消按钮, 关闭选择页走右上角✕)
    R.count_label = label(R.select, 24, H - 60, W - 280, 40, "等待U盘...", 16, C.ink2)
    button(R.select, W - 24 - 200, H - 72, 200, 48, "确认升级", 20, C.accent, 0xFFFFFF, on_confirm_click)
end

-- ==================== 进度页 ====================
local function build_progress()
    R.progress = airui.container({ x = 0, y = 0, w = W, h = H, color = C.bg })
    R.progress:set_hidden(true)

    card(R.progress, 0, 0, W, 72, C.panel)
    label(R.progress, 24, 18, 400, 40, "正在升级", 26)

    local cw, ch = 800, 380
    local cx, cy = (W - cw) / 2, 110
    local card_p = card(R.progress, cx, cy, cw, ch)

    R.prog_file  = label(card_p, 40, 30, cw - 80, 34, "-", 22)
    R.prog_stage = label(card_p, 40, 80, cw - 80, 28, "准备中...", 18, C.ink2)
    R.prog_bar   = airui.bar({
        parent = card_p, x = 40, y = 130, w = cw - 200, h = 28,
        value = 0, min = 0, max = 100, radius = 14, indicator_color = C.accent,
    })
    R.prog_pct   = label(card_p, cw - 150, 120, 110, 48, "0%", 40, C.ink, airui.TEXT_ALIGN_RIGHT)
    R.prog_bytes = label(card_p, 40, 180, cw - 80, 26, "0 B / 0 B", 16, C.ink2)
    label(card_p, 40, 240, cw - 80, 26, "升级过程中请勿断电、请勿拔出U盘", 16, C.warn)
    label(card_p, 40, 300, cw - 80, 26,
        "校验通过后设备将自动重启, 重启后自动应用升级, 结果以重启后日志中的版本号为准",
        16, C.ink3)
end

-- ==================== 对外接口 ====================

-- 建全部页面（lcd_tp.init 之后调用一次）
function M.build()
    build_idle()
    build_select()
    build_progress()
    show_page("idle")
end

-- 显示进度页并填入文件名
function M.show_progress_page(item)
    defer(function()
        if R.prog_file and item then
            -- 文件名中间截断(最多32字符), 保证"文件: xxx (3.52 MB)"一行放得下不折行
            R.prog_file:set_text("文件: " .. mid_trunc(item.name, 32) .. "  (" .. fmt_size(item.size) .. ")")
            R.prog_stage:set_text("准备中...")
            if R.prog_bar then R.prog_bar:set_value(0) end
            if R.prog_pct then R.prog_pct:set_text("0%") end
            if R.prog_bytes then R.prog_bytes:set_text("0 B / " .. fmt_size(item.size)) end
        end
        show_page("progress")
    end)
end

-- ==================== 事件订阅（业务核心 -> UI）====================
-- (UDISK_LIST 的订阅在树形浏览器一节, 这里不再重复订阅)

-- U盘拔出 -> 清空文件树回待机页
sys.subscribe("UDISK_REMOVED", function()
    defer(function()
        root_node = new_root()
        view_root = nil
        sel_item = nil
        pending_path = nil
        render_tree()
        show_page("idle")
    end)
end)

-- 升级进度
sys.subscribe("FOTA_PROGRESS", function(done, total, text)
    defer(function()
        if not R.prog_bar then return end
        local pct = (total and total > 0) and math.floor(done * 100 / total) or 0
        if pct > 100 then pct = 100 end
        R.prog_bar:set_value(pct)
        if R.prog_pct then R.prog_pct:set_text(pct .. "%") end
        if R.prog_bytes then
            R.prog_bytes:set_text(fmt_size(done) .. " / " .. fmt_size(total))
        end
        if R.prog_stage and text then R.prog_stage:set_text(text) end
    end)
end)

-- 升级结果: 成功提示后由业务核心重启; 失败回选择页可重试
sys.subscribe("FOTA_RESULT", function(ok, msg)
    defer(function()
        local m = airui.msgbox({
            w = 560, h = 220, style = { text_font_size = 20 },
            title = ok and "升级成功" or "升级失败",
            text = msg or (ok and "升级包校验通过, 即将重启" or "发生错误, 请查看UART日志"),
            buttons = { "确定" },
            on_action = function(s, l) s:hide() end,
        })
        m:show()
        if not ok then
            show_page("select")
        end
    end)
end)

return M
