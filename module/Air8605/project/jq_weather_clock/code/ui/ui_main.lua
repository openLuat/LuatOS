--[[
@module  ui_main
@summary 界面总装：场景 + 角色 + HUD + 七天预报页 + 触摸手势 + 主循环
@version 1.0
@date    2026.11.08

=== 层级（创建顺序 = z 序，后建的在上）===
root 容器
 ├── sky shape    静态天空（渐变 / 远山 / 草地）
 ├── fx  shape    动态层（星星 / 云 / 雨雪 / 地面参照物 / 小窝 / 角色）
 ├── hud shape    HUD 图标（定位针 / 房子 / 水滴 / 天气徽标）
 ├── hud labels   时间 / 日期 / 温度区间 / 城市 / 房间温湿度 / 提示
 └── forecast    七天预报整页容器（默认隐藏，x=1024）

=== 交互 ===
左滑            → 七天预报页从右侧滑入
右滑            → 收起预报页
点击中间区域    → 骑行 / 小猫 / 小狗 循环切换
点击右上角图标  → 立即重新拉一次天气

=== 触摸为什么不用控件回调 ===
airui.shape 不接收点击（CLICKABLE 被去掉），而且左滑/点击要落在整块透明区域上。
统一走 airui.touch_subscribe 拿原始坐标自己做手势判定，
再按坐标分派 —— 这样滑动/点击不会因为某个控件没吃事件而失效。
回调里只记坐标，真正的 UI 操作在定时器里做（避免在输入上下文里改控件）。
]]

local draw = require "draw"
local conf = require "conf"
local scene = require "scene"
local actor = require "actor"
local hud = require "hud"
local forecast = require "forecast"
local time_util = require "time_util"
local room = require "room_sensor"

local M = {}

local W, H = conf.W, conf.H

local root
local a                       -- 角色状态
local env                     -- 本帧环境
local wx                      -- 当前天气
local room_state = {}         -- { temp = , humi = }

local fc_open = false
local fc_x = W
local slide = { running = false, from = W, to = W, t = 0, dur = 230 }
local slide_timer            -- 滑动动画定时器 id（按需启停，见 slide_stop 注释）

--[[
滑动动画：只在滑动期间开 20ms 定时器，动画结束立即停。

**不能常驻 20ms**：sys.timerLoopStart 是固定周期触发，与回调耗时无关。
一帧场景重建要 100ms 左右，luatos 任务每轮只能消费一条事件，
而常驻 20ms 定时器每秒产生 50 条 —— 事件池入不敷出，
先刷 "no free static event"，几分钟后动态事件耗尽，
直接触发 "task event too much" 断言死机（复位原因 6）。
]]
local function slide_stop()
    if slide_timer then
        sys.timerStop(slide_timer)
        slide_timer = nil
    end
end

local function slide_step()
    if not slide.running then
        slide_stop()
        return
    end
    slide.t = slide.t + 20
    local k = draw.ease_in_out(slide.t / slide.dur)
    fc_x = math.floor(slide.from + (slide.to - slide.from) * k + 0.5)
    forecast.set_x(fc_x)
    if slide.t >= slide.dur then
        slide.running = false
        fc_x = slide.to
        forecast.set_x(fc_x)
        if not fc_open then forecast.hide() end
        slide_stop()
    end
end

local function slide_begin(from, to)
    slide.running, slide.from, slide.to, slide.t = true, from, to, 0
    if not slide_timer then
        slide_timer = sys.timerLoopStart(slide_step, 20)
    end
end

-- ==================== 帧间隔 ====================

--[[单调毫秒时钟（所有动画速度都建立在这个值上，量错一次全盘皆错）

**不要用 mcu.ticks() 当毫秒用**：Air1602 上它的单位不是 1ms（实测约 20ms/tick，≈50Hz），
直接相减得到的是"tick 数"，帧间隔会被缩小 20 倍 —— 真机上的现象就是
"人物和小动物几乎不动，不细看以为静止"（PC 模拟器 1ms/tick，所以自检看不出来）。

mcu.ticks2(0) 返回 (秒, 微秒)，是可靠口径（工程里 sip_audio / sip_selftest 同样用它）。
老固件没有 ticks2 时退到 mcu.hz() 折算；两者都没有（PC 自检 mock）按 1ms/tick。]]
local function now_ms()
    if mcu and mcu.ticks2 then
        local ok, s, us = pcall(mcu.ticks2, 0)
        if ok and type(s) == "number" then
            return s * 1000 + (tonumber(us) or 0) / 1000
        end
    end
    local ok, t = pcall(mcu.ticks)
    if not ok or type(t) ~= "number" then return nil end
    local hz = 1000
    if mcu and mcu.hz then
        local ok2, h = pcall(mcu.hz)
        if ok2 and type(h) == "number" and h > 0 then hz = h end
    end
    return t * 1000 / hz
end

local last_ms

local function dt_ms()
    local ms = now_ms()
    if not ms then return 100 end
    if not last_ms then last_ms = ms return 100 end
    local d = ms - last_ms
    last_ms = ms
    -- 卡顿超过 1.5 秒（切页面、刚开机、被后台任务抢占）按 100ms 记，
    -- 否则角色会顺着这一大段 dt 瞬移一大截
    if d <= 0 or d > 1500 then return 100 end
    return d
end

-- ==================== 预报页滑动 ====================

local function open_forecast()
    if fc_open then return end
    fc_open = true
    fc_x = W
    forecast.set_x(fc_x)
    forecast.show()
    slide_begin(W, 0)
    log.info("ui_main", "打开七天预报")
end

local function close_forecast()
    if not fc_open then return end
    fc_open = false
    slide_begin(fc_x, W)
