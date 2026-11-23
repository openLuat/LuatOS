--[[
@module  vp_app
@summary 蒸气压测定仪工艺流程引擎（三次膨胀法），阀门 / 步进电机 / 加热 / 温压采集与结果计算
@version 2.1.0
@date    2026.11.17
@author  蒋骞
@usage
本文件为 plcui_vapor_pressure 演示项目的业务引擎，负责：
1、六个工艺环节的时序推进：进液 -> 清洗密闭腔体 -> 定量进液 1/4 ->
   加热恒温 37.5℃ -> 三次膨胀测定 -> 结果计算；
2、电磁阀 1 / 电磁阀 2 / 步进电机 / 加热模块的状态与动作，
   急停时阀门全关、电机停止、加热停止、液体定格不动；
3、复位是"排液复位"：清急停、关加热、阀1 关、阀2 开、步进下行把液体排空；
   环节 6 计算完成后自动复位一次，设备回位、液体排空，三点记录与结果保留；
4、腔体温度与压力跟踪，三次膨胀的稳压读数记录；
5、按 P = P_air0 * x + P_vap 对三组数据做最小二乘拟合，
   截距即实测蒸气压，再按 1.35%/℃ 修正到 37.8℃ 标准温度。

机械模型（两个阀门都接在腔体底部）：
1、步进电机在腔体正上方，经活塞杆拖动软塞，软塞横向填满腔体内壁，
   软塞下沿就是"液面刻度线"：阀1 打开时，软塞上拉在腔底形成负压，
   液体从腔体底部被吸进腔体，液面高度始终等于软塞下沿；
   两个阀门都关（密闭）后，液体进不来也出不去，液面就停在关阀时的高度；
2、活塞行程 0~110mm 与腔体高度 178mm 同尺度，所以
   液面百分比 = 活塞位置 / 178 * 100，最大约 62%；
3、定量进液 1/4 = 活塞拉到 44.5mm，此时液面正好是腔体高度的 25%；
4、密闭后活塞继续上拉，液面不动，软塞与液面之间空出来的部分是气相，
   三次膨胀就是把这段气相体积逐次做大。

体积比 x 是"气相体积之比"，按活塞位置换算（与界面液面显示解耦，液面只做视觉）：
V_gas(pos) = 0.75 * pos / 110（液相固定 1/4 腔体，不参与膨胀），
x = V_gas(关阀位) / V_gas(当前位) = 关阀位 / 当前位，
关阀位取 44.5mm 时三点 x 约为 1 / 0.58 / 0.40。

本演示没有接真实执行机构，泵阀与温压传感器由本文件的仿真模型给出；
接真机时只需把 set_valve / set_stepper / set_heater 与传感器读数替换成实际的
GPIO / PWM / ADC 驱动，界面与工艺时序不用改。

本文件的对外接口有 19 个：
1、vp_app.start          启动 200ms 工艺节拍
2、vp_app.auto_start     自动流程启动
3、vp_app.auto_pause     自动流程暂停 / 继续
4、vp_app.auto_stop      自动流程停止
5、vp_app.estop          急停（阀门全关、电机停、加热停、液体定格）
6、vp_app.reset          复位排液（清急停、关加热、阀2开、步进下行；keep=true 保留数据）
7、vp_app.stage_start    手动启动指定环节
8、vp_app.stage_stop     手动停止当前环节
9、vp_app.device_op      设备手动点动（阀门 / 步进连续）
10、vp_app.device_jump   步进定量移动（按当前步长上移 / 下移）
11、vp_app.set_step      设定定量移动步长 mm
12、vp_app.set_valve     设定电磁阀状态（接真机时替换驱动）
13、vp_app.set_stepper   设定步进方向（接真机时替换驱动）
14、vp_app.set_heater    设定加热模块开关（接真机时替换驱动）
15、vp_app.temp_step     恒温目标温度 ±0.5℃ 调整（25.0~60.0℃，默认 37.5）
16、vp_app.calc          三次膨胀数据拟合求蒸气压
17、vp_app.chip_state    取环节步骤条状态
18、vp_app.card_state    取环节卡片状态
19、vp_app.view          取界面用的标量变量表
]]

local vp_app = {}

-- 工艺节拍：200ms，只推进模型，不碰界面（界面按 500ms 刷）
local TICK_MS = 200

