--[[
@module  fxlinks
@summary 三菱 FX 串口计算机链接协议（FxLinks，格式 1，自动和校验）
@version 1.0.0
@date    2026.11.09

适用：FX0N/FX1N/FX2N/FX3U 及兼容机（如凌一 FX-32）的 RS485/RS422 编程口或扩展 485 口。
PLC 侧 D8120 必须设成格式 1 + 自动和校验，本模块按 H6087（9600/8/E/1/格式1）编写。

=== 帧结构（全部字段为 ASCII 十六进制字符）===

请求：
    ENQ(05H) 站号(2) PLC号(2) 命令(2) 延时(1) 软元件(5) 点数/数据 校验和(2)
    例：读 D0 起 3 点（站号 00）
        05 30 30 46 46 57 52 30 44 30 30 30 30 30 33 32 43
        ENQ  "00" "FF" "WR" "0" "D0000" "03"  "2C"

读响应：
    STX(02H) 站号(2) PLC号(2) 数据 ETX(03H) 校验和(2)
    字读：每点 4 字符；位读：每点 1 字符（'0'/'1'）

写响应：
    ACK(06H) 站号(2) PLC号(2)                  -- 成功
    NAK(15H) 站号(2) PLC号(2) 错误码(2)        -- 失败

=== 校验和范围（两处不一致，最容易写错）===
    请求：从站号第一个字符到帧尾（不含 ENQ）累加，取低 8 位
    响应：从站号第一个字符到 ETX（含 ETX 本身）累加，取低 8 位

=== 命令 ===
    BR 位读    WR 字读    BW 位写    WW 字写
]]

local M = {}

local ENQ, STX, ETX, ACK, NAK = 0x05, 0x02, 0x03, 0x06, 0x15

-- NAK 错误码
local ERR_TEXT = {
    ["02"] = "和校验错误",
    ["03"] = "协议错误（D8120 设置的格式与报文不符）",
    ["06"] = "字符区错误（软元件号越界或命令不支持）",
    ["07"] = "字符错误（写入数据含非十六进制字符）",
    ["0A"] = "PLC 号错误（应为 FF）",
    ["10"] = "PLC 号错误（本机不可访问）",
    ["18"] = "远程错误（PLC 禁止远程 RUN/STOP）",
}

-- X/Y/B/W 的编号是八进制，与 PLC 面板一致；其余十进制
local OCT_DEV = { X = true, Y = true, B = true, W = true }

local cfg, plc          -- conf.uart / conf.plc
local rx = {}           -- 接收分片
local opened = false
local busy = false      -- 串行访问保护：485 是半双工共享总线

-- ===== 基础工具 =====

--[[
ASCII 累加和，取低 8 位
@param s string 待累加字符串
@return number 0~255
]]
local function sum8(s)
    local t = 0
    for i = 1, #s do
        t = t + s:byte(i)
    end
    return t % 256
end

--[[
软元件地址格式化成 5 字符：X/Y/B/W 八进制 4 位，其余十进制 4 位
@param dev string 软元件字母
@param addr number 编号
@return string 例："D0000"、"X0010"
]]
local function device_addr(dev, addr)
    dev = string.upper(dev)
    if OCT_DEV[dev] then
        return dev .. string.format("%04o", addr)
    end
    return dev .. string.format("%04d", addr)
end

--[[
拼接请求帧
@param cmd string 命令码，"WR"/"WW"/"BR"/"BW"
@param dev string 软元件字母
@param addr number 起始编号
@param payload string 点数与数据部分（已格式化为字符串）
@return string 完整帧
]]
local function build(cmd, dev, addr, payload)
    local body = string.format("%02X", plc.station)
        .. string.format("%02X", plc.plc_no)
        .. cmd
        .. string.format("%X", plc.wait)
        .. device_addr(dev, addr)
        .. payload
    return string.char(ENQ) .. body .. string.format("%02X", sum8(body))
end

--[[
把原始帧转成带空格的十六进制字符串，便于日志排查
@param s string 原始字节
@return string 例："05 30 30 46 46 "
]]
function M.hex(s)
    if not s or #s == 0 then return "" end
    return (string.gsub(s, ".", function(ch)
        return string.format("%02X ", ch:byte())
    end))
end

--[[
把原始帧转成控制码可读的形式
@param s string 原始字节
@return string 例："ENQ 00FFWR0D00000433"
]]
function M.pretty(s)
    if not s or #s == 0 then return "" end
    local t = {}
    for i = 1, #s do
        local b = s:byte(i)
        if b == ENQ then t[i] = "ENQ"
        elseif b == STX then t[i] = "STX"
        elseif b == ETX then t[i] = "ETX"
        elseif b == ACK then t[i] = "ACK"
        elseif b == NAK then t[i] = "NAK"
        else t[i] = string.char(b) end
    end
    return table.concat(t)
