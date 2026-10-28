-- @module  ctrl_app
-- @summary 开关远程控制 + 本地操作限制（电表继电器 0x01/0x02/0x05/0x0F）
-- @version 001.000.000
-- @date    2026.10.28
-- @author  OpenLuat
-- @BSD License
--[[
硬件映射（电表线圈地址，0 基；本板只有 2 路继电器，只做 1 个总开关）：
  第 1 路继电器：DO1A / DO1B 是其两个端子 → 线圈 0 → 合闸控制
  第 2 路继电器：DO2A / DO2B 是其两个端子 → 线圈 1 → 断开控制
  DI1  → 开入量地址 0（总开关反馈：1=合闸，0=断开）
  DI2  → 未使用（固定按 0 处理）

总开关只有"合闸 / 断开"两种动作，没有保护跳闸语义。

协议（说明书 5.2 报文格式指令）：
  0x01 读继电器状态 → exmodbus.COIL_STATUS
  0x02 读开入量状态 → exmodbus.INPUT_STATUS
  0x05 遥控单路继电器（0xFF00 合 / 0x0000 分）
  动作方式：目标继电器输出高电平 2000ms 后自动释放（脉冲）

限制逻辑（lock）：
  - 总限制 lock_all=1 时，单路限制被忽略（并按手册要求清掉单路设置）；
  - 平台（Web）指令永远不受限制影响，限制只约束现场本地操作；
  - 平台"断开"后自动加限制（CFG.auto_lock_on_open，日志 AUTOLOCK）；
  - 解除限制必须显式下发（Web「解除」按钮 / lock:off），合闸不会自动解除；
  - 限制生效时按平台目标**双向纠偏**（CFG.correct_both_dirs）：
      DI 与目标不一致 → 输出 2s 脉冲强制纠正（日志 CORRECT）；
      纠正后仍不一致 → 进入**监守模式**（日志 GUARD ON），
      此后每 2s 再输出一次 2s 脉冲，直到 DI 与目标一致（日志 GUARD OFF）；
      监守期间故障位 bit0 保持上报；
  - 目标状态与限制写入 fskv（ctrl_state）掉电保存，重启后继续生效。

下行命令（tag19，JSON）：
  {"type":"sw","ch":1,"act":1}    ch: 0=全部 1/2=单路；act: 1=合闸 0=跳闸
  {"type":"sw_get"}               查询状态
  {"type":"lock","all":1}         总限制开/关
  {"type":"lock","ch":1,"val":1}  单路限制（需总限制已解除）
文本命令：sw:on / sw:off / sw1:on / sw1:off / sw2:on / sw2:off / lock:on / lock:off

上报（tag）：
  1320 DI1 状态、1321 DI2 状态
  1322 平台目标位图（bit0 开关1 / bit1 开关2）
  1323 限制位图（bit0 总限制 / bit1 开关1 单限制 / bit2 开关2 单限制）
  1324 故障位图（bit0 开关1 拒动 / bit1 开关2 拒动 / bit2 通信异常）
  1325 继电器输出位图（bit0..3 = DO1A/DO1B/DO2A/DO2B）
事件：sys.publish("CTRL_STATE", snapshot)
]]

local M = {}

local exmodbus  = require "exmodbus"
local meter_app = require "meter_app"

-- ==================== 配置 ====================
local CFG = {
    pulse_ms   = 2000, -- 继电器动作脉冲宽度（需求：2 秒高电平）
    poll_ms    = 1000, -- DI/DO 巡检周期
    verify_ms  = 1200, -- 动作后等待反馈稳定的时间
    timeout    = 800,  -- 单帧超时
    guard_gap  = 2000, -- 监守模式下两次动作之间的间隔（需求：每隔 2 秒拉高 2 秒）
    correct_both_dirs = true, -- 双向纠偏：平台合闸时本地被断开也会强制合闸
    -- 平台"断开"后自动加限制（安全默认）；"合闸"不自动解除，
    -- 解除限制必须由 Web 的「解除」按钮显式下发，避免"一合闸就顺带解除"。
    auto_lock_on_open   = true,
    auto_unlock_on_close = false,
}

