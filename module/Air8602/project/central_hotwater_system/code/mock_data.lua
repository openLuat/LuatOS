--[[
@module  mock_data
@summary 太阳能热水工程控制系统 - 数据模型（模拟数据源 / 业务逻辑层）
@version 1.0.0
@date    2026.10.12
@usage
本模块是「数据 / 逻辑」与「界面」的解耦层：
  - 周期性刷新内部状态，并通过 sys.publish("SOLAR_DATA") 广播快照；
  - 界面层只订阅消息、只读快照，绝不自行计算数据；
  - 设置项、开关、继电器等修改统一走本模块接口，改完立即重新广播，
    保证「数据是唯一事实来源」。
接口：
  mock_data.init()                  -- 启动数据刷新任务
  mock_data.get()                   -- 取当前快照表
  mock_data.toggle_relay(i)         -- 切换第 i 路继电器
  mock_data.toggle_prot(key)        -- 切换保护开关
  mock_data.toggle_mode(i)          -- 切换第 i 个控制模式 启用/待机
  mock_data.set_mode(mode)          -- "自动" / "手动"
  mock_data.step_param(key, dir)    -- 步进修改运行参数（dir=1/-1）
  mock_data.ack_alarm(i)            -- 标记第 i 条报警为已处理
  mock_data.set_range(r)            -- 曲线页范围 "24h"/"7d"/"30d"
  mock_data.reset_params()          -- 恢复出厂参数
  mock_data.save_params()           -- 保存并下发
]]

local config = require "config"

local M = {}

-- ================= 静态基础数据 =================
-- 温度通道（tag / 名称 / 初始值 / 量程 / 正常区间）；颜色由视图层映射，数据层不含颜色
local TEMP_DEF = {
    { tag = "T1", name = "集热器温度", v = 76.4, min = 0,   max = 120, lo = 35, hi = 105 },
    { tag = "T2", name = "水箱温度",   v = 52.8, min = 0,   max = 100, lo = 30, hi = 80  },
    { tag = "T3", name = "回水温度",   v = 61.2, min = 0,   max = 100, lo = 25, hi = 75  },
    { tag = "T4", name = "供水温度",   v = 48.6, min = 0,   max = 100, lo = 25, hi = 70  },
    { tag = "T5", name = "环境温度",   v = 21.4, min = -20, max = 60,  lo = -5, hi = 45  },
}

-- 温度卡配色（语义色键，供视图层映射到主题色；与设计稿 --c 一致）
local TEMP_TONE = { "amber", "red", "cyan", "blue", "green" }

-- 6 路继电器
local RELAY_DEF = {
    { code = "KM1", name = "集热循环泵", on = true,  note = "温差循环" },
    { code = "KM2", name = "上水电磁阀", on = false, note = "定温上水" },
    { code = "KM3", name = "电加热器",   on = false, note = "定时加热" },
    { code = "KM4", name = "供水泵",     on = true,  note = "恒压供水" },
    { code = "KM5", name = "回水循环泵", on = true,  note = "回水控制" },
    { code = "KM6", name = "伴热带",     on = false, note = "防冻备用" },
}

-- 3 个控制模式
local MODE_DEF = {
    {
        key = "dt_loop", title = "温差循环", tone = "cyan", icon = "loop", on = true,
        desc = "集热器温度高于水箱温度达到启动差值时，循环泵 KM1 启动，将热量搬入水箱；温差低于停止值后延时停机。",
        rows = { { "启动温差", "8.0", "℃" }, { "停止温差", "3.0", "℃" }, { "循环泵延时", "30", "s" } },
    },
    {
        key = "water_fill", title = "定温上水 / 定时上水", tone = "amber", icon = "water", on = true,
        desc = "水位低于下限且在设定时段内开启上水阀 KM2，达到上限水位后关闭；夜间低温时段自动避免上水。",
        rows = { { "上水下限", "30", "%" }, { "上水上限", "95", "%" }, { "上水时段", "06:00 / 18:00", "" } },
    },
    {
        key = "elec_heat", title = "电加热辅助", tone = "green", icon = "heat", on = false,
        desc = "水箱温度低于启动值且处于低谷电时段时投入电加热 KM3；水位低于干烧保护值时强制切断加热回路。",
        rows = { { "加热启动", "50", "℃" }, { "加热停止", "60", "℃" }, { "加热时段", "22:00 - 06:00", "" } },
    },
}

