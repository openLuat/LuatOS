--[[
@module  cloud_disk_win
@summary 合宙网盘窗口（UI 层）——登录 IoT 账号、浏览空间文件、按文件名过滤、点击下载到最高优先级存储
@version 1.1
@date    2026.09.18
@author  江访

消息协议:
订阅: OPEN_CLOUD_DISK_WIN          → 创建窗口
订阅: CLOUD_DISK_ACCOUNT(info)     → 账号状态（logged_in / account / nickname / storage_label）
订阅: CLOUD_DISK_STATUS(msg)       → 状态文本，空串 = 空闲
订阅: CLOUD_DISK_FILES(list, label, meta) → 文件列表就绪
订阅: CLOUD_DISK_ERROR(msg)        → 错误提示
订阅: CLOUD_DISK_PROGRESS(pct, text) → 下载进度（传输中最高 99，100 只在业务层校验通过后上报）
订阅: CLOUD_DISK_DONE(ok, msg, path, reason) → 下载结束（reason: "ok" | "cancel" | "error"）

发布: CLOUD_DISK_OPEN              → 打开网盘（业务层读登录态，缺 space_key 时补取）
发布: CLOUD_DISK_LOAD(opts)        → 拉取/追加文件列表 { filter, page, page_size, append, keep }
发布: CLOUD_DISK_DOWNLOAD(item)    → 下载某个文件
发布: CLOUD_DISK_CANCEL_DOWNLOAD   → 取消进行中的下载（保留已下载部分，可再次点击续传）
发布: IOT_LOGIN_REQUEST(account, password) → 走工程统一的 IoT 登录流程

=== 布局要点 ===

页面自上而下：标题栏 → 内容区（登录表单 / 文件列表 + 搜索行 + 信息行）→ 页脚状态条。
状态条高度被**从内容区高度里扣掉**，而不是压在列表上再靠 move_foreground 提层 ——
后者在子控件重排后容易失效，前者是纯算术，任何主题/分辨率下都不会互相遮挡。

键盘只在需要输入的视图里创建，且必须建在 body **之后**（同为 main_container 的子控件，
后建者在上层），否则 200px 高的键盘会被 body 盖住，看起来就是「点输入框不出键盘」。

下载进度对话框挂在 airui.screen 上（不是 body），所以列表重建不会把它带走；
对话框里的「取消下载」只发一条 CLOUD_DISK_CANCEL_DOWNLOAD —— 业务层的下载是阻塞请求，
取消在**当前块**结束后生效（见 cloud_disk_app 头部说明），这里把文案切成「正在取消...」
并锁住按钮，等 CLOUD_DISK_DONE 回来再收尾。
]]

local window_id = nil
local main_container = nil
local body = nil                        -- 内容区（登录表单 / 文件列表，切换时整体重建）
local keyboard = nil
local status_label = nil
local title_status = nil                -- 标题栏右侧昵称 / 登录态
local content_y, content_h = 0, 0

local screen_w, screen_h = 480, 800
local margin = 12

local logged_in = false
local last_logged = false               -- 「刚登录成功 → 自动拉列表」边沿检测
local nickname = ""
local storage_text = ""
local files = {}
local meta = nil                        -- { total, current, pages, size, has_more }
local busy = false                      -- 正在拉取文件列表
local cur_filter = ""                   -- 已提交的过滤词（刷新/翻页时复用）

-- 下载进度对话框
local progress_mask = nil
local progress_bar = nil
local progress_label = nil
local progress_btn = nil                -- 「取消下载」按钮
local cancelling = false                -- 已发过取消请求，等业务层收尾（防重复点击）

local theme = require "ui_theme"
local CLR = theme.live()

local function update_screen_size()
    local r = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if r == 0 or r == 180 then screen_w, screen_h = pw, ph
    else screen_w, screen_h = ph, pw end
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    screen_w, screen_h = theme.content_fit(screen_w, screen_h)
    margin = theme.page_margin()
end

local function human_size(n)
    if not n or n <= 0 then return "" end
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.1f MB", n / 1024 / 1024)
end

-- 上传时间只取 "MM-DD HH:MM"，避免整行太长把文件名挤没
local function short_time(t)
    if type(t) ~= "string" then return "" end
    local m, d, hh, mm = t:match("%d+-(%d+)-(%d+)%s+(%d+):(%d+)")
    if m then return m .. "-" .. d .. " " .. hh .. ":" .. mm end
    return t
end

-- ==================== 进度对话框 ====================

local function close_progress()
    if progress_mask then
        progress_mask:destroy()
        progress_mask = nil
        progress_bar = nil
        progress_label = nil
        progress_btn = nil
    end
    cancelling = false
