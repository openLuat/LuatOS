--[[
@module  data_app
@summary 业务数据层：6 态状态机、PID 模拟、液位、事件记录、手自动两级确认
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件持有全部业务状态，UI 层只读 data_app.get() 的结果并按 ui_vars 刷屏：
1、data_app.init           初始化状态机（停机态）
2、data_app.get            返回当前视图变量表（每帧一份，标量）
3、data_app.step           每秒推进：自动态 PV/MV 波动、液位缓降、液位低告警
4、data_app.set_state       状态切换（6 态）+ 追加事件
5、data_app.toggle_dev      远程单操：泵1 / 泵2 / 搅拌机
6、data_app.confirm_mode    手自动确认；data_app.disarm_mode 取消确认
7、data_app.reset_fault     故障复位 -> 停机
本文件的对外接口有 8 个。
]]

local data_app = {}

local ui_vars = require "ui_vars"

local state = "stop"
local pv, sp, mv = nil, 5.0, 0
local level = 72
local dev = { p1 = false, p2 = false, mx = false }
local events = {}
local mode_arm = false

-- 时钟/事件时间戳：PC 模拟器与真机都支持 os.date
local function now_hms()
    return os.date("%H:%M:%S")
end

local function add_event(text)
    table.insert(events, 1, { t = now_hms(), s = text })
    if #events > 16 then table.remove(events) end
end

--[[ 初始化：停机态 ]]
function data_app.init()
    state = "stop"
    pv, mv = nil, 0
    level = 72
    dev.p1, dev.p2, dev.mx = false, false, false
    events = {}
    mode_arm = false
    add_event("系统初始化完成，等待操作")
    add_event("PLC 通讯建立 · 从站 1")
    add_event("当前状态：停机")
end

--[[ 状态切换：6 态 ]]
function data_app.set_state(key)
    if not ui_vars.STATE[key] then return false end
    state = key
    mode_arm = false
    if key == "stop" then
        pv, mv = nil, 0
        dev.p1, dev.p2, dev.mx = false, false, false
    elseif key == "localm" then
        pv, mv = 4.6, 48
    elseif key == "remote" then
        pv = 4.5
        if mv == 0 then mv = 45 end
    elseif key == "auto" then
        pv, mv = 4.2, 56
    elseif key == "fault" then
        pv, mv = nil, 0
        dev.p1, dev.p2, dev.mx = false, false, false
    elseif key == "maint" then
        pv, mv = nil, 0
        dev.p1, dev.p2, dev.mx = false, false, false
    end
    add_event("状态切换 -> " .. ui_vars.STATE[key].name)
    return true
end

function data_app.get_state()
    return state
end

--[[ 远程单操 ]]
function data_app.toggle_dev(which)
    if state ~= "remote" then return false end
    if dev[which] == nil then return false end
    dev[which] = not dev[which]
    local name = { p1 = "PAC 计量泵", p2 = "PAM 计量泵", mx = "搅拌机" }
    add_event("单操：" .. (name[which] or which) .. (dev[which] and " 启动" or " 停止"))
    return true
end

--[[ 手自动确认（两级按）：返回 true 表示进入待确认 ]]
function data_app.confirm_mode()
    if state == "auto" then
        data_app.set_state("remote")
        add_event("确认切换 -> 远程手动 / PID 退出")
    elseif state == "remote" then
        if not mode_arm then
            mode_arm = true
            add_event("切换到自动待确认，再按一次执行")
        else
            mode_arm = false
            data_app.set_state("auto")
            add_event("确认切换 -> 自动运行 / PID 投入")
        end
    else
        data_app.set_state("remote")
        add_event("控制模式 -> 远程手动")
    end
    return mode_arm
end

function data_app.disarm_mode()
    mode_arm = false
end

--[[ 故障复位 -> 停机 ]]
function data_app.reset_fault()
    if state ~= "fault" then return false end
    data_app.set_state("stop")
    add_event("故障复位 -> 系统回到停机")
    return true
end

