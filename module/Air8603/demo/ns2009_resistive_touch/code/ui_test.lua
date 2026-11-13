--[[
@module  ui_test
@summary 测试界面（AirUI 控件：container/label/button/shape）
@version 1.0
@date    2026.11.11
@usage
  local ui = require("ui_test")
  ui.init(CFG, drv_touch, w, h) -- 建 AirUI 控件；w/h 传实际分辨率（可选，缺省取 CFG.lcd）
  ui.run_calibration(unlimited) -- 四点标定；完成出"保存/不保存"页；
                                -- 手动标定超时出"标定超时+返回"页；
                                -- unlimited=true 强制模式（首次上电）：不限时、失败自动重来
  ui.start()                  -- 起主循环（接标定触发）

布局（按 W/H 自适应，字号/十字从 CFG.ui 读，兼容 480x272 / 800x480 / 1024x600）：
   顶栏：标题
   左触摸区：网格 + 准星（shape 跟随）+ 轨迹（shape 累积折线）
   右数值面板：X/Y 实时坐标（label）+ 按下/已标定状态 + 消息条
   底部 4 按钮：标定 / 准星 / 画线 / 清空（真文字标签）
   标定 overlay：干净背景 + 十字（tp.calibration 回调驱动）
   确认/超时 overlay：保存/不保存、超时 + 返回

触摸：全部走 airui.touch_subscribe（拿标定后的逻辑坐标，与 LVGL 命中检测独立），
      只在触摸区内画准星/轨迹；按钮各自 on_click；标定期间触摸归 tp 核心库。
]]

local ui = {}

-- ==================== 模块级状态 / 引用 ====================
local ui_cfg = nil     -- CFG
local touch  = nil     -- drv_touch 模块（init 注入）
local W, H   = 0, 0      -- 未初始化；init 时按实际分辨率覆盖（不写死任何分辨率）
local C      = {}      -- 主题色（init 填充）

-- 布局（480x272 小屏紧凑版：所有尺寸按 W/H 计算，禁止任何控件越界）
local HEAD_H  = 28
local PAD     = {}     -- 左触摸区
local INFO    = {}     -- 右数值面板
local BTN     = {}     -- 底部按钮行
local GRID    = 32
local MAX_SEG = 512    -- 轨迹折线段数上限（超出停止追加，点"清空"复位）
local UI      = {}     -- 派生尺寸（字号/行高/overlay 按钮等），relayout() 填充

--[[按屏幕尺寸重算布局（兼容 480x272 / 800x480 / 1024x600）：
    · 字号/读数字号/标定十字从 CFG.ui 读（font_size/val_font_size/cross_r/cross_arm）
    · 所有右/下边界都留 >=8px 余量，LVGL 不会在屏幕底部画可拖动的滚动条
    · 右面板内部行位置按 INFO.h 均分，不写死任何分辨率的大屏偏移]]
local function relayout()
    local m = math.max(4, math.floor(H * 0.03))                  -- 8
    BTN.margin, BTN.gap = m, math.max(4, math.floor(H * 0.022)) -- 8, 5
    BTN.h = math.max(28, math.floor(H * 0.13))                   -- 35
    BTN.y = H - BTN.h - m                                        -- 229
    HEAD_H = math.max(20, math.floor(H * 0.10))                  -- 27
    PAD.x, PAD.y = m, HEAD_H + 4                                 -- 8, 31
    INFO.w = math.max(96, math.min(160, math.floor(W * 0.34)))  -- 160
    INFO.x, INFO.y = W - m - INFO.w, PAD.y                       -- 312, 31
    PAD.w = INFO.x - PAD.x - m                                   -- 296
    PAD.h = BTN.y - PAD.y - 6                                    -- 192
    INFO.h = PAD.h
    GRID = math.max(20, math.floor(PAD.h / 5))                   -- 38

    local uic = (ui_cfg and ui_cfg.ui) or {}
    UI.fs     = uic.font_size or 12                              -- 中文/标签字号（hzfont 12~255）
    UI.fs_val = uic.val_font_size or (UI.fs + 4)                 -- 坐标读数字号
    UI.inner    = math.max(6, math.floor(INFO.w * 0.05))         -- 8
    UI.row      = math.floor(INFO.h / 6)                         -- 32
    UI.label_h  = UI.fs + 4                                      -- 行高随字号派生（12→16，16→20）
    UI.val_h    = UI.fs_val + 6                                  -- 读数行高（16→22，20→26）
    UI.title_h  = UI.fs + 8                                      -- 标题行高（12→20，16→24）
    UI.title_y  = math.max(2, math.floor((HEAD_H - UI.title_h) / 2))
    UI.cross_r   = uic.cross_r or 18                             -- 标定十字外圈半径（配置驱动）
    UI.cross_arm = uic.cross_arm or 28                           -- 标定十字臂长（配置驱动）
    UI.tip_y, UI.tip_h = 8, 20
    UI.bottom_tip_y = H - 28
    UI.bw2 = math.min(160, math.floor(W * 0.32))                 -- 确认页按钮宽
    UI.gap2 = math.max(8, math.floor(W * 0.03))
    UI.by2 = math.floor(H * 0.55)
    UI.bh2 = math.max(32, math.floor(H * 0.16))
    UI.bw3 = math.min(200, math.floor(W * 0.45))                 -- 超时页按钮宽
    UI.by3 = math.floor(H * 0.55)
    UI.bh3 = UI.bh2
