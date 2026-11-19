--[[
触摸兜底分发（不依赖 LVGL 命中测试）

为什么需要：
  LVGL 的 on_click 只在「热区被 LVGL 命中」时触发：命中要求对象 CLICKABLE 且
  坐标落在其 coords 内，全链路任何一环（indev、hit test、父级 scroll）不满足
  都表现为"点不动"，且没有任何日志。

这个模块做三件事：
  1) 诊断：订阅 AirUI 触摸事件，打印前若干次 state/x/y —— 有数据说明触摸硬件正常
     （问题只在命中），一条都不打印说明触摸根本没上报（tp / 接线 / 中断问题）。
  2) 兜底：自己维护热区矩形表，抬起时做矩形命中并回调。
  3) 按压反馈：DOWN 时命中的热区上挂 press(true)，UP 时 press(false)。
     固件的 on_click 只在 RELEASED 触发，按下到抬起这段时间屏幕没有任何变化，
     主观上就是"点了没反应"。高亮走这条 DOWN 通路，与点击通路互不干扰。

两条点击通路的关系（必须理解，否则一次点击会执行两次）：
  固件里 container/label/image 带 on_click 时**不注册 LVGL 事件**，改装了
  airui_release_select_event_cb，在 LV_EVENT_RELEASED 里调 CLICKED 回调
  （luat_airui_container.c:91）；本模块的 dispatch 是另一条，也在抬起时触发。
  两条通路都会调用同一个 Lua 闭包，所以每条通路执行前都必须过 gate()，
  同一次抬起只放行先到的那条。

坐标约定：登记时由 ui_widget 累加父链得到屏幕绝对坐标（本项目页面不滚动）。
]]

local M = {}

local GATE_MS = 60        -- 闸门窗口：同一次抬起只放行一次（两通路间隔约 10ms，人手连点 >100ms）
local MAX_MOVE = 24       -- 按下→抬起位移上限（px），超过视为滑动
local LONG_MS = 400       -- 长按判定（与固件 release-select 一致）
local LOG_TOUCH = 12      -- 只打印前 N 条触摸，避免刷屏
local LOG_TAP = 8         -- 命中/落空日志上限：串口是同步的，每条日志都在拖慢点击

local hits = {}           -- { x,y,w,h,fn,long_fn,press,tag,group }
-- 去重索引：fn → { [坐标键] = true }。弱键，回调随页面回收时自动清
local index = setmetatable({}, { __mode = "k" })
local down = nil
local pressed = nil
local press_seq = 0       -- 按压几代：兜底释放定时器校验用，避免撤掉下一次按压的高亮
local logged, fired, noisy = 0, 0, 0
local active = nil        -- 当前显示页（"wall"/"detail"）；隐藏页的热区不参与兜底分发

-- mcu.ticks() 返回 tick 数，不是毫秒；每秒 tick 数由 mcu.hz() 决定（本平台 ≈50）。
-- 不做这层换算，400ms 的长按会被算成 8 秒才触发。
local TICK_MS = nil
local function tick_ms()
    if not TICK_MS then
        local hz = 1000
        if mcu and mcu.hz then
            local ok, v = pcall(mcu.hz)
            if ok and type(v) == "number" and v > 0 then hz = v end
        end
        TICK_MS = 1000 / hz
    end
    return TICK_MS
end

local function now_ms()
    if mcu and mcu.ticks then
        local ok, v = pcall(mcu.ticks)
        if ok and type(v) == "number" then return v * tick_ms() end
    end
    return (os.time() or 0) * 1000
end

local function key_of(x, y)
    return x * 100003 + y
end

local function idx_add(fn, x, y)
    if not fn then return end
    local m = index[fn]
    if not m then m = {}; index[fn] = m end
    m[key_of(x, y)] = true
end

-- 增删热区后重建索引（O(n)，只在建页/收弹层时发生）
local function rebuild_index()
    index = setmetatable({}, { __mode = "k" })
    for i = 1, #hits do
        local it = hits[i]
        idx_add(it.fn or it.long_fn, it.x, it.y)
    end
end