-- 报警 / 事件记录（sev: crit/warn/info/ok）
local ALARM_DEF = {
    { sev = "crit", t = "14:32:18", txt = "系统压力过高 (0.86 MPa)，泄压阀动作后恢复正常", src = "压力通道", done = true  },
    { sev = "warn", t = "13:05:41", txt = "水箱温度传感器 T2 信号异常，已切换至备用采样值", src = "采集 MCU", done = false },
    { sev = "info", t = "11:48:02", txt = "4G 网络重连成功，当前信号强度 -68 dBm",       src = "4G 通信",  done = true  },
    { sev = "warn", t = "09:12:33", txt = "水位低于下限 30%，自动上水程序启动并完成补水", src = "水位通道", done = true  },
    { sev = "ok",   t = "07:00:00", txt = "定时上水任务执行完成，水位由 42% 升至 91%",  src = "定时任务", done = true  },
    { sev = "crit", t = "昨日 22:16", txt = "集热器超温保护触发 (118 ℃)，循环泵强制启动散热", src = "高温保护", done = true },
    { sev = "ok",   t = "昨日 18:00", txt = "定时上水任务执行完成，水位由 38% 升至 88%",  src = "定时任务", done = true },
    { sev = "info", t = "昨日 15:20", txt = "485 总线设备 0x02 采集器接入，通信正常",     src = "485 总线", done = true },
}

-- 设置页分组行（key 对应 config.params）
local SET_TEMP = {
    { key = "startup_dt", label = "集热循环启动温差" },
    { key = "stop_dt",    label = "集热循环停止温差" },
    { key = "heat_on",    label = "电加热启动温度" },
    { key = "heat_off",   label = "电加热停止温度" },
    { key = "overtemp",   label = "高温保护温度" },
    { key = "antifreeze", label = "防冻启动温度" },
}
local SET_LEVEL = {
    { key = "water_on",  label = "上水启动水位" },
    { key = "water_off", label = "上水停止水位" },
    { key = "low_level", label = "低水位报警" },
    { key = "dry_burn",  label = "防干烧保护值" },
}
-- 通讯分组：type=text 为只读文本 pill，type=step 为步进器（key 对应 config.params）
local SET_COMM = {
    { key = "fill_time_1", label = "定时上水 1",   type = "text", val = "06:00" },
    { key = "fill_time_2", label = "定时上水 2",   type = "text", val = "18:00" },
    { key = "heat_start",  label = "加热时段起点", type = "text", val = "22:00" },
    { key = "slave_addr",  label = "485 从站地址", type = "text", val = "0x01" },
    { key = "baudrate",    label = "485 波特率",   type = "text", val = "9600" },
    { key = "report_interval", label = "数据上报间隔", type = "step" },
}

-- 系统信息页：6 张卡片，row.cls ∈ {nil, "g", "a"}
local SYS_INFO = {
    {
        title = "设备信息", badge = { text = "在线", tone = "ok" }, val_w = 210,
        rows = {
            { "产品型号", "Air8602 热水工程控制器" },
            { "设备 ID",  "SN-8602-2026-0046" },
            { "固件版本", "LuatOS V2.0.3" },
            { "硬件版本", "HW V1.2" },
            { "连续运行", "12 天 04 时", "g" },
            { "主控芯片", "Air8602 / 1.2 GHz" },
            { "系统时间", "2026-10-12 15:46" },
            { "程序授权", "已激活", "g" },
        },
    },
    {
        title = "4G 通信", badge = { text = "已连接", tone = "run" }, signal = { level = 3, val = "-68", unit = "dBm", note = "信号良好" },
        rows = {
            { "运营商",   "中国移动 LTE" },
            { "本机 IP",  "10.42.118.73" },
            { "ICCID",    "89860****8829" },
            { "在线时长", "12 天 04 时", "g" },
            { "数据上报", "正常 / 60 s", "g" },
        },
    },
    {
        title = "存储 / SD 卡", badge = { text = "已挂载", tone = "ok" },
        meters = {
            { "SD 卡 8 GB", "已用 2.8 GB", 35 },
            { "日志分区",   "已用 1.9 GB", 48 },
            { "历史曲线数据", "已用 0.9 GB", 22 },
        },
        rows = {
            { "剩余可用", "5.2 GB", "g" },
            { "文件系统", "FAT32 / 已挂载" },
        },
    },
    {
        title = "串口 / 485", sub = "3 路",
        rows = {
            { "PORT1 / 隔离 485", "地址 0x01 / 9600", "g" },
            { "PORT2 / 采集 MCU", "115200 / 已连接", "g" },
            { "PORT3 / 预留",     "未启用" },
            { "校验 / 停止位",    "None / 1" },
            { "总线设备数",       "2 台" },
            { "通信成功率",       "99.8 %", "g" },
            { "平均响应",         "12 ms" },
            { "端口隔离",         "2500 V 已隔离", "g" },
        },
    },
    {
        title = "采集通道", badge = { text = "7/7 正常", tone = "ok" },
        rows = {
            { "温度输入 T1-T5", "5 路在线", "g" },
            { "水位输入",       "1 路在线", "g" },
            { "压力变送器",     "4-20 mA 正常", "g" },
            { "采样周期",       "1000 ms" },
            { "采样精度",       "12 bit" },
            { "数据上报",       "60 s / 次" },
            { "通道自检",       "全部通过", "g" },
        },
    },
    {
        title = "电源与输出", badge = { text = "正常", tone = "ok" },
        rows = {
            { "输入电源",   "DC 12 V" },
            { "实测电压",   "12.3 V", "g" },
            { "整机电流",   "0.42 A" },
            { "继电器输出", "6 路 / 已吸合 3 路" },
            { "触点容量",   "5 A / 250 VAC" },
            { "板载温度",   "38.6 ℃" },
            { "硬件看门狗", "运行正常", "g" },
        },
    },
}