-- 继电器地址（0 基线圈地址）
-- 本板只有 2 路继电器：DO1A/DO1B 是第 1 路继电器的两个端子，DO2A/DO2B 是第 2 路。
-- 总开关只需 1 个通道：继电器1 合闸（线圈0）、继电器2 断开（线圈1）；
-- DI1 反馈实际状态，DI2 本机未使用。
local RELAY_ON  = { [1] = 0 } -- 第 1 路继电器 → 合闸
local RELAY_OFF = { [1] = 1 } -- 第 2 路继电器 → 断开
local DI_ADDR   = { [1] = 0 } -- DI1 → 开入量地址 0
local CH_NAME   = { [1] = "总开关" }
local CH_COUNT  = 1           -- 只做 1 路（总开关）

-- ==================== 状态 ====================
local st = {
    di       = { [1] = 0, [2] = 0 }, -- 反馈：1=合闸
    di_raw   = 0,                    -- 4 路开入量原始位图（排查 DI 映射用）
    relay    = { 0, 0, 0, 0 },       -- 4 路继电器线圈
    target   = { [1] = 0, [2] = 0 }, -- 平台期望：1=合闸 0=分闸
    lock_all = 0,                    -- 总限制
    lock     = { [1] = 0, [2] = 0 }, -- 单路限制
    fault    = 0,                    -- bit0/1 拒动，bit2 通信异常
    online   = false,
    ts       = 0,
}
local queue      = {}                          -- 待执行动作
local guard      = { [1] = false, [2] = false } -- 监守模式：纠偏失败后持续重试
local FSKV_KEY   = "ctrl_state"

-- ==================== 持久化 ====================
local function save_state()
    if fskv and fskv.set then
        pcall(fskv.set, FSKV_KEY, json.encode({
            target = { st.target[1], st.target[2] },
            lock_all = st.lock_all,
            lock = { st.lock[1], st.lock[2] },
        }))
    end
end

local function load_state()
    if not (fskv and fskv.get) then return end
    -- 必须先初始化 fskv，否则 get/set 全部静默失败（重启后限制/目标会丢）
    if fskv.init then pcall(fskv.init) end
    local ok, s = pcall(fskv.get, FSKV_KEY)
    if not ok or type(s) ~= "string" or s == "" then return end
    local ok2, t = pcall(json.decode, s)
    if not ok2 or type(t) ~= "table" then return end
    if type(t.target) == "table" then
        st.target[1] = (t.target[1] == 1) and 1 or 0
        st.target[2] = (t.target[2] == 1) and 1 or 0
    end
    st.lock_all = (t.lock_all == 1) and 1 or 0
    if type(t.lock) == "table" then
        st.lock[1] = (t.lock[1] == 1) and 1 or 0
        st.lock[2] = (t.lock[2] == 1) and 1 or 0
    end
    if st.lock_all == 1 then st.lock[1], st.lock[2] = 0, 0 end
end

-- ==================== 总线访问 ====================
local function slave_id()
    local c = meter_app.get_cfg and meter_app.get_cfg()
    return (c and c.slave_id) or 1
end

local function bus_read(reg_type, start, count)
    local m = meter_app.get_master()
    if not m then return nil end
    meter_app.bus_lock()
    local ret = m:read({
        slave_id = slave_id(), reg_type = reg_type,
        start_addr = start, reg_count = count, timeout = CFG.timeout,
    })
    meter_app.bus_unlock()
    if ret and ret.status == exmodbus.STATUS_SUCCESS and ret.data then return ret.data end
    return nil
end

local function coil_write(addr, on)
    local m = meter_app.get_master()
    if not m then return false end
    meter_app.bus_lock()
    local ret = m:write({
        slave_id = slave_id(), reg_type = exmodbus.COIL_STATUS,
        start_addr = addr, reg_count = 1,
        data = { [addr] = on and 1 or 0 }, timeout = CFG.timeout,
    })
    meter_app.bus_unlock()
    if not (ret and ret.status == exmodbus.STATUS_SUCCESS) then
        log.warn("ctrl", "写线圈失败", addr, ret and ret.status or "nil")
        return false
    end
    return true
end

-- 输出 pulse_ms 高电平后释放
local function pulse(addr)
    if not coil_write(addr, true) then return false end
    sys.wait(CFG.pulse_ms)
    return coil_write(addr, false)
