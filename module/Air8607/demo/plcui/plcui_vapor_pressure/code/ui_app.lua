--[[
@module  ui_app
@summary plcui 界面门面：句柄缓存、事件处理表、切页与 500ms 数据刷新
@version 2.0.0
@date    2026.11.17
@author  蒋骞
@usage
本文件为 plcui_vapor_pressure 的界面层，负责：
1、持有 plcui.load 返回的 xml 实例，按「页面 + 组件 ID」缓存句柄；
2、main.xml 里每个 on-* 都在 handlers 表里注册同名函数（H.xxx）；
3、切页走「show -> 40ms 延时 -> 清句柄缓存 -> 重新取句柄」三件套，
   find 失败的句柄不缓存，避免对着失效句柄 set_text；
4、500ms 刷新一次：文本绑定走 ui_vars，步骤条 / 卡片灯 / 曲线 / 表格在这里算；
5、工艺图上的三个动件单独算：液位块按液面高度切 11 张整块素材、活塞软塞
   按活塞位置切 11 个预置件、活塞杆按同档切 11 张不同长度的杆。
   三者共用一套档位（每档 11mm），阀开时"液面顶边 = 软塞下沿"，
   杆永远从电机接到软塞顶、不会从软塞下方露出来。

急停不做 set_disabled：按钮始终可点，由 vp_app 内部拒绝并打日志，
避免"按钮变灰却看不出原因"；复位按钮在任何页面、任何状态都可点。

本文件的对外接口有 4 个：
1、ui_app.handlers   事件处理表，传给 plcui.load 的 options.handlers
2、ui_app.init       绑定 xml 实例并做首次刷新
3、ui_app.show       切换页面
4、ui_app.refresh_cbfunc  定时刷新回调（boot_app 用 500ms 起循环）
]]

local ui_app = {}

local vp_app = require "vp_app"
local ui_vars = require "ui_vars"

local xml                  -- plcui.load 返回的界面实例
local page = "run"         -- 当前页面 ID
local cache = {}           -- 页面 -> { 组件 ID -> 句柄 }
local ready = {}           -- 页面 -> 句柄是否可取

local H = {}
ui_app.handlers = H

-- 版面常量，与 tools/ui_spec.py 必须一致
local CAR_SPAN, CAR_STEPS = 110, 10   -- 行程 110mm，11 个预置档位（每档 11mm）
local LIQ_SPAN, LIQ_MAX = 110, 10     -- 液面素材按活塞行程分档，每档 11mm，共 11 级

local car_idx = 0                     -- 当前滑块档位 0..10
local liq_idx = -1                    -- 当前液位档位，-1 表示尚未设置

-- ==================== 通用工具 ====================

--[[
打印 plcui 错误表的全部字段（真机日志只给一行，必须自己打全）

@api ui_app.show_err(tag, err)

@参数 string tag 日志标签
@参数 table err plcui 返回的错误表
]]
local function show_err(tag, err)
    if err == nil then
        return
    end
    if type(err) ~= "table" then
        log.warn(tag, err)
        return
    end
    log.warn(tag, string.format("%s|%s|id=%s|attr=%s|%s:%s",
        tostring(err.code), tostring(err.message), tostring(err.id),
        tostring(err.attribute), tostring(err.line), tostring(err.column)))
end
ui_app.show_err = show_err

-- 取当前页组件句柄；取不到不缓存（切页后旧句柄会失效）
local function find(id)
    local t = cache[page]
    if not t then
        return nil
    end
    local o = t[id]
    if o then
        return o
    end
    o = xml:find(page, id)
    if o ~= nil then
        t[id] = o
    end
    return o
end

local function set_text(id, text)
    local o = find(id)
    if o then
        o:set_text(text)
    end
end

local function set_src(id, src)
    local o = find(id)
    if o then
        o:set_src(src)
    end
end

local function set_hidden(id, hidden)
    local o = find(id)
    if o then
        o:set_hidden(hidden and true or false)
    end
end

-- ==================== 数据绑定 ====================

-- 按 ui_vars.text / image 把标量变量刷到界面
local function apply_bind(page_id, v)
    local list = ui_vars.text[page_id]
    if list then
        for i = 1, #list do
            local b = list[i]
            local val = v[b.var]
            if val ~= nil then
                local o = find(b.id)
                if o then
                    if b.fmt then
                        o:set_text(string.format(b.fmt, val) .. (b.suffix or ""))
                    else
                        o:set_text(tostring(val))
                    end
                end
            end
        end
    end
    local imgs = ui_vars.image[page_id]
    if imgs then
        for i = 1, #imgs do
            local b = imgs[i]
            set_src(b.id, v[b.var] and b.on or b.off)
        end
    end
end