-- 环节定义：名称与时长（秒）
local STAGE_NAME = { "进液", "清洗密闭腔体", "定量进液 1/4",
                     "加热恒温", "三次膨胀", "结果计算" }
local STAGE_DUR = { 10, 8, 10, 16, 21, 3 }
local STAGE_CNT = 6

-- 设备与工艺参数
local POS_MAX = 110.0       -- 活塞行程 mm（与腔体像素高度同尺度）
local POS_SPEED = 15.0      -- 步进速度 mm/s
local CHAMBER_MM = 178.0    -- 腔体高度 mm，液面高度/百分比都按它换算
local POS_SEAL = 44.5       -- 定量进液终点：腔体 1/4，液面 25%
local T_SET = 37.5          -- 恒温测定温度默认值 ℃（界面上可 ±0.5 调整）
local T_SET_MIN = 25.0      -- 可设定下限 ℃
local T_SET_MAX = 60.0      -- 可设定上限 ℃
local T_SET_STEP = 0.5      -- 每次调整的步长 ℃
local T_IDLE = 25.0         -- 停机温度 ℃
local T_REF = 37.8          -- 标准温度 ℃
local HEAT_RATE = 1.4       -- 升温速率 ℃/s
local COOL_RATE = 0.25      -- 自然降温速率 ℃/s
local P_VAPOR = 46.5        -- 样本在 37.8℃ 的真实蒸气压 kPa
local P_AIR0 = 52.0         -- 密闭瞬间的气相分压 kPa
local TEMP_COEF = 0.0135    -- 蒸气压温度修正系数 1/℃
local STEP_DEFAULT = 10.0   -- 定量移动默认步长 mm

-- 三次膨胀的第二点：关阀位与满行程的中点
local POS_MID = POS_SEAL + (POS_MAX - POS_SEAL) * 0.5

-- 工艺状态表：界面只读，不允许外部直接改
vp_app.st = {
    mode = "auto",      -- auto / manual
    run = false,        -- 自动流程运行中
    stage = 0,          -- 当前环节 0=待机 1..6
    stage_run = false,  -- 当前环节是否在推进
    pause = false,      -- 自动流程暂停
    estop = false,      -- 急停已触发
    drain = false,      -- 复位排液进行中
    v1 = false,         -- 电磁阀 1 开
    v2 = false,         -- 电磁阀 2 开
    heat = false,       -- 加热模块开
    dir = 0,            -- 步进方向 1=上行 -1=下行 0=停
    target = nil,       -- 步进定量目标 mm
    step = STEP_DEFAULT,-- 定量移动步长 mm
    pos = 0.0,          -- 活塞位置 mm
    level = 0.0,        -- 腔体液面高度 mm（阀开时跟随活塞，阀关时定格）
    seal = POS_SEAL,    -- 关阀时的活塞位置，用于体积比换算
    tgt = T_SET,        -- 加热目标温度 ℃（界面 ±0.5 可调）
    temp = 24.6,        -- 腔体温度 ℃
    pres = 0.0,         -- 腔体压力 kPa
    expand = 0,         -- 已完成的测定点数 0..3
    hold = 0.0,         -- 当前环节计时 s
    records = {},       -- 三次测定记录 {x=体积比, p=压力, t=温度}
    done = {},          -- 已完成的环节标记
    press0 = nil,       -- 拟合截距（实测蒸气压）
    slope = nil,        -- 拟合斜率（气相反推值）
    rep = nil,          -- 拟合残差（重复性）
    result = nil,       -- 修正到 37.8℃ 的蒸气压
    note = "待机",
}

-- ==================== 仿真执行机构 ====================

--[[
设定电磁阀状态；接真机时替换成 gpio.setup 等实际驱动

@api vp_app.set_valve(no, on)

@参数 number no 阀门编号 1 / 2
@参数 boolean on true 开阀，false 关阀
]]
function vp_app.set_valve(no, on)
    local st = vp_app.st
    if no == 1 then
        st.v1 = on and true or false
    elseif no == 2 then
        st.v2 = on and true or false
    end
end

--[[
设定步进电机方向；接真机时替换成实际脉冲输出

@api vp_app.set_stepper(dir)

@参数 number dir 1 上行，-1 下行，0 停止
]]
function vp_app.set_stepper(dir)
    local st = vp_app.st
    st.target = nil
    st.dir = dir