end

-- 控件引用（init 填充）
local lbl_x_val, lbl_y_val, press_lbl, cal_lbl, lbl_msg
local btn_reticle, btn_trace
local trace_shape, reticle_shape, cross_shape
local ov_cal, ov_confirm, ov_timeout

-- 运行态
local S = {
    page            = "main",   -- main / cal / cal_confirm / cal_timeout
    reticle_mode    = true,     -- true=准星跟随；false=画线（永久）
    reticle_visible = false,
    calibrating     = false,    -- tp.calibration 进行中（触摸归核心库）
    pending_cal     = false,    -- 主循环拾取的标定触发标志
    trace_x         = nil,
    trace_y         = nil,
    cal_state       = false,
    last_sig        = nil,
}

-- ==================== 小工具 ====================

local function inside_pad(x, y)
    return x >= PAD.x and x < PAD.x + PAD.w and y >= PAD.y and y < PAD.y + PAD.h
end

--[[准星位置钳位：整体留在触摸区内（准星最大延伸 22px）]]
local function pad_clamp(x, y)
    local m = 22
    if x < PAD.x + m then x = PAD.x + m end
    if y < PAD.y + m then y = PAD.y + m end
    if x > PAD.x + PAD.w - m then x = PAD.x + PAD.w - m end
    if y > PAD.y + PAD.h - m then y = PAD.y + PAD.h - m end
    return x, y
end

--[[居中一个 label（容错：set_align/常量缺失时静默跳过）]]
local function center(l)
    if l and l.set_align and airui and airui.TEXT_ALIGN_CENTER then
        pcall(function() l:set_align(airui.TEXT_ALIGN_CENTER) end)
    end
end

local function set_msg(text, color)
    if lbl_msg then
        lbl_msg:set_text(text or "")
        if color then lbl_msg:set_color(color) end
    end
end

--[[所有 container 一律关掉 SCROLLABLE：airui.container 默认可滚动，子控件只要
    越界 1px，LVGL 就会在屏幕底部/右侧画出可拖动的滚动条（factory UI 同款处理）。
    固件不认识 scrollable 字段时会忽略它，无副作用。]]
local function cont(cfg)
    cfg.scrollable = false
    return airui.container(cfg)
end

--[[overlay 显示/隐藏：用 container 的 open/hide（置顶+隐藏），
    不再用 set_pos 移出屏幕——子对象超出屏幕边界会让 LVGL 出滚动条]]
local function show_overlay(ov)
    if ov.open then ov:open() elseif ov.set_hidden then ov:set_hidden(false) else ov:set_pos(0, 0) end
    if airui.refresh then pcall(airui.refresh) end
end

local function hide_overlay(ov)
    if ov.hide then ov:hide()
    elseif ov.set_hidden then ov:set_hidden(true)
    else ov:set_pos(0, 0) end   -- 无 hide 接口时保持原位，绝不制造屏外对象
end

--[[更新右侧数值面板（内容没变就跳过，省 LVGL 无效重绘）]]
local function set_value(x, y, pressed)
    local sx = math.floor(x or 0); local sy = math.floor(y or 0)
    local sig = string.format("%d|%d|%d", sx, sy, pressed and 1 or 0)
    if sig == S.last_sig then return end
    S.last_sig = sig
    if lbl_x_val then lbl_x_val:set_text(string.format("%03d", sx)) end
    if lbl_y_val then lbl_y_val:set_text(string.format("%03d", sy)) end
    if press_lbl then press_lbl:set_color(pressed and C.ok or C.grid) end
end

