--[[
@module  fx3u
@summary FX 计算机链接（格式 4）通信层
         帧：ENQ + 站号 + PC号 + 命令 + 延时A + D + 地址(4位十进制) + 点数(2位HEX) + [数据] + 和校验 + CR LF
         应答：STX + 站号 + PC号 + 数据 + ETX + 和校验 + CR LF
         写命令应答：ACK + 站号 + PC号 + CR LF（很短，不能按固定长度等）

@note  === 485 方向控制（这一版改过，是之前 100% 超时的根因） ===
固件的 uart.setup 完整签名是：
    uart.setup(id, baud, data_bits, stop_bits, parity, bit_order,
               buff_size, rs485_gpio, rs485_level, rs485_delay, debug, errdrop)
第 8/9/10 个参数就是"485 方向脚 / 接收态电平 / 换向延迟"。
只传前 5 个参数时 pin485 = 0xffffffff，固件根本不驱动方向脚，
收发器常驻接收态，TX 数据一个字节都上不了 A/B 总线 —— 现象就是永远超时。

手动翻 GPIO 也能用（合宙出厂 periph_rs485 就是这么做的），但两个细节必须对齐：
  · DE 必须覆盖整帧。预算用 (字节数 + 2) × 12 位，比 len × 11 多留两三个字符的余量；
    少算 4ms 帧尾就被截断，PLC 会当没收到。
  · 半双工收发器会把发出去的字节回采到 RX，发送窗口内收到的字节必须丢掉，
    否则自己的报文会混进应答里，表现为"偶发校验错"。

@usage
    local fx = require("fx3u")
    fx.init(config.uart, config.plc)
    fx.read(100, 3, function(vals) print(vals[1], vals[2], vals[3]) end)
    fx.write(300, 600)
]]

local M = {}

local cfg            -- 串口与协议参数
local clock = 0      -- 兜底毫秒时钟（没有 mcu.ticks 时用）
local rxbuf = ""     -- 接收缓冲
local cur = nil      -- 在途请求
local queue = {}     -- 待发请求（同一时刻只允许一帧在总线上）
local busy_until = 0 -- 发送占用的总线时间，到点才允许下一帧
local native485 = false   -- true = 方向脚交给固件；false = Lua 手动翻
local de_high = false
local fallback_tried = false   -- 内置换向失败后只降级一次，避免每帧刷日志

local TIMER_MS = 50
local stat = { ok = 0, fail = 0, timeout = 0, online = false, rtt = 0, last_ok = 0,
               rx_total = 0 }
local last_fail_log = -10000   -- 失败日志节流，避免 3Hz 刷屏拖慢模拟器

-- ==================== 单调毫秒时钟 ====================
--[[ 这一层踩过一个大坑，必须说清楚：

mcu.ticks() 返回的是"节拍数"，**不是毫秒**。一格的物理长度随平台变化，
Air1603 上一格是 20ms（mcu.hz() = 50），有些平台是 1ms。
直接把它当毫秒用，时间轴会被拉长 20 倍 —— 配 500ms 超时，实际要等 10 秒
才判超时。日志上的样子是："第一帧之后静默 10 秒，然后才开始重试"。

两种取法，优先用前者：
  · mcu.ticks2(1)  → 直接给毫秒，返回值是两个数（高位, 低位），
                     以"千秒"为分割，合起来 = h * 1000000 + l，不会溢出
  · mcu.ticks() * 1000 / mcu.hz()  → 老固件没有 ticks2 时退回这条
]]
local HZ = 1000          -- 每秒 tick 数，取不到就按 1ms/tick 兜底
local HAS_T2 = false     -- mcu.ticks2 可用性

