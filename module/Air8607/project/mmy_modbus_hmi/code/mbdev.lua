--[[
@module  mbdev
@summary 从站设备 / 点位（寄存器）模型：定义、工程量换算、阈值判定、报警与历史
@version 1.0.0
@date    2026.10.25

点位（point）字段说明：
  key     全局唯一标识
  name    点位名称
  fc      读取功能码（0x01 线圈 / 0x02 离散输入 / 0x03 保持寄存器 / 0x04 输入寄存器）
  addr    寄存器（或位）起始地址，从 0 开始
  dtype   u16 / i16 / u32 / i32 / f32 / u32lo / i32lo / f32lo / bool
  scale   工程量 = 原始值 * scale
  dec     显示小数位
  unit    单位
  lo/hi   越限告警（warn）阈值
  dlo/dhi 危险告警（danger）阈值
  rw      是否可写
  wfc     写功能码（默认 0x06 / 0x05）
  min/max 写入范围
  bits    状态字位定义（数组，索引从 bit0 开始）
  def     默认值（模拟从站初始化 / 主站侧初值）
  color   曲线颜色
]]
local conf = require "conf"
local modbus = require "modbus"

local M = {}
local C = {
    cyan = 0x22D3EE, blue = 0x4C8DFF, green = 0x3DDC97, amber = 0xFFB020,
    red = 0xFF5A5F, violet = 0xA78BFA, teal = 0x2DD4BF, pink = 0xF472B6,
}

