--[[
@module  theme
@summary UI 共享主题模块（Air8301 出厂固件）— 向后兼容桥接层
@version 1.0
@date    2026.10.08
@author  江访

=== 定位（本次 UI 优化改造） ===
本模块由原「iOS 浅色风格主题」改造为【向后兼容桥接层】：
  1) 视觉基准统一切换到新设计系统 ui_theme（480×272 深色玻璃态）；
  2) 原版本的全部对外接口（常量名、函数签名、返回值顺序）保持不变，
     使尚未迁移到 ui_theme 的页面在过渡期内仍能正常渲染（视觉自动变为深色）；
  3) 新页面请直接 require "ui_theme" 并使用其组件与页面骨架（theme.page/theme.card…），
     不要再向本模块新增接口。

=== 与旧版差异（仅视觉，无对外接口变更） ===
  1) 全部颜色常量映射到 ui_theme 的深色语义令牌；
  2) 标题栏由「蓝色实底 48px」改为「深色面板 40px + 描边」，与 ui_theme.header 一致；
  3) 内容区几何随标题栏高度同步：CONTENT_Y = 54，CONTENT_H = 210；
  4) 按键音统一走 buzzer_drv.beep_bg（非阻塞），不再直接操作 PWM。
]]

local ui = require "ui_theme"

local T = {}

-- ==================== 颜色常量（映射到 ui_theme 语义令牌） ====================
-- 主强调色统一引用 ui.C.primary：产测模式=琥珀、业务模式=品牌蓝，随主题自动切换。
T.COLOR_PRIMARY        = ui.C.primary      -- 主强调色（业务=品牌蓝 / 产测=琥珀）
T.COLOR_PRIMARY_DARK   = ui.C.primary_deep -- 主色加深（按下态）
T.COLOR_ACCENT         = ui.C.primary      -- 强调色
T.COLOR_BG             = ui.C.bg           -- 页面底色
T.COLOR_CARD           = ui.C.panel        -- 面板卡片底
T.COLOR_TEXT           = ui.C.t1           -- 主文字
T.COLOR_TEXT_SECONDARY = ui.C.t2           -- 次级文字
T.COLOR_DIVIDER        = ui.C.stroke       -- 分隔线、边框
T.COLOR_WHITE          = 0xFFFFFF          -- 白
T.COLOR_DANGER         = ui.C.rose         -- 危险 / 错误
T.COLOR_GREEN          = ui.C.green        -- 成功 / 连接
T.COLOR_ORANGE         = ui.C.amber        -- 警告 / 中等（琥珀，业务模式下为告警橙）

-- ==================== 布局常量（480×272 横屏紧凑模式） ====================
T.SCREEN_W        = ui.SCREEN_W                        -- 480
T.SCREEN_H        = ui.SCREEN_H                        -- 272
T.TITLEBAR_H      = ui.HDR_H                           -- 40
T.CONTENT_Y       = ui.HDR_H + ui.PAD + ui.GAP         -- 54
T.CONTENT_H       = ui.SCREEN_H - T.CONTENT_Y - ui.PAD -- 210
T.MARGIN          = ui.PAD                             -- 8
T.CARD_W          = ui.SCREEN_W - 2 * ui.PAD           -- 464
T.CARD_RADIUS     = ui.R.lg                            -- 8
T.BTN_RADIUS      = ui.R.md                            -- 6
T.BACK_BTN_W      = 40                                 -- 返回键宽度

-- ==================== 字号常量（均 >= hzfont 16px 下限） ====================
T.FONT_TITLE      = ui.FS.h2      -- 18 标题栏标题
T.FONT_BACK       = ui.FS.h2      -- 18 返回按钮
T.FONT_CARD_TITLE = ui.FS.h3      -- 16 卡片小标题
T.FONT_BODY       = ui.FS.body    -- 16 正文
T.FONT_SMALL      = ui.FS.small   -- 16 辅助小字

--[[
创建标题栏（深色面板 + 返回按钮 + 标题文字）

@param userdata parent   父容器
@param string   title    标题文字
@param function on_back  返回按钮点击回调
@return userdata header  标题栏容器
]]
function T.titlebar(parent, title, on_back)
    local bar = ui.header(parent, {
        x = 0, y = 0, w = T.SCREEN_W, h = T.TITLEBAR_H,
        title = title, on_back = on_back,
    })
    return bar
end

--[[
创建信息卡片（深色面板 + 圆角 + 左侧小标题 + 右侧内容）

@param userdata parent       父容器
@param number   y            Y 坐标
@param number   h            卡片高度
@param string   title_text   小标题文字
@param string   content_text 内容初始文字
@return userdata card         卡片容器
@return userdata title_label  小标题 label
@return userdata content_label 内容 label
]]
function T.info_card(parent, y, h, title_text, content_text)
    local fs_t = T.FONT_CARD_TITLE
    local fs_c = T.FONT_BODY
    local card = ui.card(parent, {
        x = T.MARGIN, y = y, w = T.CARD_W, h = h,
        color = ui.C.panel, radius = T.CARD_RADIUS, border = ui.C.stroke_soft,
    })
    local ty = math.floor((h - (fs_t + 3)) / 2)
    if ty < 0 then ty = 0 end
    local title_label = ui.label(card, {
        x = 10, y = ty, w = 80, h = fs_t + 3,
        text = title_text, px_size = fs_t, color = ui.C.t3,
    })
    local cy = math.floor((h - (fs_c + 3)) / 2)
    if cy < 0 then cy = 0 end
    local content_label = ui.label(card, {
        x = 95, y = cy, w = T.CARD_W - 105, h = fs_c + 3,
        text = content_text, px_size = fs_c, color = ui.C.t1,
    })
    return card, title_label, content_label
