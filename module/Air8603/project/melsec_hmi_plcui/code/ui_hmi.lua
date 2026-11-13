--[[
@module  ui_hmi
@summary plcui 界面层（XML 布局 + 数据绑定），替代原工程 airui 的 ui_main/ui_dash/ui_trend/ui_alarm/ui_settings
@version 1.0.0
@date    2026.11.11

职责边界：
  只做三件事 —— 切页、把业务数据写进控件、把点击事件转给业务模块。
  采集/报警/存储/语音仍然由 app_data / app_alarm / app_store / app_sound 负责，一行没改。

四个约束（都是 plcui 自身的机制，踩过才知道）：
  1. xml:find(page, id) 只认"当前页"，切页后旧句柄全部失效，所以切页时清空句柄缓存和文本缓存；
  2. xml:show() 在事件回调里是延迟生效的（分发结束后才建页），因此切页后要延迟几十毫秒再刷新；
  3. 只有 image 控件可点击（on-click），所以按钮都是 image + 3 态小图，静态文字直接烘进 PNG；
  4. 每次 set_text 都会让 LVGL 标脏重绘，所以这里用 last 缓存做"值不变不写"。

为什么不放整屏背景图：
  1024×600 的位图解码要 2.4MB 显存级缓存，还受 LVGL 图片缓存上限约束；
  改用 page 底色 + container(圆角/描边) + 小图，绘制快、flash 占用小。
]]
local M = {}

local conf  = require "conf"
local data  = require "app_data"
local alarm = require "app_alarm"
local store = require "app_store"

local STEP = 1.0                 -- 阈值步进（℃）

local xml                        -- plcui 文档句柄
local page = "dash"              -- 当前页 id
local finded = {}                -- id -> 控件句柄（false 表示没有）
local last = {}                  -- id -> 上次写入值（文本/图片/选中态）
local drawn = 0                  -- 当前页图表已绘制的历史点数
local chart_ready = nil          -- 图表已完成整串同步的页面 id
local edit = {}                  -- 阈值编辑副本
local dflt = {}                  -- 出厂默认阈值
local ch_show = { true, true }   -- 曲线通道显示开关

local SERIES = { "ch1", "ch2" }
local PILL_RES = { [0] = "pill_ok", [1] = "pill_warn", [2] = "pill_alarm" }
local LV_NAME  = { [0] = "正常", [1] = "预警", [2] = "报警" }
local NAV_TARGET = {
    nav_dash  = "dash",
    nav_trend = "trend",
    nav_alarm = "alarm",
    nav_dev   = "dev",
    nav_set   = "set",
}

-- ============ 基础读写 ============

--[[
取当前页控件句柄（带缓存）
@param id string 控件 id
@return userdata|nil 句柄
]]
local function w(id)
    local o = finded[id]
    if o ~= nil then
        return o or nil
    end
    local obj = xml and xml:find(page, id)
    finded[id] = obj or false
    return obj
end

--[[
写文本（值没变就不写，避免无谓重绘）
@param id string 控件 id
@param s string 文本
@return nil
]]
local function set_text(id, s)
    s = tostring(s)
    if last[id] == s then
        return
    end
    local o = w(id)
    if not o then
        return
    end
    last[id] = s
    o:set_text(s)
end

--[[
换图片资源（值没变就不换）
@param id string 控件 id
@param res string XML 里声明的 image 资源 id
@return nil
]]
local function set_res(id, res)
    local k = id .. "#res"
    if last[k] == res then
        return
    end
    local o = w(id)
    if not o then
        return
    end
    last[k] = res
    o:set_src(res)
end

--[[
设置显隐（值没变就不写）
@param id string 控件 id
@param hidden boolean true 隐藏
@return nil
]]
local function set_hidden(id, hidden)
    local k = id .. "#hid"
    hidden = hidden and true or false
    if last[k] == hidden then
        return
    end
    local o = w(id)
    if not o then
        return
    end
    last[k] = hidden
    o:set_hidden(hidden)
end

--[[
设置选中态（image 的 src-checked）
@param id string 控件 id
@param on boolean 是否选中
@return nil
]]
local function set_chk(id, on)
    local k = id .. "#chk"
    on = on and true or false
    if last[k] == on then
        return
    end
    local o = w(id)
    if not o then
        return
    end
    last[k] = on
    o:set_checked(on)
end

--[[
格式化一位小数；非数字返回占位符
@param v number|nil 数值
@return string
]]
local function f1(v)
    if type(v) ~= "number" then
        return "--.-"
    end
    return string.format("%.1f", v)