end

--[[
设定加热模块开关；接真机时替换成继电器 / SSR 驱动

@api vp_app.set_heater(on)

@参数 boolean on true 开始加热，false 停止加热
]]
function vp_app.set_heater(on)
    vp_app.st.heat = on and true or false
end

--[[
调整恒温目标温度：每次 ±0.5℃，限幅 25.0~60.0℃，只影响后续升温，不改历史记录

:@api vp_app.temp_step(dir)

:@参数 number dir 1 升温设定，-1 降温设定

:@return number 调整后的目标温度 ℃
]]
function vp_app.temp_step(dir)
    local st = vp_app.st
    local t = st.tgt + (dir > 0 and T_SET_STEP or -T_SET_STEP)
    if t < T_SET_MIN then
        t = T_SET_MIN
    elseif t > T_SET_MAX then
        t = T_SET_MAX
    end
    -- 0.5 的倍数不会有浮点误差，这里仍然按一位小数收敛，避免显示成 37.499999
    st.tgt = math.floor(t * 10 + 0.5) / 10
    st.note = string.format("目标温度 %.1f ℃", st.tgt)
    log.info("vp", "调整目标温度", string.format("%.1f ℃", st.tgt))
    return st.tgt
end

-- ==================== 工具 ====================

-- 数值逼近目标值，每步最多走 step
local function approach(cur, target, step)
    if cur < target then
        cur = cur + step
        if cur > target then
            cur = target
        end
    elseif cur > target then
        cur = cur - step
        if cur < target then
            cur = target
        end
    end
    return cur
end

-- 当前温度下的蒸气压（样本特性曲线）
local function vapor_at(temp)
    return P_VAPOR * (1 + TEMP_COEF * (temp - T_REF))
end

-- 气相体积：腔体总容积减去固定液相（定量进液的 1/4 腔体）
-- pos=0 时气相为 0，pos=110 时气相 = 3/4 腔体
local function gas_of(pos)
    return 0.75 * (pos / POS_MAX)
end

-- 体积比 x = 密闭瞬间的气相体积 / 当前气相体积（约简后就是 seal / pos）
-- x=1 表示还没膨胀；x 越小 → 气相拉得越大 → 空气分压越低
local function x_of(pos, seal)
    local g0, g1 = gas_of(seal), gas_of(pos)
    if g0 <= 1e-6 or g1 <= 1e-6 then
        return 1.0     -- 气相为 0 无法膨胀，交给 calc 判"体积比异常"
    end
    return g0 / g1
end

-- 密闭腔体的目标压力：气相分压随体积衰减 + 饱和蒸气压
local function target_pres()
    local st = vp_app.st
    return vapor_at(st.temp) + P_AIR0 * x_of(st.pos, st.seal)
end

-- 液面跟随：阀1 或阀2 打开时液面 = 活塞下沿，两阀全关后液面定格
local function sync_level()
    local st = vp_app.st
    if st.v1 or st.v2 then
        st.level = st.pos
    end
end

-- 关闭全部阀门、停止步进（加热单独控制）
local function all_stop()
    local st = vp_app.st
    vp_app.set_valve(1, false)
    vp_app.set_valve(2, false)
    vp_app.set_stepper(0)
    st.stage_run = false
end

-- 记录第 i 个测定点的稳压读数
local function record_expansion()
    local st = vp_app.st
    st.expand = st.expand + 1
    local i = st.expand
    local x = x_of(st.pos, st.seal)
    local p = vapor_at(st.temp) + P_AIR0 * x + (math.random() - 0.5) * 0.5
    st.records[i] = { x = x, p = p, t = st.temp }
    st.pres = p
    st.note = string.format("第 %d 点 %.1f kPa", i, p)
    log.info("vp", "测定记录", i, string.format("%.2f kPa", p),
             string.format("%.1f ℃", st.temp), string.format("体积比 %.3f", x))
end

-- ==================== 结果计算 ====================