-- 顶栏（每页同名元素）与六段步骤条
local function refresh_common(v)
    set_text(ui_vars.CLOCK_DATE_ID, os.date("%Y/%m/%d"))
    set_text(ui_vars.CLOCK_TIME_ID, os.date("%H:%M:%S"))
    set_text(ui_vars.BADGE_ID, v.badge)
    -- 状态文字与急停红胶囊同位互斥：label 改不了颜色，只能两个组件切显隐
    set_hidden(ui_vars.BADGE_ID, v.alarm)
    set_hidden(ui_vars.ALARM_ID, not v.alarm)
    for i = 1, #ui_vars.state do
        local s = ui_vars.state[i]
        set_src(s.id, s.map[v[s.var]] or s.map.idle)
    end
    for i = 1, #ui_vars.CHIP_ID do
        local state = vp_app.chip_state(i)
        local src = ui_vars.CHIP_SRC[i]
        set_src(ui_vars.CHIP_ID[i], src[state] or src.g)
    end
end

-- 工艺图两个动态件：液位图与步进滑块
-- 都用"多件预置 + 切显隐"表达，因为目标固件 PLCUI 1.0.1
-- 既没有 image:set_size 也没有 widget:set_pos（两者都是 1.0.2 新增）。
local function refresh_plant(v)
    -- 液位：11 张整块素材，按液面高度（mm）切档，每档 11mm。
    -- 阀开时液面 = 活塞位置，阀关后液面定格，所以这里用 level 不是 pos。
    local idx = math.floor(v.level * LIQ_MAX / LIQ_SPAN + 0.5)
    if idx < 0 then
        idx = 0
    elseif idx > LIQ_MAX then
        idx = LIQ_MAX
    end
    if idx <= 0 then
        set_hidden("pv_liq", true)
    else
        if idx ~= liq_idx then
            local src = ui_vars.liq_src[idx + 1]
            if src then
                set_src("pv_liq", src)
                liq_idx = idx
            end
        end
        set_hidden("pv_liq", false)
    end

    -- 软塞与活塞杆：11 个预置档位，每档 11mm，只切显隐
    local pos = v.pos
    if pos < 0 then
        pos = 0
    elseif pos > CAR_SPAN then
        pos = CAR_SPAN
    end
    local ci = math.floor(pos * CAR_STEPS / CAR_SPAN + 0.5)
    if ci < 0 then
        ci = 0
    elseif ci > CAR_STEPS then
        ci = CAR_STEPS
    end
    if ci ~= car_idx then
        -- 软塞与杆必须同档：杆的长度就是按"电机底 -> 该档软塞顶"烘的
        set_hidden(ui_vars.car_id[car_idx + 1], true)
        set_hidden(ui_vars.rod_id[car_idx + 1], true)
        set_hidden(ui_vars.car_id[ci + 1], false)
        set_hidden(ui_vars.rod_id[ci + 1], false)
        car_idx = ci
    end
end

-- 环节手动页：六张卡片的灯与状态文字
local function refresh_man()
    for i = 1, #ui_vars.card_lamp do
        local state, text = vp_app.card_state(i)
        set_src(ui_vars.card_lamp[i], ui_vars.card_map[state] or "im_lamp_idle")
        set_text(ui_vars.card_text[i], text)
    end
end

-- 膨胀参数页：记录表格 + 拟合曲线
local function refresh_test(v)
    apply_bind("test", v)
    local n = vp_app.record_count()
    local tbl = find("ts_tbl")
    local mea, fit = {}, {}
    local tsum = 0
    for i = 1, 3 do
        local r = vp_app.record(i)
        if r then
            tsum = tsum + r.t
            local y = v.press0 + v.slope * r.x
            mea[i] = r.p
            fit[i] = y
            if tbl then
                tbl:set_cell(i + 1, 2, string.format("%.1f", r.p))
                tbl:set_cell(i + 1, 3, string.format("%.1f", r.t))
                tbl:set_cell(i + 1, 4, string.format("%.3f", r.x))
                tbl:set_cell(i + 1, 5, string.format("%.2f", r.p - y))
            end
        else
            mea[i] = 0
            fit[i] = 0
        end
    end
    if tbl then
        if n >= 3 and v.result > 0 then
            tbl:set_cell(5, 2, string.format("%.1f", v.result))
            tbl:set_cell(5, 3, string.format("%.1f", tsum / 3))
            tbl:set_cell(5, 4, "--")
            tbl:set_cell(5, 5, string.format("%.2f", v.rep))
        else
            tbl:set_cell(5, 2, "---")
            tbl:set_cell(5, 3, "---")
            tbl:set_cell(5, 4, "--")
            tbl:set_cell(5, 5, "---")
        end
    end
    local chart = find("ts_chart")
    if chart then
        local ok, err = chart:set_values("mea", mea)
        if not ok then
            show_err("ui", err)
        end
        ok, err = chart:set_values("fit", fit)
        if not ok then
            show_err("ui", err)
        end
    end
end

-- ==================== 刷新与切页 ====================

