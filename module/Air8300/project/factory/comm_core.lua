--[[
@module  comm_core
@summary Modbus RTU 主站公共封装层
@version 1.0
@date    2026.10.08
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

-- 失败日志降噪阈值：连续失败次数每达到该值才输出一条 warn。
-- 背景：继电器状态周期回读为 2 秒一次，若从站持续无响应，逐条打印会把日志刷屏，
--       掩盖真正有用的信息。改为按"连续失败次数"定量输出，既能持续反映故障，又不刷屏。
local LOG_FAIL_THRESHOLD = 3
-- 各操作的连续失败计数（key 为操作标识，成功时归零）
local fail_streak = {}

-- 末字节自愈日志降噪间隔。
-- 背景：现场存在"应答末字节（CRC 高字节，值恰为 0x00）未进入接收缓冲"的常态现象，
--       本书已用 CRC 反推补全自愈，数据完全可用、不影响业务；但若每次自愈都打印，
--       2 秒周期的继电器回读会持续刷屏，掩盖真正有用的信息。
--       故改为"首次打印 1 条 + 之后每 N 次打印 1 条"，既反映该现象是否仍在发生，又保持日志干净。
local TAIL_FIX_LOG_INTERVAL = 300
-- 末字节自愈累计次数（不归零，供降噪判断与故障持续观察）
local tail_fix_count = 0

-- 记录一次"末字节自愈"（按 TAIL_FIX_LOG_INTERVAL 降噪输出）
local function log_tail_fix()
    tail_fix_count = tail_fix_count + 1
    if tail_fix_count == 1 or tail_fix_count % TAIL_FIX_LOG_INTERVAL == 0 then
        log.info("comm_core", "应答末字节丢失, 已通过 CRC 反推补全, 累计:", tail_fix_count, "次")
    end
end

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

-- 尝试恢复"仅丢失最后 1 个字节"的应答帧
-- 原理：Modbus RTU 帧末 2 字节为 CRC16-Modbus（低字节在前）。若帧只缺少最后 1 个字节，
--       可枚举该字节的 256 种取值，使整帧 CRC 校验成立的取值在数学上是唯一的。
--       命中即说明帧体数据完整（CRC 是唯一约束），可安全使用；未命中则不做任何修改。
-- 说明：现场实测出现过"响应末字节（恰好为 0x00 的 CRC 高字节）未进入接收缓冲"的现象，
--       表现为库报"数据长度不匹配，期望: 1 实际: 0"，本函数用于自愈该情况。
-- @param resp string 收到的（可能缺少末字节的）应答帧
-- @return string|nil 补全后的完整帧；nil 表示无法恢复
local function try_recover_tail(resp)
    if type(resp) ~= "string" or #resp < 4 then return nil end
    for b = 0, 255 do
        local cand = resp .. string.char(b)
        if verify_crc(cand) then
            return cand
        end
    end
    return nil
end

-- 应答帧校验（长度 + 从站地址 + 功能码 + CRC），并支持"末字节丢失"的自愈恢复
local function check_and_fix(resp, slave_id, func_code, expect_len)
    if type(resp) ~= "string" or #resp < 4 then
        return false, resp
    end
    if string.byte(resp, 1) ~= slave_id or string.byte(resp, 2) ~= func_code then
        log.warn("comm_core", "应答帧从站/功能码不符, 实际:",
            string.format("%02X %02X", string.byte(resp, 1), string.byte(resp, 2)),
            "期望:", string.format("%02X %02X", slave_id, func_code))
        return false, resp
    end

    if expect_len then
        if #resp == expect_len - 1 then
            -- 仅缺少最后 1 个字节 → 尝试 CRC 反推补全（让自愈逻辑真正生效）
            local fixed = try_recover_tail(resp)
            if fixed then
                log_tail_fix()
                return true, fixed
            end
            log.warn("comm_core", "应答帧少 1 字节且 CRC 反推补全失败, 实际长度:", #resp,
                "期望长度:", expect_len, "原帧:", M.hex(resp))
            return false, resp
        end
        if #resp ~= expect_len then
            log.warn("comm_core", "应答帧长度不符, 实际长度:", #resp, "期望长度:", expect_len,
                "原帧:", M.hex(resp))
            return false, resp
        end
        -- 长度正确 → 再校验 CRC
        if verify_crc(resp) then
            return true, resp
        end
        log.warn("comm_core", "应答帧 CRC 校验失败, 原帧:", M.hex(resp))
        return false, resp
    end

    -- 未传期望长度：保持兼容逻辑（CRC 优先，失败再尝试末字节补全）
    if verify_crc(resp) then
        return true, resp
    end
    local fixed = try_recover_tail(resp)
    if fixed then
        log_tail_fix()
        return true, fixed
    end
    return false, resp
end

-- 自行解析功能码 0x01（读线圈）应答帧，取出各线圈状态位
-- 帧结构：从站地址(1) + 功能码(1) + 字节数(1) + 数据(n) + CRC(2)
-- 不依赖库的解析结果，因此可兼容"末字节被 CRC 反推补全"的应答帧。
-- @param frame string 已通过校验的完整应答帧（含 CRC）
-- @param start_addr number 起始线圈地址
-- @param count number 线圈数量
-- @return table|nil 线圈状态数组（索引为绝对地址，值 0/1）；帧结构不符返回 nil
local function parse_coil_bits(frame, start_addr, count)
    local expect_bytes = math.ceil(count / 8)
    local expect_len = 3 + expect_bytes + 2
    if #frame ~= expect_len then
        log.warn("comm_core", "读线圈应答帧长度不符, 实际:", #frame, "期望:", expect_len)
        return nil
    end
    if string.byte(frame, 3) ~= expect_bytes then
        log.warn("comm_core", "读线圈应答字节数不符, 实际:", string.byte(frame, 3), "期望:", expect_bytes)
        return nil
    end
    local data = {}
    for i = 0, count - 1 do
        local b = string.byte(frame, 4 + math.floor(i / 8))
        data[start_addr + i] = (b >> (i % 8)) & 1
    end
    return data
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

    local count = cfg.count or 1
    -- 期望应答帧长度：从站地址(1) + 功能码(1) + 字节数(1) + 数据(n) + CRC(2)
    -- 4 路线圈 → 6 字节；8 路线圈 → 6 字节（数据字段均为 1 字节）
    local expect_len = 3 + math.ceil(count / 8) + 2

    local rcfg = {
        slave_id = cfg.slave_id,
        reg_type = exmodbus.COIL_STATUS,
        start_addr = cfg.start_addr,
        reg_count = count,
        timeout = cfg.timeout or 1000,
    }

    bus_acquire()
    local result
    local frame_ok, frame = false, nil
    for i = 0, RETRY_TIMES do
        result = master:read(rcfg)
        if result then
            -- 帧级校验：长度 + 从站地址 + 功能码 + CRC，并支持"仅丢失末字节"的 CRC 反推补全
            frame_ok, frame = check_and_fix(result.raw_response, cfg.slave_id,
                exmodbus.READ_COILS, expect_len)
            if frame_ok then
                break
            end
        end
        if i < RETRY_TIMES then
            -- 重试前先让总线静默，避免迟到应答污染下一笔事务（失败细节已由 check_and_fix 打印，此处不重复刷屏）
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if frame_ok and frame then
        -- 成功：清零连续失败计数
        fail_streak.read_coils = 0
        -- 自行解析线圈位，不依赖库的解析结果，兼容"末字节被补全"的应答帧
        return parse_coil_bits(frame, cfg.start_addr, count)
    end

    -- 失败：连续失败计数 + 降噪打印（每 LOG_FAIL_THRESHOLD 次输出一条，避免 2 秒周期回读刷屏）
    local n = (fail_streak.read_coils or 0) + 1
    fail_streak.read_coils = n
    if n % LOG_FAIL_THRESHOLD == 0 then
        if result and result.status == exmodbus.STATUS_EXCEPTION then
            log.warn("comm_core", "读线圈异常, 异常码=", result.execption_code, ", 连续失败", n, "次")
        else
            log.warn("comm_core", "读线圈失败, 库状态=", result and result.status, ", 连续失败", n, "次")
            log_raw("读线圈", result)
        end
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
        if result then
            -- 帧级校验（含末字节丢失的自愈恢复），不再依赖库返回的 status
            -- 写单线圈正常应答为 8 字节：从站(1)+功能码(1)+地址(2)+数据(2)+CRC(2)
            crc_ok = check_and_fix(result.raw_response, cfg.slave_id, exmodbus.WRITE_SINGLE_COIL, 8)
            if crc_ok then
                break
            end
            log.warn("comm_core", "写线圈应答帧校验未通过, 库状态=", result.status, "丢弃本次结果")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写线圈失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if crc_ok then
        return exmodbus.STATUS_SUCCESS, result
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
        if result then
            -- 帧级校验（含末字节丢失的自愈恢复），不再依赖库返回的 status
            -- 写多线圈正常应答为 8 字节：从站(1)+功能码(1)+地址(2)+数量(2)+CRC(2)
            crc_ok = check_and_fix(result.raw_response, cfg.slave_id, exmodbus.WRITE_MULTIPLE_COILS, 8)
            if crc_ok then
                break
            end
            log.warn("comm_core", "写多线圈应答帧校验未通过, 库状态=", result.status, "丢弃本次结果")
        end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写多线圈失败, 状态=", result and result.status, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if crc_ok then
        return exmodbus.STATUS_SUCCESS, result
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