local function clock_init()
    if mcu and mcu.ticks2 then
        local ok, h = pcall(mcu.ticks2, 1)
        -- 注意不能写 type(mcu) ~= "table" 判断库在不在：LuatOS 的 mcu 是 rotable，
        -- type() 返回 "userdata"，这么写会让初始化整个跳过、退回默认 1000
        if ok and type(h) == "number" then HAS_T2 = true end
    end
    if mcu and mcu.hz then
        local ok, v = pcall(mcu.hz)
        if ok and type(v) == "number" and v >= 1 then HZ = v end
    end
end

local prev_t, wrap_acc = nil, 0
local function mono()
    if HAS_T2 then
        local ok, h, l = pcall(mcu.ticks2, 1)
        if ok and type(h) == "number" and type(l) == "number" then
            return h * 1000000 + l
        end
    end
    if not (mcu and mcu.ticks) then return clock end
    local ok, t = pcall(mcu.ticks)
    if not ok or type(t) ~= "number" then return clock end
    if prev_t and t < prev_t then wrap_acc = wrap_acc + 4294967296 end
    prev_t = t
    return (wrap_acc + t) * 1000 / HZ      -- tick → ms，这一步以前漏了
end

-- 和校验：ASCII 累加取低 8 位
local function sum8(s)
    local v = 0
    for i = 1, #s do v = (v + s:byte(i)) & 0xFF end
    return string.format("%02X", v)
end

-- ==================== 报文日志 ====================
--[[ NAK 错误码对照
     注意帧结构是 NAK(1) 站号(2,3) PLC号(4,5) 错误码(6,7)，共 7 字节。
     取成 sub(5,6) 会拿到"PLC 号第二个字符 + 错误码第一个字符"，
     于是所有 NAK 都被显示成 "F0"、"F2" 这种不存在的码，
     错误码永远看不懂（这个坑官方工程注释里也记过）。]]
local NAK_TEXT = {
    ["02"] = "和校验错误",
    ["03"] = "协议错误（D8120 格式与报文不符）",
    ["06"] = "字符区错误（软元件号越界或命令不支持）",
    ["07"] = "字符错误（数据含非十六进制字符）",
    ["0A"] = "PLC 号错误（应为 FF）",
    ["10"] = "PLC 号错误（本机不可访问）",
    ["18"] = "远程错误（PLC 禁止远程 RUN/STOP）",
}

-- 原始字节 → 带空格的大写十六进制
local function hex(s)
    if not s or #s == 0 then return "" end
    local r = (string.gsub(s, ".", function(ch)
        return string.format("%02X ", ch:byte())
    end))
    return (r:gsub("%s+$", ""))          -- 去掉尾部空格；括号保证只返回字符串
end

-- 控制码转可读形式，便于肉眼看帧边界：ENQ00FFWR0D0100032DCRLF
local function pretty(s)
    if not s or #s == 0 then return "" end
    local NAME = { [0x05] = "ENQ", [0x02] = "STX", [0x03] = "ETX",
                   [0x06] = "ACK", [0x15] = "NAK", [0x0D] = "CR", [0x0A] = "LF" }
    local t = {}
    for i = 1, #s do
        local b = s:byte(i)
        t[i] = NAME[b] or string.char(b)
    end
    return table.concat(t)
end