-- 准星图元（相对 shape 原点，shape 尺寸 44x44，中心 22,22；set_pos 移动整体）
local function reticle_items(accent)
    return {
        { type = "circle", cx = 22, cy = 22, r = 12, color = accent, width = 2 },
        { type = "line",   x1 = 2,  y1 = 22, x2 = 16, y2 = 22, color = accent, width = 2 },
        { type = "line",   x1 = 28, y1 = 22, x2 = 42, y2 = 22, color = accent, width = 2 },
        { type = "line",   x1 = 22, y1 = 2,  x2 = 22, y2 = 16, color = accent, width = 2 },
        { type = "line",   x1 = 22, y1 = 28, x2 = 22, y2 = 42, color = accent, width = 2 },
        { type = "circle", cx = 22, cy = 22, r = 2,  color = accent, width = 1, fill = true, fill_color = accent },
    }
end

--[[准星跟随：首次显示时建图元，之后只 set_pos 移动（最省）]]
local function place_reticle(x, y)
    if not reticle_shape then return end
    x, y = pad_clamp(x, y)
    if not S.reticle_visible then
        reticle_shape:set_items(reticle_items(C.accent))
        S.reticle_visible = true
    end
    reticle_shape:set_pos(x - 22, y - 22)
end

--[[标定十字：大十字 + 圆圈（绝对坐标，画在 ov_cal 内；半径按小屏缩放）]]
local function draw_cross(x, y)
    if not cross_shape then return end
    local r, a = UI.cross_r, UI.cross_arm
    cross_shape:set_items({
        { type = "circle", cx = x, cy = y, r = r, color = C.accent, width = 2 },
        { type = "circle", cx = x, cy = y, r = math.floor(r / 3), color = C.accent, width = 2 },
        { type = "line",   x1 = x - a, y1 = y, x2 = x + a, y2 = y,   color = C.accent, width = 2 },
        { type = "line",   x1 = x, y1 = y - a, x2 = x, y2 = y + a,   color = C.accent, width = 2 },
    })
    if airui.refresh then pcall(airui.refresh) end
end

--[[模式按钮的常驻高亮（当前生效的准星/画线模式）]]
local function refresh_mode_btns()
    if btn_reticle then btn_reticle:set_text(S.reticle_mode and "● 准星" or "准星") end
    if btn_trace then btn_trace:set_text(S.reticle_mode and "画线" or "● 画线") end
end

