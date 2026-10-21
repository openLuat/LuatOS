--[[
@module  led_win
@summary 状态灯控制页面，开关控制（8301出厂固件）
@version 1.1
@date    2026.10.10
@author  江访

@usage
4G灯(GPIO21)和WiFi灯(GPIO141)的ON/OFF控制。
整卡可点击切换，右侧为自绘开关指示。发布 LED_SET_REQUEST(ch, state)。
与 do_win 统一风格。

视觉：ui_theme 深色玻璃态（两张大卡片，卡片内左侧标题 + 右侧开关指示）。
开关指示器为「只读」绘制（轨道 + 滑块均不响应点击），点击统一由卡片承接，
从而避免「父卡片与子开关同时响应导致状态翻转两次」的问题。

点击准入用本地存活性标志 ui_alive（on_create 置真 / on_destroy 置假），
不依赖 exwin 栈顶状态 —— 只要本页还在屏上，点击必然生效。
窗口打开/销毁样板由 theme.win 统一承担（单实例保护：已有非活动实例先回收）。

@note 变更 26（体积优化）：窗口样板下沉至 ui_theme.win，界面与交互行为不变。
]]

local theme = require "ui_theme"

local W                        -- 窗口控制器（文件末尾由 theme.win 建立）
local main_container, content
local led4g_track, led4g_knob, ledwifi_track, ledwifi_knob
local led4g_state = 0
local ledwifi_state = 0

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
    exwin.close(W.id)
end

--[[
绘制开关指示器（轨道 + 滑块）

轨道与滑块均绑定传入的点击回调（已去重），与父卡片共用同一回调，
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
4G灯切换

@local
@function on_led4g_click
]]
local function on_led4g_click()
    if not ui_alive then
        log.warn("led_win", "点击被丢弃 4G灯 ui_alive=", ui_alive, "win_id=", W.id)
        return
    end
    led4g_state = led4g_state == 0 and 1 or 0
    update_switch(led4g_track, led4g_knob, led4g_state == 1)
    sys.publish("LED_SET_REQUEST", 1, led4g_state)
    log.info("led_win", "4G灯切换为", led4g_state)
end

--[[
WiFi灯切换

@local
@function on_ledwifi_click
]]
local function on_ledwifi_click()
    if not ui_alive then
        log.warn("led_win", "点击被丢弃 WiFi灯 ui_alive=", ui_alive, "win_id=", W.id)
        return
    end
    ledwifi_state = ledwifi_state == 0 and 1 or 0
    update_switch(ledwifi_track, ledwifi_knob, ledwifi_state == 1)
    sys.publish("LED_SET_REQUEST", 2, ledwifi_state)
    log.info("led_win", "WiFi灯切换为", ledwifi_state)
end

--[[
创建单盏状态灯卡片（整卡可点击）

@local
@function create_led_card
@param parent userdata 父容器
@param y number Y 坐标
@param title string 卡片标题
@param subtitle string 引脚说明
@param on_click function 点击回调
@return track userdata 开关轨道
@return knob userdata 开关滑块
]]
local function create_led_card(parent, y, title, subtitle, on_click)
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
    local ctx = theme.page({ title = "状态灯", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 上下居中：总高 162，内容区 210，顶部留白 24
    local y = ctx.y + math.floor((ctx.h - (CARD_H * 2 + CARD_GAP)) / 2)

    led4g_track, led4g_knob = create_led_card(ctx.base, y, "4G状态灯", "GPIO21", on_led4g_click)
    ledwifi_track, ledwifi_knob = create_led_card(ctx.base, y + CARD_H + CARD_GAP,
        "WiFi状态灯", "GPIO141", on_ledwifi_click)
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
    -- 先失效点击准入，再释放组件，避免销毁过程中回调仍被触发
    ui_alive = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    led4g_track = nil
    led4g_knob = nil
    ledwifi_track = nil
    ledwifi_knob = nil
end

--[[窗口控制器（公共样板 theme.win）
单实例保护（replace = true：本页已有非活动实例时先回收再新建），销毁时自动清空窗口 id。]]
W = theme.win({
    open = "OPEN_LED_WIN",
    replace = true,
    on_create = on_create,
    on_destroy = on_destroy,
})