--[[
500ms 定时刷新回调

@api ui_app.refresh_cbfunc()
]]
function ui_app.refresh_cbfunc()
    if not xml or not ready[page] then
        return
    end
    local v = vp_app.view()
    refresh_common(v)
    if page == "run" then
        apply_bind("run", v)
        refresh_plant(v)
    elseif page == "man" then
        apply_bind("man", v)
        refresh_man()
    elseif page == "test" then
        refresh_test(v)
    end
end

--[[
切页：show 只登记待切，40ms 后新页句柄才可用

@api ui_app.show(target)

@参数 string target 目标页面 ID run / man / test
]]
function ui_app.show(target)
    if not xml then
        return
    end
    if not xml:show(target) then
        log.warn("ui", "切页失败", target)
        return
    end
    page = target
    cache = {}            -- 旧页句柄全部作废，一次性清空
    ready[target] = false
    sys.timerStart(ui_app.page_ready_cbfunc, 40)
end

--[[
切页 40ms 后的收尾：标记句柄可用并立刻刷一次

@api ui_app.page_ready_cbfunc()
]]
function ui_app.page_ready_cbfunc()
    cache[page] = {}
    ready[page] = true
    car_idx = 0
    liq_idx = -1
    ui_app.refresh_cbfunc()
end

--[[
绑定 xml 实例并做首次刷新

@api ui_app.init(doc)

@参数 table doc plcui.load 返回的界面实例
]]
function ui_app.init(doc)
    xml = doc
    page = "run"
    cache = {}
    ready = {}
    ready["run"] = true
    cache["run"] = {}
    ui_app.refresh_cbfunc()
    log.info("ui", "界面层已就绪", "首页 run")
end

-- ==================== 事件处理 ====================

local STAGE_OF = { mv_g1 = 1, mv_g2 = 2, mv_g3 = 3, mv_g4 = 4, mv_g5 = 5, mv_g6 = 6 }
local DEV = {
    dv_v1o = "v1_open", dv_v1c = "v1_close",
    dv_v2o = "v2_open", dv_v2c = "v2_close",
    dv_up = "up", dv_down = "down", dv_mstop = "motor_stop",
}
local STEP = { dv_s5 = 5, dv_s10 = 10, dv_s25 = 25 }
local JUMP = { dv_nup = 1, dv_ndn = -1 }

-- 事件后立刻刷一次，避免等到下一个 500ms 才看到反馈
local function touch()
    ui_app.refresh_cbfunc()
end

local function on_go_run()
    ui_app.show("run")
end

local function on_go_man()
    ui_app.show("man")
end

local function on_go_test()
    ui_app.show("test")
end

local function on_auto_start()
    vp_app.auto_start()
    touch()
end

local function on_auto_pause()
    vp_app.auto_pause()
    touch()
end

local function on_auto_stop()
    vp_app.auto_stop()
    touch()
end

local function on_reset()
    vp_app.reset()
    touch()
end

local function on_estop()
    vp_app.estop()
    touch()
end

local function on_st_go(ev)
    local idx = STAGE_OF[ev.id]
    if idx then
        vp_app.stage_start(idx)
    end
    touch()
end

local function on_st_halt(ev)
    local idx = STAGE_OF[("mv_g" .. string.sub(ev.id, 5))]
    if idx and vp_app.st.stage == idx then
        vp_app.stage_stop()
    else
        log.info("ui", "该环节当前未运行", ev.id)
    end
    touch()
end

local function on_dev_op(ev)
    local name = DEV[ev.id]
    if name then
        vp_app.device_op(name)
    end
    touch()
end

local function on_dev_step(ev)
    local mm = STEP[ev.id]
    if mm then
        vp_app.set_step(mm)
    end
    touch()
end

local function on_dev_jump(ev)
    local dir = JUMP[ev.id]
    if dir then
        vp_app.device_jump(dir)
    end
    touch()
end

local function on_test_start()
    vp_app.auto_start()
    touch()
end

local function on_test_stop()
    vp_app.auto_stop()
    touch()
end

local function on_test_calc()
    vp_app.calc()
    touch()
end

local function on_heat_on()
    vp_app.set_heater(true)
    touch()
end

local function on_heat_off()
    vp_app.set_heater(false)
    touch()
end

local function on_temp_minus()
    vp_app.temp_step(-1)
    touch()
end

local function on_temp_plus()
    vp_app.temp_step(1)
    touch()
end

H.go_run = on_go_run
H.go_man = on_go_man
H.go_test = on_go_test
H.auto_start = on_auto_start
H.auto_pause = on_auto_pause
H.auto_stop = on_auto_stop
H.reset = on_reset
H.estop = on_estop
H.st_go = on_st_go
H.st_halt = on_st_halt
H.dev_op = on_dev_op
H.dev_step = on_dev_step
H.dev_jump = on_dev_jump
H.heat_on = on_heat_on
H.heat_off = on_heat_off
H.temp_minus = on_temp_minus
H.temp_plus = on_temp_plus
H.test_start = on_test_start
H.test_stop = on_test_stop
H.test_calc = on_test_calc

return ui_app