-- ==================== 建控件 ====================
--[[
中文标签统一用 UI.fs（= CFG.ui.font_size，480x272 为 12、800/1024 为 16）；
纯数字坐标读数用 UI.fs_val（= CFG.ui.val_font_size）。两个字号都由 hzfont 矢量字库渲染。
]]
local function build_ui()
    local T = C

    -- 全屏背景 + 顶栏 + 标题
    cont({ x = 0, y = 0, w = W, h = H, color = T.bg, parent = airui.screen })
    cont({ x = 0, y = 0, w = W, h = HEAD_H, color = T.header, parent = airui.screen })
    -- ★ 宽度必须扣掉左侧 x 偏移：右缘 16+(W-32)=W-16 < W，否则又出横向滚动条
    airui.label({ x = 16, y = UI.title_y, w = W - 32, h = UI.title_h,
        text = "LCD 触摸自检（AirUI）", font_size = UI.fs, color = T.text, font = "hzfont",
        parent = airui.screen })

    -- 左触摸区：背景 + 边框 + 网格
    cont({ x = PAD.x, y = PAD.y, w = PAD.w, h = PAD.h,
        color = T.pad_bg, border_color = T.border, border_width = 2, parent = airui.screen })
    local grid_items = {}
    local gx = GRID
    while gx < PAD.w do
        table.insert(grid_items, { type = "line", x1 = gx, y1 = 0, x2 = gx, y2 = PAD.h - 1, color = T.grid, width = 1 })
        gx = gx + GRID
    end
    local gy = GRID
    while gy < PAD.h do
        table.insert(grid_items, { type = "line", x1 = 0, y1 = gy, x2 = PAD.w - 1, y2 = gy, color = T.grid, width = 1 })
        gy = gy + GRID
    end
    airui.shape({ x = PAD.x, y = PAD.y, w = PAD.w, h = PAD.h, items = grid_items, parent = airui.screen })

    -- 轨迹（全屏 shape，绝对坐标）+ 准星（44x44 shape，set_pos 移动）
    trace_shape   = airui.shape({ x = 0, y = 0, w = W, h = H, parent = airui.screen })
    reticle_shape = airui.shape({ x = 0, y = 0, w = 44, h = 44, parent = airui.screen })

    -- 右数值面板：行位置按 INFO.h 均分，小屏也不会把标签顶出屏幕
    cont({ x = INFO.x, y = INFO.y, w = INFO.w, h = INFO.h,
        color = T.panel, border_color = T.border, border_width = 1, parent = airui.screen })
    local ix, ir, iw = INFO.x + UI.inner, UI.row, INFO.w - UI.inner * 2
    airui.label({ x = ix, y = INFO.y + 4, w = 24, h = UI.label_h,
        text = "X", font_size = UI.fs, color = T.accent, font = "hzfont", parent = airui.screen })
    lbl_x_val = airui.label({ x = ix + 24, y = INFO.y, w = iw - 24, h = UI.val_h,
        text = "000", font_size = UI.fs_val, color = T.text, font = "hzfont", parent = airui.screen })
    airui.label({ x = ix, y = INFO.y + ir + 4, w = 24, h = UI.label_h,
        text = "Y", font_size = UI.fs, color = T.trace, font = "hzfont", parent = airui.screen })
    lbl_y_val = airui.label({ x = ix + 24, y = INFO.y + ir, w = iw - 24, h = UI.val_h,
        text = "000", font_size = UI.fs_val, color = T.text, font = "hzfont", parent = airui.screen })
    press_lbl = airui.label({ x = ix, y = INFO.y + math.floor(ir * 2.6), w = iw, h = UI.label_h,
        text = "● 按下", font_size = UI.fs, color = T.grid, font = "hzfont", parent = airui.screen })
    cal_lbl   = airui.label({ x = ix, y = INFO.y + math.floor(ir * 3.6), w = iw, h = UI.label_h,
        text = "● 已标定", font_size = UI.fs, color = T.grid, font = "hzfont", parent = airui.screen })
    lbl_msg   = airui.label({ x = ix, y = INFO.y + math.floor(ir * 4.6), w = iw, h = UI.label_h * 2,
        text = "", font_size = UI.fs, color = T.ok, font = "hzfont", parent = airui.screen })

    -- 底部 4 按钮
    local bw = math.floor((W - 2 * BTN.margin - 3 * BTN.gap) / 4)
    local acts = {
        { id = "cal",     label = "标定" },
        { id = "reticle", label = "准星" },
        { id = "trace",   label = "画线" },
        { id = "clear",   label = "清空" },
    }
    local style = {
        bg_color = T.btn_bg, text_color = T.text, radius = 8,
        border_color = T.border, border_width = 1, pressed_bg_color = T.btn_press,
    }
    for i, a in ipairs(acts) do
        local bx = BTN.margin + (i - 1) * (bw + BTN.gap)
        local b = airui.button({
            x = bx, y = BTN.y, w = bw, h = BTN.h,
            text = a.label, font = "hzfont", font_size = UI.fs, style = style,
            parent = airui.screen,
            on_click = function()
                if S.page ~= "main" then return end
                if a.id == "cal" then
                    S.pending_cal = true
                    set_msg("开始标定…", T.accent)
                elseif a.id == "reticle" then
                    S.reticle_mode = true
                    S.reticle_visible = false
                    refresh_mode_btns()
                    set_msg("准星模式", T.ok)
                elseif a.id == "trace" then
                    S.reticle_mode = false
                    if reticle_shape then reticle_shape:clear() end
                    S.reticle_visible = false
                    refresh_mode_btns()
                    set_msg("画线模式", T.ok)
                elseif a.id == "clear" then
                    if trace_shape then trace_shape:clear() end
                    S.trace_x, S.trace_y = nil, nil
                    set_msg("已清空", T.ok)
                end
            end,
        })
        if a.id == "reticle" then btn_reticle = b end
        if a.id == "trace" then btn_trace = b end
    end

    -- 标定 overlay：干净背景 + 十字 + 顶部提示 + 底部操作提示
    ov_cal = cont({ x = 0, y = 0, w = W, h = H, color = T.bg, parent = airui.screen })
    cross_shape = airui.shape({ x = 0, y = 0, w = W, h = H, parent = ov_cal })
    center(airui.label({ x = 0, y = UI.tip_y, w = W, h = UI.tip_h,
        text = "正在校准屏幕触摸", font_size = UI.fs, color = T.accent,
        font = "hzfont", parent = ov_cal }))
    center(airui.label({ x = 0, y = UI.bottom_tip_y, w = W, h = UI.tip_h,
        text = "按 左上→右上→左下→右下 依次点击十字", font_size = UI.fs, color = T.text,
        font = "hzfont", parent = ov_cal }))
    ov_cal:hide()               -- 初始隐藏（hide：不产生屏外区域，无滚动条）

    -- 确认页 overlay：标定完成，是否保存（按钮宽/高按 W/H 算，绝不超出屏幕）
    ov_confirm = cont({ x = 0, y = 0, w = W, h = H, color = T.bg, parent = airui.screen })
    center(airui.label({ x = 0, y = math.floor(H * 0.25), w = W, h = 24,
        text = "标定完成，是否保存？", font_size = UI.fs, color = T.text, font = "hzfont", parent = ov_confirm }))
    local bx2 = math.floor((W - 2 * UI.bw2 - UI.gap2) / 2)
    airui.button({
        x = bx2, y = UI.by2, w = UI.bw2, h = UI.bh2,
        text = "保存", font = "hzfont", font_size = UI.fs,
        style = { bg_color = T.ok, text_color = 0xFFFFFF, radius = 6, border_color = T.text, border_width = 1, pressed_bg_color = T.ok },
        parent = ov_confirm,
        on_click = function()
            local saved = (touch and touch.save_calibration()) or false
            S.page = "main"
            ov_confirm:hide()
            set_msg(saved and "标定已保存" or "保存失败", saved and T.ok or T.err)
        end,
    })
    airui.button({
        x = bx2 + UI.bw2 + UI.gap2, y = UI.by2, w = UI.bw2, h = UI.bh2,
        text = "不保存", font = "hzfont", font_size = UI.fs,
        style = { bg_color = T.err, text_color = 0xFFFFFF, radius = 6, border_color = T.text, border_width = 1, pressed_bg_color = T.err },
        parent = ov_confirm,
        on_click = function()
            S.page = "main"
            ov_confirm:hide()
            set_msg("未保存（本次生效）", T.dim)
        end,
    })
    ov_confirm:hide()

    -- 超时页 overlay：超时 + 返回
    ov_timeout = cont({ x = 0, y = 0, w = W, h = H, color = T.bg, parent = airui.screen })
    center(airui.label({ x = 0, y = math.floor(H * 0.28), w = W, h = 24,
        text = "标定超时", font_size = UI.fs, color = T.err, font = "hzfont", parent = ov_timeout }))
    airui.button({
        x = math.floor((W - UI.bw3) / 2), y = UI.by3, w = UI.bw3, h = UI.bh3,
        text = "返回", font = "hzfont", font_size = UI.fs,
        style = { bg_color = T.btn_bg, text_color = T.text, radius = 6, border_color = T.accent, border_width = 2, pressed_bg_color = T.btn_press },
        parent = ov_timeout,
        on_click = function()
            S.page = "main"
            ov_timeout:hide()
            set_msg("标定超时", T.err)
        end,
    })
    ov_timeout:hide()

    refresh_mode_btns()