end

-- ===== 串口 =====

-- 485 方向（DE）由 uart.setup 的 pin485 参数交给平台自动换向，Lua 侧不再碰方向脚。
-- tx_waiting 只表示"本帧数据是否已交清"，与方向控制无关。
local tx_waiting = false

-- ===== 心跳 =====
-- 收发过程不能用 sys.wait(ms) / sys.waitUntil(msg, ms) 轮询：两者每次调用都会
-- 创建并销毁一个 C 层定时器，800ms 超时按 10ms 步进就是每帧 80 次创建+删除。
-- SDK 的定时器实现存在"回调执行中该定时器被删除"的窗口，会打印
--   luat_timer_get 128:id xxx no find!!!
-- 随后这一次唤醒直接丢失：等待被拉长（800ms 变 1200ms）、协程迟迟不回到
-- Lua 侧，接收回调得不到处理，表现就是整帧丢（收到 0 字节）或读到上一帧的
-- 残段（数据错乱）。改为常驻一个 10ms 循环定时器，收发全程只等这个事件，
-- 不再产生任何临时定时器。循环定时器只创建一次、从不删除，不落入上述窗口。
local TICK_MS = 10
local tick_id

local function tick_start()
    if tick_id then return end
    tick_id = sys.timerLoopStart(function()
        sys.publish("FX_TICK")
    end, TICK_MS)
end

local function tick_stop()
    if tick_id then
        sys.timerStop(tick_id)
        tick_id = nil
    end
end

local function on_sent(uid)
    -- "sent" 在数据全部交给发送 FIFO/DMA 时就回调，此刻移位寄存器里还有最后
    -- 1~2 个字节在往外送，所以这里只置标志，不碰方向脚——换向由驱动自己收尾。
    tx_waiting = false
    sys.publish("FX_TICK")      -- 立即唤醒等待中的 transact，不必等下一个心跳
end