end

--[[
切页后清空缓存（句柄和文本都跟着页面重建）
@return nil
]]
local function reset_cache()
    finded = {}
    last = {}
    chart_ready = nil
end

--[[
把 page 变量对齐到 plcui 的真实当前页。
xml:find 只认当前页，句柄缓存必须跟着页面走；
切页在事件回调里是延迟生效的，所以以 status().page 为准，不靠乐观赋值。
@return nil
]]
local function sync_page()
    if not xml then
        return
    end
    local st = plcui.status()
    local cur = st and st.page
    if not cur or cur == page then
        return
    end
    page = cur
    reset_cache()
    drawn = 0
end

-- ============ 曲线 ============

--[[
把历史数据整体灌进图表（切页进入时用，长度必须等于 point-count）
@param id string 图表控件 id
@param pc number point-count
@return number 已绘制的历史点数
]]
local function sync_chart(id, pc)
    local chart = w(id)
    if not chart then
        return 0
    end
    chart:set_range(conf.scale.val_min, conf.scale.val_max)

    local n = 0
    for si = 1, 2 do
        local hist = data.hist[si] or {}
        local cnt = #hist
        if cnt > n then
            n = cnt
        end
        local arr = {}
        local pad = pc - cnt
        if pad > 0 then
            -- 历史还没攒够：左侧用最早的值铺平，避免从 0 拉一条误导性的斜线
            local fill = hist[1] or conf.scale.val_min
            for _ = 1, pad do
                arr[#arr + 1] = fill
            end
        end
        local from = cnt - pc + 1
        if from < 1 then
            from = 1
        end
        for k = from, cnt do
            arr[#arr + 1] = hist[k]
        end
        chart:set_values(SERIES[si], arr)
        chart:set_series_hidden(SERIES[si], not ch_show[si])
    end
    return n
end

--[[
增量喂点：只在有新采样时调 add_point（每点一次，比整串 set_values 省得多）
@param id string 图表控件 id
@param pc number point-count
@return nil
]]
local function feed_chart(id, pc)
    local n = #(data.hist[1] or {})
    if n == drawn then
        return
    end
    if n < drawn then
        -- 历史被清空过，整串重灌
        drawn = sync_chart(id, pc)
        return
    end
    local chart = w(id)
    if not chart then
        return
    end
    while drawn < n do
        drawn = drawn + 1
        for si = 1, 2 do
            local hist = data.hist[si]
            local v = (hist and hist[drawn]) or conf.scale.val_min
            chart:add_point(SERIES[si], v)
        end
    end
end

-- ============ 各页刷新 ============

--[[
总览页：两个实时卡片 + 迷你趋势
@return nil
]]
local function refresh_dash()
    for i = 1, #conf.chs do
        local p = "ch" .. i
        local ch = conf.chs[i]
        local v = data.online and data.val[i] or nil

        set_text(p .. "_val", f1(v))
        set_res(p .. "_pill", PILL_RES[alarm.state[i] or 0] or "pill_ok")
        local u = conf.scale.unit
        set_text(p .. "_thr", "预警 " .. f1(ch.warn) .. " " .. u .. " · 报警 " .. f1(ch.alarm) .. " " .. u)

        local rec
        for k = 1, #alarm.recs do
            if alarm.recs[k].ch == i then
                rec = alarm.recs[k]
                break
            end
        end
        if rec then
            set_text(p .. "_time", string.format("%s %s · %s %s %s",
                os.date("%m-%d %H:%M", rec.t), LV_NAME[rec.level] or "-",
                rec.acked and "已确认" or "未确认", f1(rec.val), conf.scale.unit))
        else
            set_text(p .. "_time", "无报警记录")
        end
    end

    feed_chart("dash_chart", 150)
end

--[[
趋势页：大图 + 通道开关
@return nil
]]
local function refresh_trend()
    feed_chart("trend_chart", 300)
    set_chk("ch1_toggle", ch_show[1])
    set_chk("ch2_toggle", ch_show[2])
    set_text("trend_info", string.format("CH1 %s %s · CH2 %s %s · 已存 %d/%d 点",
        f1(data.online and data.val[1] or nil), conf.scale.unit,
        f1(data.online and data.val[2] or nil), conf.scale.unit,
        #(data.hist[1] or {}), conf.trend.cap))
end

--[[
报警页：表格 + 状态条
@return nil
]]
local function refresh_alarm()
    local unacked = 0
    for k = 1, #alarm.recs do
        if not alarm.recs[k].acked then
            unacked = unacked + 1
        end
    end

    -- 表格只在记录变化时重写，避免 48 个单元格每 500ms 全刷。
    -- 记录满 8 条后新报警是"顶掉最旧一条"，条数不变，所以要把首条的时间/值也算进签名
    local top = alarm.recs[1]
    local sig = table.concat({
        #alarm.recs, unacked, alarm.muted and 1 or 0,
        top and top.t or 0, top and string.format("%.1f", top.val or 0) or "-",
    }, "/")
    if last["alarm_sig"] ~= sig then
        last["alarm_sig"] = sig
        local tb = w("alarm_table")
        if tb then
            for r = 1, conf.alarm.max do
                local rec = alarm.recs[r]
                if rec then
                    tb:set_cell(r + 1, 1, os.date("%m-%d %H:%M:%S", rec.t))
                    tb:set_cell(r + 1, 2, rec.name or ("CH" .. rec.ch))
                    tb:set_cell(r + 1, 3, LV_NAME[rec.level] or "-")
                    tb:set_cell(r + 1, 4, f1(rec.val))
                    tb:set_cell(r + 1, 5, f1(rec.thr))
                    tb:set_cell(r + 1, 6, rec.acked and "已确认" or "未确认")
                else
                    for c = 1, 6 do
                        tb:set_cell(r + 1, c, "")
                    end
                end
            end
        end
    end

    local lv = alarm.max_level()
    set_text("alarm_state", string.format("当前 %s · 未确认 %d 条 · %s",
        LV_NAME[lv] or "-", unacked, alarm.muted and "已消音" or "声音开启"))
    set_chk("alarm_mute", alarm.muted)
end

--[[
设备页：连接图上两处「实测」框显示实时温度
@return nil
]]
local function refresh_dev()
    for i = 1, #conf.chs do
        local s = f1(data.online and data.val[i] or nil)
        if s ~= "--.-" then
            s = s .. conf.scale.unit        -- 图上两处实测框只有数字，单位补在这里
        end
        set_text("tt" .. i .. "_val", s)
    end
end

--[[
设备页链路流光：静态走线不动，只换叠在上面的 8 帧小图。
4 个图层各自带相位偏移，避免完全同步显得像复制粘贴。
@return nil
]]
local ANIM_FRAMES = 8
local ANIM_LAYERS = {
    { id = "flow485a", prefix = "f485a_", offset = 0 },  -- 请求 HMI → PLC
    { id = "flow485b", prefix = "f485b_", offset = 4 },  -- 应答 PLC → HMI，错开半个周期
    { id = "flowma1",  prefix = "fma1_",  offset = 0 },  -- 变送器 1 黄线 → AD0 → D0
    { id = "flowma2",  prefix = "fma2_",  offset = 3 },  -- 变送器 2 黄线 → AD1 → D1，晚一点
}
local anim_i = 1
local anim_flagged = false        -- 只在设备页首次出光时打一条日志，方便现场确认动效真的在跑

local function anim_tick()
    if page ~= "dev" then
        return                              -- 只在设备页跑，其他页不产生 set_src
    end
    -- 断线时链路没有数据流，把光点收起来，比继续流光更贴现场
    local hide = not data.online
    for i = 1, #ANIM_LAYERS do
        set_hidden(ANIM_LAYERS[i].id, hide)   -- set_hidden 自带去重，切页后缓存清空会自动重设
    end
    if hide then
        return
    end
    if not anim_flagged then
        anim_flagged = true
        log.info("ui", "flow anim running, frames", ANIM_FRAMES)
    end
    anim_i = anim_i % ANIM_FRAMES + 1
    for i = 1, #ANIM_LAYERS do
        local L = ANIM_LAYERS[i]
        local f = (anim_i + L.offset - 1) % ANIM_FRAMES + 1
        set_res(L.id, L.prefix .. f)
    end
end

--[[
设置页：编辑副本 + 当前生效值
@return nil
]]
local function refresh_set()
    for i = 1, #conf.chs do
        local e = edit[i]
        if e then
            set_text("ch" .. i .. "_warn_val", f1(e.warn))
            set_text("ch" .. i .. "_alarm_val", f1(e.alarm))
        end
    end
    set_text("set_sum", string.format("CH1 预警 %s / 报警 %s %s · CH2 预警 %s / 报警 %s %s",
        f1(conf.chs[1].warn), f1(conf.chs[1].alarm), conf.scale.unit,
        f1(conf.chs[2].warn), f1(conf.chs[2].alarm), conf.scale.unit))

    set_text("set_info", string.format("量程 %s~%s %s · 采集 %d ms · 采样 %d ms · 报警记录 %d 条",
        f1(conf.scale.val_min), f1(conf.scale.val_max), conf.scale.unit,
        conf.poll_ms, conf.trend.sample_ms, conf.alarm.max))
end

-- ============ 事件 ============

local handlers = {}

--[[
左侧导航（5 个按钮共用一个 handler，靠 evt.id 区分）
@param evt table {type, page, id}
@return nil
]]
handlers.nav = function(evt)
    local target = NAV_TARGET[evt.id]
    if not target or target == page then
        return
    end
    if not xml:show(target) then
        log.warn("ui_hmi", "切页失败", tostring(target))
        return
    end

    page = target
    reset_cache()
    drawn = 0

    -- xml:show 在事件回调里延迟生效，等分发结束、新页控件建好再刷。
    -- 这 60ms 内 xml:find 可能拿不到新页控件，w() 会把 nil 记进缓存，
    -- 所以刷之前再清一次，避免流光图层被永久记成"找不到"。
    sys.timerStart(function()
        reset_cache()
        M.refresh()
    end, 60)
end

--[[
顶栏喇叭：静音 / 解除静音切换
@return nil
]]
handlers.toggle_mute = function()
    if alarm.muted then
        alarm.unmute()
    else
        alarm.mute()
    end
    M.refresh()
end

--[[
报警页消音按钮：只静音
@return nil
]]
handlers.alarm_mute = function()
    alarm.mute()
    M.refresh()
end

--[[
报警复位：全部标记已确认 + 静音
@return nil
]]
handlers.alarm_ack = function()
    alarm.ack()
    M.refresh()
end

--[[
清空报警记录（不动当前报警状态）
@return nil
]]
handlers.alarm_clear = function()
    alarm.clear()
    M.refresh()
end

--[[
阈值 +/-（8 个按钮共用一个 handler，evt.id 形如 ch1_warn_up）
@param evt table {type, page, id}
@return nil
]]
handlers.step = function(evt)
    local ch, kind, dir = string.match(evt.id or "", "^ch(%d)_(%a+)_(%a+)$")
    local i = tonumber(ch)
    if not i or not edit[i] then
        return
    end

    local e = edit[i]
    local d = (dir == "up") and STEP or -STEP
    local vmin, vmax = conf.scale.val_min, conf.scale.val_max
    local raw

    if kind == "warn" then
        raw = e.warn + d
        local top = e.alarm - STEP          -- 预警必须比报警低一档
        if raw > top then
            raw = top
        end
        if raw < vmin then
            raw = vmin
        end
        e.warn = math.floor(raw * 10 + 0.5) / 10
    elseif kind == "alarm" then
        raw = e.alarm + d
        local low = e.warn + STEP           -- 报警必须比预警高一档
        if raw < low then
            raw = low
        end
        if raw > vmax then
            raw = vmax
        end
        e.alarm = math.floor(raw * 10 + 0.5) / 10
    else
        return
    end

    refresh_set()
end

--[[
保存阈值：写入 conf.chs（采集/报警立即用新值）+ fskv
@return nil
]]
handlers.save = function()
    for i, e in ipairs(edit) do
        if conf.chs[i] then
            conf.chs[i].warn = e.warn
            conf.chs[i].alarm = e.alarm
        end
    end
    store.save_channels(conf.chs)
    log.info("ui_hmi", "阈值已保存",
        "CH1", conf.chs[1].warn, conf.chs[1].alarm,
        "CH2", conf.chs[2].warn, conf.chs[2].alarm)
    -- 只刷当前页：跨页调 refresh_xxx 会拿到别的页的 id（xml:find 只认当前页）
    M.refresh()
end

--[[
恢复出厂默认（只回填编辑副本，仍需点保存才生效）
@return nil
]]
handlers.defaults = function()
    for i = 1, #conf.chs do
        if dflt[i] and edit[i] then
            edit[i].warn = dflt[i].warn
            edit[i].alarm = dflt[i].alarm
        end
    end
    refresh_set()
end

--[[
曲线通道显示开关
@return nil
]]
handlers.toggle_ch1 = function()
    ch_show[1] = not ch_show[1]
    set_chk("ch1_toggle", ch_show[1])
    local c = w("trend_chart")
    if c then
        c:set_series_hidden(SERIES[1], not ch_show[1])
    end
end

handlers.toggle_ch2 = function()
    ch_show[2] = not ch_show[2]
    set_chk("ch2_toggle", ch_show[2])
    local c = w("trend_chart")
    if c then
        c:set_series_hidden(SERIES[2], not ch_show[2])
    end
end

--[[
清空曲线历史（只清显示和历史缓存，不动 PLC 数据）
@return nil
]]
handlers.clear_trend = function()
    for i = 1, #conf.chs do
        data.hist[i] = {}
        data.stamps[i] = {}
    end
    drawn = sync_chart("trend_chart", 300)
    chart_ready = "trend"
    refresh_trend()
    log.info("ui_hmi", "曲线已清空")
end

-- ============ 对外接口 ============

--[[
初始化 plcui：接管 display 0 → 加载 XML → 进入入口页
调用前提：display 已经按 1024×600 / RGB / rotation=0 / 双 framebuffer 初始化完成；
plcui 与 airui 同一时间只能用一套（都要接管 display 0）。
@param opts table 可选，{defaults = {{warn=,alarm=},...}} 出厂默认阈值
@return boolean 成功返回 true
]]
function M.init(opts)
    opts = opts or {}

    -- 出厂默认值：main 在 store.load_channels 之前抓的快照
    for i, ch in ipairs(conf.chs) do
        edit[i] = { warn = ch.warn, alarm = ch.alarm }
        dflt[i] = opts.defaults and opts.defaults[i] or { warn = ch.warn, alarm = ch.alarm }
    end

    -- 先用大一点的缓存把内置字库点着，界面里有 12~58px 共 9 种字号。
    -- hzfont.init(路径, 缓存字节, 是否放PSRAM)：路径传 nil 用固件内置字库；
    -- 它失败是"返回 false"而不是抛错，所以 pcall 的第二个返回值才算数
    if hzfont and hzfont.init then
        local cs = hzfont.HZFONT_CACHE_2048 or hzfont.HZFONT_CACHE_1024 or 262144
        local pok, ready = pcall(hzfont.init, nil, cs)
        if not pok or not ready then
            log.warn("ui_hmi", "hzfont 初始化失败，中文会显示成方框（固件是否带内置字库）")
        end
    end

    local ok, err = plcui.init({ width = conf.W, height = conf.H })
    if not ok then
        log.error("ui_hmi", "plcui.init 失败", err and err.message or "")
        return false
    end

    xml, err = plcui.load("/luadb/main.xml", { handlers = handlers })
    if not xml then
        log.error("ui_hmi", "界面加载失败", err and err.message or "")
        return false
    end

    local st = plcui.status()
    page = (st and st.page) or "dash"
    reset_cache()
    log.info("ui_hmi", "界面已加载", "入口页", page)
    return true
end

--[[
全量刷新当前页（定时器每 500ms 调一次）
@return nil
]]
function M.refresh()
    if not xml then
        return
    end

    -- 页面可能已经被切走，先更句柄缓存
    sync_page()

    -- 顶栏（每页都有）
    set_text("clock", os.date("%H:%M:%S"))
    set_res("dot", data.online and "dot_on" or "dot_off")
    set_text("comm", data.online and "PLC 在线" or "PLC 离线")
    set_chk("sound", alarm.muted)

    -- 导航选中态
    set_chk("nav_dash", page == "dash")
    set_chk("nav_trend", page == "trend")
    set_chk("nav_alarm", page == "alarm")
    set_chk("nav_dev", page == "dev")
    set_chk("nav_set", page == "set")

    -- 图表进入页面后先整串灌一次，之后只喂增量点
    if page == "dash" and chart_ready ~= "dash" then
        drawn = sync_chart("dash_chart", 150)
        chart_ready = "dash"
    elseif page == "trend" and chart_ready ~= "trend" then
        drawn = sync_chart("trend_chart", 300)
        chart_ready = "trend"
    end

    if page == "dash" then
        refresh_dash()
    elseif page == "trend" then
        refresh_trend()
    elseif page == "alarm" then
        refresh_alarm()
    elseif page == "dev" then
        refresh_dev()
    elseif page == "set" then
        refresh_set()
    end
end

--[[
启动界面刷新：500ms 轮询 + 报警变化立即刷
@return nil
]]
function M.start()
    if not xml then
        return
    end

    -- 首屏刷新（里面会灌曲线）
    M.refresh()

    -- 报警变化（新报警/恢复/消音/复位/清空）立即刷一次，不等到下个 500ms
    alarm.on_change(function()
        M.refresh()
    end)

    sys.timerLoopStart(M.refresh, 500)
    sys.timerLoopStart(anim_tick, 200)      -- 流光 5 fps：8 帧一轮 1.6 s
end

return M