end

-- ==================== 触摸分发（airui.touch_subscribe） ====================
--[[
AirUI 触摸回调：fn(state, x, y, track_id, timestamp, touches)
  state = airui.TP_DOWN / TP_HOLD / TP_UP（第一指）
  x,y   = 标定后的逻辑坐标
只在主页面、且触点在触摸区内时画准星/轨迹；按钮走各自 on_click。
]]
local function on_touch(state, x, y)
    if S.calibrating or S.page ~= "main" then return end

    -- 坐标/按下状态：全屏任意位置都更新（不局限于左侧触摸区）
    local pressed = (state == airui.TP_DOWN or state == airui.TP_HOLD)
    set_value(x, y, pressed)

    if state == airui.TP_UP then
        S.trace_x, S.trace_y = nil, nil
        return
    end

    -- 准星/轨迹绘制：仍只在触摸区内（按钮区域触摸归各自 on_click）
    if not inside_pad(x, y) then return end

    if state == airui.TP_DOWN then
        S.trace_x, S.trace_y = x, y
        if S.reticle_mode then place_reticle(x, y) end
    elseif state == airui.TP_HOLD then
        if S.reticle_mode then
            place_reticle(x, y)
        else
            -- 画线模式：位移够大才追加一段，段数封顶
            if S.trace_x
                and math.abs(x - S.trace_x) + math.abs(y - S.trace_y) >= 3
                and trace_shape:get_count() < MAX_SEG then
                trace_shape:add_item({
                    type = "line",
                    x1 = S.trace_x, y1 = S.trace_y, x2 = x, y2 = y,
                    color = C.trace, width = 2,
                })
                S.trace_x, S.trace_y = x, y
            end
        end
    end
