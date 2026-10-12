--[[
@module  comm_core
@summary Modbus RTU 主站公共封装层
@version 1.2
@date    2026.09.18
@usage
本文件为 Modbus RTU 主站公共封装层，统一封装 exmodbus 主站实例的创建、读操作、写操作，
供 temp_sensor（温湿度采集）与 relay_ctrl（继电器控制）两个模块复用，避免重复代码。

对外接口：
1、comm_core.create_master(cfg)      → 创建 RTU 主站实例
2、comm_core.read_regs(master, cfg)  → 读寄存器（含状态判断与重试）
3、comm_core.read_coils(master, cfg) → 读线圈状态（0x01）
4、comm_core.write_coil(master, cfg) → 写单个线圈（0x05）
5、comm_core.write_coils(master, cfg)→ 写多个线圈（0x0F）
6、comm_core.write_raw(master, cfg)  → 原始帧写入（0x05/0x0F 等，含应答校验）
7、comm_core.hex(str)                → 字节串转 HEX 字符串（调试用）
]]

local exmodbus = require "exmodbus"
local M = {}

-- ==================== 总线互斥锁 ====================
-- exmodbus RTU 库的接收缓冲 read_buf 为模块级（库级）共享变量，
-- 多路 UART 同时收发时，一路的字节可能被拼进另一路的缓冲区，导致应答帧被污染/截断。
-- 因此此处用一把全局锁，把所有 Modbus 事务串行化，同一时刻只允许一路总线收发。
local bus_busy = false

-- 安全等待：仅在可让出的协程上下文中等待，避免在非协程回调里调用 sys.wait 出错
local function safe_wait(ms)
    if coroutine.isyieldable and coroutine.isyieldable() then
        sys.wait(ms)
    end
end

local function bus_acquire()
    while bus_busy do
        safe_wait(5)
    end
    bus_busy = true
end

local function bus_release()
    bus_busy = false
end

-- 幂等操作的失败重试次数（额外重试次数，0 表示不重试）
local RETRY_TIMES = 1
-- 重试前的等待时间（毫秒）
local RETRY_WAIT = 100
-- 总线静默期（毫秒）：事务结束/重试前先等总线安静，避免超时事务的迟到应答污染下一笔事务
local BUS_SILENCE_MS = 50