--[[
按三组测定读数拟合 P = a + b * x，截距 a 为实测蒸气压

@api vp_app.calc()

@return boolean 拟合成功返回 true，数据不足或退化返回 false
]]
function vp_app.calc()
    local st = vp_app.st
    local n = #st.records
    if n < 3 then
        st.note = "测定数据不足 3 组"
        log.warn("vp", "测定数据不足，无法计算")
        return false
    end
    local sx, sy, sxx, sxy, tsum = 0, 0, 0, 0, 0
    for i = 1, n do
        local r = st.records[i]
        sx = sx + r.x
        sy = sy + r.p
        sxx = sxx + r.x * r.x
        sxy = sxy + r.x * r.p
        tsum = tsum + r.t
    end
    local den = n * sxx - sx * sx
    if den == 0 then
        st.note = "体积比异常，无法拟合"
        log.warn("vp", "拟合分母为 0，体积比异常")
        return false
    end
    local slope = (n * sxy - sx * sy) / den
    local intercept = (sy - slope * sx) / n
    local rep = 0
    for i = 1, n do
        local r = st.records[i]
        local e = math.abs(r.p - (intercept + slope * r.x))
        if e > rep then
            rep = e
        end
    end
    local tavg = tsum / n
    st.press0 = intercept
    st.slope = slope
    st.rep = rep
    st.result = intercept * (1 + TEMP_COEF * (T_REF - tavg))
    st.note = string.format("蒸气压 %.1f kPa（37.8℃）", st.result)
    log.info("vp", "结果计算", string.format("截距 %.2f", intercept),
             string.format("斜率 %.2f", slope), string.format("重复性 %.2f", rep),
             string.format("标准值 %.2f", st.result))
    return true
end

-- ==================== 环节控制 ====================

-- 进入指定环节，按环节初始动作开阀 / 启停步进 / 开关加热
local function enter_stage(idx, manual)
    local st = vp_app.st
    st.stage = idx
    st.pause = false
    st.hold = 0.0
    st.done[idx] = nil
    st.target = nil
    st.mode = manual and "manual" or "auto"
    if idx == 1 then
        -- 进液：阀1 开，活塞从下限上拉把液体吸进腔体，液面跟着活塞走
        vp_app.set_heater(false)
        vp_app.set_valve(1, true)
        vp_app.set_valve(2, false)
        st.pos = 0.0
        st.level = 0.0
        st.pres = 0.0
        st.target = POS_MAX
    elseif idx == 2 then
        -- 清洗：双阀关闭，清洗气脉动冲刷；后段阀2 开、活塞下行吹扫排空
        vp_app.set_heater(false)
        vp_app.set_valve(1, false)
        vp_app.set_valve(2, false)
        vp_app.set_stepper(0)
    elseif idx == 3 then
        -- 定量进液 1/4：阀2 关、阀1 开，活塞拉到 44.5mm，液面正好 25%
        vp_app.set_heater(false)
        vp_app.set_valve(2, false)
        vp_app.set_valve(1, true)
        st.pos = 0.0
        st.level = 0.0
        st.pres = 0.0
        st.target = POS_SEAL
    elseif idx == 4 then
        -- 加热恒温：双阀关闭，液面定格在 25%，升温到 37.5℃ 并保持
        vp_app.set_valve(1, false)
        vp_app.set_valve(2, false)
        vp_app.set_stepper(0)
        vp_app.set_heater(true)
        st.seal = st.pos
        st.expand = 0
        st.records = {}
        st.pres = target_pres()
    elseif idx == 5 then
        -- 三次膨胀：双阀关闭、液面定格，活塞上拉把气相体积做大
        vp_app.set_valve(1, false)
        vp_app.set_valve(2, false)
        vp_app.set_heater(true)
        if st.expand == 0 then
            st.records = {}
            record_expansion()
        end
    else
        vp_app.set_heater(false)
        all_stop()
    end
    st.stage_run = true
    st.note = "环节 " .. idx .. " " .. STAGE_NAME[idx]
    log.info("vp", "进入环节", idx, STAGE_NAME[idx])
end

-- 环节结束收尾
local function finish_stage()
    local st = vp_app.st
    st.done[st.stage] = true
    st.stage_run = false
    st.target = nil
    if st.stage == 4 then
        -- 加热与恒温要延续到膨胀环节，这里只停阀与步进
        vp_app.set_valve(1, false)
        vp_app.set_valve(2, false)
        vp_app.set_stepper(0)
        st.note = "恒温稳定，已记录第 1 点"
    elseif st.stage == 6 then
        vp_app.set_heater(false)
        all_stop()
        st.note = st.result and string.format("测定完成 %.1f kPa", st.result) or "计算失败"
    else
        all_stop()
        st.note = STAGE_NAME[st.stage] .. " 完成"
    end
    log.info("vp", "环节完成", st.stage, STAGE_NAME[st.stage])