-- ==================== 设备 / 点位定义 ====================
M.DEF = {
    {
        id = 1, name = "车间温湿度变送器", model = "TH-200", kind = "th", color = C.cyan,
        desc = "RS485 / 9600 8N1",
        polls = { { fc = 0x03, addr = 0x0000, count = 4 } },
        points = {
            { key = "hum",  name = "环境湿度",   fc = 0x03, addr = 0, dtype = "u16", scale = 0.1, dec = 1, unit = "%",
              lo = 30, hi = 70, dlo = 20, dhi = 80, color = C.blue,  def = 55.0 },
            { key = "temp", name = "环境温度",   fc = 0x03, addr = 1, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              lo = 10, hi = 32, dlo = 2,  dhi = 40, color = C.amber, def = 24.0 },
            { key = "dew",  name = "露点温度",   fc = 0x03, addr = 2, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              color = C.teal, def = 14.0 },
            { key = "thst", name = "变送器状态", fc = 0x03, addr = 3, dtype = "u16", scale = 1,   dec = 0, unit = "",
              bits = { "探头故障", "超量程", "需校准", "通讯降级" }, color = C.violet, def = 0 },
        },
    },
    {
        id = 2, name = "三相电力仪表", model = "PM-300", kind = "pm", color = C.green,
        desc = "RS485 / 9600 8E1",
        polls = { { fc = 0x04, addr = 0x0000, count = 12 } },
        points = {
            { key = "ua", name = "A 相电压", fc = 0x04, addr = 0, dtype = "u16", scale = 0.1, dec = 1, unit = "V",
              lo = 350, hi = 410, dlo = 320, dhi = 430, color = C.cyan,   def = 380.0 },
            { key = "ub", name = "B 相电压", fc = 0x04, addr = 1, dtype = "u16", scale = 0.1, dec = 1, unit = "V",
              lo = 350, hi = 410, dlo = 320, dhi = 430, color = C.blue,   def = 380.0 },
            { key = "uc", name = "C 相电压", fc = 0x04, addr = 2, dtype = "u16", scale = 0.1, dec = 1, unit = "V",
              lo = 350, hi = 410, dlo = 320, dhi = 430, color = C.violet, def = 380.0 },
            { key = "ia", name = "A 相电流", fc = 0x04, addr = 3, dtype = "u16", scale = 0.01, dec = 2, unit = "A",
              hi = 20, dhi = 28, color = C.amber, def = 12.5 },
            { key = "ib", name = "B 相电流", fc = 0x04, addr = 4, dtype = "u16", scale = 0.01, dec = 2, unit = "A",
              hi = 20, dhi = 28, color = C.pink,  def = 12.2 },
            { key = "ic", name = "C 相电流", fc = 0x04, addr = 5, dtype = "u16", scale = 0.01, dec = 2, unit = "A",
              hi = 20, dhi = 28, color = C.teal,  def = 12.8 },
            { key = "pw", name = "总有功功率", fc = 0x04, addr = 6, dtype = "u32", scale = 0.1, dec = 1, unit = "kW",
              hi = 12, dhi = 16, color = C.green, def = 7.8 },
            { key = "pf", name = "功率因数", fc = 0x04, addr = 8, dtype = "u16", scale = 0.001, dec = 3, unit = "",
              lo = 0.85, color = C.cyan, def = 0.95 },
            { key = "freq", name = "电网频率", fc = 0x04, addr = 9, dtype = "u16", scale = 0.01, dec = 2, unit = "Hz",
              lo = 49.5, hi = 50.5, dlo = 49.0, dhi = 51.0, color = C.blue, def = 50.0 },
            { key = "ep", name = "总有功电能", fc = 0x04, addr = 10, dtype = "u32", scale = 0.1, dec = 1, unit = "kWh",
              color = C.violet, def = 1234.5 },
        },
    },
    {
        id = 3, name = "冷库温控器", model = "TC-100", kind = "tc", color = C.blue,
        desc = "RS485 / 9600 8N1",
        polls = {
            { fc = 0x03, addr = 0x0000, count = 3 },
            { fc = 0x04, addr = 0x0000, count = 2 },
            { fc = 0x01, addr = 0x0000, count = 2 },
            { fc = 0x02, addr = 0x0000, count = 2 },
        },
        points = {
            { key = "tset", name = "目标温度",   fc = 0x03, addr = 0, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              rw = true, wfc = 0x06, min = -25, max = 20, color = C.cyan, def = -15.0 },
            { key = "thys", name = "控制回差",   fc = 0x03, addr = 1, dtype = "u16", scale = 0.1, dec = 1, unit = "°C",
              rw = true, wfc = 0x06, min = 0.5, max = 5, color = C.teal, def = 2.0 },
            { key = "dly",  name = "启停延时",   fc = 0x03, addr = 2, dtype = "u16", scale = 1,   dec = 0, unit = "s",
              rw = true, wfc = 0x06, min = 0, max = 600, color = C.violet, def = 180 },
            { key = "tcur", name = "库内温度",   fc = 0x04, addr = 0, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              lo = -18, hi = -12, dlo = -25, dhi = -5, color = C.amber, def = -15.0 },
            { key = "teva", name = "蒸发器温度", fc = 0x04, addr = 1, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              color = C.blue, def = -22.0 },
            { key = "comp", name = "压缩机",     fc = 0x01, addr = 0, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "运行", off_text = "停机", color = C.green, def = 1 },
            { key = "defrost", name = "除霜加热", fc = 0x01, addr = 1, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "加热", off_text = "关闭", color = C.pink, def = 0 },
            { key = "door", name = "库门状态",   fc = 0x02, addr = 0, dtype = "bool",
              on_text = "开启", off_text = "关闭", color = C.amber, def = 0 },
            { key = "prot", name = "高低压保护", fc = 0x02, addr = 1, dtype = "bool",
              on_text = "动作", off_text = "正常", alarm_on = true, color = C.red, def = 0 },
        },
    },
    {
        id = 4, name = "液位流量计", model = "FM-400", kind = "fm", color = C.teal,
        desc = "RS485 / 19200 8N1",
        polls = { { fc = 0x04, addr = 0x0000, count = 7 } },
        points = {
            { key = "level", name = "罐体液位",   fc = 0x04, addr = 0, dtype = "u16", scale = 0.1, dec = 1, unit = "%",
              lo = 20, hi = 90, dlo = 10, dhi = 95, color = C.teal,  def = 55.0 },
            { key = "flow",  name = "瞬时流量",   fc = 0x04, addr = 1, dtype = "u32", scale = 0.01, dec = 2, unit = "m³/h",
              hi = 45, dhi = 60, color = C.cyan, def = 24.0 },
            { key = "total", name = "累计流量",   fc = 0x04, addr = 3, dtype = "u32", scale = 0.1, dec = 1, unit = "m³",
              color = C.violet, def = 8621.0 },
            { key = "ftemp", name = "介质温度",   fc = 0x04, addr = 5, dtype = "i16", scale = 0.1, dec = 1, unit = "°C",
              lo = 10, hi = 70, color = C.amber, def = 45.0 },
            { key = "fpres", name = "管道压力",   fc = 0x04, addr = 6, dtype = "u16", scale = 0.01, dec = 2, unit = "MPa",
              hi = 0.8, dhi = 1.0, color = C.blue, def = 0.45 },
        },
    },
    {
        id = 5, name = "数字量 IO 模块", model = "IO-808", kind = "io", color = C.violet,
        desc = "RS485 / 9600 8N1",
        polls = {
            { fc = 0x01, addr = 0x0000, count = 4 },
            { fc = 0x02, addr = 0x0000, count = 4 },
        },
        points = {
            { key = "do1", name = "DO1 进料泵",   fc = 0x01, addr = 0, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "开", off_text = "关", color = C.green,  def = 1 },
            { key = "do2", name = "DO2 出料阀",   fc = 0x01, addr = 1, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "开", off_text = "关", color = C.cyan,   def = 0 },
            { key = "do3", name = "DO3 搅拌机",   fc = 0x01, addr = 2, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "开", off_text = "关", color = C.amber,  def = 1 },
            { key = "do4", name = "DO4 声光报警", fc = 0x01, addr = 3, dtype = "bool", rw = true, wfc = 0x05,
              on_text = "开", off_text = "关", color = C.red,    def = 0 },
            { key = "di1", name = "DI1 上限位",   fc = 0x02, addr = 0, dtype = "bool",
              on_text = "触发", off_text = "释放", color = C.blue,   def = 0 },
            { key = "di2", name = "DI2 下限位",   fc = 0x02, addr = 1, dtype = "bool",
              on_text = "触发", off_text = "释放", color = C.teal,   def = 1 },
            { key = "di3", name = "DI3 急停按钮", fc = 0x02, addr = 2, dtype = "bool",
              on_text = "按下", off_text = "正常", alarm_on = true, color = C.red, def = 0 },
            { key = "di4", name = "DI4 运行反馈", fc = 0x02, addr = 3, dtype = "bool",
              on_text = "有", off_text = "无", color = C.green, def = 1 },
        },
    },
}