--- 登记热区（绝对坐标）。long_fn 可选，按住超过 LONG_MS 时改调它。
--- 返回热区记录，调用方可后续补 press 回调（按压高亮）
function M.add(x, y, w, h, fn, tag, group, long_fn)
    if not fn and not long_fn then return end
    if not x or not y or not w or not h then return end
    if w <= 0 or h <= 0 then return end
    if fn then
        local m = index[fn]
        if m and m[key_of(x, y)] then return end
    end
    idx_add(fn or long_fn, x, y)
    local it = {
        x = x, y = y, w = w, h = h,
        fn = fn, long_fn = long_fn, tag = tag, group = group,
    }
    hits[#hits + 1] = it
    return it
end

--- 清空全部热区（整屏重建前调用）
function M.clear()
    hits = {}
    rebuild_index()
    down = nil
    M.release()
end

--- 按组删除（弹层关闭时只删弹层那一组）
function M.drop(group)
    if not group then return end
    local keep = {}
    for i = 1, #hits do
        if hits[i].group ~= group then keep[#keep + 1] = hits[i] end
    end
    hits = keep
    rebuild_index()
    M.release()
end

--- 设置当前显示页：只有该页与弹层组的热区能命中。
--- LVGL 会自动跳过 HIDDEN 对象，兜底表是静态坐标，必须在这里自己过滤，
--- 否则隐藏页同位置的按钮会被误触发。
function M.set_active(g)
    active = g
    down = nil
    M.release()
end

function M.count() return #hits end

--- 热区是否仍登记在案。页面/弹层销毁时 release/drop/clear 会把记录移出 hits，
--- 所以"记录不在了"等价于"控件已经回收"。延迟回调（如按压水膜 90ms 淡出）
--- 必须用它当存活判据：对已销毁的 airui 组件调 set_color 会打 C 层错误
--- access destroyed airui component，pcall 拦不住。
function M.alive(it)
    if not it then return false end
    for i = 1, #hits do
        if hits[i] == it then return true end
    end
    return false
end

--- 松开按压高亮（页面切换/销毁前调用，避免高亮层留在已销毁的对象上）
function M.release()
    local p = pressed
    pressed = nil
    if p and p.press then pcall(p.press, false) end
end

--- 双通路闸门：固件的 release-select 通路与本模块兜底通路是同一次抬起的两条独立路径，
--- 每条执行回调前都过这里，只有先到的那条放行。放行后 60ms 内不再放行：
--- 两条通路间隔约 10ms（兜底还多了 10ms 定时器），而人手两次点击最快也在 100ms 以上。
--- 用"定时器重新上膛"而不是比较时间戳，避免 mcu.ticks 不可用时退化成秒级精度。
local armed = true
function M.gate()
    if not armed then return false end
    armed = false
    sys.timerStart(function() armed = true end, GATE_MS)
    return true
end

--- 给回调加闸门（ui_widget 使用）：包裹后的函数同时交给 LVGL 与兜底表，两条通路共用。
--- 幂等：同一个回调被重复包装不会叠加闸门（否则第二次必然被自己拦住）
local wrapped = setmetatable({}, { __mode = "k" })
function M.guard(fn)
    if not fn or wrapped[fn] then return fn end
    local g = function(...)
        if not M.gate() then return false end
        fn(...)
        return true
    end
    wrapped[g] = true
    return g
end

local function visible(it)
    local g = it.group
    if g == nil or g == "sheet" then return true end
    return active == nil or g == active
end

--- 自上而下找命中的热区（后登记的在上层）
local function hit_at(x, y)
    for i = #hits, 1, -1 do
        local it = hits[i]
        if visible(it)
            and x >= it.x and x < it.x + it.w and y >= it.y and y < it.y + it.h then
            return it
        end
    end
    return nil
end

local function fire(fn, tag, x, y)
    fired = fired + 1
    -- fn 由 ui_widget.guard 包过，闸门在闭包内部：本次抬起若已被 release-select 通路处理，
    -- 这里返回 false，不会再执行一次业务回调
    local ok, ran = pcall(fn)
    if not ok then
        log.error("uit", "点击回调异常", tostring(ran))
    elseif noisy < LOG_TAP then
        noisy = noisy + 1
        log.info("uit", "命中", tag or "-", x, y, "#" .. fired)
    end
    return true
end

local function dispatch(x, y, dur)
    local it = hit_at(x, y)
    if not it then
        if noisy < LOG_TAP then
            noisy = noisy + 1
            log.info("uit", "落空", x, y, "热区数", #hits)
        end
        return false
    end
    if it.long_fn and dur and dur >= LONG_MS then
        return fire(it.long_fn, (it.tag or "-") .. ":long", x, y)
    end
    if it.fn then return fire(it.fn, it.tag, x, y) end
    return false
end

--- 订阅触摸。返回是否订阅成功
function M.start()
    if M.started then return true end
    if not (airui and airui.touch_subscribe) then
        log.warn("uit", "固件没有 airui.touch_subscribe，兜底分发与按压反馈不可用")
        return false
    end

    local ok, ret = pcall(airui.touch_subscribe, function(state, x, y)
        if state == 1 then                 -- AIRUI_TOUCH_STATE_DOWN
            down = { x = x, y = y, t = now_ms() }
            if logged < LOG_TOUCH then
                logged = logged + 1
                log.info("uit", "触摸 DOWN", x, y, "#" .. logged)
            end
            -- 按下立刻高亮：只改颜色，不建/毁对象，可以在输入回调里做
            local it = hit_at(x, y)
            if it and it.press then
                M.release()
                press_seq = press_seq + 1
                pressed = { press = it.press, seq = press_seq }
                pcall(it.press, true)
            end
        elseif state == 3 then             -- AIRUI_TOUCH_STATE_UP
            local d = down
            down = nil
            if logged < LOG_TOUCH then
                log.info("uit", "触摸 UP", x, y)
            end
            if not d then
                M.release()
                return
            end
            local dx, dy = x - d.x, y - d.y
            if dx * dx + dy * dy > MAX_MOVE * MAX_MOVE then
                M.release()
                return
            end
            --[[
            高亮不在抬起时立刻撤：业务回调多半是 later() 才建/切页面，
            抬起就撤会形成"亮 → 灭 → 页面出现"的断点。
            这里等 dispatch 之后由业务主动 release（M.open / M.back / close_sheet），
            300ms 兜底释放，避免点了空白返回时高亮一直亮着。
            ]]
            local px, py = d.x, d.y
            local dur = now_ms() - d.t
            local my = pressed and pressed.seq
            -- 不要停在 LVGL 输入回调栈里改界面，排进定时器（>=5ms）
            sys.timerStart(function()
                dispatch(px, py, dur)
                if my then
                    sys.timerStart(function()
                        if pressed and pressed.seq == my then M.release() end
                    end, 300)
                end
            end, 10)
        end
    end)

    M.started = (ok and ret) and true or false
    log.info("uit", "触摸订阅", M.started, "已登记热区", #hits)
    return M.started
end

return M
