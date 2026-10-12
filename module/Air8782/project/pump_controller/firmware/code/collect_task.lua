--[[
@module  collect_task
@summary 采集主任务（600ms 周期采集 15 项寄存器）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.2 与嵌入式软件总体设计.md 4.9 / 8.2：
1. 等待网络就绪（NET_READY）；
2. 初始化 Modbus 主站（modbus_master.setup，含 485 供电使能）；
3. 按 config_app.collect_ms（600ms）周期，顺序读取 modbus_map.fields 的 15 项寄存器；
4. 经 state_norm 规整后发布 PUMP_DATA_READY；
5. 降级模拟采集：PC 模拟器无 485，或真机未接/离线变频器时，若 config_app.sim_fake_collect
   为真（真机还需 sim_fake_on_device=true），自动切换“模拟采集数据”继续跑通上报链路，
   并周期探测变频器恢复后自动切回真实采集。
本模块无对外接口，直接 require "collect_task" 即加载运行。
]]

local msg_bus       = require("msg_bus")
local config_app    = require("config_app")
local modbus_map    = require("modbus_map")
local modbus_master = require("modbus_master")
local state_norm    = require("state_norm")

-- 模拟采集的轮次计数（用于让模拟数据随轮次变化）
local sim_round = 0

-- 读取单项（含重试），失败返回 nil
local function read_one(f)
    local attempts = config_app.modbus_retry + 1
    for _ = 1, attempts do
        local v = modbus_master.read_reg(f.reg)
        if v ~= nil then
            return v
        end
        sys.wait(20)
    end
    log.warn("collect_task", "采集失败", f.key, string.format("0x%04X", f.reg))
    return nil
end

-- 读取单项（模拟）：返回模拟原始值（仅 PC 模拟器无 485 时使用）
-- 当 config_app.sim_fake_dynamic 为真时，数值随采集轮次小幅波动；devstate 默认保持不变（见下）
local function read_one_sim(f)
    local base = config_app.sim_fake_raw[f.key] or 0
    if not config_app.sim_fake_dynamic then
        return base
    end
    -- devstate：默认保持不变（避免频繁触发即时上报，保证以 60s 心跳为主）；
    -- 开启 sim_fake_devstate_change 后，按序列轮转、且每个值保持 sim_fake_devstate_hold 轮
    if f.key == "devstate" then
        if not config_app.sim_fake_devstate_change then
            return base
        end
        local seq = config_app.sim_fake_devstate_seq
        if seq and #seq > 0 then
            local hold = config_app.sim_fake_devstate_hold or 1
            return seq[(math.floor(sim_round / hold) % #seq) + 1]
        end
        return base
    end
    -- 其它字段：按轮次做 ±sim_fake_wave_percent% 的小幅波动
    local span = config_app.sim_fake_wave_percent or 0
    local wave = (sim_round % 11) - 5      -- -5..5
    local v = base * (1 + (wave / 5) * (span / 100))
    if v < 0 then
        v = 0
    end
    return math.floor(v)
end

-- 是否允许降级模拟采集（PC 模拟器 或 真机且开启 sim_fake_on_device）
local function sim_allowed()
    return config_app.sim_fake_collect and (config_app.is_pc or config_app.sim_fake_on_device)
end

-- 快速在线探测：读首个寄存器（重试 modbus_retry 次），返回变频器是否在线
local function probe_vfd_online()
    for _ = 1, config_app.modbus_retry + 1 do
        if modbus_master.read_reg(modbus_map.fields[1].reg) ~= nil then
            return true
        end
        sys.wait(20)
    end
    return false
end

-- 采集主循环
local function collect_task_func()
    -- 等待网络就绪
    sys.waitUntil(msg_bus.NET_READY)
    log.info("collect_task", "网络就绪，启动采集循环")

    local use_sim       = false -- 当前是否模拟采集
    local fail_rounds   = 0     -- 真实采集下连续全失败轮数
    local probe_counter = 0     -- 模拟模式下恢复探测计数

    -- 初始化 Modbus 主站
    if modbus_master.setup() then
        -- 启动快速在线探测：变频器在线走真实采集，离线（且允许模拟）直接切模拟
        if probe_vfd_online() then
            use_sim = false
            log.info("collect_task", "变频器在线，开始真实采集")
        elseif sim_allowed() then
            use_sim = true
            log.warn("collect_task", "变频器离线，改用模拟采集数据跑通上报链路")
        else
            use_sim = false
            log.warn("collect_task", "变频器离线且未启用模拟数据，继续真实采集（将持续失败）")
        end
    elseif sim_allowed() then
        -- Modbus 主站初始化失败（如 PC 模拟器无 485/UART2 外设）
        use_sim = true
        log.warn("collect_task", "Modbus 主站初始化失败，改用模拟采集数据跑通上报链路")
    else
        log.error("collect_task", "Modbus 主站初始化失败，采集任务退出")
        return
    end

    while true do
        if use_sim then
            sim_round = sim_round + 1
        end

        -- 采集一轮
        local raw = {}
        local ok_count = 0
        for _, f in ipairs(modbus_map.fields) do
            local v
            if use_sim then
                v = read_one_sim(f)
            else
                v = read_one(f)
            end
            raw[f.key] = v
            if (not use_sim) and v ~= nil then
                ok_count = ok_count + 1
            end
        end

        -- 状态迁移
        if not use_sim then
            -- 真实采集：连续全失败超过阈值 → 判定变频器离线，切模拟
            if ok_count == 0 then
                fail_rounds = fail_rounds + 1
                if fail_rounds >= config_app.sim_fake_fail_threshold and sim_allowed() then
                    use_sim = true
                    fail_rounds = 0
                    log.warn("collect_task", "连续采集失败，判定变频器离线，切换模拟数据")
                end
            else
                fail_rounds = 0
            end
        else
            -- 模拟采集：周期性探测变频器是否恢复在线
            probe_counter = probe_counter + 1
            if probe_counter >= config_app.sim_fake_recover_probe then
                probe_counter = 0
                if probe_vfd_online() then
                    use_sim = false
                    fail_rounds = 0
                    log.info("collect_task", "探测到变频器在线，恢复真实采集")
                end
            end
        end

        local data = state_norm.normalize(raw)
        sys.publish(msg_bus.PUMP_DATA_READY, data)

        sys.wait(config_app.collect_ms)
    end
end

sys.taskInit(collect_task_func)
