-- @module  meter_app
-- @summary 三相电表 RS485 Modbus-RTU 采集（Air780EPM 方案，串口2）
-- @version 001.000.000
-- @date    2026.10.26
-- @author  OpenLuat
-- @BSD License
--[[
职责：RS485(Modbus-RTU) 轮询三相电表，解析寄存器数据。
无 UI 依赖，采集结果通过 sys.publish("METER_DATA", data) 广播，
aircloud_app 订阅后组 TLV 上报；也可通过 M.get_data() 主动读取。

接线：板载 RS485（串口2），485 芯片供电 GPIO25 由 board_hw.init() 拉高。
方向脚 GPIO23（接收发器 DE/RE）必须通过 CFG.dir_gpio 交给 uart.setup，
由串口硬件在发送时自动拉高、发送完自动拉低；不能当普通 GPIO 手动拉高（会钉死在发送态）。

寄存器映射、解析公式与 meter_demo/pc_modbus_test.py 同口径。
]]

local M = {}

local exmodbus = require "exmodbus"
local hw       = require "board_hw"   -- 板级资源（485 供电/EN、LED、按键、看门狗、ADC）

-- ==================== 配置 ====================
local CFG = {
    port           = 2,            -- 串口2（板载 RS485）
    slave_id       = 1,            -- 从站地址（电表面板设置）
    baud           = 9600,         -- 波特率
    parity         = uart.None,    -- 校验位
    data_bits      = 8,
    stop_bits      = 1,
    -- RS485 方向脚：必须交给 uart.setup 的 485 方向参数（exmodbus 透传 rs485_dir_gpio），
    -- 由串口硬件在发送时自动拉高、发送完自动拉低。填 nil 会没人驱动 DE/RE，
    -- 发送时 DE 一直为 0 → 总线上没有差分信号 → 电表收不到，永远超时。
    dir_gpio       = 23,           -- GPIO23 → 收发器 DE/RE（板载 RS485 EN）
    poll_interval  = 2000,         -- 轮询间隔 ms
    retry          = 2,            -- 超时重试次数
    timeout        = 1000,         -- 请求超时 ms
    concat_timeout = 50,           -- 字节拼接超时 ms
    debug          = true,         -- 排障：打印收发原始报文（hex），定位后可关
}

-- 读取区间（与直连真表验证通过的 meter_ui_sim.js 完全同口径）
local BLOCKS = {
    { start = 0x00,  count = 20 }, -- U I P Q S（0x00~0x13）
    { start = 0x14,  count = 9 },  -- 功率因数 频率（0x14~0x1C）
    { start = 0x1D,  count = 8 },  -- 电能 4×32bit（0x1D~0x24）
}

-- 配置块（地址/PT/CT/波特率/校验/接线方式）只需首轮读一次，不必每轮都读
local CFG_BLOCK = { start = 0x26, count = 6 }

-- ==================== 状态 ====================
local poll_task    = nil
local master       = nil
local running      = false
local pending      = false       -- 手动触发单次采集
local last         = { online = false }
local cfg_regs     = nil         -- 电表配置（0x26~0x2B），首轮读取后缓存

-- ==================== 协议解析（与真表验证通过的 meter_ui_sim.js 逐条对应） ====================
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

-- 电能：hi×655.36 + lo×0.01（kWh，JS energy_kwh 同算法）
local function energy_kwh(raw, a)
    return (raw[a] or 0) * 655.36 + (raw[a + 1] or 0) * 0.01
end