-- ==================== 索引 ====================
local DEV_BY_ID = {}
local PT_BY_KEY = {}
local DEV_OF_KEY = {}

for _, dev in ipairs(M.DEF) do
    DEV_BY_ID[dev.id] = dev
    for _, pt in ipairs(dev.points) do
        pt.dev_id = dev.id
        if not pt.wfc then
            if pt.dtype == "bool" then
                pt.wfc = 0x05
            elseif modbus.reg_count(pt.dtype) > 1 then
                pt.wfc = 0x10
            else
                pt.wfc = 0x06
            end
        end
        pt.scale = pt.scale or 1
        pt.dec = pt.dec or 1
        pt.unit = pt.unit or ""
        PT_BY_KEY[pt.key] = pt
        DEV_OF_KEY[pt.key] = dev
    end
end

function M.devices() return M.DEF end
function M.dev(id) return DEV_BY_ID[id] end
function M.point(key) return PT_BY_KEY[key] end
function M.dev_of(key) return DEV_OF_KEY[key] end

-- 总览页 4 个关键指标
M.KPI = { "temp", "pw", "tcur", "level" }

-- 趋势页可选通道
M.TREND = {
    "temp", "hum", "pw", "ia", "freq", "tcur", "level", "flow",
}

-- ==================== 运行时状态 ====================
local HIST_N = conf.sim.history_n