local function on_receive(uid, len)
    local d = uart.read(uid, len)
    if d and #d > 0 then
        rx[#rx + 1] = d
        sys.publish("FX_TICK")  -- 同上：来数据就唤醒，响应处理零延迟
    end
end

--[[
打开串口（8 数据位 + 偶校验，485 方向默认交给平台自动换向）
@param c table conf.uart
@param p table conf.plc
@return boolean ok, string|number err
]]
function M.init(c, p)
    cfg, plc = c, p

    -- 第 8/9/10 参数交给平台做 485 自动换向：pin485、接收态电平、换向延迟(us)。
    -- 驱动在最后一个字节真正移出移位寄存器后，再等这个延迟才释放 DE，比在 Lua 层
    -- 等 "sent" 再切脚可靠（sent 在数据灌进 FIFO 时就触发，提前切会把帧尾的校验
    -- 字符截掉，PLC 直接回 NAK 02）。
    -- 第 12 个参数 error_drop = 0：接收出错时不丢弃缓存，便于看到完整原始字节
    local r = uart.setup(cfg.id, cfg.baud, cfg.databits, cfg.stopbits, cfg.parity,
        uart.LSB, 1024, cfg.de_pin, cfg.de_rx_level, cfg.rs485_delay_us, nil, 0)
    if r ~= 0 then
        return false, "uart.setup 失败，返回 " .. tostring(r)
    end

    -- uart 硬件就绪需要时间，先等一小段
    sys.wait(100)

    uart.on(cfg.id, "receive", on_receive)
    uart.on(cfg.id, "sent", on_sent)
    opened = true
    tick_start()

    -- 平台首次写出的帧在总线上无效（PLC 不回，第二帧起正常），
    -- 这里在初始化阶段先发一帧哑请求并丢弃响应，把"第一帧"消耗掉，
    -- 否则每次开机都会报一次响应超时、白等 800ms
    uart.write(cfg.id, build("WR", "D", 0, "01"))
    sys.wait(150)
    uart.read(cfg.id, 2048)

    log.info("fxlinks", "串口已打开", cfg.baud,
        cfg.databits .. "位", "偶校验", cfg.stopbits .. "停止位",
        "DE=GPIO" .. tostring(cfg.de_pin) .. "(自动换向)",
        "站号=" .. plc.station)
    return true
end

--[[
关闭串口，释放回调
]]
function M.close()
    if not opened then return end
    uart.on(cfg.id, "receive", nil)
    uart.on(cfg.id, "sent", nil)
    uart.close(cfg.id)
    tick_stop()
    opened = false
end

-- ===== 收发 =====

--[[
判断缓冲区里是否已组成完整帧
@param s string 累积数据
@return number >0 完整帧长度；0 还没收完；-1 首字节非法
]]
local function frame_len(s)
    if #s < 1 then return 0 end
    local c = s:byte(1)

    if c == ACK then
        return #s >= 5 and 5 or 0
    elseif c == NAK then
        return #s >= 7 and 7 or 0
    elseif c == STX then
        local etx = s:find("\3", 1, true)   -- 数据区只含 ASCII，不会出现 0x03
        if etx and #s >= etx + 2 then return etx + 2 end
        return 0
    end
    return -1
end

--[[
解析响应帧
@param raw string 完整响应
@return table { ok=true, data="..." } 或 { ok=false, err="..." }
]]
local function parse(raw)
    local c = raw:byte(1)

    if c == ACK then
        return { ok = true }
    end

    if c == NAK then
        -- NAK 帧：NAK(1) 站号(2,3) PLC号(4,5) 错误码(6,7)，共 7 字节。
        -- 原来取 sub(5,6) 取到的是 PLC 号的第二个字符，于是"FF"+"02"
        -- 被拼成 "F0"，所有 NAK 都显示成"未知错误"，错误码一直没被看懂过。
        local code = string.upper(raw:sub(6, 7))
        return {
            ok   = false,
            code = code,
            err  = string.format("PLC 返回 NAK %s：%s", code, ERR_TEXT[code] or "未知错误"),
        }
    end

    if c ~= STX then
        return { ok = false, err = "响应首字节非法：" .. M.hex(raw:sub(1, 1)) }
    end

    local etx = raw:find("\3", 1, true)
    local body = raw:sub(2, etx)              -- 站号 ~ ETX（含 ETX）
    local got  = tonumber(raw:sub(etx + 1, etx + 2), 16)

    if got ~= sum8(body) then
        return { ok = false, err = string.format("和校验错误：帧内 %02X，计算 %02X", got or -1, sum8(body)) }
    end

    local st = tonumber(raw:sub(2, 3), 16)
    if st ~= plc.station then
        return { ok = false, err = string.format("站号不匹配：回 %02X，期望 %02X", st or -1, plc.station) }
    end

    -- 帧结构：STX(1) 站号(2,3) PLC号(4,5) 数据(6..etx-1) ETX 校验(2)
    -- 数据必须从第 6 个字节开始，写成 7 会丢掉第一个字符：
    --   单点读时前导 0 恰好把错误掩盖（"0366" 截成 "366" 数值仍是 870），
    --   但多点读会少 1 个字符，直接触发下面的"响应数据不足"。
    return { ok = true, data = raw:sub(6, etx - 1) }
end

--[[
发送一帧并等待响应（阻塞，只能在协程里调用）
@param frame string 请求帧
@return string|nil 完整响应帧, string|nil 错误
]]
local function transact_inner(frame)
    rx = {}
    -- 清掉硬件 FIFO 里上一帧的残留字节，避免旧数据串到本次响应前面
    uart.read(cfg.id, 2048)

    -- 方向脚由驱动在 uart.write 内部自动拉高并在发送完毕后释放，这里只管写
    tx_waiting = true
    local n = uart.write(cfg.id, frame)
    if not n or n <= 0 then
        tx_waiting = false
        return nil, "串口写入失败"
    end

    -- 等 "sent" 事件确认数据交清（方向脚由驱动自己收尾，这里不等它）；
    -- 异步调度延迟时最多等"按帧长算出的发送耗时 + 8ms"，按心跳折算成次数。
    -- 8E1 每字节 11 位（1 起始 + 8 数据 + 1 校验 + 1 停止）
    local tx_ms = math.ceil(#frame * 11 * 1000 / cfg.baud)
    local tx_ticks = math.max(1, math.ceil((tx_ms + 8) / TICK_MS))
    for _ = 1, tx_ticks do
        if not tx_waiting then break end
        sys.waitUntil("FX_TICK")
    end
    tx_waiting = false

    -- 等响应：每次心跳或有新分片到达就看一次帧是否完整；
    -- 只有"数据长度还在增长"才重置空闲计数，否则残帧会因 #data > 0
    -- 一直成立而永远不判超时
    local max_idle = math.ceil(plc.timeout / TICK_MS)
    local idle = 0
    local last_n = -1

    while idle <= max_idle do
        local data = table.concat(rx)
        local len = frame_len(data)

        if len > 0 then
            rx = {}
            return data:sub(1, len)
        elseif len < 0 then
            rx = {}
            return nil, "响应数据错乱：" .. M.hex(data:sub(1, 8))
        end

        if #data ~= last_n then
            last_n = #data
            idle = 0
        else
            idle = idle + 1
        end

        sys.waitUntil("FX_TICK")
    end

    -- 带上 "sent 是否触发"：未触发说明写口没交清，多半是串口层问题而不是线路问题
    return nil, string.format("响应超时（收到 %d 字节，%s）",
        #table.concat(rx), tx_waiting and "发送未完成" or "发送已完成")
end

local function transact(frame)
    if not opened then return nil, "串口未打开" end
    if busy then return nil, "串口忙，上一个请求未完成" end

    busy = true
    local ok, a, b = pcall(transact_inner, frame)
    busy = false

    if not ok then
        return nil, "内部异常：" .. tostring(a)
    end
    return a, b
end

--[[
应用层请求：构造 → 发送 → 校验
@param cmd string 命令码
@param dev string 软元件
@param addr number 起始编号
@param payload string 点数/数据
@return table|nil 解析结果, string|nil 错误
]]
local function request(cmd, dev, addr, payload)
    local frame = build(cmd, dev, addr, payload)

    log.debug("fxlinks", "=>", M.hex(frame), M.pretty(frame))

    local raw, err = transact(frame)
    if not raw then
        log.warn("fxlinks", "<= 无响应", err)
        return nil, err
    end

    log.debug("fxlinks", "<=", M.hex(raw), M.pretty(raw))

    local r = parse(raw)
    if not r.ok then
        log.warn("fxlinks", "<=", r.err)
        return nil, r.err
    end
    return r
end

-- ===== 对外 API =====

--[[
离线核对用：只拼帧不发送
@param cmd string 命令码，"WR"/"WW"/"BR"/"BW"
@param dev string 软元件
@param addr number 起始编号
@param payload string 点数/数据
@return string 请求帧
]]
function M.build_frame(cmd, dev, addr, payload)
    return build(cmd, dev, addr, payload)
end

--[[
离线核对用：解析一帧响应（含和校验、站号校验）
@param raw string 完整响应帧
@return table { ok=true, data="..." } 或 { ok=false, err="..." }
]]
function M.parse_frame(raw)
    return parse(raw)
end

--[[
字软元件批量读（WR）
@param dev string 软元件，如 "D"
@param addr number 起始编号
@param count number 点数 1~64
@return table|nil 数值数组（1 起）, string|nil 错误
]]
function M.read_words(dev, addr, count)
    count = count or 1
    if count < 1 or count > 64 then
        return nil, "点数需 1~64"
    end

    local r, err = request("WR", dev, addr, string.format("%02X", count))
    if not r then return nil, err end

    local s = r.data or ""
    if #s < count * 4 then
        return nil, string.format("响应数据不足：期望 %d 字符，实得 %d", count * 4, #s)
    end

    local out = {}
    for i = 1, count do
        out[i] = tonumber(s:sub((i - 1) * 4 + 1, i * 4), 16)
    end
    return out
end

--[[
字软元件批量写（WW）
@param dev string 软元件，如 "D"
@param addr number 起始编号
@param values table 数值数组（1 起，自动截断到 16 位）
@return boolean|nil 成功, string|nil 错误
]]
function M.write_words(dev, addr, values)
    local n = #values
    if n < 1 or n > 64 then
        return nil, "点数需 1~64"
    end

    local t = { string.format("%02X", n) }
    for i = 1, n do
        t[#t + 1] = string.format("%04X", math.floor(values[i]) % 0x10000)
    end

    local r, err = request("WW", dev, addr, table.concat(t))
    if not r then return nil, err end
    return true
end

--[[
位软元件批量读（BR）
@param dev string 软元件，如 "X"/"Y"/"M"
@param addr number 起始编号
@param count number 点数 1~64
@return table|nil 0/1 数组, string|nil 错误
]]
function M.read_bits(dev, addr, count)
    count = count or 1
    if count < 1 or count > 64 then
        return nil, "点数需 1~64"
    end

    local r, err = request("BR", dev, addr, string.format("%02X", count))
    if not r then return nil, err end

    local s = r.data or ""
    if #s < count then
        return nil, string.format("响应数据不足：期望 %d 字符，实得 %d", count, #s)
    end

    local out = {}
    for i = 1, count do
        out[i] = (s:sub(i, i) == "1") and 1 or 0
    end
    return out
end

--[[
位软元件批量写（BW）
@param dev string 软元件，如 "Y"/"M"
@param addr number 起始编号
@param values table 0/1 数组
@return boolean|nil 成功, string|nil 错误
]]
function M.write_bits(dev, addr, values)
    local n = #values
    if n < 1 or n > 64 then
        return nil, "点数需 1~64"
    end

    local t = { string.format("%02X", n) }
    for i = 1, n do
        t[#t + 1] = (values[i] ~= 0 and values[i] ~= false) and "1" or "0"
    end

    local r, err = request("BW", dev, addr, table.concat(t))
    if not r then return nil, err end
    return true
end

return M