end

-- ==================== 标定（核心库 tp.calibration，本体在 drv_touch） ====================

local function show_confirm_page()
    S.page = "cal_confirm"
    show_overlay(ov_confirm)
end

local function show_timeout_page()
    S.page = "cal_timeout"
    show_overlay(ov_timeout)
end

--[[
四点标定：调 drv_touch.calibrate（内部包 tp.calibration，兼容阻塞/异步固件）。
本函数负责：显示干净标定页 + 十字、完成后的去向。
   成功   → SAVE/NO 选择页（保存 / 不保存）
   超时   → TIMEOUT + 返回页（unlimited=true 时除外，见下）
   未启动 → 回主界面报失败（unlimited=true 时除外）
标定期间触摸由核心库接管（on_touch 靠 S.calibrating 自动忽略）。
@param boolean unlimited  true=强制模式（上电首次标定用）：任何失败都自动重新
       开始，用户无法离开标定页，直到标定成功——未标定坐标上下颠倒，
       所以首次上电必须完成一次标定。手动标定不传此参，保留超时+返回。
@return boolean 标定流程是否成功
]]
function ui.run_calibration(unlimited)
    if S.calibrating then return false end
    if not (touch and tp and tp.calibration and touch.get()) then
        set_msg("无法标定（无 tp/设备）", C.err)
        return false
    end
    log.info("ui", "开始四点标定；按左上、右上、左下、右下顺序点击十字",
        unlimited and "首次标定：不限时，直到成功" or "超时 60 秒")
    S.calibrating = true
    S.page = "cal"
    S.trace_x, S.trace_y = nil, nil
    show_overlay(ov_cal)

    local ok, reason
    while true do
        ok, reason = touch.calibrate(function(ev, a, b)
            if ev == "point" then
                draw_cross(a, b)
            end
        end, unlimited and math.huge or nil)   -- 不限时模式：等待永不超时
        if ok then break end
        if not unlimited then break end
        -- 强制模式：无论何种失败（固件侧超时/失败、tp.calibration 启动失败）
        -- 都自动重新开始，永不显示超时页——用户必须标完才能进主界面
        log.warn("ui", "首次标定未完成（" .. tostring(reason) .. "），1 秒后自动重新开始")
        sys.wait(1000)   -- 启动失败时避免紧密死循环刷日志
    end
    S.calibrating = false
    S.page = "main"
    hide_overlay(ov_cal)

    if not ok then
        if reason == "timeout" or reason == "cal_fail" then
            log.warn("ui", "标定未成功", reason)
            show_timeout_page()
        else
            set_msg("标定失败", C.err)
            if airui.refresh then pcall(airui.refresh) end
        end
        return false
    end

    S.cal_state = true
    if cal_lbl then cal_lbl:set_color(C.warn) end
    log.info("ui", "标定完成", tostring(reason))
    show_confirm_page()
    return true
end

-- ==================== 对外接口 ====================

--[[
初始化界面
@param table c    config.lua 的 CFG
@param table tmod drv_touch 模块
@param number w   实际屏幕宽（可选，缺省取 c.lcd.w）
@param number h   实际屏幕高（可选，缺省取 c.lcd.h）
]]
function ui.init(c, tmod, w, h)
    ui_cfg = c
    touch  = tmod
    -- 优先用 main 传入的实际分辨率（drv.width()/height()），保证与 airui.init 一致
    W = w or (c.lcd and c.lcd.w) or 480
    H = h or (c.lcd and c.lcd.h) or 272
    relayout()

    local t = (c.ui and c.ui.color) or {}
    for k, v in pairs(t) do C[k] = v end

    build_ui()

    -- 订阅触摸（准星/轨迹），拿标定后的逻辑坐标
    if airui and airui.touch_subscribe then
        airui.touch_subscribe(on_touch)
    end

    if airui.refresh then pcall(airui.refresh) end
    log.info("ui", "AirUI 界面已构建", W .. "x" .. H)
end

--[[主循环：20ms，拾取按钮触发的标定请求（标定阻塞，必须在协程里跑）]]
function ui.start()
    sys.taskInit(function()
        while true do
            if S.pending_cal then
                S.pending_cal = false
                if S.page == "main" then
                    ui.run_calibration()
                end
            end
            sys.wait(20)
        end
    end)
end

return ui