-- ================= 运行时状态 =================
local state = {}

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function rnd(lo, hi)
    return lo + math.random() * (hi - lo)
end

-- 温度卡 spark 折线：围绕当前值生成一段历史
local function seed_hist(t)
    t.hist = {}
    for i = 1, config.data.spark_points do
        local k = i / config.data.spark_points
        t.hist[i] = t.v + (math.sin(k * 6.2 + t.v) * 0.5 + (k - 0.5)) * 4.2
    end
end

-- 曲线页三条温度序列（集热器 T1 / 水箱 T2 / 回水 T3）
local function build_trend(range)
    local n = (range == "24h") and 25 or 8
    local base = { 70, 52, 45 }
    local amp  = { 20, 7, 6 }
    local out = {}
    for si = 1, 3 do
        local arr = {}
        for i = 1, n do
            local t = (i - 1) / (n - 1) * math.pi * 2
            local noise = math.sin(t * 7.3 + si * 3.1) * amp[si] * 0.10
            arr[i] = math.floor(base[si] + amp[si] * math.sin(t * 0.92 + si)
                + amp[si] * 0.34 * math.sin(t * 2.6 + si * 2) + noise + 0.5)
        end
        out[si] = arr
    end
    return out
end

local function reset_state()
    state.clock   = os.date("%H:%M:%S")
    state.hm      = os.date("%H:%M")
    state.tick    = 0

    state.temps = {}
    for i, d in ipairs(TEMP_DEF) do
        state.temps[i] = {
            tag = d.tag, name = d.name, v = d.v,
            min = d.min, max = d.max, lo = d.lo, hi = d.hi,
            tone = TEMP_TONE[i],
            hist = {},
        }
        seed_hist(state.temps[i])
    end

    state.level    = 82
    state.volume   = 5.0 * state.level / 100
    state.valve    = "已关闭"
    state.press    = 0.32
    state.dt       = 23.6
    state.cyc_on   = true

    state.pump = { power = 1.42, runtime = "2h18m", today = 6, flow = 18.6,
        timeline = { 22, 0, 31, 0, 14, 0, 26 } }

    state.relays = {}
    for i, r in ipairs(RELAY_DEF) do
        state.relays[i] = { code = r.code, name = r.name, on = r.on, note = r.note }
    end

    state.modes = {}
    for i, m in ipairs(MODE_DEF) do
        state.modes[i] = { key = m.key, title = m.title, tone = m.tone, icon = m.icon,
            on = m.on, desc = m.desc, rows = m.rows }
    end

    state.prot = {}
    for k, v in pairs(config.switches) do state.prot[k] = v end
    state.mode = "自动"

    state.stats = { today = 3, pending = 1, total = 128, recovered = 127 }
    state.health = 96

    state.alarms = {}
    for i, a in ipairs(ALARM_DEF) do
        state.alarms[i] = { sev = a.sev, t = a.t, txt = a.txt, src = a.src, done = a.done }
    end

    state.params = {}
    for k, v in pairs(config.params) do state.params[k] = v end
    state.set_temp  = SET_TEMP
    state.set_level = SET_LEVEL
    state.set_comm  = SET_COMM
    state.sysinfo   = SYS_INFO

    state.range = "24h"
    state.trend = build_trend("24h")
    state.trend_stat = { max = 92.6, min = 34.2, avg = 186.4 }