local function parse(raw)
    -- 电压/电流倍率来自电表配置块 0x27/0x28（load_cfg 首轮读一次后缓存），
    -- 配置块不再混进 raw，所以这里必须取缓存值，否则永远是 1 倍。
    local PT = (cfg_regs and cfg_regs.pt) or 1
    local CT = (cfg_regs and cfg_regs.ct) or 1
    if PT <= 0 then PT = 1 end   -- 电表变比被清零时按 1 处理，避免 ×0
    if CT <= 0 then CT = 1 end

    local d = {
        pt = PT, ct = CT,
        ua = (raw[0x00] or 0) * 0.1 * PT,
        ub = (raw[0x01] or 0) * 0.1 * PT,
        uc = (raw[0x02] or 0) * 0.1 * PT,
        ia = (raw[0x03] or 0) * 0.001 * CT,
        ib = (raw[0x04] or 0) * 0.001 * CT,
        ic = (raw[0x05] or 0) * 0.001 * CT,
        p  = s16(raw[0x07] or 0) * PT * CT / 1000, -- W → kW（上报口径）
        q  = s16(raw[0x0B] or 0) * PT * CT / 1000, -- var → kvar
        s  = (raw[0x0F] or 0) * PT * CT / 1000,    -- VA → kVA
        pfa = (raw[0x14] or 0) / 1000,
        pfb = (raw[0x15] or 0) / 1000,
        pfc = (raw[0x16] or 0) / 1000,
        fa = (raw[0x1A] or 0) * 0.01,
        ep_imp = energy_kwh(raw, 0x1D) * PT * CT,
        ep_exp = energy_kwh(raw, 0x1F) * PT * CT,
        eq_imp = energy_kwh(raw, 0x21) * PT * CT,
        eq_exp = energy_kwh(raw, 0x23) * PT * CT,
    }

    d.pf = (d.s and d.s > 0) and (d.p / d.s) or d.pfa
    d.f = d.fa
    d.ep = d.ep_imp

    for k, v in pairs(d) do
        if type(v) == "number" then d[k] = tonumber(string.format("%.3f", v)) end
    end
    return d
end