end

-- ==================== 触摸 ====================

local tp = { x = 0, y = 0, down_x = 0, down_y = 0 }

local function actor_hit(x, y)
    return x > 250 and x < 810 and y > 180 and y < 500
end

local function switch_actor()
    local kind = actor.next_kind(a.kind)
    local x = (kind == "cyclist") and conf.actor.x or a.x
    a = actor.new(kind, x)
    log.info("ui_main", "切换形象", kind, actor.NAMES[kind] or "")
end

local function on_touch(state, x, y)
    if state == airui.TP_DOWN then
        tp.down_x, tp.down_y, tp.x, tp.y = x, y, x, y
        return
    end

    if state == airui.TP_HOLD then
        tp.x, tp.y = x, y
        return
    end

    if state ~= airui.TP_UP then return end

    -- 滑动动画期间不再接收新手势：预报页此刻有一半在屏幕外，
    -- 再来一次拖动容易和 LVGL 自己的滚动叠在一起（画面抖一下）
    if slide.running then return end

    -- 抬手点的坐标有的驱动会给 0，0：非 0 才更新
    if x and x > 0 then tp.x = x end
    if y and y > 0 then tp.y = y end

    local dx, dy = tp.x - tp.down_x, tp.y - tp.down_y

    if math.abs(dx) > 70 and math.abs(dx) > math.abs(dy) * 1.3 then
        if dx < 0 then
            open_forecast()
        else
            close_forecast()
        end
        return
    end

    -- 点击（容差 22px，避免手指轻微抖动被判成滑动）
    if math.abs(dx) < 22 and math.abs(dy) < 22 then
        if fc_open then return end
        if actor_hit(tp.x, tp.y) then
            switch_actor()
        elseif tp.x > 880 and tp.y < 120 then
            sys.publish("WEATHER_REQUEST")
            log.info("ui_main", "手动刷新天气")
        end
    end
end

-- ==================== 主循环 ====================

-- 帧率统计：主循环名义 10fps，一帧要重建 ~150 个图元，
-- 真机掉到 5fps 以下就会"一顿一顿"。每 50 帧打一条，方便对照日志排查。
local stat_n, stat_ms = 0, 0

local function tick()
    local dt = dt_ms()
    local now = time_util.now()

    env = scene.env(now, wx)
    actor.update(a, dt, env)
    scene.update_sky(env)
    -- 预报页的背景要跟桌面同一片天，天空翻页时同步过去（内部按颜色缓存）
    forecast.set_sky(env)

    -- 预报页盖住桌面时不必刷新场景，省一半 CPU；HUD 在页面后面也看不见
    if not fc_open then
        scene.tick(dt, env, a)
        hud.refresh(now, wx, room_state)
        hud.draw_icons(env, wx)
    end

    stat_n, stat_ms = stat_n + 1, stat_ms + dt
    if stat_n >= 50 then
        log.info("ui_main", "帧率", string.format("%.1f fps", stat_n * 1000 / stat_ms))
        stat_n, stat_ms = 0, 0
    end
end

-- ==================== 启动 ====================

function M.start()
    root = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = 0x081018, radius = 0, border_width = 0,
    })

    a = actor.new(conf.actor.default, conf.actor.x)

    scene.build(root)
    hud.build(root)
    forecast.build(root)

    -- 先跑一帧，别让首屏停在空白上（天气数据随后到）
    env = scene.env(time_util.now(), wx)
    scene.update_sky(env)
    forecast.set_sky(env)
    scene.tick(100, env, a)
    hud.refresh(time_util.now(), wx, room_state)
    hud.draw_icons(env, wx)

    -- 触摸：只记坐标，UI 操作留给下面的回调（输入上下文里改控件不安全）
    airui.touch_subscribe(on_touch)

    -- 天气
    sys.subscribe("WEATHER_UPDATED", function(d)
        if type(d) ~= "table" then return end
        wx = d
        forecast.set_data(d)
        if env then hud.draw_icons(env, d) end
        log.info("ui_main", "天气更新", tostring(d.city), tostring(d.condition),
            tostring(d.temp), d.demo and "(离线)" or "")
    end)
    sys.publish("WEATHER_REQUEST")

    -- 房间温湿度：独立任务，避免 I2C 阻塞动画
    sys.taskInit(function()
        while true do
            local now = time_util.now()
            local t, h = room.read((wx and wx.temp) or 20, now.hour_f)
            room_state = { temp = t, humi = h }
            sys.wait(5000)
        end
    end)

    -- 主循环：10fps。角色/云/雨雪都在这一拍里推进。
    -- 用「跑完再等」而不是 timerLoopStart：固定周期定时器不管回调花了多久都照样
    -- 触发，一帧要 100ms 时事件生产速度就超过消费速度，事件池几分钟内耗尽，
    -- 最终 "task event too much" 断言死机。sys.wait 是从本帧结束才计时，天然不积压。
    sys.taskInit(function()
        while true do
            local ok, err = pcall(tick)
            if not ok then
                log.error("ui_main", "主循环异常", tostring(err))
            end
            sys.wait(100)
        end
    end)

    -- 滑动动画（20ms 一步）不在这里常驻，由 slide_begin() 按需启停

    -- 底部操作提示 10 秒后收起，避免常年挡在草地上
    sys.timerStart(function() hud.hide_hint() end, 10000)

    log.info("ui_main", "界面就绪", PROJECT, VERSION)
end

--- 供调试：当前角色形象
function M.actor_kind() return a and a.kind end

--- 供调试：当前角色完整状态（x / state / tx），排障时看"为什么它不回窝"
function M.actor_state() return a end

return M
