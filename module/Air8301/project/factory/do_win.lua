--[[
@module  do_win
@summary DO控制页面，开关控制继电器（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
DO1(GPIO24)/DO2(GPIO25) 继电器控制，整卡可点击切换，右侧为自绘开关指示。
发布 DO_SET_REQUEST(ch, state) 到 do_app。

视觉：ui_theme 深色玻璃态（两张大卡片，卡片内左侧标题 + 右侧开关指示）。
开关指示器为「只读」绘制（轨道 + 滑块均不响应点击），点击统一由卡片承接，
从而彻底避免「父卡片与子开关同时响应导致状态翻转两次」的问题。

=== v2.1 修复：点击无响应 / 关闭困难 ===
现象：进入本页后点击卡片无反应，返回键也很难点动。
根因：点击回调首行用 exwin.is_active(win_id) 作准入条件，而 win_id 是模块级变量。
      窗口被批量回收（exwin 菜单切换事务）或多实例并存时，旧实例的 on_destroy
      会把共享的 win_id 置为 nil，导致屏幕上这个实例的 is_active(win_id) 恒为 false，
      所有点击在入口被静默丢弃。
修复：
  1) 改用本地存活性标志 ui_alive 作准入条件，不再依赖 exwin 栈顶状态；
  2) open_handler 增加单实例保护，避免同页多实例互相覆盖 win_id；
  3) 点击被丢弃时打印日志，便于现场定位。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local do1_track, do1_knob, do2_track, do2_knob
local do1_state = 0
local do2_state = 0

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护
local ui_alive = false

-- 卡片几何（内容区 464×210：76 + 10 + 76 = 162，上下居中）
local CARD_H   = 76
local CARD_GAP = 10
local SW_W, SW_H, SW_PAD = 44, 24, 3

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not ui_alive then return end
    exwin.close(win_id)
end

--[[
绘制开关指示器（轨道 + 滑块）

v2.2：轨道与滑块均绑定传入的点击回调（已去重），与父卡片共用同一回调，
      保证点开关区域也能响应；一次物理点击只翻转一次。

@local
@function make_switch
@param parent userdata 父容器
@param x number X 坐标
@param y number Y 坐标
@param state boolean 初始状态
@param on_click function 点击回调（与父卡片同一去重回调，可为 nil）
@return track userdata 轨道容器
@return knob userdata 滑块容器
]]
local function make_switch(parent, x, y, state, on_click)
    local on = (state == true)
    local kd = SW_H - SW_PAD * 2
    local track = theme.box(parent, {
        x = x, y = y, w = SW_W, h = SW_H,
        color = on and theme.C.green or theme.C.track,
        opa = 255, radius = math.floor(SW_H / 2),
        on_click = on_click,
    })
    local knob = theme.box(track, {
        x = on and (SW_W - SW_PAD - kd) or SW_PAD, y = SW_PAD, w = kd, h = kd,
        color = on and theme.C.knob or theme.C.knob_off,
        opa = 255, radius = math.floor(kd / 2),
        on_click = on_click,
    })
    return track, knob
end

--[[
刷新开关指示器状态

@local
@function update_switch
@param track userdata 轨道容器
@param knob userdata 滑块容器
@param state boolean 新状态
]]
local function update_switch(track, knob, state)
    if not track or not knob then return end
    local on = (state == true)
    local kd = SW_H - SW_PAD * 2
    local c = on and theme.C.green or theme.C.track
    track:set_color(c, 255)
    knob:set_color(on and theme.C.knob or theme.C.knob_off, 255)
    knob:set_pos(on and (SW_W - SW_PAD - kd) or SW_PAD, SW_PAD)
end

--[[
DO1 切换

@local
@function on_do1_click
]]
local function on_do1_click()
    if not ui_alive then
        log.warn("do_win", "点击被丢弃 DO1 ui_alive=", ui_alive, "win_id=", win_id)
        return
    end
    do1_state = do1_state == 0 and 1 or 0
    update_switch(do1_track, do1_knob, do1_state == 1)
    sys.publish("DO_SET_REQUEST", 1, do1_state)
    log.info("do_win", "DO1 切换为", do1_state)
end

--[[
DO2 切换

@local
@function on_do2_click
]]
local function on_do2_click()
    if not ui_alive then
        log.warn("do_win", "点击被丢弃 DO2 ui_alive=", ui_alive, "win_id=", win_id)
        return
    end
    do2_state = do2_state == 0 and 1 or 0
    update_switch(do2_track, do2_knob, do2_state == 1)
    sys.publish("DO_SET_REQUEST", 2, do2_state)
    log.info("do_win", "DO2 切换为", do2_state)
end

--[[
创建单路 DO 卡片（整卡可点击）

@local
@function create_do_card
@param parent userdata 父容器
@param y number Y 坐标
@param title string 卡片标题
@param subtitle string 引脚说明
@param on_click function 点击回调
@return track userdata 开关轨道
@return knob userdata 开关滑块
]]
local function create_do_card(parent, y, title, subtitle, on_click)
    -- 点击贯通：卡片、两行文字、开关轨道与滑块全部绑同一去重回调，
    -- 避免「只有卡片空白处能点 → 按钮非常不灵敏」
    local card, tap = theme.tap_card(parent, {
        x = theme.PAD, y = y, w = theme.SCREEN_W - theme.PAD * 2, h = CARD_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
        on_click = on_click,
    })
    theme.label(card, {
        x = 16, y = 12, w = 300, h = 22,
        text = title, px_size = 18, color = theme.C.t1,
        on_click = tap,
    })
    theme.label(card, {
        x = 16, y = 42, w = 300, h = 19,
        text = subtitle, px_size = 16, color = theme.C.t2,
        on_click = tap,
    })
    local track, knob = make_switch(card, theme.SCREEN_W - theme.PAD * 2 - 16 - SW_W,
        math.floor((CARD_H - SW_H) / 2), false, tap)
    return track, knob
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "DO输出", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 上下居中：总高 162，内容区 210，顶部留白 24
    local y = ctx.y + math.floor((ctx.h - (CARD_H * 2 + CARD_GAP)) / 2)

    do1_track, do1_knob = create_do_card(ctx.base, y, "DO1 继电器", "GPIO24", on_do1_click)
    do2_track, do2_knob = create_do_card(ctx.base, y + CARD_H + CARD_GAP,
        "DO2 继电器", "GPIO25", on_do2_click)
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    ui_alive = true
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    -- 先失效点击准入，再释放组件
    ui_alive = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    do1_track = nil
    do1_knob = nil
    do2_track = nil
    do2_knob = nil
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus() end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_DO_WIN 消息处理器

单实例保护：已在栈顶的本页实例直接忽略重复请求；
若存在残留的非活动实例则先回收，保证同一时刻只有一个本页实例。

@local
@function open_handler
]]
local function open_handler()
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_DO_WIN", open_handler)
