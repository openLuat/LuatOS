--[[
@module  main
@summary 双路温度监控 · Air8603W1 + FX3U 计算机链接（多页面版）
]]

PROJECT = "melsec_temp_hmi"
VERSION = "1.2.0"

local cfg      = require("config")
local board    = require("board")
local fx       = require("fx3u")
local signal   = require("signal")
local alarmlib = require("alarm_mgr")
local store    = require("store")
local sound    = require("sound")
local home     = require("ui_home")

log.info("main", PROJECT, VERSION)

-- ===== 看门狗 =====
--[[ 这里有两颗，别混：
      · wdt          —— LuatOS 内部软件看门狗，系统卡死时自己重启；
      · exair153x_wdt —— 板载 Air153D 外部硬件看门狗，靠 GPIO57 周期喂脉冲。
     第二颗才是"约 12 分钟必重启"的元凶：它是硬件芯片，主控不喂就一直拉复位。
     860X 的工程都会在起来之后立刻 init，这里同理。]]
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- ===== 阈值 =====
local thresholds = {
    { warn = cfg.channels[1].warn, alarm = cfg.channels[1].alarm },
    { warn = cfg.channels[2].warn, alarm = cfg.channels[2].alarm },
}
do
    local saved = store.load_thresholds()
    if saved then
        for i = 1, 2 do
            thresholds[i].warn  = saved[i].warn  or thresholds[i].warn
            thresholds[i].alarm = saved[i].alarm or thresholds[i].alarm
        end
        log.info("main", "阈值已恢复", thresholds[1].warn, thresholds[1].alarm)
    end
    local recs = store.load_records()
    if recs then alarmlib.set_records(recs) end
end

-- ===== 屏 =====
local ui_ok = board.init()
if not ui_ok then
    log.error("main", "屏初始化失败，进入无界面模式（串口日志仍可用）")
end

-- ===== 外部硬件看门狗（Air153D，GPIO57）=====
--[[ 必须在板级上电之后立刻起：这颗是硬件芯片，主控不喂它就一直计，
--     约 12 分钟拉一次整机复位。症状是"跑一阵子自己重启"，日志还查不出原因。
--     固件不带 exair153x_wdt 时降级成 warning，不影响其它功能。]]
if cfg.board.wdt_pin then
    local okw, errw = pcall(function()
        local w = require("exair153x_wdt")
        w.init({ wdt_pin = cfg.board.wdt_pin })
    end)
    if okw then
        log.info("main", "外部看门狗已启动, GPIO" .. tostring(cfg.board.wdt_pin))
    else
        log.warn("main", "外部看门狗启动失败（固件是否带 exair153x_wdt）", tostring(errw))
    end
end

-- ===== 运行统计 =====
local frames, fails, up = 0, 0, 0
local mm = { mx1 = nil, mn1 = nil, mx2 = nil, mn2 = nil }

local function mmReset()
    mm = { mx1 = nil, mn1 = nil, mx2 = nil, mn2 = nil }
end

local function mmFeed(t1, t2)
    if t1 then
        mm.mx1 = (mm.mx1 and math.max(mm.mx1, t1)) or t1
        mm.mn1 = (mm.mn1 and math.min(mm.mn1, t1)) or t1
    end
    if t2 then
        mm.mx2 = (mm.mx2 and math.max(mm.mx2, t2)) or t2
        mm.mn2 = (mm.mn2 and math.min(mm.mn2, t2)) or t2
    end
end

-- ===== 界面 =====
local last_seq = -1

local function refresh(force)
    if not ui_ok then return end
    for i = 1, 2 do
        local s = signal.get(i)
        s.level = alarmlib.level(i)
        s.warn  = thresholds[i].warn
        s.alarm = thresholds[i].alarm
        home.update_channel(i, s)
    end

    local sq = alarmlib.seq()
    if force or sq ~= last_seq then
        home.update_alarms(alarmlib.records())
        if force or last_seq >= 0 then
            store.save_records(alarmlib.records())     -- 仅记录变化时写 fskv
        end
        last_seq = sq
    end

    home.set_muted(alarmlib.is_muted(), alarmlib.any_active())
