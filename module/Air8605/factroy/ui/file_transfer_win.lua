--[[
@module  file_transfer_win
@summary 文件传输窗口（服务状态/共享清单/传输记录）
@version 1.3
@date    2026.09.22
@author  江访
@usage
本窗口为「文件传输」内置应用的展示层，单页三卡布局：
1、服务状态卡：hzadb 状态 / 鉴权状态（右侧[设置]开关鉴权+配token）/ 接收目录（右侧[设置]进入接收目录管理）；
2、共享清单卡（设备→PC）：目录/文件白名单，[添加]按钮进选择器，点行移除；
3、传输记录卡：实时随 FILE_TRANSFER_LOG 刷新，顶部进度行显示传输中状态。

目录选择器（共享添加 / 接收目录管理 共用，全按钮操作）：
[关闭] 右上退出 | [＋添加当前目录] 整行按钮 | [←返回上一级/存储列表] 整行按钮 |
条目行 = 左区点击进入目录 + 右侧[添加]按钮直接加入（多选无需逐层进出）|
存储列表含 / 、/sd 、/little_flash 、/ram 、/lua（io.dexist 过滤不存在的）

消息协议（订阅/发布）:
订阅: OPEN_FILE_TRANSFER_WIN                          → 打开本页
订阅: FILE_TRANSFER_STATUS(st)                        → 刷新状态卡
订阅: FILE_TRANSFER_LOG(entry)                        → 刷新传输记录卡
订阅: FILE_TRANSFER_PROGRESS({dir, path, bytes})      → 刷新进度行（300ms节流）
订阅: UI_THEME_CHANGED                                → 换肤重建
发布: 无（业务操作直接调用 file_transfer_app 接口）

布局约束：
1、所有单行文本按 theme.text_width 截断 + ASCII "..."（LVGL label 默认换行会双向撑破行盒）；
2、共享/记录/选择器列表行数按可用高度动态计算，任何子组件不超出父容器、不出滚动条；
3、全部右侧小按钮统一宽度 BTN_W、统一横坐标 BTN_X（右缘内收 2px）；
4、**子组件长宽按父容器倒角内缩**：圆角容器的内容一律落在 x/y=INSET、w=INNER_W 的
   内接矩形里（卡片显式传圆角 CARD_R，INSET=dp(CARD_R)），贴边会触发容器出滚动条。

设计原则与 file_manager_win 一致：
纯 AirUI 容器、每卡持有 card 引用原地重建、跨节函数引用经 view table 运行时解析。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"
local file_transfer_app = require "file_transfer_app"

local window_id = nil
local main_container = nil

-- 布局（update_screen_size 计算）
local sw, sh = 480, 800
local margin = 10
local card_w = 460
local row_h = 44
local header_h = 56
local CARD_R = 18      -- 卡片圆角逻辑值（与 theme.card 默认 R.lg 一致，显式传入保证内缩量对齐）
local inset = 18       -- 倒角内缩像素 = theme.dp(CARD_R)，子组件一律落在内接矩形里
local inner_w = 424    -- 卡片内容区宽 = card_w - 2 * inset
local btn_w = 110      -- 右侧小按钮统一宽度
local btn_x = 300      -- 右侧小按钮统一横坐标（相对行内容区，右缘内收 2px）

-- 主题令牌动态代理（换主题自动取新色值）
local CLR = theme.live()

-- 所有需要运行时绑定的函数存于此表（解决 LuatOS bytecode 前向引用问题）
local view = {}

-- 状态卡值标签（订阅消息到达时直接 set_text）
local status_labels = {}
-- 进度行标签（传输中显示，空闲显示提示）
local progress_label = nil
-- 进度刷新节流时间戳（mcu.ticks 毫秒）
local last_prog_update = 0

-- 卡片容器与堆叠位置（原地重建用）
local shared_card = nil
local shared_y = 0
local shared_rows_shown = 0   -- 共享行预算 0..3（0=仅卡头；on_create 按可用行数分配）
local record_card = nil
local records_y = 0
local record_rows_shown = 0   -- 记录行预算（render_shared 按实际剩余高度计算）
local page_bottom_y = 0       -- 页面内容底界（记录卡底缘不得越过）

-- 目录选择器状态
local picker_overlay = nil
local picker_container = nil
local picker_mode = nil       -- "shared"=共享添加 | "receive"=接收目录管理
local picker_mount = nil      -- nil=设备列表层，否则为当前挂载点（"/"、"/sd"等）
local picker_path = nil       -- 挂载点内子路径（""=挂载点根，如 "/photos"）
local picker_rows = {}

-- ==================== 工具函数 ====================

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = display.getSize()
    if rotation == 0 or rotation == 180 then
        sw, sh = phys_w, phys_h
    else
        sw, sh = phys_h, phys_w
    end
    sw, sh = theme.content_fit(sw, sh)
    margin = theme.page_margin()
    card_w = sw - 2 * margin
    header_h = theme.dp(56)
    row_h = math.max(36, math.floor(theme.fs("body") * 2.4))
    -- 倒角内缩：圆角 CARD_R(dp 后) 的容器，内容一律放在内接矩形里
    inset = theme.dp(CARD_R)

    --[[高密度/矮屏适配：固定 chrome（页眉+3卡倒角+卡间隙）吃掉高度后，
    先保证最小 8 行（状态3 + 共享2 + 记录3）能放下，行高不够就压缩行高
    （下限 = 正文行高 + 8，保证文字放得下），倒角随行高减半收。
    没有这一步时高密度屏连最小堆叠都会顶出页底出滑块（实测 1024x600 d1.5）。]]
    local target_rows = 8
    local min_row_h = theme.fs("body") + 8
    local chrome = header_h + 4 * margin + 6 * inset
    if sh - margin - chrome < target_rows * row_h then
        row_h = math.max(min_row_h, math.floor((sh - margin - chrome) / target_rows))
        inset = math.min(inset, math.floor(row_h / 2))
        -- 倒角收窄后 chrome 变小，再收敛一次行高即可（不必迭代到极致）
        chrome = header_h + 4 * margin + 6 * inset
        row_h = math.max(min_row_h, math.floor((sh - margin - chrome) / target_rows))
    end
    -- 极端密度兜底：连正文下限行高都放不下绝对最小 6 行（状态3+共享卡头+记录2）时，
    -- 放弃文字行高下限（文字局促可接受，页底出滑块不可接受）
    if sh - margin - chrome < 6 * row_h then
        row_h = math.max(24, math.floor((sh - margin - chrome) / 6))
        inset = math.min(inset, math.floor(row_h / 2))
    end

    inner_w = card_w - 2 * inset
    -- 右侧小按钮：统一宽度、统一横坐标，右缘距行内容区右缘内收 2px
    btn_w = math.floor(inner_w * 0.24)
    btn_x = inner_w - btn_w - theme.dp(12) - 2
end

-- 单行文本截断：超宽截到预算内并补 ASCII "..."
-- 不用省略号 U+2026：内置 hzfont 没有这个字形，会渲染成方框（同 settings_about_win 的教训）
local function fit_text(text, w, px, lines)
    text = tostring(text or "")
    if text == "" then return "--" end
    lines = lines or 1
    local budget = w * lines
    if theme.text_width(text, px) <= budget then return text end
    local keep = px * 3 + px
    local cut = #text
    while cut > 1 and theme.text_width(string.sub(text, 1, cut), px) > budget - keep do
        cut = cut - 1
    end
    -- 不切在多字节字符中间（UTF-8 续字节 0x80~0xBF）
    while cut > 1 do
        local b = string.byte(text, cut)
        if b and b >= 0x80 and b < 0xC0 then cut = cut - 1 else break end
    end
    return string.sub(text, 1, cut) .. "..."
end

-- 字节格式化：与 file_manager_win 同款（<0.1 KB / x.x KB / x.x MB）
local function fmt_size(bytes)
    local kb = (tonumber(bytes) or 0) / 1024
    if kb < 0.1 then
        return "<0.1 KB"
    elseif kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    end
    return string.format("%.1f KB", kb)
end

-- 记录条目单行文本：时间 方向 结果 大小 路径（拒绝时带原因、大小显示 --）
local function fmt_record(entry)
    local dir_text = (entry.dir == "D2P") and "设备→PC" or "PC→设备"
    local result_text = ({ ok = "成功", denied = "拒绝", io = "失败" })[entry.result] or tostring(entry.result)
    local time_text = os.date("%H:%M:%S", entry.time) or ""
    local size_text = (entry.result == "ok") and fmt_size(entry.size) or "--"
    local line = time_text .. " " .. dir_text .. " " .. result_text .. " " .. size_text
    if entry.result == "denied" and entry.reason then
        line = line .. " " .. entry.reason
    end
    return line .. "  " .. (entry.path or "")
end

-- ==================== 通用构件 ====================
-- 坐标约定：行/整行按钮一律 x=INSET、w=INNER_W（倒角内缩），y 由调用方从 INSET 起累计

-- 行容器 + 底部分隔线（与 file_manager_win 未选中行同款外观）
local function mk_row(parent, y, h, on_click)
    local r = theme.box(parent, {
        x = inset, y = y, w = inner_w, h = h,
        color = theme.C.black, opa = 0,
        on_click = on_click,
    })
    theme.divider(r, { x = theme.dp(12), y = h - 1, w = inner_w - theme.dp(24), h = 1 })
    return r
end

-- 行内单行文本（hzfont 行高 = 字号 + 3，垂直居中，超宽自动截断）
local function mk_row_text(row, text, px, color, x, w, align)
    local lh = px + 3
    local ly = math.max(0, math.floor((row_h - lh) / 2))
    return theme.label(row, {
        x = x, y = ly, w = w, h = lh,
        text = fit_text(text, w, px), px_size = px, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 右侧小按钮：统一宽度 BTN_W、统一横坐标 BTN_X（全局所有小按钮共用，含"添加/清空/关闭/设置/移除"）
local function mk_side_button(parent, text, on_click)
    local btn_h = math.floor(row_h * 0.7)
    local btn = theme.box(parent, {
        x = btn_x, y = math.floor((row_h - btn_h) / 2),
        w = btn_w, h = btn_h,
        color = CLR.primary, opa = theme.OPA.fill_hi, radius = theme.r("xs"),
        on_click = on_click,
    })
    local fs_px = theme.fs("label")
    theme.label(btn, {
        x = 0, y = math.floor((btn_h - (fs_px + 3)) / 2),
        w = btn_w, h = fs_px + 3,
        text = text, px_size = fs_px, color = CLR.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return btn
end

-- 整行按钮（选择器里的"添加当前目录/返回上一级"等动作），按钮样式，宽度=INNER_W
local function mk_full_button(parent, y, text, color, on_click)
    local pad = theme.dp(12)
    local btn = theme.box(parent, {
        x = inset, y = y, w = inner_w, h = row_h,
        color = color or CLR.primary, opa = theme.OPA.fill_hi, radius = theme.r("xs"),
        on_click = on_click,
    })
    local fs_px = theme.fs("body")
    theme.label(btn, {
        x = pad, y = math.floor((row_h - (fs_px + 3)) / 2),
        w = inner_w - pad * 2, h = fs_px + 3,
        text = fit_text(text, inner_w - pad * 2, fs_px),
        px_size = fs_px, color = CLR.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    return btn
end

-- ==================== 状态卡 ====================

-- 状态卡值区宽度（右侧留出[设置]按钮位）
local function status_value_w()
    return btn_x - math.floor(inner_w * 0.32) - theme.dp(4)
end

local function refresh_status_text()
    if not status_labels.hzadb then return end
    local st = file_transfer_app.get_status()
    status_labels.hzadb:set_text(st.hzadb_ok and "运行中" or "固件未启用")
    if not st.hzadb_ok then
        status_labels.auth:set_text("--")
    elseif st.auth_on then
        status_labels.auth:set_text("已开启")
    else
        status_labels.auth:set_text("关闭")
    end
    local dirs = st.receive_dirs or {}
    if #dirs == 0 then
        status_labels.receive:set_text("未设置(禁止PC写入)")
    else
        status_labels.receive:set_text(fit_text(table.concat(dirs, " or "), status_value_w(), theme.fs("body")))
    end
end

local function build_status_card(parent, y)
    local pad = theme.dp(12)
    local fs_key = theme.fs("micro")
    local fs_val = theme.fs("body")
    local rows = {
        { key = "传输服务", field = "hzadb", button = nil,    act = nil },
        { key = "鉴权",     field = "auth",  button = "设置", act = "auth" },
        { key = "接收目录", field = "receive", button = "设置", act = "receive" },
    }
    -- 卡片高度 = 2 倒角内缩 + 行数 x 行高；行从 INSET 起堆叠
    local total_h = 2 * inset + row_h * #rows
    local card = theme.card(parent, {
        x = margin, y = y, w = card_w, h = total_h, radius = CARD_R,
    })
    for i, it in ipairs(rows) do
        -- 可点行整行可点 + 右侧[设置]按钮，两个入口动作一致
        local on_click = nil
        if it.act == "auth" then
            on_click = function() view.show_auth_dialog() end
        elseif it.act == "receive" then
            on_click = function() view.show_picker("receive") end
        end
        local row = mk_row(card, inset + (i - 1) * row_h, row_h, on_click)
        mk_row_text(row, it.key, fs_key, CLR.t3, pad, math.floor(inner_w * 0.28))
        status_labels[it.field] = mk_row_text(row, "--", fs_val, CLR.t2,
            math.floor(inner_w * 0.32), status_value_w())
        if it.button then
            mk_side_button(row, it.button, on_click)
        end
    end
    refresh_status_text()
    return total_h
end

-- ==================== 目录选择器（共享添加 / 接收目录管理） ====================

local function hide_picker()
    if picker_overlay then
        picker_overlay:destroy()
        picker_overlay = nil
        picker_container = nil
        picker_rows = {}
        picker_mount = nil
        picker_path = nil
        picker_mode = nil
    end
end

-- 选择器当前目录全路径（设备列表层返回nil）
local function picker_full_path()
    if picker_mount == nil then return nil end
    if picker_path == nil or picker_path == "" then return picker_mount end
    -- 根挂载点"/"与子路径直接拼会拼出"//xxx"，VFS 归一化后每层都显示根条目（little_flash/ram等）
    if picker_mount == "/" then return picker_path end
    return picker_mount .. picker_path
end

-- 渲染选择器列表（全按钮操作；条目行 = 左区进入 + 右侧[添加]直接加入）
-- 布局预算：标题行 + 动作行 + 返回行 + [接收目录行] + 条目行，全部落在内接矩形内
local function picker_render()
    if not picker_container then return end
    for _, r in ipairs(picker_rows) do
        if r.ref then r.ref:destroy() end
    end
    picker_rows = {}
    local pad = theme.dp(12)
    local fs_px = theme.fs("body")
    local container_h = sh - 2 * margin
    local y = inset          -- 内容从倒角内缩起堆叠
    local gap = theme.dp(4)

    -- 标题行：模式标题 + 右侧[关闭]按钮（退出选择器）
    -- 固定行也入 picker_rows 销毁表：picker_render 会反复执行，漏销毁的固定行会叠出文字残影
    local title_row = mk_row(picker_container, y, row_h, nil)
    picker_rows[#picker_rows + 1] = { ref = title_row }
    local mode_title = (picker_mode == "receive") and "管理接收目录" or "添加共享目录"
    mk_row_text(title_row, mode_title, fs_px, CLR.t2, pad, btn_x - pad - gap)
    mk_side_button(title_row, "关闭", hide_picker)
    y = y + row_h + gap

    --[[接收模式：单一开关列表（候选 = 挂载点根 + 已添加的自定义目录），行尾按钮 [添加]/[移除] 互切。
    不做"已添加 + 浏览可选"混合视图——两套列表放一起分不清哪个是哪个，
    现在只有一张列表，按钮就是状态：点亮 [移除] 的是已添加，[添加] 的是可选。]]
    if picker_mode == "receive" then
        local receive_set = {}
        local candidates = {}
        local mounts = {
            { name = "/", label = "内置文件系统" },
            { name = "/sd", label = "外挂TF卡" },
            { name = "/little_flash", label = "外挂Flash" },
            { name = "/ram", label = "RAM盘" },
        }
        for _, m in ipairs(mounts) do
            -- VFS 挂载点存在性两种写法都试；/luadb 禁传不进候选
            if io.dexist(m.name) or io.dexist(m.name .. "/") then
                candidates[#candidates + 1] = { path = m.name, label = m.label }
            end
        end
        for _, p in ipairs(file_transfer_app.get_cfg().receive_dirs or {}) do
            receive_set[p] = true
            local known = false
            for _, c in ipairs(candidates) do
                if c.path == p then known = true break end
            end
            if not known then
                candidates[#candidates + 1] = { path = p, label = nil }
            end
        end
        -- 行数按剩余高度预算，放不下出汇总行（入销毁表防残影）
        local max_rows = math.max(0, math.floor((container_h - inset - y - gap) / row_h))
        if #candidates > max_rows and max_rows > 0 then
            max_rows = max_rows - 1
        end
        local show_n = math.min(#candidates, max_rows)
        for i = 1, show_n do
            local cand = candidates[i]
            local added = receive_set[cand.path] and true or false
            -- 整行点与按钮同为"切换"动作，点击不串扰也无副作用差异
            local on_toggle = function()
                if added then
                    file_transfer_app.remove_receive_dir(cand.path)
                else
                    file_transfer_app.add_receive_dir(cand.path)
                end
                picker_render()
            end
            local row = mk_row(picker_container, y, row_h, on_toggle)
            picker_rows[#picker_rows + 1] = { ref = row }
            local text = cand.label and (cand.label .. " " .. cand.path) or cand.path
            mk_row_text(row, text, fs_px,
                added and CLR.primary_light or CLR.t2, pad, btn_x - pad - gap)
            mk_side_button(row, added and "移除" or "添加", on_toggle)
            y = y + row_h
        end
        if #candidates > show_n then
            local row = mk_row(picker_container, y, row_h, nil)
            picker_rows[#picker_rows + 1] = { ref = row }
            theme.label(row, {
                x = pad, y = math.floor((row_h - (fs_px + 3)) / 2),
                w = inner_w - pad * 2, h = fs_px + 3,
                text = "…等" .. (#candidates - show_n) .. "项",
                px_size = fs_px, color = CLR.t3, align = airui.TEXT_ALIGN_LEFT,
            })
        end
        return
    end

    -- 动作行：整行按钮，共享当前浏览到的目录（多选：连点多个层级或条目右侧[添加]）
    -- 存储层给出明确指引：右侧[添加]=共享整个存储，点名称=进入选子目录
    -- 浏览到 /luadb 等禁传目录时不提供添加（不可下载/上传）
    local full = picker_full_path()
    local full_denied = full and ((full == "/luadb") or (full:sub(1, 8) == "/luadb/"))
    local action_text = full_denied and "固件资源目录不可共享"
        or (full and ("＋ 添加共享此目录: " .. full)
            or "点行尾[添加]共享整个存储, 或点名称进入选目录")
    local action_btn = mk_full_button(picker_container, y, action_text, CLR.primary, function()
        if not full or full_denied then return end
        file_transfer_app.add_shared(full, true)
        hide_picker()
        view.render_shared()
    end)
    picker_rows[#picker_rows + 1] = { ref = action_btn }
    y = y + row_h + gap

    -- 返回行：目录层显示，显式文字按钮（挂载点根回存储列表，其余回上一级）
    if picker_mount ~= nil then
        local back_text = (picker_path == nil or picker_path == "") and "← 返回存储列表" or "← 返回上一级"
        local back_btn = mk_full_button(picker_container, y, back_text, CLR.surface, function()
            if picker_path == nil or picker_path == "" then
                picker_mount = nil
            else
                picker_path = picker_path:match("^(.+)/[^/]*$") or ""
            end
            picker_render()
        end)
        picker_rows[#picker_rows + 1] = { ref = back_btn }
        y = y + row_h + gap
    end

    -- 列表数据：设备列表层列可用挂载点（io.dexist 过滤），目录层列子目录/文件
    local entries = {}
    if picker_mount == nil then
        -- 存储行带中文名（显示为"名称 路径"），根挂载点不再补"/"后缀（曾显示成"//"）
        local mounts = {
            { name = "/", type = 1, size = 0, label = "内置文件系统" },
            { name = "/sd", type = 1, size = 0, label = "外挂TF卡" },
            { name = "/little_flash", type = 1, size = 0, label = "外挂Flash" },
            { name = "/ram", type = 1, size = 0, label = "RAM盘" },
            { name = "/luadb", type = 1, size = 0, label = "脚本区" },
        }
        for _, m in ipairs(mounts) do
            -- VFS 挂载点存在性两种写法都试："/sd" 与 "/sd/"（file_manager 的 MOUNT_POINTS 用带尾斜杠形式）
            if io.dexist(m.name) or io.dexist(m.name .. "/") then
                entries[#entries + 1] = m
            end
        end
    else
        local file_manager_app = require "file_manager_app"
        local ret, items = file_manager_app.list_directory(picker_full_path())
        if ret and items then
            entries = items
        end
        -- 目录先排、文件后排
        table.sort(entries, function(a, b)
            if a.type ~= b.type then return a.type > b.type end
            return a.name < b.name
        end)
    end

    -- 条目行数按剩余高度计算（底部再留 INSET 倒角内缩），放不下时显示"…等N项"汇总行
    local max_entries = math.max(0, math.floor((container_h - inset - y - gap) / row_h))
    if #entries > max_entries and max_entries > 0 then
        max_entries = max_entries - 1  -- 腾出一行放汇总
    end
    local show_n = math.min(#entries, max_entries)
    local hidden_n = #entries - show_n

    for i = 1, show_n do
        local item = entries[i]
        local is_dir = (item.type == 1)
        -- 行 = 左区(进入目录/存储) + 右侧[添加]按钮(直接加入)，两个平级点击区互不嵌套，点击不串扰
        local row = mk_row(picker_container, y, row_h, nil)
        local name_zone = theme.box(row, {
            x = 0, y = 0, w = btn_x - theme.dp(4), h = row_h,
            color = theme.C.black, opa = 0,
            on_click = function()
                if picker_mount == nil then
                    picker_mount = item.name
                    picker_path = ""
                elseif is_dir then
                    picker_path = (picker_path == nil or picker_path == "")
                        and ("/" .. item.name) or (picker_path .. "/" .. item.name)
                end
                picker_render()
            end,
        })
        -- 存储行显示"名称 路径"（不补斜杠，根挂载曾显示成"//"）；目录行补"/"，文件行带大小
        local show_text
        if picker_mount == nil then
            show_text = (item.label or item.name) .. " " .. item.name
        elseif is_dir then
            show_text = item.name .. "/"
        else
            show_text = item.name .. "  " .. fmt_size(item.size)
        end
        mk_row_text(name_zone, show_text, fs_px,
            is_dir and CLR.primary_light or CLR.t2, pad, btn_x - pad - gap)

        -- [添加]按钮：目录=共享该目录，文件=共享该文件
        -- /luadb 等禁传目录不出现[添加]（不可下载/上传，加入也无效）
        local entry_path
        if picker_mount == nil then
            entry_path = item.name
        else
            local base = picker_full_path() or ""
            entry_path = (base == "/") and ("/" .. item.name) or (base .. "/" .. item.name)
        end
        local deny_path = (entry_path == "/luadb") or (entry_path:sub(1, 8) == "/luadb/")
        if not deny_path then
            mk_side_button(row, "添加", function()
                file_transfer_app.add_shared(entry_path, is_dir)
                hide_picker()
                view.render_shared()
            end)
        end
        picker_rows[#picker_rows + 1] = { ref = row }
        y = y + row_h
    end
    if hidden_n > 0 then
        local row = mk_row(picker_container, y, row_h, nil)
        picker_rows[#picker_rows + 1] = { ref = row }
        theme.label(row, {
            x = pad, y = math.floor((row_h - (fs_px + 3)) / 2),
            w = inner_w - pad * 2, h = fs_px + 3,
            text = "…等" .. hidden_n .. "项(请先进入子目录)",
            px_size = fs_px, color = CLR.t3, align = airui.TEXT_ALIGN_LEFT,
        })
    end
end

view.show_picker = function(mode)
    if not main_container then return end
    hide_picker()
    picker_mode = mode or "shared"
    picker_mount = nil
    picker_path = nil
    picker_overlay = theme.box(main_container, {
        x = 0, y = 0, w = sw, h = sh,
        color = theme.C.black, opa = theme.OPA.fill_hi,
    })
    picker_container = theme.box(picker_overlay, {
        x = margin, y = margin, w = card_w, h = sh - 2 * margin,
        color = CLR.bg, opa = theme.OPA.fill_hi, radius = CARD_R,
    })
    picker_render()
end

-- ==================== 共享清单卡 ====================

-- 移除一条共享（共享行点击 = 移除）
local function on_remove_shared(path)
    file_transfer_app.remove_shared(path)
    view.render_shared()
end

view.render_shared = function()
    if not main_container then return end
    if shared_card then
        shared_card:destroy()
        shared_card = nil
    end
    local pad = theme.dp(12)
    local fs_px = theme.fs("body")
    local gap = theme.dp(4)
    local items = file_transfer_app.get_cfg().shared_items or {}
    local show_n = math.min(#items, shared_rows_shown)

    -- 卡头 + 行区；body 行数 = 预算内实际所需（空清单占一行提示；预算 0 时仅卡头，极端紧凑不出滑块）
    local head_h = row_h
    local body_rows = 0
    if shared_rows_shown >= 1 then
        body_rows = (show_n == 0) and 1 or show_n
    end
    local body_h = row_h * body_rows
    local card_h = 2 * inset + head_h + body_h
    shared_card = theme.card(main_container, {
        x = margin, y = shared_y, w = card_w, h = card_h, radius = CARD_R,
    })
    local head = mk_row(shared_card, inset, head_h, nil)
    local title = "共享清单(设备→PC)"
    if #items > show_n then
        title = title .. " " .. show_n .. "/" .. #items
    end
    mk_row_text(head, title, fs_px, CLR.t2, pad, btn_x - pad - gap)
    mk_side_button(head, "添加", function() view.show_picker("shared") end)

    if body_rows == 0 then
        -- 预算 0：仅卡头（极端紧凑屏），标题已带条目计数
    elseif #items == 0 then
        local row = mk_row(shared_card, inset + head_h, row_h, nil)
        mk_row_text(row, "空清单 = 不允许 PC 读取任何文件", theme.fs("label"), CLR.t3, pad, inner_w - pad * 2)
    else
        for i = 1, show_n do
            local it = items[i]
            local shown = it.path
            -- 目录补"/"标明属性；根目录"/"与已是尾斜杠的不重复补（曾显示成"//"）
            if it.is_dir and it.path ~= "/" and it.path:sub(-1) ~= "/" then
                shown = shown .. "/"
            end
            local on_remove = function() on_remove_shared(it.path) end
            local row = mk_row(shared_card, inset + head_h + (i - 1) * row_h, row_h, on_remove)
            mk_row_text(row, shown, fs_px, it.is_dir and CLR.primary_light or CLR.t2,
                pad, btn_x - pad - gap)
            mk_side_button(row, "移除", on_remove)
        end
    end
    -- 共享卡高度随条目数变化：联动下移记录卡并原地重建（view 表运行时解析，无前向引用问题）
    records_y = shared_y + card_h + margin
    -- 记录行数按实际剩余高度计算（卡内行数=卡头+进度+记录，故减2），严格不越页底
    record_rows_shown = math.max(0, math.min(12,
        math.floor((page_bottom_y - records_y - 2 * inset) / row_h) - 2))
    view.render_records()
end

-- ==================== 传输记录卡 ====================

view.render_records = function()
    if not main_container then return end
    if record_card then
        record_card:destroy()
        record_card = nil
        progress_label = nil
    end
    local pad = theme.dp(12)
    local fs_px = theme.fs("label")
    local gap = theme.dp(4)
    local records = file_transfer_app.get_records()
    local show_n = math.min(#records, record_rows_shown)
    -- 空提示行只有预算≥1行时才放（计入卡高；无预算时不放，防止顶出页底）
    local empty_row = (show_n == 0) and (record_rows_shown >= 1)

    -- 卡头 + 进度行 + [空提示] + 记录行；行数全部计入卡高，严格贴合预算
    local head_h = row_h
    local body_h = row_h * (1 + show_n + (empty_row and 1 or 0))
    record_card = theme.card(main_container, {
        x = margin, y = records_y, w = card_w, h = 2 * inset + head_h + body_h, radius = CARD_R,
    })
    local head = mk_row(record_card, inset, head_h, nil)
    mk_row_text(head, "传输记录", fs_px + 2, CLR.t2, pad, btn_x - pad - gap)
    mk_side_button(head, "清空", function()
        file_transfer_app.clear_records()
        view.render_records()
    end)

    -- 进度行：传输中显示路径与已传字节，空闲提示用法
    local prog_row = mk_row(record_card, inset + head_h, row_h, nil)
    progress_label = mk_row_text(prog_row, "空闲(Luatools 连接后自动收发)", fs_px, CLR.t3,
        pad, inner_w - pad * 2)

    if empty_row then
        local row = mk_row(record_card, inset + head_h + row_h, row_h, nil)
        mk_row_text(row, "暂无传输记录", fs_px, CLR.t3, pad, inner_w - pad * 2)
    else
        for i = 1, show_n do
            local entry = records[i]
            local row = mk_row(record_card, inset + head_h + row_h * i, row_h, nil)
            mk_row_text(row, fmt_record(entry), fs_px,
                entry.result == "ok" and CLR.t2 or CLR.amber,
                pad, inner_w - pad * 2)
        end
    end
end

-- ==================== 鉴权设置对话框（开关 + token 输入） ====================

local auth_overlay = nil
local auth_dialog = nil
local auth_input = nil
local auth_keyboard = nil
local auth_hint = nil

local function hide_auth_dialog()
    if auth_keyboard then
        auth_keyboard:destroy()
        auth_keyboard = nil
    end
    if auth_overlay then
        auth_overlay:destroy()
        auth_overlay = nil
    end
    auth_dialog = nil
    auth_input = nil
    auth_hint = nil
end

-- 保存并开启鉴权：token 8..64 字节，与上位机输入完全一致（含大小写）
local function on_auth_save_click()
    local text = auth_input and auth_input:get_text() or ""
    if text then text = text:match("^%s*(.-)%s*$") end
    if file_transfer_app.save_auth(true, text or "") then
        hide_auth_dialog()
    else
        if auth_hint then
            auth_hint:set_text("保存失败: token需8..64字节")
        end
    end
end

-- 关闭鉴权：设备不再要求鉴权，上位机 auth 直接跳过
local function on_auth_disable_click()
    file_transfer_app.save_auth(false)
    hide_auth_dialog()
end

view.show_auth_dialog = function()
    if not main_container then return end
    hide_auth_dialog()
    update_screen_size()
    local density = _G.density_scale or 1.0

    --[[键盘统一规范（同 file_manager 输入框）：
        parent 必须是「宽 = 内容区宽」的本页根容器，y=0（相对父容器底部居中），
        高度 dp(200)，带 preview 输入预览条]]
    auth_keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = sw, h = math.floor(200 * density),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    auth_overlay = airui.container({
        parent = main_container,
        x = 0, y = 0, w = sw, h = sh,
        color = theme.C.black,
        opacity = 40,
        on_click = function() hide_auth_dialog() end,
    })

    local dialog_w = math.floor(sw * 0.85)
    local dialog_h = math.floor(200 * density)
    local dialog_x = math.floor((sw - dialog_w) / 2)
    local dialog_y = math.floor(sh * 0.18)

    auth_dialog = airui.container({
        parent = auth_overlay,
        x = dialog_x, y = dialog_y,
        w = dialog_w, h = dialog_h,
        color = theme.C.surface, color_opacity = theme.OPA.glass,
        border_color = theme.C.stroke, border_width = 1, radius = theme.r("md"),
    })

    local st = file_transfer_app.get_status()
    local pad = math.floor(16 * density)

    -- 标题 + 当前状态
    airui.label({
        parent = auth_dialog,
        x = pad, y = math.floor(8 * density),
        w = dialog_w - pad * 2, h = math.floor(22 * density),
        text = "鉴权设置", font_size = theme.fs("body"),
        color = CLR.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = auth_dialog,
        x = pad, y = math.floor(30 * density),
        w = dialog_w - pad * 2, h = math.floor(18 * density),
        text = st.auth_on and "当前: 已开启" or "当前: 未开启",
        font_size = theme.fs("caption"),
        color = CLR.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    -- token 输入框（8..64 字节，与上位机输入完全一致）
    auth_input = theme.input({
        parent = auth_dialog,
        x = pad, y = math.floor(52 * density),
        w = dialog_w - pad * 2, h = math.floor(40 * density),
        placeholder = "token 8..64字节, 须与上位机一致",
        font_size = theme.fs("label"),
        color = CLR.t1,
        keyboard = auth_keyboard,
    })

    -- 提示行（保存失败原因）
    auth_hint = airui.label({
        parent = auth_dialog,
        x = pad, y = math.floor(96 * density),
        w = dialog_w - pad * 2, h = math.floor(18 * density),
        text = "开启后上位机须输入同款token", font_size = theme.fs("caption"),
        color = CLR.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 底部按钮：[关闭鉴权] [保存并开启]
    local btn_w = math.floor(110 * density)
    local btn_h = math.floor(40 * density)
    local btn_y = dialog_h - btn_h - math.floor(10 * density)
    local btn_gap = math.floor(16 * density)
    local two_btn_w = btn_w * 2 + btn_gap
    local btn_start_x = math.floor((dialog_w - two_btn_w) / 2)

    airui.button({
        parent = auth_dialog,
        x = btn_start_x, y = btn_y, w = btn_w, h = btn_h,
        text = "关闭鉴权", font_size = theme.fs("label"),
        style = { bg_color = CLR.line_soft, pressed_bg_color = CLR.t2, text_color = CLR.t1, radius = theme.r("xs"), border_width = 0 },
        on_click = on_auth_disable_click,
    })
    airui.button({
        parent = auth_dialog,
        x = btn_start_x + btn_w + btn_gap, y = btn_y, w = btn_w, h = btn_h,
        text = "保存并开启", font_size = theme.fs("label"),
        style = { bg_color = CLR.primary, pressed_bg_color = theme.C.primary_deep, text_color = CLR.white, radius = theme.r("xs"), border_width = 0 },
        on_click = on_auth_save_click,
    })
end

-- ==================== 页面生命周期 ====================

local function on_create()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = titlebar.create(main_container, "文件传输", sw,
        function() exwin.close(window_id) end)
    local y = margin + th + margin
    y = y + build_status_card(main_container, y) + margin

    -- 布局预算（严格贴合页底，任何分辨率/密度不出滑块）：
    -- 两卡总行数 avail_rows = (页底 - 共享区顶 - 卡间隙 - 两卡倒角) / 行高
    -- 共享卡 = 1 卡头 + body(0..3)；记录卡 = 卡头 + 进度 + 记录（剩余全给）
    -- 行数不足先砍共享 body（极端时共享卡仅卡头）——宁可少显示，绝不超页底
    page_bottom_y = sh - margin
    local avail_rows = math.floor((page_bottom_y - y - margin - 4 * inset) / row_h)
    if avail_rows >= 8 then
        shared_rows_shown = 3
    elseif avail_rows >= 6 then
        shared_rows_shown = 2
    elseif avail_rows >= 5 then
        shared_rows_shown = 1
    else
        shared_rows_shown = 0
    end
    shared_y = y
    view.render_shared()   -- 末尾联动计算 record_rows_shown 并重建记录卡
end

local function on_destroy()
    hide_picker()
    hide_auth_dialog()
    if shared_card then
        shared_card:destroy()
        shared_card = nil
    end
    if record_card then
        record_card:destroy()
        record_card = nil
    end
    status_labels = {}
    progress_label = nil
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    window_id = nil
end

-- 换肤：打脏标记，等本页回到前台时重建
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()
sys.subscribe("UI_THEME_CHANGED", mark_theme_dirty)

local function on_get_focus()
    if take_theme_dirty() then
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
    end
end

local function on_lose_focus() end

-- ==================== 事件订阅（模块级常驻，窗口未开时静默忽略） ====================

local function on_status_msg(_st)
    refresh_status_text()
end

-- 记录卡原地重建（行数上限已预算，不会顶出页面）
local function on_log_msg(_entry)
    view.render_records()
end

local function on_progress_msg(prog)
    if not progress_label then return end
    -- 节流：写片最密约200片/秒，300ms 刷一次足够
    local now = mcu.ticks() or 0
    if last_prog_update > 0 and (now - last_prog_update) < 300 then return end
    last_prog_update = now
    local dir_text = (prog.dir == "D2P") and "设备→PC" or "PC→设备"
    progress_label:set_text(fit_text("传输中 " .. dir_text .. " " .. (prog.path or "")
        .. " 已传 " .. fmt_size(prog.bytes), inner_w - theme.dp(24), theme.fs("label")))
end

sys.subscribe("FILE_TRANSFER_STATUS", on_status_msg)
sys.subscribe("FILE_TRANSFER_LOG", on_log_msg)
sys.subscribe("FILE_TRANSFER_PROGRESS", on_progress_msg)

-- ==================== 事件注册 ====================

local function open_handler()
    window_id = exwin.open({
        on_create    = on_create,
        on_destroy   = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_FILE_TRANSFER_WIN", open_handler)