local st = {
    value   = {},   -- key -> 工程量
    raw     = {},   -- key -> 原始寄存器值数组
    stamp   = {},   -- key -> 与 history 一一对应的采集时刻（os.time 秒，0 = 未知）
    status  = {},   -- key -> normal / warn / danger / offline
    prev    = {},
    history = {},   -- key -> 数组
    online  = {},   -- dev id -> bool
    alarms  = {},
    tick    = 0,
}

function M.init()
    for _, dev in ipairs(M.DEF) do
        -- 在线状态先置 nil：首次轮询成功时不产生"通讯恢复"事件
        st.online[dev.id] = nil
        for _, pt in ipairs(dev.points) do
            st.value[pt.key] = pt.def or 0
            st.status[pt.key] = "offline"
            st.prev[pt.key] = "offline"
            -- 历史曲线从空开始，只画真实采样点。
            -- 早期版本在上电时用 def 填满 HIST_N 个点，导致开机后 80 秒内
            -- 曲线大部分是一条假的水平线，看起来像"数据没变"。
            st.history[pt.key] = {}
            st.stamp[pt.key] = {}
        end
    end
    st.alarms = {}
    st.tick = 0
end

-- ==================== 报警 ====================
local function push_alarm(level, key, text)
    table.insert(st.alarms, 1, {
        time = os.date("%H:%M:%S"),
        level = level, key = key, text = text,
        dev = (DEV_OF_KEY[key] and DEV_OF_KEY[key].name) or "系统",
    })
    if #st.alarms > conf.alarm.max_log then
        for i = #st.alarms, conf.alarm.max_log + 1, -1 do st.alarms[i] = nil end
    end
end

function M.push_comm_alarm(dev_id, online)
    local dev = DEV_BY_ID[dev_id]
    if not dev then return end
    if online then
        push_alarm("ok", "", string.format("从站 #%d %s 通讯恢复", dev.id, dev.name))
    else
        push_alarm("danger", "", string.format("从站 #%d %s 通讯中断", dev.id, dev.name))
    end
end

function M.alarms() return st.alarms end
function M.clear_alarms() st.alarms = {} end

function M.alarm_count(level)
    local n = 0
    for _, a in ipairs(st.alarms) do
        if a.level == level then n = n + 1 end
    end
    return n
end

-- ==================== 值更新 ====================
local function judge(pt, v)
    if pt.dtype == "bool" then
        if pt.alarm_on then
            return (v ~= 0) and "danger" or "normal"
        end
        return "normal"
    end
    if pt.dhi and v >= pt.dhi then return "danger" end
    if pt.dlo and v <= pt.dlo then return "danger" end
    if pt.hi and v > pt.hi then return "warn" end
    if pt.lo and v < pt.lo then return "warn" end
    return "normal"
end