end

local function show_progress(name)
    close_progress()
    --[[遮罩挂在 airui.screen 上、坐标从 (0,0) 起，必须用整屏尺寸；
    本页 screen_w 已被 content_fit 收窄为内容区宽度，用它当遮罩会在右侧漏出一条。]]
    local full_w = _G.screen_w or screen_w
    local full_h = _G.screen_h or screen_h
    local d = _G.density_scale or 1.0
    local msk = airui.container({
        parent = airui.screen, x = 0, y = 0, w = full_w, h = full_h,
        color = theme.C.black, color_opacity = 180,
    })
    --[[布局：自上而下按「实际行高 + 间距」累加，并由此反推对话框高度。

    上一版按 dh 的百分比摆元素，多一个按钮后就会在矮屏/高密度下把按钮顶出对话框
    （或压到进度文本上）。累加法是纯算术，dh 由内容算出来，任何主题/分辨率都不互相遮挡。]]
    local pad    = math.max(12, math.floor(16 * d))
    local gap    = math.max(8,  math.floor(12 * d))
    local h3     = theme.fs("h3") + 3
    local cap    = theme.fs("caption") + 3
    local micro  = theme.fs("micro") + 3
    local bar_h  = 10
    local btn_h  = math.max(30, math.floor(36 * d))

    local dw = math.min(400, full_w - 80)
    local y_title = pad
    local y_name  = y_title + h3 + gap
    local y_bar   = y_name + cap + gap
    local y_lab   = y_bar + bar_h + math.floor(gap * 0.8)
    local y_btn   = y_lab + micro + gap
    local dh      = y_btn + btn_h + pad
    if dh > full_h - 20 then dh = full_h - 20 end
    -- 高度被裁时压扁按钮，绝不让它越出对话框
    if y_btn + btn_h > dh - 4 then btn_h = math.max(18, dh - 4 - y_btn) end

    local dlg = airui.container({
        parent = msk,
        x = math.floor((full_w - dw) / 2),
        y = math.floor((full_h - dh) / 2),
        w = dw, h = dh,
        color = CLR.dialog, radius = theme.r("lg"),
        border_width = 1, border_color = CLR.line_soft,
    })
    airui.label({
        parent = dlg, x = 16, y = y_title, w = dw - 32, h = h3,
        text = "正在下载", font_size = theme.fs("h3"), color = CLR.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = dlg, x = 16, y = y_name, w = dw - 32, h = cap,
        text = tostring(name or ""), font_size = theme.fs("caption"), color = CLR.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })
    progress_bar = theme.bar(dlg, {
        x = 20, y = y_bar, w = dw - 40, h = bar_h, value = 0,
        color = CLR.primary,
    })
    progress_label = airui.label({
        parent = dlg, x = 20, y = y_lab, w = dw - 40, h = micro,
        text = "准备下载...", font_size = theme.fs("micro"), color = CLR.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 取消按钮：只置取消意图，真正的收尾由业务层在块边界完成
    local btn_w = math.min(dw - 40, math.floor(dw * 0.5))
    progress_btn = theme.ghost_button(dlg, {
        x = math.floor((dw - btn_w) / 2), y = y_btn, w = btn_w, h = btn_h,
        text = "取消下载", size = 13, fg = CLR.rose,
        on_click = function()
            if cancelling then return end
            cancelling = true
            if progress_btn then pcall(progress_btn.set_text, progress_btn, "正在取消...") end
            if progress_label then
                pcall(progress_label.set_text, progress_label, "正在取消（已下载部分会保留）...")
            end
            sys.publish("CLOUD_DISK_CANCEL_DOWNLOAD")
        end,
    })
    progress_mask = msk
end

local function on_progress(pct, text)
    if not progress_bar then return end
    pcall(progress_bar.set_value, progress_bar, pct or 0)
    -- 已点取消后不再让进度文本盖掉「正在取消...」
    if progress_label and not cancelling then
        pcall(progress_label.set_text, progress_label,
            text or string.format("下载中 %d%%", pct or 0))
    end
end

-- ==================== 提示弹窗 ====================

--[[轻提示：不用 parent（默认挂屏幕，居中坐标不受内容区收窄影响），
timeout 到点自动消失；on_action 里再 destroy，避免只 hide 留下的空壳对象。]]
local function toast(title, text, timeout)
    local ok, box = pcall(airui.msgbox, {
        w = math.min(400, screen_w - 60),
        h = math.floor(screen_h * 0.24),
        title = title, text = tostring(text or ""),
        buttons = { "确定" },
        timeout = timeout,
        on_action = function(self)
            pcall(self.destroy, self)
        end,
    })
    if ok and box and box.show then pcall(box.show, box) end
end

-- ==================== 登录表单 ====================

local function build_login()
    local d = _G.density_scale or 1.0
    local pad = margin
    local row_h = math.max(40, math.floor(44 * d))
    local gap = math.floor(10 * d)
    local inner = screen_w - 2 * pad
    local label_w = math.floor(inner * 0.22)
    local tx = math.floor(10 * d)
    local input_w = inner - label_w - 2 * tx
    local fs = theme.fs("label")
    local lh = fs + 3

    local y = pad
    theme.label(body, {
        x = pad, y = y, w = inner, h = lh,
        text = "登录 IoT 账号即可访问你的合宙网盘空间",
        px_size = theme.fs("caption"), color = CLR.t3,
        align = airui.TEXT_ALIGN_LEFT,
    })
    y = y + lh + math.floor(gap * 1.5)

    local function kv_row(label_text, password)
        local row = theme.card(body, {
            x = pad, y = y, w = inner, h = row_h, radius = theme.R.sm,
        })
        theme.label(row, {
            x = tx, y = math.floor((row_h - lh) / 2), w = label_w, h = lh,
            text = label_text, px_size = fs, color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local inp_h = math.max(30, math.floor(32 * d))
        local inp = theme.input({
            parent = row, x = tx + label_w, y = math.floor((row_h - inp_h) / 2),
            w = input_w, h = inp_h, text = "", font_size = fs,
            password_mode = password or nil, keyboard = keyboard,
        })
        y = y + row_h + gap
        return inp
    end

    local name_input = kv_row("账号", false)
    local pwd_input = kv_row("密码", true)
    y = y + math.floor(gap * 2)

    local btn_w = math.floor(inner * 0.7)
    theme.button(body, {
        x = math.floor((inner - btn_w) / 2), y = y, w = btn_w, h = row_h,
        text = "登录", size = 14, bg = CLR.primary, fg = CLR.white,
        on_click = function()
            if keyboard then keyboard:hide() end
            local account = name_input and name_input:get_text() or ""
            local password = pwd_input and pwd_input:get_text() or ""
            if account == "" or password == "" then
                toast("提示", "账号和密码不能为空")
                return
            end
            -- 走工程统一的 IoT 登录（exapp），成功后业务层再补取 space_key
            if status_label then pcall(status_label.set_text, status_label, "登录中...") end
            sys.publish("IOT_LOGIN_REQUEST", account, password)
        end,
    })
end

-- ==================== 文件列表 ====================

local function build_list()
    local d = _G.density_scale or 1.0
    local pad = margin
    local inner = screen_w - 2 * pad
    local gap = math.floor(6 * d)
    local row_h = math.max(46, math.floor(54 * d))
    local tool_h = math.max(30, math.floor(36 * d))
    local btn_w = math.max(56, math.floor(64 * d))

    -- ---- 搜索行：过滤输入框 + 搜索按钮 ----
    local y = pad
    local input_w = inner - btn_w - gap
    local fs = theme.fs("label")
    local filter_input = theme.input({
        parent = body, x = pad, y = y, w = input_w, h = tool_h,
        text = cur_filter, font_size = theme.fs("caption"),
        keyboard = keyboard, align = airui.TEXT_ALIGN_LEFT,
    })
    local function submit_filter()
        if busy then return end
        if keyboard then keyboard:hide() end
        cur_filter = (filter_input and filter_input:get_text() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        files = {}
        meta = nil
        sys.publish("CLOUD_DISK_LOAD", { filter = (cur_filter ~= "" and cur_filter or nil) })
    end
    theme.ghost_button(body, {
        x = pad + input_w + gap, y = y, w = btn_w, h = tool_h,
        text = "搜索", size = 12, on_click = submit_filter,
    })
    y = y + tool_h + gap

    -- ---- 信息行：条数/页码 +（下一页）刷新 ----
    local right = {}
    if meta and meta.has_more then
        right[#right + 1] = {
            text = "下一页",
            fn = function()
                if busy then return end
                sys.publish("CLOUD_DISK_LOAD", {
                    filter = (cur_filter ~= "" and cur_filter or nil),
                    page = (meta.current or 1) + 1,
                    page_size = meta.size or 10,
                    append = true,
                    keep = files,
                })
            end,
        }
    end
    right[#right + 1] = {
        text = busy and "获取中" or "刷新",
        fn = function()
            if busy then return end
            files = {}
            meta = nil
            sys.publish("CLOUD_DISK_LOAD", { filter = (cur_filter ~= "" and cur_filter or nil) })
        end,
    }
    local tip = "获取中..."
    if meta then
        tip = string.format("共 %d 个 | 第 %d/%d 页",
            meta.total or #files, meta.current or 1, meta.pages or 1)
    elseif not busy then
        tip = "共 " .. #files .. " 个文件"
    end
    local tip_w = inner - #right * (btn_w + gap)
    if tip_w < math.floor(inner * 0.3) then tip_w = math.floor(inner * 0.3) end
    theme.label(body, {
        x = pad, y = y, w = tip_w, h = tool_h,
        text = tip, px_size = theme.fs("micro"), color = CLR.t3,
        align = airui.TEXT_ALIGN_LEFT,
    })
    for i, b in ipairs(right) do
        local bx = pad + inner - i * (btn_w + gap) + gap
        theme.ghost_button(body, {
            x = bx, y = y, w = btn_w, h = tool_h,
            text = b.text, size = 12, on_click = b.fn,
        })
    end
    y = y + tool_h + gap

    -- ---- 列表（可滚动）----
    local list_h = content_h - y - pad
    if list_h < row_h then list_h = row_h end
    local list = airui.container({
        parent = body, x = pad, y = y, w = inner, h = list_h,
        color = CLR.surface, color_opacity = 0, scrollable = true,
    })

    if #files == 0 then
        theme.label(list, {
            x = 0, y = math.floor(row_h * 0.6), w = inner, h = theme.fs("label") + 3,
            text = busy and "正在获取文件列表..."
                or (cur_filter ~= "" and ("没有匹配 " .. cur_filter .. " 的文件") or "网盘暂无文件"),
            px_size = theme.fs("label"), color = CLR.t2,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    --[[行副标题文案：必须能塞进「行宽 - 图标 - 右侧大小」这一段。

    storage_text 形如 "外挂NAND Flash (/little_flash/cloud/)"，括号里的挂载点对用户没用
    却占掉半行 —— 行盒高只有「副字号 + 3」，文字一换行就会被裁掉，所以这里先用
    %b() 把括号段去掉，只留位置名，再补上固定的落地目录。]]
    local target = (storage_text ~= "" and storage_text or "存储")
    target = target:gsub("%s*%b()", "")
    for i, item in ipairs(files) do
        theme.row(list, {
            x = 0, y = (i - 1) * (row_h + gap),
            w = inner, h = row_h,
            icon = "cloud_disk", icon_size = math.floor(row_h * 0.56),
            text = item.name,
            sub = "下载到 " .. target .. " cloud/"
                .. (item.mtime ~= "" and (" | " .. short_time(item.mtime)) or ""),
            px_size = fs, sub_px = theme.fs("micro"),
            right = human_size(item.size), right_w = math.floor(inner * 0.22),
            right_px = theme.fs("micro"),
            on_click = function()
                if busy then return end
                -- 同一时刻只允许一个下载任务（业务层也会拒，但这里先拦住并给出提示）
                if progress_mask then
                    toast("提示", "已有下载任务进行中")
                    return
                end
                show_progress(item.name)
                sys.publish("CLOUD_DISK_DOWNLOAD", item)
            end,
        })
    end
end

-- ==================== 主体重建 ====================

--[[重建内容区

键盘与 body 同属 main_container，必须**后建**才在 body 之上；
所以先销毁旧键盘、重建 body，最后按当前视图决定要不要新建键盘
（列表视图的过滤框同样需要输入，所以两种视图都建，auto_hide 保证不聚焦时不显示）。]]
local function rebuild_body()
    if not main_container then return end
    if keyboard then pcall(keyboard.destroy, keyboard); keyboard = nil end
    if body then body:destroy(); body = nil end

    body = airui.container({
        parent = main_container, x = 0, y = content_y, w = screen_w, h = content_h,
        color = CLR.surface, color_opacity = 0,
    })

    local d = _G.density_scale or 1.0
    keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * d),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })

    if logged_in then build_list() else build_login() end
end

-- ==================== 状态同步 ====================

local function refresh_title()
    if not title_status then return end
    if logged_in then
        pcall(title_status.set_text, title_status, nickname ~= "" and nickname or "已登录")
        pcall(title_status.set_color, title_status, CLR.green)
    else
        pcall(title_status.set_text, title_status, "未登录")
        pcall(title_status.set_color, title_status, CLR.rose)
    end
end

local function on_account(info)
    if type(info) ~= "table" then return end
    local was = logged_in
    logged_in = info.logged_in and true or false
    nickname = info.nickname or ""
    if info.storage_label and info.storage_label ~= "" then storage_text = info.storage_label end
    refresh_title()

    if logged_in and not last_logged then
        -- 刚登录成功（或打开时已登录）：切到列表视图并拉一次列表
        last_logged = true
        files = {}
        meta = nil
        rebuild_body()
        sys.publish("CLOUD_DISK_LOAD", {})
    elseif (not logged_in) and was then
        -- 已登出：回登录表单，清空列表态
        last_logged = false
        files = {}
        meta = nil
        cur_filter = ""
        rebuild_body()
    end
end

local function on_files(list, label, m)
    files = (type(list) == "table") and list or {}
    meta = (type(m) == "table") and m or nil
    busy = false
    if label and label ~= "" then storage_text = label end
    if logged_in then rebuild_body() end
end

local function on_status(msg)
    if status_label then
        pcall(status_label.set_text, status_label, msg or "")
    end
    local is_busy = (msg ~= nil and msg ~= "")
    if is_busy ~= busy then
        busy = is_busy
        if logged_in then rebuild_body() end
    end
end

local function on_error(msg)
    busy = false
    close_progress()
    toast("提示", msg or "操作失败")
end

local function on_done(ok, msg, path, reason)
    close_progress()
    if ok then
        toast("下载完成", msg or "", 2500)
    elseif reason == "cancel" then
        -- 取消不是失败：已下载部分保留，下次点同一个文件即从断点续传
        toast("已取消下载", "已下载的部分已保留，再次点击该文件可继续下载", 2500)
    else
        toast("下载失败", msg or "")
    end
end

-- ==================== 窗口生命周期 ====================

local function build_ui()
    update_screen_size()
    local d = _G.density_scale or 1.0

    main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    local _, th, _title, tstatus = theme.header(main_container, {
        x = margin, y = margin, w = screen_w - 2 * margin, h = math.floor(56 * d),
        title = "合宙网盘",
        on_back = function() if window_id then exwin.close(window_id) end end,
        right = "未登录", right_w = math.floor(78 * d), right_color = CLR.rose,
    })
    title_status = tstatus

    -- 页脚状态条：高度从内容区里扣掉，不与列表重叠（详见模块头部「布局要点」）
    local status_h = math.max(20, math.floor(24 * d))
    content_y = margin + th + margin
    content_h = screen_h - content_y - margin - status_h
    if content_h < 1 then content_h = 1 end

    status_label = airui.label({
        parent = main_container, x = 0, y = screen_h - status_h,
        w = screen_w, h = status_h,
        text = "", font_size = theme.fs("micro"), color = CLR.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    logged_in = false
    last_logged = false
    files = {}
    meta = nil
    busy = false
    cur_filter = ""
    refresh_title()
    -- 先用登录表单占位；若已登录，on_account 回来会立刻切成列表
    rebuild_body()
end

local function on_create()
    build_ui()
    sys.subscribe("CLOUD_DISK_ACCOUNT", on_account)
    sys.subscribe("CLOUD_DISK_STATUS", on_status)
    sys.subscribe("CLOUD_DISK_FILES", on_files)
    sys.subscribe("CLOUD_DISK_ERROR", on_error)
    sys.subscribe("CLOUD_DISK_PROGRESS", on_progress)
    sys.subscribe("CLOUD_DISK_DONE", on_done)
    sys.publish("CLOUD_DISK_OPEN")
end

local function on_destroy()
    close_progress()
    sys.unsubscribe("CLOUD_DISK_ACCOUNT", on_account)
    sys.unsubscribe("CLOUD_DISK_STATUS", on_status)
    sys.unsubscribe("CLOUD_DISK_FILES", on_files)
    sys.unsubscribe("CLOUD_DISK_ERROR", on_error)
    sys.unsubscribe("CLOUD_DISK_PROGRESS", on_progress)
    sys.unsubscribe("CLOUD_DISK_DONE", on_done)
    if keyboard then pcall(keyboard.destroy, keyboard); keyboard = nil end
    if body then body:destroy(); body = nil end
    if main_container then main_container:destroy(); main_container = nil end
    status_label = nil
    title_status = nil
    files = {}
    meta = nil
    logged_in = false
    last_logged = false
    busy = false
    cur_filter = ""
    window_id = nil
end

-- 失焦时收起键盘（输入框还在，回来再点即可），避免键盘浮在别的页面上
local function on_lose_focus()
    if keyboard then pcall(keyboard.hide, keyboard) end
end

-- 换肤：打脏标记，回到前台时重建
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

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CLOUD_DISK_WIN", open_handler)
