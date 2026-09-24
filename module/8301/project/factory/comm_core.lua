--[[
@module  comm_core
@summary Modbus RTU 主站公共封装层（8301出厂固件）
@version 1.1
@date    2026.09.24
@usage
本文件为 Modbus RTU 主站公共封装层，统一封装 exmodbus 主站实例的创建、读操作、写操作，
供 relay_ctrl（继电器控制）等模块复用，避免重复代码。

对外接口：
1、comm_core.create_master(cfg)      → 创建 RTU 主站实例
2、comm_core.read_regs(master, cfg)  → 读寄存器（含状态判断与重试）
3、comm_core.read_coils(master, cfg) → 读线圈状态（0x01）
4、comm_core.write_coil(master, cfg) → 写单个线圈（0x05）
5、comm_core.write_coils(master, cfg)→ 写多个线圈（0x0F）
6、comm_core.write_raw(master, cfg)  → 原始帧写入（0x05/0x0F 等，含应答校验）
7、comm_core.hex(str)                → 字节串转 HEX 字符串（调试用）
8、comm_core.read_coils_raw(master, cfg)  → 读线圈（0x01，原始帧+自校验，容忍末字节丢失）
9、comm_core.write_coil_raw(master, cfg)  → 写单线圈（0x05，原始帧+自校验，容忍应答回显）
10、comm_core.write_coils_raw(master,cfg) → 写多线圈（0x0F，原始帧+自校验，容忍应答回显）
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

-- ==================== 非标准应答兼容层（实测踩坑点） ====================
--[[
背景：本工程实测所用的 485 继电器模块，其 Modbus 应答不符合标准帧格式，表现为：
1、写多线圈（0x0F）时，模块把整个请求帧原样回显（4 路模块为 10 字节），
   而标准应答应为 8 字节；exmodbus 库内部强制校验 8 字节，会直接判为
   "写入多个线圈响应报文长度不正确"，导致继电器实际已动作、但固件认为失败、
   状态缓存不更新（网页/屏幕/云端显示与实际不符）。
2、读线圈（0x01）时，模块应答的最后一个字节（CRC 高字节）丢失（收到 5 字节），
   exmodbus 库按 "数据区 = 响应长度 - 2" 计算，会判为 "数据长度不匹配"。

因此，凡对接这类模块的读写，统一改走"原始帧 + 自校验"通道：
- 请求帧由本模块自行组帧（含 CRC），通过 exmodbus 的 raw_request 分支发送；
- 应答帧由本模块自行解析校验（容忍上述非标准应答），不依赖库的帧格式强校验。
]]

-- 构建带 CRC 的标准 Modbus RTU 帧（CRC 低字节在前）
-- @param body string 除 CRC 外的帧体字节串
-- @return string 完整帧（含 CRC）
local function build_frame(body)
    local crc = crypto.crc16_modbus(body)
    return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

--[[
校验写命令应答帧（容忍"请求帧回显"与"回显末字节丢失"两种非标准应答）

判定顺序：
1、完整回显：应答与请求帧逐字节一致（长度相同），直接视为模块已受理；
2、回显但末字节丢失：应答是请求帧的前缀，且用 CRC 低字节对前缀自校验通过；
3、标准应答：长度等于标准长度、前 6 字节（从站地址/功能码/地址/数量或值）与请求一致、CRC 正确。

@local
@function check_write_response
@param resp string 原始应答帧
@param frame string 原始请求帧
@param expect_len number 标准应答长度（单线圈/多线圈写均为 8）
@return boolean true=应答可信
]]
local function check_write_response(resp, frame, expect_len)
    if type(resp) ~= "string" or type(frame) ~= "string" then
        return false
    end
    local len = #resp

    -- 1、完整回显
    if len == #frame and resp == frame then
        return true
    end

    -- 2、回显但末字节丢失（用 CRC 低字节确认前缀未被截断）
    if len == #frame - 1 and resp == frame:sub(1, len) then
        local calc = crypto.crc16_modbus(resp:sub(1, len - 1))
        if (calc & 0xFF) == string.byte(resp, len) then
            return true
        end
    end

    -- 3、标准应答
    if len == expect_len and resp:sub(1, 6) == frame:sub(1, 6) and verify_crc(resp) then
        return true
    end

    return false
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
    -- 【关键修复】补写 concat_timeout。
    -- exmodbus RTU 库的 modbus:new() 只从 config 拷贝 mode/uart_id/波特率/方向脚等字段，
    -- 唯独把实例的 concat_timeout 固定写成 nil（库内 "obj.concat_timeout = nil"），
    -- 于是库里 "if instance.concat_timeout then 启动拼接定时器 else 立即处理" 永远走 else 分支：
    -- 串口回调中只要当场读不到更多字节，就把已收到的片段当成完整帧交给解析，
    -- 造成"响应报文长度不足"等间歇性失败（重试后常能成功）。
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

    -- 自行校验应答帧：标准 8 字节应答，或模块把请求帧回显（含回显末字节丢失）
    if check_write_response(resp, cfg.raw_request, 8) then
        return exmodbus.STATUS_SUCCESS, result
    end

    log.warn("comm_core", "原始帧命令失败" ..
        "（需为标准 8 字节应答或请求帧回显，实际长度: " .. (resp and #resp or 0) .. "）")
    log_raw("原始帧", result)
    return exmodbus.STATUS_DATA_INVALID, result
end

--[[
解析读线圈（0x01）应答帧，兼容"末字节丢失"的非标准应答

标准应答： [从站][0x01][字节数][数据...][CRC低][CRC高]  共 3 + 字节数 + 2 字节
容忍应答： [从站][0x01][字节数][数据...][CRC低]        共 3 + 字节数 + 1 字节（末字节丢失）
           此类帧用 CRC 低字节反向校验：对前 (3 + 字节数) 个字节计算 CRC，
           低字节需与帧尾一致；校验通过才认为数据区完整可用，避免把错帧当有效数据。

@local
@function parse_coils_response
@param resp string 原始应答帧
@param slave_id number 期望从站地址
@param start_addr number 起始线圈地址
@param count number 线圈数量
@return table 线圈状态表（索引为绝对地址，值 0/1），nil 表示应答不可信
]]
local function parse_coils_response(resp, slave_id, start_addr, count)
    if type(resp) ~= "string" then return nil end
    local len = #resp
    if len < 4 then return nil end
    -- 从站地址与功能码必须匹配（异常应答 0x81 亦在此被排除）
    if string.byte(resp, 1) ~= slave_id or string.byte(resp, 2) ~= 0x01 then
        return nil
    end
    -- 应答声明的数据字节数必须与请求的线圈数量匹配
    local byte_count = string.byte(resp, 3)
    if byte_count ~= math.ceil(count / 8) then
        return nil
    end
    if len == 3 + byte_count + 2 then
        -- 标准帧：校验完整 CRC
        if not verify_crc(resp) then return nil end
    elseif len == 3 + byte_count + 1 then
        -- 末字节丢失帧：用 CRC 低字节确认数据区完整
        local calc = crypto.crc16_modbus(resp:sub(1, 3 + byte_count))
        if (calc & 0xFF) ~= string.byte(resp, len) then return nil end
        log.warn("comm_core", "读线圈应答缺少 CRC 高字节，已按 CRC 低字节校验通过")
    else
        return nil
    end

    -- 线圈数据按位打包，bit0 对应起始地址（Modbus 标准：低位在前）
    local coils = {}
    for i = 0, count - 1 do
        local b = string.byte(resp, 4 + math.floor(i / 8)) or 0
        coils[start_addr + i] = (b >> (i % 8)) & 0x01
    end
    return coils
end

--[[
读线圈状态（功能码 0x01，原始帧方式 + 自校验，失败自动重试）

@param master object 主站实例
@param cfg table 读配置（slave_id/start_addr/count/timeout）
@return table 线圈状态表（索引为绝对地址，值 0/1），nil 表示失败
]]
function M.read_coils_raw(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return nil
    end

    local addr = cfg.start_addr
    local count = cfg.count
    local frame = build_frame(string.char(
        cfg.slave_id,
        0x01,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (count >> 8) & 0xFF, count & 0xFF
    ))

    bus_acquire()
    local coils, resp
    for i = 0, RETRY_TIMES do
        local result = master:read({ raw_request = frame, timeout = cfg.timeout or 1000 })
        resp = result and result.raw_response
        coils = parse_coils_response(resp, cfg.slave_id, addr, count)
        if coils then break end
        if i < RETRY_TIMES then
            log.warn("comm_core", "读线圈(原始帧)失败, 应答长度=", resp and #resp or 0, "准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if coils then return coils end
    log.warn("comm_core", "读线圈(原始帧)失败 请求帧:", M.hex(frame),
        "应答帧:", M.hex(resp), "长度:", resp and #resp or 0)
    return nil
end

--[[
写单个线圈（功能码 0x05，原始帧方式 + 自校验，失败自动重试）

@param master object 主站实例
@param cfg table 写配置（slave_id/start_addr/value/timeout，value 取 0/1）
@return number status 状态码，table result 写入结果
]]
function M.write_coil_raw(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    -- 0x05 的数据域：0xFF00=接通、0x0000=断开
    local value = (cfg.value == 1) and 0xFF00 or 0x0000
    local frame = build_frame(string.char(
        cfg.slave_id,
        0x05,
        (cfg.start_addr >> 8) & 0xFF, cfg.start_addr & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF
    ))

    bus_acquire()
    local result, ok
    for i = 0, RETRY_TIMES do
        result = master:write({ raw_request = frame, timeout = cfg.timeout or 1000 })
        ok = check_write_response(result and result.raw_response, frame, 8)
        if ok then break end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写单线圈(原始帧)失败, 准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if ok then return exmodbus.STATUS_SUCCESS, result end
    log.warn("comm_core", "写单线圈(原始帧)失败 请求帧:", M.hex(frame),
        "应答帧:", M.hex(result and result.raw_response))
    return exmodbus.STATUS_DATA_INVALID, result
end

--[[
写多个线圈（功能码 0x0F，原始帧方式 + 自校验，失败自动重试）

应答判定（满足其一即视为成功，见 check_write_response）：
1、标准应答：8 字节 [从站][0x0F][起始地址高][起始地址低][数量高][数量低][CRC低][CRC高]；
2、回显应答：模块把请求帧原样回显（长度与请求帧相同、逐字节一致）。

@param master object 主站实例
@param cfg table 写配置（slave_id/start_addr/count/data/timeout）
@return number status 状态码，table result 写入结果
]]
function M.write_coils_raw(master, cfg)
    if not master then
        log.error("comm_core", "主站实例为空")
        return exmodbus.STATUS_PARAM_INVALID, nil
    end

    local addr = cfg.start_addr
    local count = cfg.count
    local byte_count = math.ceil(count / 8)

    -- 线圈数据按位打包，bit0 对应起始地址
    local data_bytes = {}
    for b = 0, byte_count - 1 do
        local v = 0
        for i = 0, 7 do
            local offset = b * 8 + i
            if offset < count and cfg.data[addr + offset] == 1 then
                v = v | (1 << i)
            end
        end
        data_bytes[#data_bytes + 1] = string.char(v)
    end

    local frame = build_frame(string.char(
        cfg.slave_id,
        0x0F,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (count >> 8) & 0xFF, count & 0xFF,
        byte_count
    ) .. table.concat(data_bytes))

    bus_acquire()
    local result, ok
    for i = 0, RETRY_TIMES do
        result = master:write({ raw_request = frame, timeout = cfg.timeout or 1000 })
        ok = check_write_response(result and result.raw_response, frame, 8)
        if ok then break end
        if i < RETRY_TIMES then
            log.warn("comm_core", "写多线圈(原始帧)失败, 准备重试")
            safe_wait(BUS_SILENCE_MS)
            safe_wait(RETRY_WAIT)
        end
    end
    safe_wait(BUS_SILENCE_MS)
    bus_release()

    if ok then return exmodbus.STATUS_SUCCESS, result end
    log.warn("comm_core", "写多线圈(原始帧)失败 请求帧:", M.hex(frame),
        "应答帧:", M.hex(result and result.raw_response),
        "长度:", result and result.raw_response and #result.raw_response or 0)
    return exmodbus.STATUS_DATA_INVALID, result
end

return M