end

if ui_ok then
    home.build({
        th = thresholds,
        mute = function()
            alarmlib.toggle_mute()
            sound.set_muted(alarmlib.is_muted())
            refresh()
        end,
        reset = function()
            alarmlib.reset()
            mmReset()
            home.hide_alert()
            sound.clear()
            refresh()
        end,
        on_thresholds = function(out)
            thresholds = out
            store.save_thresholds(thresholds)
            home.set_thresholds(thresholds)
            alarmlib.update({ signal.temp_int(1), signal.temp_int(2) }, thresholds)
            refresh()
            log.info("main", "阈值已保存", out[1].warn, out[1].alarm, out[2].warn, out[2].alarm)
        end,
    })
    refresh(true)
end

-- ===== 报警提示：弹窗 + 语音 =====
--[[ 订阅 alarm_mgr 的事件，不在这里判断级别 —— 判定只有一处，避免两套逻辑打架。
      · new     → 弹窗 + 开始播报（新报警会自动解除消音，见 alarm_mgr.add_record）
      · recover → 两路都回到正常才关弹窗、停播报
      · reset   → 同上]]
--[[ 语音文案由 main 现拼，不在报警触发时冻结。
     两个理由：
       1. 温度在变，重复播报应该念"当前"多少度，而不是触发那一刻的旧值；
       2. 温度回落到阈值以下（但还没跌破回差、记录仍挂着）时，返回 nil 让它闭嘴 —— 
          屏幕上还标着"未恢复"是对的，但语音再念"当前 30 度"就自相矛盾了。
     TTS 念小数会说成"六十八点四"，所以四舍五入到整度；通道用中文数字更稳。]]
local CN_NUM = { "一", "二", "三", "四" }

sound.set_provider(function()
    local pick, picklv = nil, 0
    for i = 1, 2 do
        local lv = alarmlib.level(i)
        local v = signal.temp_int(i)
        if lv > 0 and v then
            local lim = (lv == 2) and thresholds[i].alarm or thresholds[i].warn
            if v >= lim and lv > picklv then      -- 报警优先于预警，同级取先命中的
                pick, picklv = { ch = i, lv = lv, v = v }, lv
            end
        end
    end
    if not pick then return nil end
    return string.format("%s，通道%s，当前%d摄氏度",
        pick.lv == 2 and "报警" or "预警",
        CN_NUM[pick.ch] or tostring(pick.ch),
        math.floor(pick.v / 10 + 0.5))
end)

-- 播报用的边沿状态，subscribe 回调里要重置，所以先声明
local was_above = { false, false }   -- 上一轮该通道是否在阈值之上
local fall_said = { false, false }   -- 本段报警是否已经播过"已回落"

sound.start()

alarmlib.subscribe(function(evt, rec)
    if evt == "new" then
        -- 新一段报警：边沿状态归零，温度此刻必在阈值之上
        if rec and rec.ch then
            was_above[rec.ch] = true
            fall_said[rec.ch] = false
        end
        if ui_ok and cfg.alarm.popup ~= false then home.show_alert(rec) end
        if cfg.alarm.speech ~= false then sound.alert() end
    elseif evt == "recover" then
        -- 只有两路都回到正常才停播报；单路恢复不打断另一路的报警
        if not alarmlib.any_active() then
            if ui_ok then home.hide_alert() end
            sound.clear()
        end
    elseif evt == "reset" then
        if ui_ok then home.hide_alert() end
        sound.clear()
    end
end)

-- ===== 通信 =====
local comm_ok = fx.init(cfg.uart, cfg.plc)
if not comm_ok then
    log.error("main", "通信初始化失败，不启动采样（检查 config.uart）")
end
if cfg.plc.enable == false then
    comm_ok = false
    log.info("main", "plc.enable=false，跳过轮询（只调界面）")
    if ui_ok then home.set_status("模拟模式", cfg.color.dim) end
end

local inflight, last_poll_ok = false, false