--[[
主站轮询成功后调用：写入解析出的原始寄存器 / 位，换算工程量并判状态

@param key  点位 key
@param regs 寄存器数组（模拟量）或 nil
@param bit  位值（true/false，开关量）或 nil
]]
function M.update(key, regs, bit)
    local pt = PT_BY_KEY[key]
    if not pt then return end
    if pt.dtype == "bool" then
        if bit == nil then return end
        st.raw[key] = { bit and 1 or 0 }
        st.value[key] = bit and 1 or 0
    else
        if not regs then return end
        -- st.raw 保存原始寄存器（供寄存器工具/详情页显示 HEX），st.value 是换算后的工程量
        st.raw[key] = {}
        for i, r in ipairs(regs) do st.raw[key][i] = r end
        st.value[key] = modbus.decode(regs, pt.dtype, 1) * pt.scale
        local his = st.history[key]
        his[#his + 1] = st.value[key]
        if #his > HIST_N then table.remove(his, 1) end
        -- 采集时刻与历史样本严格一一对应，趋势游标才能显示该点的真实时间
        local sts = st.stamp[key]
        sts[#sts + 1] = os.time()
        if #sts > HIST_N then table.remove(sts, 1) end
    end

    local s = judge(pt, st.value[key])
    if st.status[key] ~= s then
        if s ~= "normal" then
            push_alarm(s, key, string.format("%s %s%s %s", DEV_OF_KEY[key].name,
                M.fmt(key, st.value[key]), pt.unit,
                (s == "danger") and "触发报警" or "偏离正常"))
        end
        st.prev[key] = st.status[key]
        st.status[key] = s
    end
end

-- ==================== 读取接口 ====================
function M.get(key) return st.value[key] end
function M.raw(key) return st.raw[key] end
function M.status(key) return st.status[key] or "offline" end
function M.history(key) return st.history[key] or {} end
function M.stamps(key) return st.stamp[key] or {} end
function M.hist_n() return HIST_N end        -- 窗口容量（上限）
function M.hist_len(key) return #(st.history[key] or {}) end   -- 实际已采样点数

function M.online(dev_id) return st.online[dev_id] == true end

function M.set_online(dev_id, b)
    local old = st.online[dev_id]
    st.online[dev_id] = b
    if old ~= nil and old ~= b then
        local dev = DEV_BY_ID[dev_id]
        if dev then
            M.push_comm_alarm(dev_id, b)
            for _, pt in ipairs(dev.points) do
                if not b then st.status[pt.key] = "offline" end
            end
        end
    end
end

function M.online_count()
    local n = 0
    for _, dev in ipairs(M.DEF) do
        if st.online[dev.id] then n = n + 1 end
    end
    return n
end

function M.any_alarm()
    for _, dev in ipairs(M.DEF) do
        if not st.online[dev.id] then return true end
        for _, pt in ipairs(dev.points) do
            local s = st.status[pt.key]
            if s == "warn" or s == "danger" then return true end
        end
    end
    return false
end

function M.dev_alarm_count(dev_id)
    local n = 0
    local dev = DEV_BY_ID[dev_id]
    if not dev then return 0 end
    if not st.online[dev_id] then n = n + 1 end
    for _, pt in ipairs(dev.points) do
        local s = st.status[pt.key]
        if s == "warn" or s == "danger" then n = n + 1 end
    end
    return n
end

-- ==================== 格式化 ====================
function M.fmt(key, v)
    local pt = PT_BY_KEY[key]
    if not pt then return "" end
    v = v or st.value[key]
    if v == nil then return "--" end
    if pt.dtype == "bool" then
        local on = (v ~= 0)
        return on and (pt.on_text or "ON") or (pt.off_text or "OFF")
    end
    return string.format("%." .. pt.dec .. "f", v)
end

function M.fmt_with_unit(key, v)
    local pt = PT_BY_KEY[key]
    if not pt then return "" end
    return M.fmt(key, v) .. pt.unit
end

-- 状态字：把数值解成位文本
function M.bit_text(key, v)
    local pt = PT_BY_KEY[key]
    if not pt or not pt.bits then return "" end
    v = v or st.value[key]
    if v == nil then return "" end
    local n = math.floor(v)
    local t = {}
    for i, bn in ipairs(pt.bits) do
        if ((n >> (i - 1)) & 1) == 1 then t[#t + 1] = bn end
    end
    if #t == 0 then return "正常" end
    return table.concat(t, "/")
end

function M.tick_count() return st.tick end
function M.bump_tick() st.tick = st.tick + 1; return st.tick end

return M