end

-- ==================== 节拍：环境量推进 ====================

-- 温度、活塞位置、液面：与环节无关的公共推进
local function step_env(dt)
    local st = vp_app.st

    if st.heat then
        st.temp = approach(st.temp, st.tgt, HEAT_RATE * dt)
        if math.abs(st.temp - st.tgt) < 0.15 then
            st.temp = st.tgt + (math.random() - 0.5) * 0.08
        end
    else
        st.temp = approach(st.temp, T_IDLE, COOL_RATE * dt)
        if math.abs(st.temp - T_IDLE) < 0.15 then
            st.temp = T_IDLE + (math.random() - 0.5) * 0.06
        end
    end

    -- 步进：定量目标优先，其次连续方向
    if st.target then
        st.pos = approach(st.pos, st.target, POS_SPEED * dt)
        if st.pos == st.target then
            st.target = nil
            st.dir = 0
        end
    elseif st.dir > 0 then
        st.pos = approach(st.pos, POS_MAX, POS_SPEED * dt)
        if st.pos >= POS_MAX then
            st.dir = 0
        end
    elseif st.dir < 0 then
        st.pos = approach(st.pos, 0, POS_SPEED * dt)
        if st.pos <= 0 then
            st.dir = 0
        end
    end

    if st.pos < 0 then
        st.pos = 0.0
    elseif st.pos > POS_MAX then
        st.pos = POS_MAX
    end

    sync_level()
    st.flow = st.dir ~= 0 or st.target ~= nil
end

-- 复位排液：阀2 开、活塞下行，液面跟着活塞落回腔底
local function step_drain(dt)
    local st = vp_app.st
    st.pres = approach(st.pres, 0, 20.0 * dt)
    if st.pos <= 0.4 and st.level <= 0.4 then
        st.pos = 0.0
        st.level = 0.0
        st.drain = false
        vp_app.set_valve(2, false)
        vp_app.set_stepper(0)
        st.note = "复位完成，已排空"
        log.info("vp", "复位排液完成")
    end
end

local function step_stage(dt)
    local st = vp_app.st
    local s = st.stage
    if s == 1 then
        st.target = POS_MAX
        st.pres = approach(st.pres, 0.4, 10.0 * dt)
    elseif s == 2 then
        if st.hold < STAGE_DUR[2] * 0.40 then
            -- 前段密闭脉动冲刷（液面定格在进液高度）
            local wobble = 18.0 * math.abs(math.sin(st.hold * 1.6))
            st.pres = approach(st.pres, 6.0 + wobble, 30.0 * dt)
        else
            -- 后段吹扫排空：阀2 开、活塞下行，液面跟着落下
            vp_app.set_valve(2, true)
            st.target = 0.0
            st.pres = approach(st.pres, 1.0, 25.0 * dt)
        end
    elseif s == 3 then
        vp_app.set_valve(2, false)
        vp_app.set_valve(1, true)
        st.target = POS_SEAL
        st.pres = approach(st.pres, 0.4, 12.0 * dt)
    elseif s == 4 then
        vp_app.set_heater(true)
        st.pres = approach(st.pres, target_pres(), 22.0 * dt)
        if st.expand == 0 and st.hold >= 6.0
                and math.abs(st.temp - st.tgt) < 0.35 then
            record_expansion()
        end
    elseif s == 5 then
        vp_app.set_heater(true)
        local goal = POS_MID
        if st.expand >= 2 then
            goal = POS_MAX
        end
        if math.abs(st.pos - goal) > 0.3 then
            st.target = goal
        else
            st.target = nil
            local mark = 4.0 + 7.0 * (st.expand - 1)
            if st.expand < 3 and st.hold >= mark then
                record_expansion()
            end
        end
        st.pres = approach(st.pres, target_pres(), 22.0 * dt)
    elseif s == 6 then
        if st.hold >= 1.0 and not st.result then
            vp_app.calc()
        end
    end
end

