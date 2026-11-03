--[[
@module  sim
@summary UAV GCS - 飞行状态机与遥测仿真
@version 1.0
@date    2026.11.02

=== 为什么要有这一层 ===
这个工程是"展示无人机姿态与飞控"的应用，机上一时半会接不到真飞控，
所以界面上所有会动的数字都来自这里：一个把四旋翼飞行动力学压缩到 200 行的仿真。
它不是物理精确的，但**所有量之间是互相咬合的**：
  倾斜角 -> 水平速度 -> 位置 -> 距起飞点距离 -> 链路质量 -> 丢包率
  桨转速 -> 电流 -> 电池电压 / 剩余电量 / 电调温度
  高度变化率 -> 垂直速度 -> 爬升时的电流峰值
所以界面上不会出现"速度 0 但位置在跑"这种一眼假的情况。

=== 三种输入源 ===
1、自动演示：上电 8 秒无人操作后自动跑一条完整航线
   （待机 -> 解锁 -> 起飞 12m -> 悬停 -> 定点巡航 -> 自动返航 -> 降落 -> 待机）
2、手动：姿态页按住 3D 视图 = 虚拟摇杆，左右横滚、上下俯仰；松手回中
3、按钮：功能页 / 姿态页的动作按钮直接改写目标高度与飞行模式

=== 坐标约定 ===
px 向东为正、py 向北为正（单位 m），yaw 0 度朝北、顺时针增大。
航向向量 = (sin(yaw), cos(yaw))，所以"回家"的期望航向是 atan2(-px, -py)。
]]
local fx = require "fx"

local M = {}

M.MODES = { "自稳", "定高", "定点", "返航" }
M.MODE_EN = { "STAB", "ALTH", "POS", "RTL" }

local S = nil
M.s = nil

-- ==================== 日志 ====================
local LOG_MAX = 40

--[[标点清洗：hzfont 的标点子集不全，全角逗号 / 冒号 / 问号在部分固件上会渲染成方框。
日志会被直接贴到功能页的 label 上，所以在这里统一换成空格 —— 单点收口，
比让每个调用点自己记住"别写全角标点"靠谱。字节转义是为了不受文件编码影响。]]
local function plain(s)
    s = string.gsub(s, "\239\188\140", " ")   -- ，
    s = string.gsub(s, "\239\188\154", " ")   -- ：
    s = string.gsub(s, "\239\188\159", " ")   -- ？
    return s
end

function M.log(level, text)
    if not S then return end
    local item = { t = S.t, txt = plain(text or ""), lv = level or "info" }
    table.insert(S.logs, 1, item)
    while #S.logs > LOG_MAX do
        table.remove(S.logs)
    end
    if log and log.info then
        if level == "warn" then
            log.warn("uav", text)
        elseif level == "err" then
            log.error("uav", text)
        else
            log.info("uav", text)
        end
    end
end