--[[ 每秒推进：自动态 PID 波动 + 液位缓降 ]]
function data_app.step()
    local changed = false
    if state == "auto" then
        pv = 4.2 + (math.random(0, 70) - 35) / 100.0
        if pv < 3.6 then pv = 3.6 end
        if pv > 4.9 then pv = 4.9 end
        mv = 56 + math.random(-6, 6)
        level = level - 0.12
        if level < 15 then level = 15 end
        changed = true
    end
    return changed
end

local function level_src()
    local i = math.floor((100 - level) / 20)
    if i < 0 then i = 0 end
    if i > 4 then i = 4 end
    return "lv" .. i
end

--[[ 返回视图变量表：每项都是标量，绝不把整张表塞给 set_text ]]
function data_app.get()
    local v = {}
    local st = ui_vars.STATE[state]
    v.state_name = st.name
    v.state_ico  = st.ico
    v.badge_src  = st.badge
    v.banner_src = st.banner
    v.banner_txt = st.txt
    v.banner_hint = st.hint

    -- 待确认时横幅给出提示
    if mode_arm then
        v.banner_txt = "再按一次「手/自动」确认切换到自动运行"
        v.banner_hint = "5 秒内未确认自动解除"
    end

    -- 设备徽章
    local function devbadge(key)
        if state == "stop" then
            return "stop"
        elseif state == "localm" then
            return "localm"
        elseif state == "remote" then
            return dev[key] and "remote" or "stop"
        elseif state == "auto" then
            return "auto"
        elseif state == "fault" then
            return "fault"
        else
            return "lock"
        end
    end
    -- 设备徽章：显式写出每个变量，便于静态自检核对绑定表
    local b1 = ui_vars.BADGE[devbadge("p1")] or ui_vars.BADGE.stop
    v.p1_badge, v.p1_btxt = b1.src, b1.txt
    local b2 = ui_vars.BADGE[devbadge("p2")] or ui_vars.BADGE.stop
    v.p2_badge, v.p2_btxt = b2.src, b2.txt
    local bm = ui_vars.BADGE[devbadge("mx")] or ui_vars.BADGE.stop
    v.mx_badge, v.mx_btxt = bm.src, bm.txt
    local lv_key = "normal"
    if state == "fault" then
        lv_key = "low"
    elseif state == "maint" then
        lv_key = "lock"
    end
    local bl = ui_vars.BADGE[lv_key]
    v.lv_badge, v.lv_btxt = bl.src, bl.txt

    v.p1_out = tostring(math.floor(mv)) .. "%"
    v.p2_out = tostring(math.floor(mv * 0.8)) .. "%"
    v.level_txt = tostring(math.floor(level)) .. "%"
    v.level_src = level_src()

    -- 工艺流程底图按状态切换（用 STATE 表的显式资源名，避免 localm -> flow_localm 的拼接错）
    v.flow_src = st.flow
    v.flow_anim_hidden = (state ~= "auto")

    -- PID
    v.pv_txt = (pv == nil and "--" or string.format("%.1f", pv)) .. " NTU"
    v.mv_txt = tostring(math.floor(mv)) .. " %"
    v.mv_width = math.floor(mv / 100 * 180)
    if v.mv_width < 1 then v.mv_width = 1 end
    if v.mv_width > 180 then v.mv_width = 180 end

    -- 维护罩
    v.maint_hidden = (state ~= "maint")

    -- 操作按钮使能
    local single = (state == "remote")
    v.btn_p1_dis  = not single
    v.btn_p2_dis  = not single
    v.btn_mx_dis  = not single
    v.btn_mode_dis = not (state == "remote" or state == "auto")
    v.btn_rst_dis = (state ~= "fault")
    v.op_hint = ({
        stop = "操作区 · 全部禁用",
        localm = "现场控制中 · HMI 只读",
        remote = "远程单操 · 已解锁",
        auto = "PID 自动调节中",
        fault = "仅故障复位可用",
        maint = "挂牌锁定 · 禁止操作",
    })[state]

    -- 事件记录最近 3 行
    for i = 1, 3 do
        local e = events[i]
        v["log" .. i] = e and (e.t .. " " .. e.s) or "--:--:--"
    end

    return v
end

return data_app
