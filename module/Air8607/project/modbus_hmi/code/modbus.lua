--[[
@module  modbus
@summary Modbus 协议核心：CRC16、RTU/TCP 帧封装与解析、功能码 PDU、数据类型编解码
@version 1.0.0
@date    2026.10.25

支持的协议数据单元（PDU）：
  0x01 读线圈          0x02 读离散输入
  0x03 读保持寄存器    0x04 读输入寄存器
  0x05 写单个线圈      0x06 写单个保持寄存器
  0x0F 写多个线圈      0x10 写多个保持寄存器

支持的数据类型（dtype）：
  u16 / i16                     单寄存器
  u32 / i32 / f32               双寄存器，高字在前（CD AB 之外的常见“字序高在前”）
  u32lo / i32lo / f32lo         双寄存器，低字在前（"CD AB" 字序）

所有 32 位量默认按「大端字节 + 高字在前」解析，可通过 *lo 变体切换字序。
]]
local M = {}

-- ==================== 常量表 ====================
M.FC_NAME = {
    [0x01] = "读线圈", [0x02] = "读离散输入",
    [0x03] = "读保持寄存器", [0x04] = "读输入寄存器",
    [0x05] = "写单线圈", [0x06] = "写单寄存器",
    [0x0F] = "写多线圈", [0x10] = "写多寄存器",
}

M.EXC_NAME = {
    [0x01] = "非法功能", [0x02] = "非法数据地址", [0x03] = "非法数据值",
    [0x04] = "从站设备故障", [0x05] = "确认(需长时处理)", [0x06] = "从站设备忙",
    [0x07] = "否定确认", [0x08] = "存储奇偶性错误",
    [0x0A] = "网关路径不可用", [0x0B] = "网关目标无响应",
}

M.DTYPE_NAME = {
    u16 = "UINT16", i16 = "INT16", u32 = "UINT32", i32 = "INT32",
    f32 = "FLOAT32", u32lo = "UINT32(低字在前)", i32lo = "INT32(低字在前)",
    f32lo = "FLOAT32(低字在前)", bool = "BIT",
}

-- ==================== CRC16 (Modbus, 多项式 0xA001) ====================
local CRC_TABLE = nil

local function build_crc_table()
    local t = {}
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if (crc & 1) ~= 0 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
        t[i] = crc & 0xFFFF
    end
    return t
end

function M.crc16(s)
    if not CRC_TABLE then CRC_TABLE = build_crc_table() end
    local crc = 0xFFFF
    for i = 1, #s do
        local b = string.byte(s, i)
        crc = ((crc >> 8) ~ CRC_TABLE[(crc ~ b) & 0xFF]) & 0xFFFF
    end
    return crc
end

-- ==================== RTU 帧 ====================
function M.rtu_wrap(slave, pdu)
    local s = string.char(slave & 0xFF) .. pdu
    local crc = M.crc16(s)
    return s .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

