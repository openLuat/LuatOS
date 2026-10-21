--[[
@module  prod_do_win
@summary DO控制页面（产测模式），开关控制继电器
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_DO_WIN，避免与业务页面冲突

@usage
DO1(GPIO24)/DO2(GPIO25) 继电器控制，整卡可点击切换，右侧为自绘开关指示。
发布 DO_SET_REQUEST(ch, state) 到 do_app（产测与业务共用 do_app）。

视觉：ui_theme 深色玻璃态（两张大卡片，卡片内左侧标题 + 右侧开关指示）。

=== v3.0 修复：按钮不好用（与业务模式 do_win v2.1/v2.2 对齐）===
本页 v2.0 漏掉了业务模式已做的两项修复，导致「按钮非常不灵敏、时好时坏」：
  1) 点击准入：原用 exwin.is_active(win_id) 判定，而 win_id 是模块级共享变量，
     当同页出现多实例或旧实例被批量回收时会被置 nil，使准入恒为假、点击被静默丢弃。
     现改用本地存活性标志 ui_alive（on_create 置真 / on_destroy 置假）。
  2) 点击贯通：airui 的触摸命中不会从子元素回传给父容器。原实现只在卡片外层绑
     on_click，卡片内的标题/副标题两条 label 与开关轨道/滑块都会把点击吞掉，
     于是只有卡片空白边缘能点（= 不灵敏）。现用 theme.tap_card 取出去重回调 tap，
     让卡片、两行文字、开关轨道与滑块全部绑定同一 tap，
     保证「整卡任意处可点」且「一次物理点击只翻转一次」。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local do1_track, do1_knob, do2_track, do2_knob
local do1_state = 0
local do2_state = 0

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护，点击回调据此准入
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
绘制开关指示器（轨道 + 滑块，均绑定传入的去重回调，保证点开关区域也响应）

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
        log.warn("prod_do_win", "点击被丢弃 DO1 ui_alive=", ui_alive, "win_id=", win_id)
        return
    end
    do1_state = do1_state == 0 and 1 or 0
    update_switch(do1_track, do1_knob, do1_state == 1)
    sys.publish("DO_SET_REQUEST", 1, do1_state)
    log.info("prod_do_win", "DO1继电器切换为", do1_state)
end

--[[
DO2 切换

@local
@function on_do2_click
]]
local function on_do2_click()
    if not ui_alive then
        log.warn("prod_do_win", "点击被丢弃 DO2 ui_alive=", ui_alive, "win_id=", win_id)
        return
    end
    do2_state = do2_state == 0 and 1 or 0
    update_switch(do2_track, do2_knob, do2_state == 1)
    sys.publish("DO_SET_REQUEST", 2, do2_state)
    log.info("prod_do_win", "DO2继电器切换为", do2_state)
end

--[[
创建单路 DO 卡片（整卡可点击）

点击贯通：卡片、两行文字、开关轨道与滑块全部绑同一去重回调 tap，
避免「只有卡片空白处能点 → 按钮非常不灵敏」。

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
    log.info("prod_do_win", "[UI-MARK] 产测DO输出页 v1.0 已加载（点击贯通 + ui_alive 准入）")
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    -- 先失效点击准入，再释放组件，避免销毁过程中回调仍被触发
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
OPEN_PROD_DO_WIN 消息处理器

单实例保护：已在栈顶的本页实例直接忽略重复请求；
若存在残留的非活动实例则先回收，保证同一时刻只有一个本页实例。

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
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

sys.subscribe("OPEN_PROD_DO_WIN", open_handler)