--[[
工艺节拍回调：200ms 推进温度 / 压力 / 活塞 / 液面与环节计时

@api vp_app.tick_cbfunc()
]]
function vp_app.tick_cbfunc()
    local st = vp_app.st
    local dt = TICK_MS / 1000

    if st.estop then
        -- 急停：液体、阀门、电机、加热全部定格
        st.flow = false
        return
    end

    step_env(dt)

    if st.drain then
        step_drain(dt)
        return
    end

    if not st.stage_run or st.pause then
        st.flow = st.dir ~= 0 or st.target ~= nil
        if st.stage_run then
            -- 暂停时压力缓慢泄放，温度保持
            st.pres = approach(st.pres, 0, 1.0 * dt)
        end
        return
    end

    st.hold = st.hold + dt
    step_stage(dt)

    if st.hold >= STAGE_DUR[st.stage] then
        local finished = st.stage
        finish_stage()
        if finished >= STAGE_CNT then
            -- 计算完成 -> 自动复位排液：设备回位、液体排空，三点记录与结果保留
            st.run = false
            st.mode = "auto"
            if st.result then
                vp_app.reset(true)
            end
        elseif st.run then
            enter_stage(finished + 1, false)
        end
    end
end

--[[
启动工艺节拍（由 boot_app 在界面就绪后调用一次）

@api vp_app.start()
]]
function vp_app.start()
    sys.timerLoopStart(vp_app.tick_cbfunc, TICK_MS)
    log.info("vp", "工艺节拍启动", TICK_MS .. "ms")
end

-- ==================== 对外操作 ====================

--[[
自动流程启动：从环节 1 开始顺序执行到结果计算

@api vp_app.auto_start()

@return boolean 已启动返回 true，急停状态下拒绝启动返回 false
]]
function vp_app.auto_start()
    local st = vp_app.st
    if st.estop then
        st.note = "急停未复位，禁止启动"
        log.warn("vp", "急停未复位，拒绝自动启动")
        return false
    end
    st.run = true
    st.drain = false
    st.done = {}
    st.records = {}
    st.expand = 0
    st.result = nil
    st.press0 = nil
    st.slope = nil
    st.rep = nil
    enter_stage(1, false)
    log.info("vp", "自动流程启动")
    return true
end

--[[
自动流程暂停 / 继续

@api vp_app.auto_pause()

@return boolean 暂停中返回 true，已继续返回 false
]]
function vp_app.auto_pause()
    local st = vp_app.st
    if not st.run then
        st.note = "自动流程未运行"
        return false
    end
    st.pause = not st.pause
    st.note = st.pause and "流程已暂停" or "流程继续"
    log.info("vp", st.pause and "流程暂停" or "流程继续")
    return st.pause
end

--[[
自动流程停止：阀门全关、步进停止、加热停止，保留已采集数据

@api vp_app.auto_stop()
]]
function vp_app.auto_stop()
    local st = vp_app.st
    st.run = false
    st.pause = false
    st.target = nil
    vp_app.set_heater(false)
    all_stop()
    st.note = "流程停止"
    log.info("vp", "自动流程停止")
end

--[[
急停：阀门全关、步进立即停止、加热停止、液面定格，需复位后才能再次启动

@api vp_app.estop()
]]
function vp_app.estop()
    local st = vp_app.st
    st.estop = true
    st.run = false
    st.pause = false
    st.drain = false
    st.target = nil
    vp_app.set_heater(false)
    all_stop()
    st.flow = false
    st.note = "急停：阀全关、电机停、加热停"
    log.warn("vp", "急停已触发")
end

--[[
复位排液：清急停、关加热、阀1 关、阀2 开、步进下行把液体排空

@api vp_app.reset(keep)

@参数 boolean keep 可选，true 表示保留三点记录与拟合结果（测定完成后自动复位），
        省略或 false 时清空记录、结果与环节标记（手动复位）

@return boolean 总是返回 true，复位动作可重复执行
]]
function vp_app.reset(keep)
    local st = vp_app.st
    st.estop = false
    st.run = false
    st.pause = false
    st.stage = 0
    st.stage_run = false
    st.hold = 0.0
    st.seal = POS_SEAL
    st.target = 0.0
    vp_app.set_heater(false)
    st.v1 = false
    st.v2 = true
    st.dir = -1
    st.drain = true
    if keep then
        -- 测定完成后的自动复位：只把设备回位，三点记录与拟合结果留给界面
        st.note = "测定完成，自动复位排液中"
        log.info("vp", "测定完成，自动复位排液", string.format("%.1f kPa", st.result or 0))
    else
        st.expand = 0
        st.records = {}
        st.done = {}
        st.press0 = nil
        st.slope = nil
        st.rep = nil
        st.result = nil
        st.note = "复位：阀2 开，步进下行排液"
        log.info("vp", "复位到待机，开始排液")
    end
    return true