end

--[[
主按钮（主强调色实底 + 反色文字）

@param userdata parent   父容器
@param number   x,y,w,h  位置尺寸
@param string   text     按钮文字
@param function on_click 点击回调
@return userdata btn     按钮容器
]]
function T.btn_primary(parent, x, y, w, h, text, on_click)
    return ui.btn(parent, {
        x = x, y = y, w = w, h = h, text = text,
        bg = ui.C.primary, fg = ui.C.on_primary, on_click = on_click,
    })
end

--[[
危险按钮（玫红实底 + 深色文字）

@return userdata btn 按钮容器
]]
function T.btn_danger(parent, x, y, w, h, text, on_click)
    return ui.btn(parent, {
        x = x, y = y, w = w, h = h, text = text,
        bg = ui.C.rose, fg = 0x2A0A10, on_click = on_click,
    })
end

--[[
成功按钮（绿色实底 + 深色文字）

@return userdata btn 按钮容器
]]
function T.btn_success(parent, x, y, w, h, text, on_click)
    return ui.btn(parent, {
        x = x, y = y, w = w, h = h, text = text,
        bg = ui.C.green, fg = 0x06231A, on_click = on_click,
    })
end

--[[
可切换状态按钮（底色 / 文字色由调用方给定，便于 ON/OFF 两态切换）

@param number bg_color   初始背景色
@param number text_color 初始文字色
@return userdata btn     按钮容器
@return userdata label   文字标签
]]
function T.toggle_btn(parent, x, y, w, h, text, bg_color, text_color, on_click)
    local fs = T.FONT_BODY
    local btn = ui.card(parent, {
        x = x, y = y, w = w, h = h,
        color = bg_color or ui.C.panel, radius = T.BTN_RADIUS,
        border = ui.C.stroke, on_click = on_click,
    })
    local label = ui.label(btn, {
        x = 0, y = math.floor((h - (fs + 3)) / 2), w = w, h = fs + 3,
        text = text, px_size = fs, color = text_color or ui.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return btn, label
end

--[[
自绘开关（轨道 + 滑块），状态由调用方维护并调用 T.toggle_switch_update 刷新

@param boolean  state    初始状态（true=ON, false=OFF）
@param function on_click 点击回调（无参数，调用方自行切换状态）
@return userdata track   滑轨容器
@return userdata knob    旋钮容器
]]
function T.toggle_switch(parent, x, y, state, on_click)
    local w, h = 44, 24
    local pad = 3
    local kd = h - pad * 2
    local on = (state == true)
    local track_c = on and ui.C.green or ui.C.track
    -- 点击去重：滑块与轨道都会收到同一次点击，各自回调会导致「翻转两次 = 没反应」
    local click_locked = false
    local function unlock_click()
        click_locked = false
    end
    local function on_track_click()
        if click_locked then return end
        click_locked = true
        sys.timerStart(unlock_click, 50)
        if on_click then on_click() end
    end
    local track = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = track_c, color_opacity = 255,
        radius = math.floor(h / 2),
        border_color = track_c, border_width = 1,
        -- 裸 airui.container 的 scrollable 默认是 true，固定尺寸开关必须关闭滚动
        scrollable = false,
        on_click = on_track_click,
    })
    local knob = airui.container({
        parent = track,
        x = on and (w - pad - kd) or pad, y = pad, w = kd, h = kd,
        color = on and ui.C.knob or ui.C.knob_off, color_opacity = 255,
        radius = math.floor(kd / 2),
        scrollable = false,
        on_click = on_track_click,
    })
    return track, knob
end

--[[
刷新自绘开关的状态显示

@param userdata track  滑轨容器
@param userdata knob   旋钮容器
@param boolean  state  新状态（true=ON, false=OFF）
]]
function T.toggle_switch_update(track, knob, state)
    if not track or not knob then return end
    local w, h = 44, 24
    local pad = 3
    local kd = h - pad * 2
    local on = (state == true)
    local c = on and ui.C.green or ui.C.track
    track:set_color(c, 255)
    track:set_border_color(c, 1)
    knob:set_color(on and ui.C.knob or ui.C.knob_off, 255)
    knob:set_pos(on and (w - pad - kd) or pad, pad)
end

-- ==================== 按键音兜底 ====================

local buzzer_mod = nil

--[[
按需加载蜂鸣器驱动（加载失败时返回 nil，不影响点击主逻辑）
]]
local function load_buzzer()
    if buzzer_mod == nil then
        local ok, drv = pcall(require, "buzzer_drv")
        buzzer_mod = ok and drv or false
    end
    return buzzer_mod or nil
end

--[[
包装点击回调：先发非阻塞提示音，再执行原回调

@param function fn 原点击回调
@return function   包装后的回调（fn 非法时原样返回）
]]
function T.with_beep(fn)
    if type(fn) ~= "function" then return fn end
    local function wrapped()
        local drv = load_buzzer()
        if drv and drv.beep_bg then drv.beep_bg(40) end
        fn()
    end
    return wrapped
end

_G.T = T

return T