function M.fmt_time(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- ==================== 初始化 ====================
function M.init()
    S = {
        t = 0, tt = 0,
        armed = false, mode = 2,
        roll = 0, pitch = 0, yaw = 0,
        alt = 0, vspd = 0, gs = 0,
        vx = 0, vy = 0, px = 0, py = 0,
        volt = 16.7, curr = 0, mah = 0, batt = 100,
        sats = 0, hdop = 9.9, rssi = -120, loss = 100, lat = 0,
        temp_esc = 26, temp_imu = 28, vib = 0.05,
        rpm = { 0, 0, 0, 0 },
        link = false,
        cmd = { r = 0, p = 0, y = 0, alt = 0 },
        stick = { r = 0, p = 0, y = 0 },
        manual = false,
        demo = false,
        mission = "idle", mt = 0,
        idle = 0,
        dist = 0,
        flight_t = 0, armed_t = 0,
        track = {}, track_n = 0, trk_acc = 0,
        alt_hist = {}, alt_n = 0, alt_acc = 0,
        rssi_hist = {}, rssi_n = 0,
        logs = {},
        cal = { kind = "", t = 0, dur = 0 },
        fault = nil, fault_t = 0,
        wp = {}, wp_n = 0,
        home = { x = 0, y = 0 },
        last_touch = 0,
    }
    for i = 1, 200 do S.track[i] = { x = 0, y = 0 } end
    for i = 1, 90 do
        S.alt_hist[i] = 0
        S.rssi_hist[i] = -60
    end
    M.s = S
    M.log("info", "地面站启动，等待飞控连接")
    M.connect(true)
    return S
end

-- ==================== 连接 ====================
function M.connect(on)
    if not S then return end
    S.link = on and true or false
    if S.link then
        S.rssi = -58
        S.loss = 0.4
        S.lat = 24
        S.sats = 14
        S.hdop = 0.8
        M.log("info", "链路已建立，飞控心跳正常")
    else
        S.rssi = -120
        S.loss = 100
        S.lat = 0
        S.sats = 0
        S.hdop = 99
        S.demo = false
        S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
        M.log("warn", "链路已断开，飞行器进入失控保护")
    end
end

-- ==================== 动作 ====================
local function set_mission(name)
    S.mission = name
    S.mt = 0
end

function M.arm(on)
    if not S then return end
    on = on and true or false
    if S.armed == on then return end
    S.armed = on
    if on then
        S.flight_t = 0
        S.track_n = 0
        S.trk_acc = 0
        S.armed_t = S.t
        M.log("info", "飞控已解锁，电机怠速运转")
    else
        S.cmd.alt = 0
        S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
        M.log("info", string.format("飞控已上锁，本次飞行 %s", M.fmt_time(S.flight_t)))
    end
end

function M.set_mode(i)
    if not S then return end
    i = fx.clamp(math.floor(i), 1, #M.MODES)
    if S.mode == i then return end
    S.mode = i
    if i == 4 then
        S.cmd.alt = math.max(S.cmd.alt, 10)
        M.log("warn", "已切换 返航 模式，正在飞回起飞点")
    else
        M.log("info", "飞行模式切换为 " .. M.MODES[i])
    end
end

function M.takeoff(alt)
    if not S then return end
    if not S.link then
        M.log("err", "链路未连接，无法起飞")
        return
    end
    M.arm(true)
    M.set_mode(2)
    S.cmd.alt = alt or 12
    M.log("info", string.format("一键起飞，目标高度 %d m", math.floor(S.cmd.alt + 0.5)))
end

function M.land()
    if not S then return end
    S.cmd.alt = 0
    S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
    M.log("info", "执行降落，垂直下降中")
end

function M.rtl()
    if not S then return end
    M.set_mode(4)
    S.cmd.alt = math.max(S.cmd.alt, 10)
    if M.s.demo then set_mission("rtl") end
end

function M.hover()
    if not S then return end
    M.set_mode(3)
    S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
    S.cmd.alt = math.max(S.alt, 6)
    M.log("info", "定点悬停，位置保持已生效")
end

function M.calibrate(kind)
    if not S then return end
    local name = (kind == "compass") and "罗盘" or ((kind == "accel") and "加速度计" or "水平")
    S.cal.kind = name
    S.cal.t = 0
    S.cal.dur = 2.6
    M.log("info", "开始校准" .. name .. "，请保持飞行器静止")
end

function M.inject_fault(kind)
    if not S then return end
    if kind == nil or S.fault == kind then
        S.fault = nil
        S.fault_t = 0
        M.log("info", "故障注入已撤销，系统恢复正常")
        return
    end
    S.fault = kind
    S.fault_t = 9
    if kind == "gps" then
        M.log("err", "注入故障：GPS 失锁，卫星数归零")
    elseif kind == "link" then
        M.log("err", "注入故障：链路丢包 60%")
    else
        M.log("err", "注入故障：磁罗盘受扰")
    end
end

function M.reset_stats()
    if not S then return end
    S.mah = 0
    S.batt = 100
    S.alt_n = 0
    S.rssi_n = 0
    S.track_n = 0
    M.log("info", "统计与航迹已清零")
end

-- ==================== 触摸 / 摇杆 ====================
function M.touch()
    if not S then return end
    S.idle = 0
    if S.demo then
        S.demo = false
        -- 退出演示必须同时把上一帧的指令清零：
        -- 否则演示正处在"巡航"（pitch 0.55）时被接管，飞机会一直往前飞
        S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
        M.log("info", "检测到手动操作，退出自动演示")
    end
end

function M.set_stick(r, p, y)
    if not S then return end
    S.manual = true
    S.cmd.r = fx.clamp(r, -1, 1)
    S.cmd.p = fx.clamp(p, -1, 1)
    S.cmd.y = fx.clamp(y, -1, 1)
end

function M.stick_neutral()
    if not S then return end
    S.manual = false
    S.cmd.r, S.cmd.p, S.cmd.y = 0, 0, 0
end

-- ==================== 自动演示 ====================
function M.demo(dt)
    S.mt = S.mt + dt
    local C = S.cmd
    C.r, C.p, C.y = 0, 0, 0
    local m = S.mission

    if m == "idle" then
        C.alt = 0
        if S.mt > 3 then
            M.log("info", "自动演示：飞控自检通过，准备起飞")
            set_mission("arm")
        end
    elseif m == "arm" then
        if S.mt > 0.5 then
            M.arm(true)
            M.set_mode(2)
            set_mission("takeoff")
        end
    elseif m == "takeoff" then
        C.alt = 12
        if S.alt > 11.4 then
            M.log("info", "已到达 12 m，定高悬停")
            set_mission("hover")
        elseif S.mt > 14 then
            set_mission("hover")
        end
    elseif m == "hover" then
        C.alt = 12
        if S.mt > 4 then
            M.log("info", "切定点模式，执行预设航线")
            M.set_mode(3)
            set_mission("cruise")
        end
    elseif m == "cruise" then
        C.alt = 14 + math.sin(S.t * 0.4) * 1.5
        C.p = 0.55
        C.y = 0.35
        C.r = math.sin(S.t * 0.7) * 0.25
        if S.mt > 20 or S.dist > 45 then
            M.log("warn", "航线完成，触发自动返航")
            set_mission("rtl")
        end
    elseif m == "rtl" then
        C.alt = 12
        local want = math.deg(fx.atan2(-S.px, -S.py))
        C.y = fx.clamp(fx.deg_delta(S.yaw, want) / 25, -1, 1)
        C.p = fx.clamp(S.dist / 14, 0.12, 0.6)
        if S.dist < 2.5 or S.mt > 26 then
            M.log("info", "已回到起飞点上方，开始降落")
            set_mission("land")
        end
    elseif m == "land" then
        C.alt = 0
        if S.alt < 0.25 then
            M.arm(false)
            set_mission("done")
        end
    elseif m == "done" then
        if S.mt > 6 then
            set_mission("idle")
        end
    end
end

-- ==================== 每帧推进 ====================
local function push_track()
    if S.track_n >= #S.track then
        -- 满了就整体左移，避免每帧 table.remove(1)
        local tr = S.track
        for i = 2, #tr do
            tr[i - 1].x = tr[i].x
            tr[i - 1].y = tr[i].y
        end
        S.track_n = #tr - 1
        S.trk_acc = 0
    end
    local i = S.track_n + 1
    S.track[i].x = S.px
    S.track[i].y = S.py
    S.track_n = i
    S.trk_acc = 0
end

local function push_hist()
    local ah = S.alt_hist
    for i = 2, #ah do ah[i - 1] = ah[i] end
    ah[#ah] = S.alt
    local rh = S.rssi_hist
    for i = 2, #rh do rh[i - 1] = rh[i] end
    rh[#rh] = S.rssi
    S.alt_acc = 0
end

function M.update(dt)
    if not S then return end
    dt = fx.clamp(dt, 0.001, 0.2)
    S.t = S.t + dt
    S.idle = S.idle + dt

    -- 故障注入倒计时
    if S.fault_t > 0 then
        S.fault_t = S.fault_t - dt
        if S.fault_t <= 0 then
            S.fault = nil
            M.log("info", "故障已自动恢复，系统回到正常状态")
        end
    end

    -- 校准动画
    if S.cal.dur > 0 then
        S.cal.t = S.cal.t + dt
        if S.cal.t >= S.cal.dur then
            S.cal.dur = 0
            M.log("info", S.cal.kind .. "校准完成，偏置已写入")
        end
    end

    if S.demo then
        M.demo(dt)
    elseif S.manual then
        S.mt = S.mt + dt
    end

    -- 1、姿态跟随（微小的气动抖动混进目标值，再由趋近滤波抹平）
    local wob = (fx.noise1(S.t * 1.9) - 0.5) * 1.2
    local roll_t = S.cmd.r * 22
    local pitch_t = -S.cmd.p * 18
    if S.armed and S.alt > 0.5 then
        roll_t = roll_t + wob
        pitch_t = pitch_t + (fx.noise1(S.t * 2.3 + 7) - 0.5) * 1.0
    end
    S.roll = fx.approach(S.roll, roll_t, 0.16, dt)
    S.pitch = fx.approach(S.pitch, pitch_t, 0.16, dt)
    S.yaw = (S.yaw + S.cmd.y * 45 * dt) % 360

    -- 2、高度：目标高度做一阶跟随，限速爬升 / 下降
    local alt_t = S.armed and S.cmd.alt or 0
    local vmax = S.armed and 2.2 or 1.0
    local v = fx.clamp((alt_t - S.alt) * 0.85, -vmax, vmax)
    S.vspd = fx.approach(S.vspd, v, 0.25, dt)
    S.alt = S.alt + S.vspd * dt
    if S.alt <= 0 then
        S.alt = 0
        if S.vspd < 0 then S.vspd = 0 end
        if S.armed and alt_t <= 0.05 then
            M.arm(false)
        end
    end

    -- 3、水平运动：四旋翼倾多少飞多快
    local flying = S.armed and S.alt > 0.4
    local th = math.rad(S.yaw)
    local fwd = -S.pitch * 0.55
    local side = S.roll * 0.30
    local vx = math.sin(th) * fwd + math.cos(th) * side
    local vy = math.cos(th) * fwd - math.sin(th) * side
    if flying then
        S.vx = fx.approach(S.vx, vx, 0.12, dt)
        S.vy = fx.approach(S.vy, vy, 0.12, dt)
    else
        S.vx, S.vy = 0, 0
    end
    S.px = S.px + S.vx * dt
    S.py = S.py + S.vy * dt
    S.gs = math.sqrt(S.vx * S.vx + S.vy * S.vy)
    S.dist = math.sqrt(S.px * S.px + S.py * S.py)

    -- 4、动力：桨转速 -> 电流 -> 电量 / 电压 / 温度
    local load = 0
    if S.armed then
        load = fx.clamp(0.16 + S.gs * 0.05 + math.abs(S.cmd.p) * 0.16 + S.vspd * 0.09, 0.1, 1)
    end
    S.curr = fx.approach(S.curr, S.armed and (3.5 + 44 * load) or 0, 0.12, dt)
    S.mah = S.mah + S.curr * dt / 3.6
    S.batt = fx.clamp(100 - S.mah / 52, 0, 100)
    S.volt = 13.2 + S.batt * 0.036 - S.curr * 0.008
    S.temp_esc = fx.approach(S.temp_esc, 26 + S.curr * 0.85, 0.04, dt)
    S.temp_imu = fx.approach(S.temp_imu, 28 + S.curr * 0.22, 0.04, dt)
    S.vib = 0.06 + load * 0.22 + fx.noise1(S.t * 3.1) * 0.06

    local rpm0 = S.armed and (3300 + 4300 * load) or 0
    for i = 1, 4 do
        local j = fx.noise1(S.t * 5.3 + i * 11) - 0.5
        -- M1 右前 / M2 左前 / M3 右后 / M4 左后：右滚时右侧两桨加速
        local side_k = (i == 1 or i == 3) and 26 or -26
        S.rpm[i] = rpm0 + j * 300 + S.roll * side_k
    end

    if S.armed then
        S.flight_t = S.flight_t + dt
        S.armed_t = S.armed_t + dt
    end

    -- 5、链路
    if S.link then
        local sat = 13 + math.floor(fx.noise1(S.t * 0.35) * 5)
        if S.fault == "gps" then sat = 0 end
        S.sats = sat
        S.hdop = sat > 0 and (0.6 + fx.noise1(S.t * 0.21) * 0.5) or 9.9
        local rssi_t = -50 - S.dist * 0.10 - fx.noise1(S.t * 0.9) * 10
        local loss_t = 0.1 + fx.noise1(S.t * 0.7) * 0.8 + S.dist * 0.01
        if S.fault == "link" then
            rssi_t = rssi_t - 25
            loss_t = 55 + fx.noise1(S.t) * 12
        end
        S.rssi = fx.approach(S.rssi, rssi_t, 0.10, dt)
        S.loss = fx.approach(S.loss, loss_t, 0.10, dt)
        S.lat = fx.approach(S.lat, 16 + fx.noise1(S.t * 0.5) * 18 + S.dist * 0.05, 0.10, dt)
    else
        S.sats = 0
        S.hdop = 99
        S.rssi = fx.approach(S.rssi, -120, 0.2, dt)
        S.loss = fx.approach(S.loss, 100, 0.2, dt)
        S.lat = 0
    end

    -- 6、采样：航迹 0.3s 一点，曲线 0.2s 一点
    if S.armed then
        S.trk_acc = S.trk_acc + dt
        if S.trk_acc >= 0.3 then push_track() end
    end
    S.alt_acc = S.alt_acc + dt
    if S.alt_acc >= 0.2 then push_hist() end
end

return M