end

--[[
手动启动指定环节（自动流程会停止）

@api vp_app.stage_start(idx)

@参数 number idx 环节号 1..6

@return boolean 启动成功返回 true，急停或参数非法返回 false
]]
function vp_app.stage_start(idx)
    local st = vp_app.st
    if st.estop then
        st.note = "急停未复位，禁止启动环节"
        log.warn("vp", "急停未复位，拒绝手动启动")
        return false
    end
    if not idx or idx < 1 or idx > STAGE_CNT then
        return false
    end
    st.run = false
    st.drain = false
    enter_stage(idx, true)
    return true
end

--[[
手动停止当前环节

@api vp_app.stage_stop()
]]
function vp_app.stage_stop()
    local st = vp_app.st
    if not st.stage_run then
        return
    end
    st.run = false
    st.stage_run = false
    st.target = nil
    vp_app.set_heater(false)
    all_stop()
    st.note = "环节手动停止"
    log.info("vp", "手动停止环节", st.stage)
end

--[[
设备手动操作：阀门与步进的连续点动，不改变流程环节

@api vp_app.device_op(name)

@参数 string name 动作名 v1_open / v1_close / v2_open / v2_close /
                  up / down / motor_stop

@return boolean 动作被接受返回 true
]]
function vp_app.device_op(name)
    local st = vp_app.st
    if st.estop then
        st.note = "急停未复位，禁止设备操作"
        log.warn("vp", "急停未复位，拒绝设备操作", name)
        return false
    end
    if name == "v1_open" then
        vp_app.set_valve(1, true)
    elseif name == "v1_close" then
        vp_app.set_valve(1, false)
    elseif name == "v2_open" then
        vp_app.set_valve(2, true)
    elseif name == "v2_close" then
        vp_app.set_valve(2, false)
    elseif name == "up" then
        vp_app.set_stepper(1)
    elseif name == "down" then
        vp_app.set_stepper(-1)
    elseif name == "motor_stop" then
        vp_app.set_stepper(0)
    else
        return false
    end
    st.note = "设备手动 " .. name
    log.info("vp", "设备手动操作", name)
    return true
end

--[[
步进定量移动：按当前步长上移 / 下移，到底或到顶自动截断

@api vp_app.device_jump(dir)

@参数 number dir 1 上移，-1 下移

@return boolean 动作被接受返回 true
]]
function vp_app.device_jump(dir)
    local st = vp_app.st
    if st.estop then
        st.note = "急停未复位，禁止设备操作"
        log.warn("vp", "急停未复位，拒绝定量移动")
        return false
    end
    if dir ~= 1 and dir ~= -1 then
        return false
    end
    local goal = st.pos + dir * st.step
    if goal < 0 then
        goal = 0.0
    elseif goal > POS_MAX then
        goal = POS_MAX
    end
    st.target = goal
    st.dir = 0
    st.note = string.format("定量%s %.0f mm", dir > 0 and "上移" or "下移", st.step)
    log.info("vp", "步进定量移动", dir, string.format("%.1f -> %.1f mm", st.pos, goal))
    return true
end

--[[
设定定量移动步长

@api vp_app.set_step(mm)

@参数 number mm 步长 1..100
]]
function vp_app.set_step(mm)
    local st = vp_app.st
    if not mm or mm < 1 or mm > 100 then
        return
    end
    st.step = mm
    st.note = string.format("定量步长 %.0f mm", mm)
    log.info("vp", "设定步长", mm)
end

-- ==================== 界面取数 ====================

--[[
取第 i 个环节的步骤条状态

@api vp_app.chip_state(i)

@参数 number i 环节号 1..6

@return string "g" 未开始 / "a" 进行中 / "d" 已完成
]]
function vp_app.chip_state(i)
    local st = vp_app.st
    if st.done[i] then
        return "d"
    end
    if st.stage == i and st.stage_run then
        return "a"
    end
    return "g"