-- 返回 slave, pdu；失败返回 nil, 错误信息
function M.rtu_unwrap(frame)
    if (not frame) or #frame < 4 then return nil, "帧长不足" end
    local body = frame:sub(1, #frame - 2)
    local crc = M.crc16(body)
    local lo = string.byte(frame, #frame - 1)
    local hi = string.byte(frame, #frame)
    if (crc & 0xFF) ~= lo or ((crc >> 8) & 0xFF) ~= hi then
        return nil, "CRC 校验失败"
    end
    return string.byte(body, 1), body:sub(2)
end

-- 根据已收到的响应字节判断还需要多少字节（用于串口收帧）
function M.rtu_need_len(buf)
    if (not buf) or #buf < 3 then return nil end
    local fc = string.byte(buf, 2)
    if fc == nil then return nil end
    if fc >= 0x80 then return 5 end
    if fc == 0x01 or fc == 0x02 or fc == 0x03 or fc == 0x04 then
        local n = string.byte(buf, 3)
        if n == nil then return nil end
        return 3 + n + 2
    end
    if fc == 0x05 or fc == 0x06 or fc == 0x0F or fc == 0x10 then return 8 end
    return nil
end

-- ==================== TCP (MBAP) 帧 ====================
function M.tcp_wrap(txn, slave, pdu)
    local len = #pdu + 1
    return string.char(
        (txn >> 8) & 0xFF, txn & 0xFF,
        0x00, 0x00,
        (len >> 8) & 0xFF, len & 0xFF,
        slave & 0xFF
    ) .. pdu
end

function M.tcp_unwrap(resp, txn, slave)
    if (not resp) or #resp < 8 then return nil, "帧长不足" end
    local t = string.byte(resp, 1) * 256 + string.byte(resp, 2)
    local pid = string.byte(resp, 3) * 256 + string.byte(resp, 4)
    -- local len = string.byte(resp,5)*256 + string.byte(resp,6)
    local uid = string.byte(resp, 7)
    if pid ~= 0 then return nil, "协议标识错误" end
    if txn and t ~= (txn & 0xFFFF) then return nil, "事务标识不匹配" end
    if slave and uid ~= (slave & 0xFF) then return nil, "从站地址不匹配" end
    return resp:sub(8)
end

function M.tcp_need_len(buf)
    if (not buf) or #buf < 6 then return nil end
    local len = string.byte(buf, 5) * 256 + string.byte(buf, 6)
    if len < 1 or len > 260 then return nil end
    return 6 + len
end

-- ==================== PDU 构建 ====================
local function be16(v)
    v = v & 0xFFFF
    return string.char((v >> 8) & 0xFF, v & 0xFF)
end

function M.read_pdu(fc, addr, count)
    return string.char(fc) .. be16(addr) .. be16(count)
end

function M.write_single_pdu(fc, addr, value)
    return string.char(fc) .. be16(addr) .. be16(value)
end

function M.write_multi_reg_pdu(addr, values)
    local n = #values
    local p = string.char(0x10) .. be16(addr) .. be16(n) .. string.char(n * 2)
    for i = 1, n do p = p .. be16(values[i] or 0) end
    return p
end

function M.write_multi_coil_pdu(addr, bits)
    local n = #bits
    local nb = math.ceil(n / 8)
    local p = string.char(0x0F) .. be16(addr) .. be16(n) .. string.char(nb)
    for i = 1, nb do
        local b = 0
        for j = 0, 7 do
            local idx = (i - 1) * 8 + j + 1
            if bits[idx] then b = b | (1 << j) end
        end
        p = p .. string.char(b)
    end
    return p
end

-- ==================== PDU 解析 ====================
-- 返回 {ok=true, fc=, regs=/bits=/addr=/value=/count=} 或 {ok=false, err=, code=, fc=}
-- qty 为可选：读位时 PDU 只给字节数，按主站请求的位数截断
function M.parse_pdu(pdu, qty)
    if (not pdu) or #pdu < 1 then return { ok = false, err = "空 PDU" } end
    local fc = string.byte(pdu, 1)

    if fc >= 0x80 then
        return { ok = false, err = "exception", fc = fc - 0x80, code = string.byte(pdu, 2) or 0 }
    end

    if fc == 0x01 or fc == 0x02 then
        local n = string.byte(pdu, 2) or 0
        local bits = {}
        for i = 1, n do
            local b = string.byte(pdu, 2 + i) or 0
            for j = 0, 7 do
                bits[#bits + 1] = ((b >> j) & 1) == 1
            end
        end
        if qty and qty > 0 and qty < #bits then
            local b2 = {}
            for i = 1, qty do b2[i] = bits[i] end
            bits = b2
        end
        return { ok = true, fc = fc, bits = bits, count = #bits }
    end

    if fc == 0x03 or fc == 0x04 then
        local n = string.byte(pdu, 2) or 0
        local regs = {}
        for i = 1, (n // 2) do
            local hi = string.byte(pdu, 2 + (i - 1) * 2 + 1) or 0
            local lo = string.byte(pdu, 2 + (i - 1) * 2 + 2) or 0
            regs[i] = hi * 256 + lo
        end
        return { ok = true, fc = fc, regs = regs, count = #regs }
    end

    if fc == 0x05 or fc == 0x06 then
        local a = (string.byte(pdu, 2) or 0) * 256 + (string.byte(pdu, 3) or 0)
        local v = (string.byte(pdu, 4) or 0) * 256 + (string.byte(pdu, 5) or 0)
        return { ok = true, fc = fc, addr = a, value = v }
    end

    if fc == 0x0F or fc == 0x10 then
        local a = (string.byte(pdu, 2) or 0) * 256 + (string.byte(pdu, 3) or 0)
        local q = (string.byte(pdu, 4) or 0) * 256 + (string.byte(pdu, 5) or 0)
        return { ok = true, fc = fc, addr = a, count = q }
    end

    return { ok = false, err = "不支持的功能码 " .. tostring(fc) }
end

function M.err_text(res)
    if not res then return "无响应" end
    if res.ok then return "OK" end
    if res.err == "exception" then
        return string.format("异常码 0x%02X %s", res.code or 0, M.EXC_NAME[res.code] or "未知")
    end
    return tostring(res.err)
end

-- ==================== 数据类型编解码 ====================
-- 从寄存器数组解码工程量原始值（未乘 scale）
function M.decode(regs, dtype, start)
    start = start or 1
    local a = regs[start] or 0
    if dtype == "bool" then return a ~= 0 and 1 or 0 end
    if dtype == "u16" then return a end
    if dtype == "i16" then return (a >= 0x8000) and (a - 0x10000) or a end

    local b = regs[start + 1] or 0
    local hi, lo = a, b
    if dtype == "u32lo" or dtype == "i32lo" or dtype == "f32lo" then
        hi, lo = b, a
    end
    local u = hi * 65536 + lo

    if dtype == "u32" or dtype == "u32lo" then return u end
    if dtype == "i32" or dtype == "i32lo" then
        return (u >= 0x80000000) and (u - 0x100000000) or u
    end
    return M.f32_from_u32(u)
end

-- 编码为寄存器数组（输入为工程量原始值，未除 scale）
function M.encode(v, dtype)
    v = tonumber(v) or 0
    if dtype == "u16" then return { math.floor(v) & 0xFFFF } end
    if dtype == "i16" then
        local x = math.floor(v)
        if x < 0 then x = x + 0x10000 end
        return { x & 0xFFFF }
    end
    local u
    if dtype == "f32" or dtype == "f32lo" then
        u = M.u32_from_f32(v)                     -- 浮点不能先取整
    else
        u = math.floor(v)
        if u < 0 then u = u + 0x100000000 end
    end
    local hi = (u >> 16) & 0xFFFF
    local lo = u & 0xFFFF
    if dtype == "u32lo" or dtype == "i32lo" or dtype == "f32lo" then
        return { lo, hi }
    end
    return { hi, lo }
end

function M.reg_count(dtype)
    if dtype == "u16" or dtype == "i16" or dtype == "bool" then return 1 end
    return 2
end

-- ==================== IEEE754 float32（纯 Lua 实现，不依赖 string.pack） ====================
function M.f32_from_u32(x)
    x = x & 0xFFFFFFFF
    local sign = (x >> 31) & 1
    local exp = (x >> 23) & 0xFF
    local man = x & 0x7FFFFF
    local v
    if exp == 0 then
        v = man * 2.0 ^ -149
    else
        v = (1.0 + man / 8388608.0) * 2.0 ^ (exp - 127)
    end
    if sign == 1 then v = -v end
    return v
end

function M.u32_from_f32(v)
    v = tonumber(v) or 0
    if v ~= v then return 0 end                       -- NaN
    if v == math.huge then return 0x7F800000 end
    if v == -math.huge then return 0xFF800000 end
    local sign = 0
    if v < 0 then sign = 1; v = -v end
    if v == 0 then return sign << 31 end
    local exp = 0
    local man = 0
    if v < 1.17549435e-38 then
        -- 次正规数（极少用到，按 0 处理即可）
        return sign << 31
    else
        exp = math.floor(math.log(v) / 0.6931471805599453)
        if exp < -126 then exp = -126 end
        if exp > 127 then exp = 127 end
        local norm = v / 2.0 ^ exp
        if norm >= 2.0 then exp = exp + 1; norm = v / 2.0 ^ exp end
        if norm < 1.0 then exp = exp - 1; norm = v / 2.0 ^ exp end
        man = math.floor((norm - 1.0) * 8388608.0 + 0.5)
        if man >= 8388608 then man = 0; exp = exp + 1 end
        if man < 0 then man = 0 end
        exp = exp + 127
        if exp < 1 then exp = 1 end
        if exp > 254 then exp = 254; man = 0x7FFFFF end
    end
    return ((sign << 31) | (exp << 23) | man) & 0xFFFFFFFF
end

-- ==================== 工具 ====================
function M.hex(s, sep)
    if not s then return "" end
    local t = {}
    for i = 1, #s do t[#t + 1] = string.format("%02X", string.byte(s, i)) end
    return table.concat(t, sep or " ")
end

function M.addr_text(fc, addr)
    local base = 0
    if fc == 0x01 then base = 00001 end
    if fc == 0x02 then base = 10001 end
    if fc == 0x03 then base = 40001 end
    if fc == 0x04 then base = 30001 end
    if base == 0 then return string.format("0x%04X", addr) end
    return string.format("%d (0x%04X)", base + addr, addr)
end

return M