local function on_fail(err)
    inflight = false
    fails = fails + 1
    if ui_ok then home.set_link(false, 0) end
    if last_poll_ok then
        last_poll_ok = false
        signal.invalidate()
        refresh()
        log.warn("main", "通讯中断", err)
    end
end

--[[ 温度从阈值之上回落到之下时，插播一句"预警已回落"。
     为什么要限一次：阈值附近来回抖（30.0 ↔ 29.9）时，如果每次都播，会变成
     "已回落 …… 已回落 ……" 的噪音。所以每段报警只播一次，等新的报警记录产生、
     或者彻底恢复正常才重置。
     注意这只影响语音；屏幕上的记录仍按回差判定，该挂"未恢复"就继续挂着。]]
local function check_fall_speech()
    for i = 1, 2 do
        local lv = alarmlib.level(i)
        local v  = signal.temp_int(i)
        if not v then
            -- 数值无效：不判边沿，避免断线恢复时误播
        elseif lv > 0 then
            local lim = (lv == 2) and thresholds[i].alarm or thresholds[i].warn
            local above = (v >= lim)
            if was_above[i] and not above and not fall_said[i] then
                fall_said[i] = true
                if cfg.alarm.speech ~= false then
                    sound.announce(string.format("%s已回落，通道%s，当前%d摄氏度",
                        lv == 2 and "报警" or "预警",
                        CN_NUM[i] or tostring(i),
                        math.floor(v / 10 + 0.5)))
                end
            end
            was_above[i] = above
        else
            was_above[i] = false
            fall_said[i] = false        -- 恢复正常，下一段报警重新计数
        end
    end
end

local function on_data(vals)
    inflight = false
    last_poll_ok = true
    frames = frames + 1

    signal.update(vals)
    local t1, t2 = signal.temp_int(1), signal.temp_int(2)
    alarmlib.update({ t1, t2 }, thresholds)
    check_fall_speech()
    mmFeed(t1, t2)

    if ui_ok then
        local st = fx.stats()
        home.set_link(true, st.rtt)
        home.update_stats(
            mm.mx1 and mm.mx1 / 10, mm.mn1 and mm.mn1 / 10,
            mm.mx2 and mm.mx2 / 10, mm.mn2 and mm.mn2 / 10)
        home.update_live(t1 and t1 / 10, t2 and t2 / 10)
        home.update_device({
            rtt = st.rtt,
            ok_rate = (frames + fails > 0) and (frames * 100 / (frames + fails)) or 100,
            frames = frames,
            uptime = string.format("%02d:%02d", math.floor(up / 60), up % 60),
        }, { vals[1], vals[2], vals[3] })
    end

    refresh(false)
end

if comm_ok then
    sys.timerLoopStart(function()
        if inflight then return end
        inflight = true
        fx.read(cfg.plc.start_addr, cfg.plc.count, function(vals, err)
            if vals then on_data(vals) else on_fail(err) end
        end)
    end, cfg.plc.poll_ms)
end

-- ===== 趋势落点（3s 一点，600 点 = 30 分钟）=====
sys.timerLoopStart(function()
    if not ui_ok then return end
    for i = 1, 2 do
        local t = signal.temp_int(i)
        if t then home.push_trend(i, t / 10) end
    end
end, cfg.trend.period_ms)

-- ===== 时钟 / 运行时长 =====
sys.timerLoopStart(function()
    up = up + 1
    if ui_ok then
        home.set_clock(os.date("%H:%M:%S"))
        local st = fx.stats()
        home.update_device({
            rtt = st.rtt,
            ok_rate = (frames + fails > 0) and (frames * 100 / (frames + fails)) or 100,
            frames = frames,
            uptime = string.format("%02d:%02d", math.floor(up / 60), up % 60),
        }, {})
    end
end, 1000)

-- ===== 报警音 =====
-- 喇叭接 J13。声音走 Air1103（exaudio/audio），按固件实际接口接入后，
-- 在这里根据 alarmlib.any_active() 与 alarmlib.is_muted() 控制播放。

sys.run()