end

-- 单帧刷新（UI 无关，纯数据推进）
local function tick()
    state.tick = state.tick + 1
    state.clock = os.date("%H:%M:%S")
    state.hm    = os.date("%H:%M")

    -- 温度漂移 + spark 历史推进
    for i = 1, #state.temps do
        local t = state.temps[i]
        t.v = clamp(t.v + rnd(-0.25, 0.25), t.min, t.max)
        t.hist[#t.hist + 1] = t.v
        if #t.hist > config.data.spark_points then table.remove(t.hist, 1) end
    end

    -- 温差与集热循环
    state.dt = state.temps[1].v - state.temps[2].v
    state.cyc_on = state.dt >= config.params.stop_dt

    -- 水位：低于 30% 时缓慢上水，否则微幅波动
    if state.level < 30 then
        state.level = clamp(state.level + math.abs(rnd(0, 0.5)) * 1.6, 0, 100)
    else
        state.level = clamp(state.level + rnd(-0.3, 0.3), 0, 100)
    end
    state.volume = 5.0 * state.level / 100
    if state.level >= 95 then
        state.valve = "已关闭"
    elseif state.level <= 30 then
        state.valve = "上水中"
    else
        state.valve = "已关闭"
    end

    -- 压力
    state.press = clamp(state.press + rnd(-0.03, 0.03), 0.05, 0.95)

    -- 泵状态跟随循环标志
    state.pump.power = state.cyc_on and (1.42 + rnd(-0.06, 0.06)) or 0

    sys.publish("SOLAR_DATA", state)
end

-- ================= 对外接口 =================
function M.get()
    return state
end

function M.init()
    math.randomseed(os.time())
    reset_state()
    log.info("mock_data", "数据层初始化完成")
    sys.taskInit(function()
        -- 先发一帧，保证界面首屏即有数据
        sys.publish("SOLAR_DATA", state)
        while true do
            sys.wait(config.data.tick_ms)
            tick()
        end
    end)
end

function M.toggle_relay(i)
    local r = state.relays[i]
    if not r then return end
    r.on = not r.on
    sys.publish("SOLAR_DATA", state)
end

function M.toggle_prot(key)
    if state.prot[key] == nil then return end
    state.prot[key] = not state.prot[key]
    sys.publish("SOLAR_DATA", state)
end

function M.toggle_mode(i)
    local m = state.modes[i]
    if not m then return end
    m.on = not m.on
    sys.publish("SOLAR_DATA", state)
end

function M.set_mode(mode)
    state.mode = mode
    sys.publish("SOLAR_DATA", state)
end

function M.step_param(key, dir)
    local spec = config.param_spec[key]
    if not spec then return end
    local v = state.params[key] or spec.min
    v = clamp(v + dir * spec.step, spec.min, spec.max)
    state.params[key] = v
    sys.publish("SOLAR_DATA", state)
end

function M.ack_alarm(i)
    local a = state.alarms[i]
    if not a or a.done then return end
    a.done = true
    state.stats.pending = 0
    for _, x in ipairs(state.alarms) do
        if not x.done then state.stats.pending = state.stats.pending + 1 end
    end
    sys.publish("SOLAR_DATA", state)
end

function M.set_range(r)
    state.range = r
    state.trend = build_trend(r)
    local s = state.trend[1]
    local mn, mx, sum = s[1], s[1], 0
    for _, v in ipairs(s) do
        if v < mn then mn = v end
        if v > mx then mx = v end
        sum = sum + v
    end
    state.trend_stat = { max = mx, min = mn, avg = math.floor(sum / #s * 10 + 0.5) / 10 }
    sys.publish("SOLAR_DATA", state)
end

function M.reset_params()
    for k, v in pairs(config.params) do state.params[k] = v end
    for i, m in ipairs(MODE_DEF) do
        state.modes[i].on = m.on
    end
    sys.publish("SOLAR_DATA", state)
end

function M.save_params()
    log.info("mock_data", "参数已保存并下发", state.params.report_interval)
    sys.publish("SOLAR_DATA", state)
end

return M