-- 字节串转 HEX 字符串（调试打印用）
function M.hex(s)
    if not s then return "nil" end
    local t = {}
    for i = 1, #s do
        t[#t + 1] = string.format("%02X", string.byte(s, i))
    end
    return table.concat(t, " ")
end

-- 打印失败时的原始帧（便于定位丢字节/截断问题）
local function log_raw(tag, result)
    if not result then
        log.warn("comm_core", tag, "无返回数据")
        return
    end
    log.warn("comm_core", tag, "请求帧:", M.hex(result.raw_request))
    log.warn("comm_core", tag, "应答帧:", M.hex(result.raw_response),
        "长度:", result.raw_response and #result.raw_response or 0)
end

-- 校验 Modbus RTU 应答帧 CRC
-- 说明：exmodbus RTU 库解析应答时不做 CRC 校验（只校验从站地址/功能码/数据长度），
--       一旦总线受扰导致帧内容错乱而长度凑巧，就会把错误数据当成功返回。
--       本函数补上 CRC16-Modbus 校验：对除末 2 字节外的全部内容计算 CRC，接收值低字节在前。
-- @param resp string 原始应答帧（raw_response，含 2 字节 CRC）
-- @return boolean true=CRC 正确
local function verify_crc(resp)
    if type(resp) ~= "string" or #resp < 4 then
        return false
    end
    local calc = crypto.crc16_modbus(resp:sub(1, -3))
    local recv = string.byte(resp, -2) + string.byte(resp, -1) * 256
    return calc == recv
end

-- 创建 RTU 主站实例
-- @param cfg table 主站配置（mode/uart_id/baud_rate 等）
-- @return 主站实例 object 或 nil
function M.create_master(cfg)
    if not cfg or type(cfg) ~= "table" then
        log.error("comm_core", "创建主站配置必须为表格")
        return nil
    end
    local master = exmodbus.create(cfg)
    if not master then
        log.error("comm_core", "RTU 主站创建失败, uart_id=", cfg.uart_id)
        return nil
    end
    -- 【V1.2 关键修复】补写 concat_timeout。
    -- exmodbus RTU 库的 modbus:new() 只从 config 拷贝 mode/uart_id/波特率/方向脚等字段，
    -- 唯独把实例的 concat_timeout 固定写成 nil（库内 "obj.concat_timeout = nil"），
    -- 于是库里 "if instance.concat_timeout then 启动拼接定时器 else 立即处理" 永远走 else 分支：
    -- 串口回调中只要当场读不到更多字节，就把已收到的片段当成完整帧交给解析，
    -- 造成"响应报文长度不足"/"数据长度不匹配，期望: 4 实际: -1"等间歇性失败（重试后常能成功）。
    -- 实例是普通 table（__metatable 保护的是元表，不阻止字段赋值），此处直接补写即可生效。
    if cfg.concat_timeout then
        master.concat_timeout = cfg.concat_timeout
    end
    log.info("comm_core", "RTU 主站创建成功, uart_id=", cfg.uart_id,
        "concat_timeout=", master.concat_timeout or "nil")
    return master
end

-- 读寄存器（主站向从站发起读取请求，失败自动重试）
-- @param master object 主站实例
-- @param cfg table 读配置（slave_id/reg_type/start_addr/reg_count/timeout）
-- @return number status 状态码（exmodbus.STATUS_*），table result 读取结果
function M.read_regs(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    bus_acquire()
    local result
    local crc_ok = false
    for i = 0, RETRY_TIMES do
        result = master:read(cfg)
        if result and result.status == exmodbus.STATUS_SUCCESS then
            -- 成功状态下再补 CRC 校验，避免"帧内容错乱但长度凑巧"的错值被当成有效数据
            crc_ok = verify_crc(result.raw_response)
            if crc_ok then
                break
            end
            log.warn("comm_core", "读取应答 CRC 校验失败, 丢弃本次数据")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "读取失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if result and result.status == exmodbus.STATUS_SUCCESS and crc_ok then
        return exmodbus.STATUS_SUCCESS, result
    end
    if result and result.status == exmodbus.STATUS_SUCCESS then
        log.warn("comm_core", "读取应答 CRC 校验失败, 数据不可信已丢弃")
        return exmodbus.STATUS_DATA_INVALID, result
    end

    if result and result.status == exmodbus.STATUS_EXCEPTION then
        log.warn("comm_core", "读取异常, 异常码=", result.execption_code)
    elseif result and result.status == exmodbus.STATUS_TIMEOUT then
        log.warn("comm_core", "读取超时, 从站=", cfg.slave_id, "起始=", cfg.start_addr)
    else
        log.warn("comm_core", "读取失败/数据无效, 状态=", result and result.status)
        log_raw("读取", result)
    end
    return result and result.status or exmodbus.STATUS_DATA_INVALID, result
end

-- 读线圈状态（功能码 0x01，失败自动重试）
-- @param master object 主站实例
-- @param cfg table 读配置（slave_id/start_addr/count/timeout）
-- @return table 线圈状态数组 data（索引为绝对地址，值为 0/1），nil 表示失败
function M.read_coils(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return nil
    end

    local rcfg = {
        slave_id = cfg.slave_id,
        reg_type = exmodbus.COIL_STATUS,
        start_addr = cfg.start_addr,
        reg_count = cfg.count,
        timeout = cfg.timeout or 1000,
    }

    bus_acquire()
    local result
    local crc_ok = false
    for i = 0, RETRY_TIMES do
        result = master:read(rcfg)
        if result and result.status == exmodbus.STATUS_SUCCESS then
            crc_ok = verify_crc(result.raw_response)
            if crc_ok then
                break
            end
            log.warn("comm_core", "读线圈应答 CRC 校验失败, 丢弃本次数据")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "读线圈失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if result and result.status == exmodbus.STATUS_SUCCESS and crc_ok then
        return result.data
    end
    if result and result.status == exmodbus.STATUS_SUCCESS then
        log.warn("comm_core", "读线圈应答 CRC 校验失败, 数据不可信已丢弃")
        return nil
    end

    if result and result.status == exmodbus.STATUS_EXCEPTION then
        log.warn("comm_core", "读线圈异常, 异常码=", result.execption_code)
    else
        log.warn("comm_core", "读线圈失败, 状态=", result and result.status)
        log_raw("读线圈", result)
    end
    return nil
end

-- 写单个线圈（功能码 0x05，data[addr]=0/1，库自动转 0xFF00/0x0000）
-- 注意：exmodbus 的读/写接口都强制要求 reg_count，单线圈写必须显式传 reg_count = 1，
--       且 force_multiple = false 才会使用 0x05 功能码，否则会误用 0x0F。
-- @param master object 主站实例
-- @param cfg table 写配置（slave_id/start_addr/value/timeout）
-- @return number status 状态码，table result 写入结果
function M.write_coil(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    local wcfg = {
        slave_id = cfg.slave_id,
        reg_type = exmodbus.COIL_STATUS,
        start_addr = cfg.start_addr,
        reg_count = 1,                                    -- 必需：单线圈写为 1
        data = { [cfg.start_addr] = cfg.value or 0 },
        force_multiple = false,                           -- 必需：false 才走 0x05
        timeout = cfg.timeout or 1000,
    }

    bus_acquire()
    local result
    local crc_ok = false
    for i = 0, RETRY_TIMES do
        result = master:write(wcfg)
        if result and result.status == exmodbus.STATUS_SUCCESS then
            crc_ok = verify_crc(result.raw_response)
            if crc_ok then
                break
            end
            log.warn("comm_core", "写线圈应答 CRC 校验失败, 丢弃本次结果")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写线圈失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if result and result.status == exmodbus.STATUS_SUCCESS and crc_ok then
        return exmodbus.STATUS_SUCCESS, result
    end
    if result and result.status == exmodbus.STATUS_SUCCESS then
        log.warn("comm_core", "写线圈应答 CRC 校验失败, 未确认写入成功")
        return exmodbus.STATUS_DATA_INVALID, result
    end

    if result and result.status == exmodbus.STATUS_EXCEPTION then
        log.warn("comm_core", "写线圈异常, 异常码=", result.execption_code)
    else
        log.warn("comm_core", "写线圈失败, 状态=", result and result.status)
        log_raw("写线圈", result)
    end
    return result and result.status or exmodbus.STATUS_DATA_INVALID, result
end

-- 写多个线圈（功能码 0x0F，data[addr]=0/1，失败自动重试）
-- @param master object 主站实例
-- @param cfg table 写配置（slave_id/start_addr/count/data/timeout）
-- @return number status 状态码，table result 写入结果
function M.write_coils(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    local wcfg = {
        slave_id = cfg.slave_id,
        reg_type = exmodbus.COIL_STATUS,
        start_addr = cfg.start_addr,
        reg_count = cfg.count,
        data = cfg.data,
        force_multiple = true,
        timeout = cfg.timeout or 1000,
    }

    bus_acquire()
    local result
    local crc_ok = false
    for i = 0, RETRY_TIMES do
        result = master:write(wcfg)
        if result and result.status == exmodbus.STATUS_SUCCESS then
            crc_ok = verify_crc(result.raw_response)
            if crc_ok then
                break
            end
            log.warn("comm_core", "写多线圈应答 CRC 校验失败, 丢弃本次结果")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写多线圈失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if result and result.status == exmodbus.STATUS_SUCCESS and crc_ok then
        return exmodbus.STATUS_SUCCESS, result
    end
    if result and result.status == exmodbus.STATUS_SUCCESS then
        log.warn("comm_core", "写多线圈应答 CRC 校验失败, 未确认写入成功")
        return exmodbus.STATUS_DATA_INVALID, result
    end

    if result and result.status == exmodbus.STATUS_EXCEPTION then
        log.warn("comm_core", "写多线圈异常, 异常码=", result.execption_code)
    else
        log.warn("comm_core", "写多线圈失败, 状态=", result and result.status)
        log_raw("写多线圈", result)
    end
    return result and result.status or exmodbus.STATUS_DATA_INVALID, result
end

-- 原始帧写入（用于库的字段参数方式不支持的命令，如翻转 0x05 + 0x5500）
-- 注意：exmodbus 的 raw_request 分支不做任何应答校验（收到任意字节即返回成功），
--       因此本函数自行校验：应答必须为 8 字节，且从站地址、功能码与请求一致。
--       该函数不做重试（避免翻转类命令被重复执行）。
-- @param master object 主站实例
-- @param cfg table 写配置（slave_id/func_code/raw_request/timeout）
-- @return number status 状态码，table result 写入结果
function M.write_raw(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    bus_acquire()
    local result = master:write({
        raw_request = cfg.raw_request,
        timeout = cfg.timeout or 1000,
    })
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    local resp = result and result.raw_response

    -- 自行校验应答帧：单线圈/多线圈写的正常应答均为 8 字节，且必须通过 CRC 校验
    if resp and #resp == 8
        and string.byte(resp, 1) == cfg.slave_id
        and string.byte(resp, 2) == cfg.func_code
        and verify_crc(resp) then
        return exmodbus.STATUS_SUCCESS, result
    end

    log.warn("comm_core", "原始帧命令失败" ..
        "（应答需 8 字节、从站/功能码匹配且 CRC 正确，实际长度: " .. (resp and #resp or 0) .. "）")
    log_raw("原始帧", result)
    return exmodbus.STATUS_DATA_INVALID, result
end

return M