-- ==================== 读寄存器 ====================
local function regs_hex(d, start, count)
    local t = {}
    for i = 0, count - 1 do
        t[#t + 1] = string.format("%04X", (d[start + i] or 0) % 0x10000)
    end
    return table.concat(t, " ")
end

local function is_all_zero(d, start, count)
    for i = 0, count - 1 do
        if (d[start + i] or 0) ~= 0 then return false end
    end
    return true
end

-- 读一块寄存器，返回以「绝对寄存器地址」为键的表；失败返回 nil
-- 关键：exmodbus 的 ret.data 以绝对地址为键（data[start_addr]），
-- 早期写成 ret.data[i + 1] 会全部取到 nil，表现为"帧通、数据全 0"。
local function read_block(start, count, tag)
    for attempt = 1, CFG.retry do
        local ret = master:read({
            slave_id   = CFG.slave_id,
            reg_type   = exmodbus.HOLDING_REGISTER,
            start_addr = start,
            reg_count  = count,
            timeout    = CFG.timeout,
        })
        -- exmodbus 的成功码是 STATUS_SUCCESS（STATUS_OK 为 nil，会导致恒判失败）
        if ret and ret.status == exmodbus.STATUS_SUCCESS and ret.data then
            local d = {}
            for i = 0, count - 1 do
                local addr = start + i
                local v = ret.data[addr]          -- 标准：绝对地址为键
                if v == nil then v = ret.data[i + 1] end -- 兼容 1 基下标实现
                d[addr] = v or 0
            end
            if CFG.debug then
                log.info("meter", string.format("[读 0x%04X+%d]", start, count),
                    tag or "", regs_hex(d, start, count))
                if is_all_zero(d, start, count) then
                    log.warn("meter", string.format(
                        "0x%04X+%d 整块返回 0（帧是通的，是电表给出的值为 0）", start, count))
                end
            end
            return d
        end
        if attempt == CFG.retry then
            log.warn("meter", string.format("读 0x%04X+%d 失败", start, count),
                ret and ret.status or "nil", "已重试", CFG.retry, "次")
        end
    end
    return nil
end

-- 电表配置（地址/PT/CT/波特率/校验/接线方式），首轮读一次后缓存
local function load_cfg()
    if cfg_regs then return cfg_regs end
    local d = read_block(CFG_BLOCK.start, CFG_BLOCK.count, "配置")
    if not d then return nil end
    cfg_regs = {
        dev_addr = d[0x26], pt = d[0x27], ct = d[0x28],
        baud = d[0x29], parity = d[0x2A], wiring = d[0x2B],
    }
    log.info("meter", "电表配置", "地址", cfg_regs.dev_addr, "PT", cfg_regs.pt,
        "CT", cfg_regs.ct, "接线方式", cfg_regs.wiring)
    if cfg_regs.pt <= 0 or cfg_regs.ct <= 0 then
        log.warn("meter", "电表 PT/CT 读回 0（0x27/0x28 未设置）→ 本次按 1 倍处理",
            "请到电表面板 INPT 菜单恢复 变比 Γ.U / Γ.I")
    end
    return cfg_regs
end

-- ==================== 轮询任务 ====================
local function poll_once()
    if not master then return false end
    load_cfg() -- 读不到也照常采集，parse() 内部按 1 倍处理
    local raw = {}
    for _, blk in ipairs(BLOCKS) do
        local d = read_block(blk.start, blk.count, "数据")
        if not d then return false end
        for k, v in pairs(d) do raw[k] = v end
    end
    last = parse(raw)
    last.online = true
    last.ts = os.time()
    if cfg_regs then last.pt, last.ct = cfg_regs.pt, cfg_regs.ct end
    if CFG.debug then
        log.info("meter", string.format(
            "ua=%.1f ub=%.1f uc=%.1f ia=%.3fA p=%.3fkW q=%.3fkvar pf=%.3f f=%.2fHz Ep+=%.2fkWh",
            last.ua, last.ub, last.uc, last.ia, last.p, last.q, last.pf, last.f, last.ep_imp))
    end
    sys.publish("METER_DATA", last)
    return true
end

local function poll_task_fn()
    sys.wait(50) -- 等待 485 芯片上电稳定
    while true do
        if running or pending then
            pending = false
            local ok = poll_once()
            if not ok and last.online then
                last.online = false
                sys.publish("METER_STATUS", { err = "comm timeout" })
            elseif ok then
                sys.publish("METER_STATUS", { online = true })
            end
        end
        -- 等待下一轮；M.refresh() 会发 METER_POLL_NOW 提前唤醒
        sys.waitUntil("METER_POLL_NOW", CFG.poll_interval)
    end
end

-- ==================== 对外接口 ====================
function M.start()
    hw.init()                 -- 板级：3.3V 电平、485 供电、LED、按键、看门狗、ADC（幂等）
    hw.rs485_power(true)      -- 重复拉高无副作用，确保 UART 打开前 485 芯片已上电
    -- 注意：RS485 EN(GPIO23→DE/RE) 由 UART2 硬件自动换向控制，不要在这里拉高
    exmodbus.debug(CFG.debug) -- 排障：打印收发原始报文（须在 create 之前调用）
    if not master then
        master = exmodbus.create({
            mode               = exmodbus.RTU_MASTER,
            uart_id            = CFG.port,
            baud_rate          = CFG.baud,
            data_bits          = CFG.data_bits,
            stop_bits          = CFG.stop_bits,
            parity_bits        = CFG.parity,
            -- 注意：exmodbus 没有 LITTLE_ENDIAN 常量，写错会传 nil；字节序用 uart.LSB
            byte_order         = uart.LSB,
            rs485_dir_gpio     = CFG.dir_gpio, -- GPIO23 → DE/RE，发送时自动拉高
            rs485_dir_rx_level = 0,
            concat_timeout     = CFG.concat_timeout,
        })
        if not master then
            log.error("meter", "exmodbus.create 失败，串口", CFG.port, "无法打开")
            return
        end
    end
    running = true
    if not poll_task then
        poll_task = sys.taskInit(poll_task_fn)
        log.info("meter", "采集任务已启动", "从站", CFG.slave_id, "串口", CFG.port, CFG.baud)
    end
end

function M.stop() running = false end

function M.refresh()
    pending = true
    sys.publish("METER_POLL_NOW") -- 立即唤醒采集任务，不必等满一个轮询周期
end

function M.is_running() return running end

function M.get_data() return last end

-- 板级数据：供电电压/模拟量/输入口（由 board_hw 周期采样）
function M.get_hw_data() return hw.get_hw_data() end

function M.get_cfg()
    return {
        port = CFG.port, slave_id = CFG.slave_id, baud = CFG.baud,
        pt = cfg_regs and cfg_regs.pt,
        ct = cfg_regs and cfg_regs.ct,
        wiring = cfg_regs and cfg_regs.wiring,
    }
end

return M