end

--[[
取第 i 个环节的卡片状态

@api vp_app.card_state(i)

@return string 状态名 idle / run / done / alarm
@return string 状态文字
]]
function vp_app.card_state(i)
    local st = vp_app.st
    if st.estop then
        return "alarm", "急停"
    end
    if st.stage == i and st.stage_run then
        return "run", "运行中"
    end
    if st.done[i] then
        return "done", "已完成"
    end
    return "idle", "待机"
end

--[[
取界面用的标量变量表；绑定表里每个 var 都必须是标量，不许塞表

@api vp_app.view()

@return table 变量表
]]
function vp_app.view()
    local st = vp_app.st
    local v = {}
    v.pres = st.pres
    v.temp = st.temp
    v.pos = st.pos
    v.level = st.level
    v.liq = 100.0 * st.level / CHAMBER_MM
    -- 体积比只对"密闭后膨胀"有意义：活塞还没越过关阀位时按 1.000 显示，
    -- 避免进液阶段出现 x>1 的怪读数（压力模型仍用 x_of 原值）
    local x = x_of(st.pos, st.seal)
    v.x = x > 1.0 and 1.0 or x
    v.x_s = string.format("体积比 %.3f", v.x)
    v.car_s = string.format("软塞高度 %.1f mm", st.pos)
    v.lv_s = string.format("液面高度 %.1f mm", st.level)
    v.flow = st.flow
    v.heat = st.heat
    v.tgt = st.tgt
    v.tgt_s = string.format("设定 %.1f℃", st.tgt)
    v.press0 = st.press0 or 0.0
    v.slope = st.slope or 0.0
    v.rep = st.rep or 0.0
    v.result = st.result or 0.0
    v.v1 = st.v1
    v.v2 = st.v2
    v.step = st.step
    v.lvl_s = string.format("液位 %d%%", math.floor(v.liq + 0.5))
    v.pos_s = string.format("步进 %.1f mm", st.pos)
    v.step_s = string.format("步长 %.0f", st.step)
    v.result_s = st.result and string.format("%.1f kPa", st.result) or "-- kPa"
    v.v1_s = st.v1 and "阀1:开" or "阀1:关"
    v.v2_s = st.v2 and "阀2:开" or "阀2:关"
    v.valve_s = string.format("%s %s", v.v1_s, v.v2_s)
    v.heat_s = string.format("加热 %s %.1f℃", st.heat and "开" or "关", st.tgt)
    v.state_s = v.valve_s .. " / " .. v.heat_s
    v.note = st.note

    local stage_txt = st.stage > 0 and (st.stage .. " " .. STAGE_NAME[st.stage]) or "--"
    v.stage_s = "环节 " .. stage_txt
    v.sum1 = "当前环节 " .. stage_txt
    v.sum2 = string.format("腔体压力 %.1f kPa", st.pres)
    v.sum3 = string.format("腔体温度 %.1f ℃", st.temp)
    v.sum4 = string.format("步进位置 %.1f mm", st.pos)
    v.sum5 = v.state_s
    v.sum6 = st.result and string.format("蒸气压 %.1f kPa", st.result) or "蒸气压 -- kPa"

    if st.estop then
        v.lamp = "alarm"
        v.badge = "急停"
        v.alarm = true
    elseif st.drain then
        v.lamp = "run"
        v.badge = "复位排液中"
        v.alarm = false
    elseif st.stage_run then
        v.lamp = "run"
        v.badge = st.pause and "已暂停" or (STAGE_NAME[st.stage] .. " 进行中")
        v.alarm = false
    else
        v.lamp = "idle"
        v.badge = st.result and "测定完成" or "待机"
        v.alarm = false
    end
    return v
end

--[[
取三次测定记录条数（测试页表格用）

@api vp_app.record_count()

@return number 已记录的测定点数
]]
function vp_app.record_count()
    return #vp_app.st.records
end

--[[
取第 i 条测定记录

@api vp_app.record(i)

@param number i 记录序号 1..3

@return table 记录表 {x=体积比, p=压力, t=温度}，不存在返回 nil
]]
function vp_app.record(i)
    return vp_app.st.records[i]
end

return vp_app
