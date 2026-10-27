--[[
@module  settings_uvc_win
@summary USB 摄像头预览页（设置页入口 · UVC 画面显示）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_UVC_WIN              → 打开本页
发布: UVC_OPEN_REQ / UVC_CLOSE_REQ(gen) / UVC_RESTART_REQ
订阅: UVC_STATUS(text, level)    → 状态文案（level = info / ok / err）
订阅: UVC_CLOSED(gen)            → 关流完成，本页据此销毁画面组件

门控: features.uvc（与 settings_app 里 settings_uvc_app 的门控条件一致）

=== 页面结构 ===

  预览区（黑底框 + airui.camera 组件覆盖在上面出画面）
  状态行（连接状态 / 分辨率 / 旋转角度 / 报错）
  [重开] [旋转] [适配]

=== 画面旋转 ===

摄像头物理摆正后画面还是歪的，用 `rotation` 纠正（airui.camera 的能力）：
**顺时针** 0 / 90 / 180 / 270 四档，在缩放前对 RGB565 帧生效，不经过 Lua。

- 默认值来自 config 里 uvc 条目的 `rotation` 字段（不写即 0），建组件时传入；
  预览区按「旋转后的宽高比」算（90/270 时宽高互换），所以进页面就是正确比例。
- 页面上的「旋转」按钮调 `set_rotation` 当场切换，用来试角度 —— 但它改不了预览区
  尺寸（组件没有 resize），旋转 90/270 后画面会被 contain 压小，**只用来确认方向**。
  角度定下来后写进 config 的 `rotation`，下次进页面就正常了。
- 底层那条 `camera.config(0, CONF_PREVIEW_ROTATE, ...)` 在本固件是 LUAT_WEAK 空壳
  （就是开流时打的那条 D/camera not support yet），**不能用**，只能走组件这条。

=== 三条硬约束（踩了就是黑屏或死机） ===

1. airui.camera 组件必须在**建界面时**就建好并 register + start，且早于开流。
   组件建晚了（例如等摄像头连上再建）时，固件解码出的预览帧找不到接收方，
   全程不出画面且一条报错日志都没有。本页因此先建组件、再发 UVC_OPEN_REQ。
2. 关窗顺序不可颠倒：先关数据流（app 侧 excamera.close 含 sys.wait），
   收到 UVC_CLOSED 后才能销毁组件 —— 反序会让固件解码线程往已释放的组件里画，
   触发非对齐访问死机。所以 on_destroy 里只把根控件 set_hidden 立刻撤画面，
   销毁交给 UVC_CLOSED 回调。
3. 组件尺寸受内存约束：airui.camera 的两块显示缓冲是 视口 w×h×2 字节 × 2 块，
   源分辨率越大相机侧吃得越多（约 4.25×w×h），预览区要按剩余内存收口（见 preview_size）。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil
local cam_widget = nil          -- airui.camera 控件
local preview_area = nil        -- 预览区（黑底框）几何
local status_label = nil

local sw, sh = 480, 800

-- 画面适配模式（airui.camera 的 set_fit 取值），按此顺序循环
local FIT_ORDER = { "contain", "cover", "center", "stretch" }
local FIT_TITLE = {
    contain = "适应", cover = "铺满", center = "居中", stretch = "拉伸",
}
local fit_mode = "contain"

-- 画面旋转（airui.camera 的 rotation：顺时针，仅 0/90/180/270，在缩放前对 RGB565 帧生效）
-- 摄像头摆正后画面还是歪的，就是靠它纠正：方向反了就在四档里换一个
local ROT_ORDER = { 0, 90, 180, 270 }
local rot_mode = 0

-- airui.camera 双显示缓冲预算上限（2 块 × 视口 w×h×2 字节）
local PREVIEW_FB_BUDGET = 512 * 1024

-- 开流分辨率（与 app 层同一套口径，只用来算预览区宽高比与内存预算）
-- 实际档位由 app 层校正；实际档低于这里的申请档时，预算只会偏保守（预览区偏小）
local DEFAULT_W, DEFAULT_H = 1280, 720
local sensor_w, sensor_h = DEFAULT_W, DEFAULT_H
local max_pixels = DEFAULT_W * DEFAULT_H

-- 界面代数：快速「退出再进入」时，旧界面的销毁不能误删新界面
local ui_gen = 0
local pending = {}              -- { {gen=, container=, widget=}, ... } 待销毁的界面

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
end

--[[取 config.peripherals 里的 uvc 条目（只取分辨率，用于算预览区宽高比与内存预算）
口径与 app 层保持一致：max_pixels 缺省即默认档像素数；w/h 超过上限就退回默认档。]]
local function find_uvc_params()
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return end
    for _, p in ipairs(list) do
        if p and p.type == "uvc" then
            if p.max_pixels and p.max_pixels > 0 then max_pixels = p.max_pixels end
            if p.w and p.h and (p.w * p.h) <= max_pixels then
                sensor_w, sensor_h = p.w, p.h
            else
                sensor_w, sensor_h = DEFAULT_W, DEFAULT_H
            end
            if type(p.rotation) == "number" then rot_mode = p.rotation end
            return
        end
    end
end

-- 堆剩余字节（sys + psram 合计），取不到返回 nil
local function heap_free()
    local total = 0
    local got = false
    for _, pool in ipairs({ "sys", "psram" }) do
        local ok, t, u = pcall(rtos.meminfo, pool)
        if ok and type(t) == "number" and type(u) == "number" and t > u then
            total = total + (t - u)
            got = true
        end
    end
    return got and total or nil
end

-- 相机侧开销：双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2，合计约 4.25×w×h
local function sensor_cost()
    return math.floor(sensor_w * sensor_h * 4.25) + 16 * 1024
end

-- 预览区尺寸：与源分辨率同比缩进黑底框，再按显示缓冲预算收口
local function preview_size(avail_w, avail_h)
    local src_w = sensor_w > 0 and sensor_w or 16
    local src_h = sensor_h > 0 and sensor_h or 9
    -- 旋转 90/270 后画面宽高互换，预览区要按旋转后的比例算，否则竖画面塞进横框只剩一条
    if rot_mode == 90 or rot_mode == 270 then src_w, src_h = src_h, src_w end
    local w, h = math.floor(avail_w), math.floor(avail_h)
    local scale = math.min(w / src_w, h / src_h)
    w, h = math.floor(src_w * scale), math.floor(src_h * scale)

    local budget = PREVIEW_FB_BUDGET
    collectgarbage()
    local free = heap_free()
    if free then
        local after = math.floor((free - sensor_cost()) * 0.6)
        if after < budget then budget = after end
        log.info("settings_uvc_win", "内存预算", "开流前剩余", free,
                 "相机侧", sensor_cost(), "显示缓冲", budget)
    end
    if budget < 64 * 1024 then budget = 64 * 1024 end
    local max_px = math.floor(budget / 4)
    if w * h > max_px then
        local k = math.sqrt(max_px / (w * h))
        w, h = math.floor(w * k), math.floor(h * k)
    end
    if w < theme.dp(80) then w = theme.dp(80) end
    if h < theme.dp(60) then h = theme.dp(60) end
    log.info("settings_uvc_win", "预览区", w, "x", h, "显示缓冲", (w * h * 4), "字节")
    return w, h
end

local function set_status(text, level)
    if status_label and not status_label:is_destroyed() then
        local s = tostring(text or "")
        if rot_mode ~= 0 then s = s .. " | 旋转" .. rot_mode .. "°" end
        status_label:set_text(s)
        local color = theme.C.t2
        if level == "ok" then color = theme.SEM.success end
        if level == "err" then color = theme.SEM.danger end
        status_label:set_color(color)
    end
end

-- ==================== 画面组件 ====================

-- 按当前源分辨率建 airui.camera 控件（黑底框内居中），并挂上解码通道
local function create_widget()
    if cam_widget and not cam_widget:is_destroyed() then return true end
    if not preview_area then
        log.warn("settings_uvc_win", "预览区未就绪，跳过建组件")
        return false
    end

    local w, h = preview_size(preview_area.w, preview_area.h)
    local x = preview_area.x + math.floor((preview_area.w - w) / 2)
    local y = preview_area.y + math.floor((preview_area.h - h) / 2)

    local okw, wdg = pcall(airui.camera, {
        parent = main_container,
        x = x, y = y, w = w, h = h,
        fit = fit_mode, auto_start = false, rotation = rot_mode,
    })
    cam_widget = okw and wdg or nil
    if not cam_widget then
        log.warn("settings_uvc_win", "airui.camera 创建失败")
        set_status("本固件不含 airui.camera 组件，无法显示画面", "err")
        return false
    end
    log.info("settings_uvc_win", "预览组件", w, "x", h, "源", sensor_w, "x", sensor_h)
    pcall(cam_widget.register, cam_widget)
    pcall(cam_widget.start, cam_widget)
    return true
end

-- 切换画面适配方式
local function do_fit()
    local idx = 1
    for i, m in ipairs(FIT_ORDER) do
        if m == fit_mode then idx = i end
    end
    fit_mode = FIT_ORDER[(idx % #FIT_ORDER) + 1]
    if cam_widget and not cam_widget:is_destroyed() then
        pcall(cam_widget.set_fit, cam_widget, fit_mode)
    end
    set_status("适配方式 " .. (FIT_TITLE[fit_mode] or fit_mode), "info")
end

--[[切换画面旋转（0→90→180→270 循环，顺时针）
set_rotation 下一帧就生效，方向对不对当场能看出来；但预览区是按进页面时的角度算的，
旋转 90/270 后画面宽高互换、框子比例对不上（画面会被 contain 压小）。
定好角度后把它写进 config 的 rotation 字段，下次进页面预览区就是正确的比例。]]
local function do_rotation()
    local idx = 1
    for i, v in ipairs(ROT_ORDER) do
        if v == rot_mode then idx = i end
    end
    rot_mode = ROT_ORDER[(idx % #ROT_ORDER) + 1]
    if cam_widget and not cam_widget:is_destroyed() and cam_widget.set_rotation then
        pcall(cam_widget.set_rotation, cam_widget, rot_mode)
    end
    set_status("画面旋转 " .. rot_mode .. "°（顺时针）", "info")
end

-- ==================== 界面 ====================

local function build_ui()
    update_screen_size()

    local ctx = theme.page({
        title = "USB 摄像头",
        sub = "AirCAMERA_1034 预览 · 5V 由底板常供",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local w = ctx.w
    local y = ctx.y

    local gap = theme.dp(10)
    local btn_h = theme.dp(40)
    local status_h = theme.fs("caption") + theme.dp(10)

    -- 底部：状态行 + 按钮行，剩余高度全给预览区
    local bottom_h = status_h + gap + btn_h
    local preview_h = ctx.h - bottom_h
    if preview_h < theme.dp(80) then preview_h = theme.dp(80) end

    -- 预览区：纯黑底 + 描边，airui.camera 覆盖在上面出画面
    theme.box(main_container, {
        x = ctx.x, y = y, w = w, h = preview_h,
        color = theme.C.black or 0x000000, opa = 255,
        radius = theme.R.lg, border = theme.C.stroke, border_w = 1,
    })
    preview_area = { x = ctx.x, y = y, w = w, h = preview_h }
    -- 组件必须建在开流之前（见文件头第 1 条）
    create_widget()

    local sy = y + preview_h + gap
    status_label = theme.label(main_container, {
        x = ctx.x, y = sy, w = w, h = status_h,
        text = "准备中...", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    local cy = sy + status_h + gap
    local n = 3
    local bw = math.floor((w - (n - 1) * gap) / n)
    theme.button(main_container, {
        x = ctx.x, y = cy, w = bw, h = btn_h,
        text = "重开", size = 13,
        on_click = function()
            set_status("正在重新开流...", "info")
            sys.publish("UVC_RESTART_REQ")
        end,
    })
    theme.ghost_button(main_container, {
        x = ctx.x + bw + gap, y = cy, w = bw, h = btn_h,
        text = "旋转", size = 13, fg = theme.C.t2, border = theme.C.stroke,
        on_click = function() do_rotation() end,
    })
    theme.ghost_button(main_container, {
        x = ctx.x + 2 * (bw + gap), y = cy, w = bw, h = btn_h,
        text = "适配", size = 13, fg = theme.C.t2, border = theme.C.stroke,
        on_click = function() do_fit() end,
    })
end

-- ==================== 销毁 ====================

-- 销毁一组界面：先停组件再销毁，容器最后收（见文件头第 2 条）
local function dispose(it)
    if it.widget and not it.widget:is_destroyed() then
        pcall(it.widget.stop, it.widget)
        pcall(it.widget.destroy, it.widget)
    end
    if it.container and not it.container:is_destroyed() then
        pcall(it.container.destroy, it.container)
    end
end

-- 关流完成：销毁「代数不晚于这批」的界面，新界面的控件不在这批里，不会被误删
local function on_closed(gen)
    if not pending or #pending == 0 then return end
    local keep = {}
    for _, it in ipairs(pending) do
        if gen == nil or it.gen == nil or it.gen <= gen then
            dispose(it)
        else
            keep[#keep + 1] = it
        end
    end
    pending = keep
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    ui_gen = ui_gen + 1
    find_uvc_params()
    build_ui()
    sys.subscribe("UVC_STATUS", set_status)
    sys.publish("UVC_OPEN_REQ")
end

local function on_destroy()
    -- 退订状态：后续回调不能打到待销毁的控件上
    sys.unsubscribe("UVC_STATUS", set_status)
    -- 根控件先隐藏，画面立刻撤掉；真正的销毁等 UVC_CLOSED（关流含 sys.wait）
    if main_container and not main_container:is_destroyed() then
        pcall(main_container.set_hidden, main_container, true)
    end
    pending[#pending + 1] = {
        gen = ui_gen, container = main_container, widget = cam_widget,
    }
    main_container = nil
    cam_widget = nil
    preview_area = nil
    status_label = nil
    window_id = nil
    sys.publish("UVC_CLOSE_REQ", ui_gen)
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    -- 与 settings_app 里 settings_uvc_app 的门控条件保持一致
    local fe = (_G.project_config or {}).features or {}
    if not fe.uvc then
        log.warn("settings_uvc", "features.uvc 未开启，忽略打开请求")
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

-- 关流完成常驻订阅：页面已销毁时也要能收尾
sys.subscribe("UVC_CLOSED", on_closed)
sys.subscribe("OPEN_UVC_WIN", open_handler)