end

-- ==================== 读取 ====================
local function bits_of(t, start, count)
    local out = {}
    for i = 0, count - 1 do
        local v = t[start + i]
        if v == nil then v = t[start + i + 1] end -- 兼容 1 基下标
        out[start + i] = (tonumber(v) or 0) ~= 0 and 1 or 0
    end
    return out
end

local function read_di()
    local d = bus_read(exmodbus.INPUT_STATUS, 0x0000, 4)
    if not d then return false end
    local b = bits_of(d, 0, 4)
    st.di[1] = b[DI_ADDR[1]]
    st.di[2] = 0 -- DI2 未使用，固定 0
    local raw = 0
    for i = 0, 3 do if b[i] == 1 then raw = raw | (1 << i) end end
    st.di_raw = raw
    return true
end

local function read_relay()
    local d = bus_read(exmodbus.COIL_STATUS, 0x0000, 4)
    if not d then return false end
    local b = bits_of(d, 0, 4)
    for i = 1, 4 do st.relay[i] = b[i - 1] end
    return true
end

-- ==================== 状态快照 ====================
-- ==================== 事件日志（环形，掉电保存） ====================
-- 键名带 v2：早期版本存的是中文，云端 ASCII 字段会乱码，升级时直接丢弃旧记录
local LOG_KEY = "ctrl_log_v2"
local LOG_MAX = 40
local logs    = {}

local function save_logs()
    if fskv and fskv.set then pcall(fskv.set, LOG_KEY, json.encode(logs)) end
end