local function dump(tag, s)
    if not cfg.log_frames then return end
    log.info("fx3u", tag, #s .. "B", hex(s), "|", pretty(s))
end

local function build(cmd, addr, cnt, data)
    local body = cfg.station .. cfg.pcno .. cmd .. (cfg.wait_char or "0") .. "D"
        .. string.format("%04d", addr)
        .. string.format("%02X", cnt)
        .. (data or "")
    return "\5" .. body .. sum8(body) .. (cfg.crlf and "\r\n" or "")
end

-- ==================== 发送 ====================
--[[发一帧。DE 的覆盖时长按 (字节数+2)×12 位算：
8E1 每字符 11 位，12 位是给停止位和驱动排队留的余量，+2 个字符兜住 FIFO 延迟。
9600 下发 19 字节约 29ms，PLC 的应答最早也在 10ms 之后，不会撞上。]]
local function send(frame)
    -- 清掉 FIFO 里上一帧的残留（含哑帧的回响），避免旧字节串到本次应答前面。
    -- 用 uart.read 而不是只 rxClear：read 会把硬件缓冲一起抽干。
    if uart.read then pcall(uart.read, cfg.uart_id, 2048) end
    if uart.rxClear then pcall(uart.rxClear, cfg.uart_id) end
    rxbuf = ""

    if not native485 then
        gpio.set(cfg.de_pin, 1)          -- 手动模式：拉高 DE
        de_high = true
    end

    local n = uart.write(cfg.uart_id, frame)
    dump("TX", frame)                        -- 原始发送帧（config.plc.log_frames 控制）
    if type(n) == "number" and n <= 0 then
        --[[ write 返回 <=0 说明数据没进驱动。最常见的原因是固件不认第 8 参数、
        方向脚没被接管，导致驱动拒绝发送（Air8000W 上就是直接返回 -1）。
        这里自动降级到手翻 GPIO，并把方向脚收回来自己管。]]
        if native485 and not fallback_tried then
            fallback_tried = true
            native485 = false
            pcall(gpio.setup, cfg.de_pin, 0)
            log.error("fx3u", "uart.write 返回", n,
                "固件可能不支持内置 485 换向，改用手动方向控制；仍失败请查 config.uart.de_pin")
        else
            log.error("fx3u", "uart.write 返回", n, "本帧未上总线")
        end
    end

    --[[ DE 由固件管时的覆盖时间就是 rs485_delay（2000us），这里算的 tx_ms 只用来
    占住总线、避免连续发送互相踩：比整帧多留两个字符的余量。]]
    local tx_ms = math.floor((#frame + 2) * 12 * 1000 / cfg.baud) + 3
    busy_until = mono() + tx_ms
    if cur then cur.rx0 = stat.rx_total end   -- 记录本帧起点，失败时好算"收到几个字节"

    if not native485 then
        sys.timerStart(function()
            if de_high then
                gpio.set(cfg.de_pin, 0)
                de_high = false
            end
        end, tx_ms)
    end
end

-- ==================== 收 ====================
-- 尝试从 rxbuf 解出一帧；返回 "wait"/"data"/"ack"/"nak"/"bad"/"skip"
local function try_parse()
    local b = rxbuf:byte(1)
    if not b then return "wait" end

    if b == 0x06 then                       -- ACK（写成功）
        rxbuf = rxbuf:sub(2)
        return "ack"
    end

    if b == 0x15 then                       -- NAK + 站号 + PC号 + 错误码
        -- 帧长 7：NAK(1) 站号(2,3) PLC号(4,5) 错误码(6,7)
        if #rxbuf < 7 then return "wait" end
        local code = rxbuf:sub(6, 7):upper()
        rxbuf = rxbuf:sub(8)
        return "nak", code
    end

    if b == 0x02 then                       -- STX ... ETX 校验 CRLF
        local etx = rxbuf:find("\3", 2, true)
        if not etx then return "wait" end
        if #rxbuf < etx + 2 then return "wait" end
        local payload = rxbuf:sub(2, etx - 1)       -- 站号 + PC号 + 数据
        local got = rxbuf:sub(etx + 1, etx + 2):upper()
        local skip = etx + 2
        if cfg.crlf and rxbuf:sub(skip + 1, skip + 2) == "\r\n" then
            skip = skip + 2                          -- 格式4 的帧尾，一并吃掉
        end
        rxbuf = rxbuf:sub(skip + 1)
        if sum8(payload .. "\3") ~= got then return "bad" end
        local hex = payload:sub(5)
        local vals = {}
        for i = 1, #hex, 4 do vals[#vals + 1] = tonumber(hex:sub(i, i + 3), 16) end
        return "data", vals
    end

    rxbuf = rxbuf:sub(2)                    -- 未知字节，丢掉继续
    return "skip"
end

local function finish(kind, vals, err)
    local req = cur
    cur = nil
    if kind then
        stat.ok = stat.ok + 1
        stat.online = true
        stat.last_ok = mono()
        stat.rtt = math.floor(stat.last_ok - req.t0 + 0.5)
        if req.cb then req.cb(vals or {}) end
    else
        stat.fail = stat.fail + 1
        stat.online = false
        stat.last_ok = 0
        local t = mono()
        if t - last_fail_log >= 5000 then
            last_fail_log = t
            --[[ 带上"本帧收到几个字节"，这一项比错误名有用得多：
                 · 收到 0 字节  → 物理层问题：DE 没换向 / 485 没供电 / A B 接反
                 · 收到若干字节但解析不了 → 波特率或格式（CRLF/8E1）对不上
                 · 只收到半帧 → DE 释放太早，帧尾被截断 ]]
            local got = 0
            if req and req.rx0 then got = stat.rx_total - req.rx0 end
            log.warn("fx3u", "请求失败", err, "本帧收到", got, "字节", "累计", stat.fail)
        end
        if req.cb then req.cb(nil, err) end
    end
end

local function dispatch()
    if not cur then rxbuf = "" return end
    while true do
        local kind, val = try_parse()
        if kind == "wait" then return end
        if kind == "data" or kind == "ack" then
            finish(true, val)
            return
        elseif kind == "nak" then
            finish(false, nil, string.format("NAK %s %s", tostring(val),
                NAK_TEXT[tostring(val)] or "未知错误"))
            return
        elseif kind == "bad" then
            finish(false, nil, "checksum")
            return
        end
        -- "skip" 继续循环
    end
end

local function pump()
    if cur then return end
    if mono() < busy_until then return end
    local req = table.remove(queue, 1)
    if not req then return end
    cur = req
    req.t0 = mono()
    send(req.frame)
end

local function tick()
    clock = clock + TIMER_MS
    local t = mono()

    if cur and (t - cur.t0) > cfg.timeout_ms then
        stat.timeout = stat.timeout + 1
        if cur.tries < cfg.retry then
            cur.tries = cur.tries + 1
            cur.t0 = t
            send(cur.frame)
            log.debug("fx3u", "超时重试", cur.tries)
        else
            finish(false, nil, "timeout")
        end
    end

    -- 心跳式在线判定：超过 3 秒没有成功应答就算掉线
    if stat.online and (t - stat.last_ok) > 3000 then
        stat.online = false
    end

    pump()
end

-- ==================== 初始化 ====================
function M.init(ucfg, pcfg)
    cfg = {}
    for k, v in pairs(ucfg) do cfg[k] = v end
    for k, v in pairs(pcfg) do cfg[k] = v end

    -- 参数自检：宁可报错返回，也不要让 uart.setup 抛异常把 VM 带崩
    local miss = {}
    for _, k in ipairs({ "uart_id", "baud", "de_pin", "pwr_pin", "station", "pcno" }) do
        if cfg[k] == nil then miss[#miss + 1] = k end
    end
    if #miss > 0 then
        log.error("fx3u", "配置缺失:", table.concat(miss, ","))
        return false
    end

    gpio.setup(cfg.pwr_pin, 1)      -- 485 收发芯片供电，必须先拉高
    clock_init()                    -- 时间基准先就位，后面所有超时都靠它

    local ok, ret
    if cfg.rs485_native ~= false then
        --[[ 固件内置换向：第 8 = 方向脚，第 9 = 接收态电平（本板低电平接收），
        第 10 = 发完到转接收的延迟（us），第 11 = 调试开关（nil 用默认），
        第 12 = 接收出错是否丢缓存（0 = 不丢，便于看到完整原始字节）。
        方向脚由 uart.setup 接管，之后不要再 gpio.setup / gpio.set 它。]]
        ok, ret = pcall(uart.setup, cfg.uart_id, cfg.baud, 8, 1, uart.EVEN,
            uart.LSB, 1024, cfg.de_pin, 0, cfg.rs485_delay or 2000, nil, 0)
        if ok and (ret == nil or ret == true or ret == 0) then
            native485 = true
        else
            log.warn("fx3u", "内置 485 换向初始化失败，退回手动方向控制", ret)
            pcall(uart.close, cfg.uart_id)
            ok, ret = pcall(uart.setup, cfg.uart_id, cfg.baud, 8, 1, uart.EVEN)
            native485 = false
        end
    else
        ok, ret = pcall(uart.setup, cfg.uart_id, cfg.baud, 8, 1, uart.EVEN)
        native485 = false
        log.info("fx3u", "config.uart.rs485_native = false，用手动方向控制")
    end

    if not ok then
        log.error("fx3u", "uart.setup 失败", ret)
        return false
    end
    if not native485 then
        gpio.setup(cfg.de_pin, 0)   -- 手动模式：方向脚自己管，空闲停接收态
    end

    pcall(uart.on, cfg.uart_id, "receive", function(id, len)
        local d = uart.read(id, len)
        if not d or #d == 0 then return end
        dump("RX", d)                        -- 原始接收字节（可能是分片的半帧）
        -- 注意：不要再按"发送窗口"过滤字节。485 模式下驱动自己会把发送期间
        -- 回采进来的字节丢掉，Lua 侧再拦一道反而会把 PLC 早到的应答一起吃掉。
        rxbuf = rxbuf .. d
        stat.rx_total = stat.rx_total + #d
        if #rxbuf > 512 then rxbuf = rxbuf:sub(-256) end
        dispatch()
    end)

    --[[ 平台开启串口后的第一帧在总线上是无效的（PLC 不回，第二帧起才正常）。
    这里延后 200ms 发一帧哑请求把它消耗掉 —— 顺带等 uart 硬件就绪，
    否则第一帧可能连发都没发出去，"消耗首帧"就白做了。]]
    sys.timerStart(function()
        local n = uart.write(cfg.uart_id, build("WR", cfg.start_addr or 0, 1))
        if type(n) == "number" and n <= 0 then
            log.warn("fx3u", "首帧哑请求发送失败，返回", n)
        end
    end, 200)

    sys.timerLoopStart(tick, TIMER_MS)
    log.info("fx3u", "时间基准",
        HAS_T2 and "ticks2(1) 直接给毫秒"
        or ("ticks/" .. HZ .. "Hz，一格 " .. string.format("%.0f", 1000 / HZ) .. "ms"),
        "timeout=" .. tostring(cfg.timeout_ms) .. "ms")
    log.info("fx3u", "init", "UART" .. tostring(cfg.uart_id), cfg.baud, "8E1",
        native485 and ("内置485 换向 DE=GPIO" .. tostring(cfg.de_pin) ..
            " delay=" .. tostring(cfg.rs485_delay or 2000) .. "us")
        or ("手动换向 DE=GPIO" .. tostring(cfg.de_pin)),
        "pwr=GPIO" .. tostring(cfg.pwr_pin))
    return true
end

-- 读 D 区：cb(vals) 或 cb(nil, err)
function M.read(addr, cnt, cb)
    queue[#queue + 1] = {
        kind = "read",
        frame = build("WR", addr, cnt),
        cb = cb,
        tries = 0,
        t0 = 0,
    }
    pump()
end

-- 写 D 区单字：cb(true) 或 cb(nil, err)
function M.write(addr, val, cb)
    queue[#queue + 1] = {
        kind = "write",
        frame = build("WW", addr, 1, string.format("%04X", val & 0xFFFF)),
        cb = cb,
        tries = 0,
        t0 = 0,
    }
    pump()
end

function M.stats() return stat end
function M.now() return mono() end
function M.is_native485() return native485 end

return M