local function add_log(text)
    logs[#logs + 1] = { t = os.time(), s = text }
    while #logs > LOG_MAX do table.remove(logs, 1) end
    save_logs()
    log.info("ctrl", "事件", text)
end

local function load_logs()
    if not (fskv and fskv.get) then return end
    local ok, s = pcall(fskv.get, LOG_KEY)
    if not ok or type(s) ~= "string" or s == "" then return end
    local ok2, t = pcall(json.decode, s)
    if ok2 and type(t) == "table" then logs = t end
end

-- 取最近 n 条（新的在前），返回 JSON 数组字符串
function M.get_log_json(n)
    n = tonumber(n) or 20
    if n < 1 then n = 1 end
    if n > LOG_MAX then n = LOG_MAX end
    local out = {}
    local start = math.max(1, #logs - n + 1)
    for i = #logs, start, -1 do out[#out + 1] = logs[i] end
    return json.encode(out)
end

local function set_fault(ch, flag)
    local bit = (ch == 1) and 1 or 2
    local old = st.fault
    if flag then st.fault = st.fault | bit else st.fault = st.fault & (~bit & 0x07) end
    if old ~= st.fault then log.info("ctrl", "故障位", st.fault) end
end

local function snapshot()
    local tb, lb, rb = 0, 0, 0
    for ch = 1, CH_COUNT do if st.target[ch] == 1 then tb = tb | (1 << (ch - 1)) end end
    if st.lock_all == 1 then
        lb = 1
    else
        for ch = 1, CH_COUNT do if st.lock[ch] == 1 then lb = lb | (1 << ch) end end
    end
    for i = 1, 4 do if st.relay[i] == 1 then rb = rb | (1 << (i - 1)) end end
    return {
        di1 = st.di[1], di2 = st.di[2], di_raw = st.di_raw,
        target = tb, lock = lb, relay = rb,
        fault = st.fault, online = st.online, ts = st.ts,
        lock_all = st.lock_all, lock1 = st.lock[1], lock2 = st.lock[2],
    }
end

-- ==================== 动作 ====================
local function do_action(ch, act)
    local addr = (act == 1) and RELAY_ON[ch] or RELAY_OFF[ch]
    local what = act == 1 and "合闸" or "断开" -- 总开关无保护跳闸语义，统一叫"断开"
    local what_en = act == 1 and "CLOSE" or "OPEN" -- 日志只用 ASCII（云端 TLV 为 ASCII，中文会乱码）
    add_log(string.format("CMD DO%d %s", ch, what_en))
    pulse(addr)
    sys.wait(CFG.verify_ms)
    if not read_di() then return end
    if st.di[ch] ~= act then
        set_fault(ch, true)
        log.warn("ctrl", CH_NAME[ch], "动作未到位", "DI =", st.di[ch], "期望", act)
        add_log(string.format("DO%d %s FAIL DI=%d", ch, what_en, st.di[ch]))
        sys.publish("CTRL_FAULT", { ch = ch, reason = "no_feedback" })
    else
        set_fault(ch, false)
        add_log(string.format("DO%d %s OK", ch, what_en))
    end
end

-- 生效限制判断
local function locked(ch)
    if st.lock_all == 1 then return true end
    return st.lock[ch] == 1
end

-- 限制模式下的本地操作纠正
-- 限制模式下的偏差纠正（以平台目标为准，双向）：
--   DI 与目标一致 → 若处于监守模式则退出
--   DI 与目标偏离 → 输出 2s 脉冲纠正；纠正失败进入监守模式，
--   之后每隔 guard_gap(2s) 再动作一次（每次 2s 高电平），直到 DI 恢复正常
local function enforce_local()
    for ch = 1, CH_COUNT do
        if not locked(ch) then
            if guard[ch] then
                guard[ch] = false
                set_fault(ch, false)
                add_log(string.format("GUARD OFF DO%d", ch))
            end
        else
            local want, actual = st.target[ch], st.di[ch]
            if actual == want then
                if guard[ch] then
                    guard[ch] = false
                    set_fault(ch, false)
                    add_log(string.format("GUARD OFF DO%d", ch))
                    log.info("ctrl", CH_NAME[ch], "状态已恢复正常，退出监守模式")
                end
            elseif want == 1 and not CFG.correct_both_dirs then
                set_fault(ch, true) -- 关闭双向纠偏时：平台合闸而现场断开只上报，不自动重合
            else
                local addr  = (want == 1) and RELAY_ON[ch] or RELAY_OFF[ch]
                local act_en = (want == 1) and "CLOSE" or "OPEN"
                if guard[ch] then
                    log.warn("ctrl", CH_NAME[ch], "监守模式：继续纠偏", "DI=", actual, "目标=", want)
                else
                    log.warn("ctrl", CH_NAME[ch], "本地状态偏离平台目标，强制纠偏",
                        "DI=", actual, "目标=", want)
                    add_log(string.format("CORRECT DO%d %s DI=%d", ch, act_en, actual))
                end
                pulse(addr)
                sys.wait(CFG.verify_ms)
                read_di()
                if st.di[ch] == want then
                    set_fault(ch, false)
                    if guard[ch] then
                        guard[ch] = false
                        add_log(string.format("GUARD OFF DO%d", ch))
                    else
                        add_log(string.format("DO%d %s OK", ch, act_en))
                    end
                else
                    set_fault(ch, true)
                    if not guard[ch] then
                        guard[ch] = true
                        add_log(string.format("GUARD ON DO%d", ch))
                        sys.publish("CTRL_FAULT", { ch = ch, reason = "guard" })
                    end
                end
            end
        end
    end
end

-- 平台目标 / 本地反馈状态对比：状态变化时立即打印，无变化也每 10 轮（约 10s）打一次心跳
local last_state_sig = nil
local state_round = 0
local function log_state()
    local ch = 1
    state_round = state_round + 1
    local sig = string.format("%d|%d|%d|%d|%d",
        st.target[ch], st.di[ch], st.lock_all, st.lock[ch], st.fault)
    if sig == last_state_sig and (state_round % 10) ~= 0 then return end
    last_state_sig = sig
    log.info("ctrl", string.format("平台目标=%s 本地反馈=%s 限制=%s 故障=%d 在线=%s",
        st.target[ch] == 1 and "合闸" or "断开",
        st.di[ch] == 1 and "合闸" or "断开",
        locked(ch) and "已限制" or "已解除",
        st.fault, st.online and "是" or "否"))
end

-- ==================== 控制任务 ====================
local function ctrl_task()
    sys.wait(1000) -- 等 meter_app 建立主站
    while true do
        while #queue > 0 do
            local job = table.remove(queue, 1)
            do_action(job.ch, job.act)
        end

        if read_di() then
            if not st.online then
                st.online = true
                st.fault = st.fault & (~4 & 0x07)
            end
            read_relay()
            enforce_local()
        else
            st.online = false
            st.fault = st.fault | 4
        end
        st.ts = os.time()
        log_state() -- 平台目标 / 本地反馈 对比（仅变化时打印）
        sys.publish("CTRL_STATE", snapshot())
        -- 监守模式：缩短间隔，每 2s 再动作一次（每次 2s 高电平），直到状态恢复
        sys.waitUntil("CTRL_REQ", guard[1] and CFG.guard_gap or CFG.poll_ms)
    end
end

-- ==================== 对外接口 ====================
-- 平台控制：ch=0 表示全部，act=1 合闸 / 0 跳闸（不受 lock 限制）
function M.switch(ch, act)
    -- 只有 1 路总开关：ch=0（全部）与 ch=1 等价
    if ch ~= 0 and not RELAY_ON[ch] then
        return '{"code":1,"type":"sw","value":"invalid ch, only 1 channel"}'
    end
    local list = (ch == 0) and { 1 } or { ch }
    for _, c in ipairs(list) do
        if RELAY_ON[c] then
            st.target[c] = (act == 1) and 1 or 0
            -- 限制本地合闸：
            --   平台断开 → 自动加限制（现场再手动合闸会被自动断开并上报）
            --   平台合闸 → 默认不自动解除（解除必须显式点「解除」按钮，
            --              否则"点合闸"会顺带解除限制并直接合闸）
            if act == 0 and CFG.auto_lock_on_open and st.lock[c] == 0 then
                st.lock[c] = 1
                add_log(string.format("AUTOLOCK DO%d", c))
            elseif act == 1 and CFG.auto_unlock_on_close
                and (st.lock_all == 1 or st.lock[c] == 1) then
                st.lock_all, st.lock[c] = 0, 0
                add_log(string.format("AUTOUNLOCK DO%d", c))
            end
            queue[#queue + 1] = { ch = c, act = (act == 1) and 1 or 0 }
            guard[c] = false
        end
    end
    save_state()
    sys.publish("CTRL_REQ")
    return string.format('{"code":0,"type":"sw","ch":%d,"act":%d}', ch, (act == 1) and 1 or 0)
end

-- 设置限制：all 传入时改总限制；ch+val 改单路限制（总限制开启时忽略单路设置）
function M.set_lock(all, ch, val)
    if all ~= nil then
        local nv = (all == 1) and 1 or 0
        if nv ~= st.lock_all then
            st.lock_all = nv
            add_log("LOCK ALL " .. (nv == 1 and "ON" or "OFF"))
        end
        if st.lock_all == 1 then
            st.lock[1], st.lock[2] = 0, 0 -- 总限制生效时清掉单路限制
            guard[1], guard[2] = false, false
        end
    end
    if ch then
        if st.lock_all == 1 then
            save_state()
            return '{"code":1,"type":"lock","value":"total lock is on"}'
        end
        st.lock[ch] = (val == 1) and 1 or 0
        guard[ch] = false
        add_log(string.format("LOCK DO%d %s", ch, st.lock[ch] == 1 and "ON" or "OFF"))
    end
    save_state()
    local s = snapshot()
    return string.format('{"code":0,"type":"lock","lock":%d,"lock_all":%d,"lock1":%d,"lock2":%d}',
        s.lock, s.lock_all, s.lock1, s.lock2)
end

function M.get() return snapshot() end

function M.get_json()
    local s = snapshot()
    return string.format(
        '{"code":0,"type":"sw_get","di1":%d,"di2":%d,"di_raw":%d,"target":%d,"lock":%d,"relay":%d,'
        .. '"fault":%d,"online":%s,"lock_all":%d,"lock1":%d,"lock2":%d}',
        s.di1, s.di2, s.di_raw, s.target, s.lock, s.relay, s.fault,
        s.online and "true" or "false", s.lock_all, s.lock1, s.lock2)
end

-- ==================== 启动 ====================
load_state()
load_logs()
sys.taskInit(ctrl_task)
log.info("ctrl", "开关控制就绪", "总限制", st.lock_all, "脉冲", CFG.pulse_ms, "ms")

return M
