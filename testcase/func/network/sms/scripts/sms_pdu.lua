--[[
sms_pdu.lua —— 仅供测试使用: 构造 7bit/8bit/UCS2 的 SMS-DELIVER PDU 十六进制串

约定与实网抓包一致(已用 test_long_7bit_sms_reassembly 的 part1 校验):
  长短信的 UDH 按字节对齐存放, UDH 之后的填充位是 SM 首字节的最低位,
  即 luat_sms_pdu_message_unpack 里 payload_pos = udhl + 1 / fill_bits 的算法。
]]

local M = {}

-- SCTS: 年月日时分秒, 每个字段按 (十位<<4)|个位 存放
local SCTS = "\x62\x10\x70\x21\x43\x65\x78"

-- 默认发送方号码(半字节交换)
local DEFAULT_OA_DIGITS = "1234567890"

-- GSM7 基本字符: 可打印 ASCII 中除 '@'(septet 0x00) 外与 septet 同码
-- '[' ']' '\' '^' 属于扩展表, 本模块不支持, 遇到直接报错
local function septet_of(ch)
    if ch == "@" then
        return 0x00
    end
    local c = string.byte(ch)
    if c >= 0x20 and c <= 0x3F then
        return c
    end
    if c >= 0x41 and c <= 0x5A then
        return c
    end
    if c >= 0x61 and c <= 0x7A then
        return c
    end
    error(string.format("sms_pdu: 不支持的字符 %q", ch))
end

local function to_septets(str)
    local out = {}
    for i = 1, #str do
        out[i] = septet_of(string.sub(str, i, i))
    end
    return out
end

-- 7bit 压缩: septet 逐个按 7 比特拼进字节流, 首个 septet 从 bit_offset 开始
local function pack7bit(septets, bit_offset)
    bit_offset = bit_offset or 0
    local total_bits = bit_offset + #septets * 7
    local bytes = {}
    for i = 1, math.max((total_bits + 7) // 8, 1) do
        bytes[i] = 0
    end
    for i = 1, #septets do
        local bit_pos = bit_offset + (i - 1) * 7
        local byte_idx = bit_pos // 8 + 1
        local bit_idx = bit_pos % 8
        bytes[byte_idx] = (bytes[byte_idx] + (septets[i] << bit_idx)) % 256
        if bit_idx + 7 > 8 then
            bytes[byte_idx + 1] = (bytes[byte_idx + 1] + (septets[i] >> (8 - bit_idx))) % 256
        end
    end
    return string.char(unpack(bytes, 1, #bytes))
end

-- 半字节交换地址编码, 奇数位数字补 0x0F
local function pack_semi_octets(digits)
    local bytes = {}
    for i = 1, #digits, 2 do
        local lo = tonumber(string.sub(digits, i, i))
        local hi = tonumber(string.sub(digits, i + 1, i + 1)) or 0x0F
        bytes[#bytes + 1] = (hi << 4) | lo
    end
    return string.char(unpack(bytes, 1, #bytes))
end

local function to_hex(str)
    return (str:gsub(".", function(c)
        return string.format("%02X", string.byte(c))
    end))
end

-- 公共头部: SCA(0 字节) + FO + OA + PID + DCS + SCTS
local function deliver_header(fo, oa, dcs)
    return "\x00" .. string.char(fo) .. oa .. "\x00" .. string.char(dcs) .. SCTS
end

-- 数值地址 OA 字段
local function numeric_oa(digits)
    return string.char(#digits, 0x91) .. pack_semi_octets(digits)
end

--- 7bit 字母地址(alphanumeric, OA type 0xD5)的单条短信
-- ADL = 字符数, 地址值按 7bit 压缩占 ceil(ADL*7/8) 字节(3GPP TS 23.040 9.2.2.21)
function M.buildAlphaDeliver(sender, text, digits)
    local addr = pack7bit(to_septets(sender), 0)
    local oa = string.char(#sender, 0xD5) .. addr
    local body = pack7bit(to_septets(text), 0)
    local pdu = deliver_header(0x04, oa, 0x00)
        .. string.char(#text)            -- TP-UDL (septet 数)
        .. body
    return to_hex(pdu)
end

--- 7bit 长短信的单个分片
-- udh16 = true 用 16bit 参考号(UDHL=6), 否则 8bit(UDHL=5)
function M.buildSegment7bit(text, ref, total, seq, udh16)
    assert(text and #text > 0)
    local utl = udh16 and 7 or 6            -- UDH 字节数(含 UDHL 本身)
    local rem = (utl * 8) % 7
    local fill = (rem ~= 0) and (7 - rem) or 0
    local udh_septets = (utl * 8 + fill) // 7
    local body = pack7bit(to_septets(text), fill)
    local udh
    if udh16 then
        udh = string.char(0x06, 0x08, 0x04, (ref >> 8) & 0xFF, ref & 0xFF, total, seq)
    else
        udh = string.char(0x05, 0x00, 0x03, ref & 0xFF, total, seq)
    end
    local pdu = deliver_header(0x44, numeric_oa(DEFAULT_OA_DIGITS), 0x00)
        .. string.char(#text + udh_septets) -- TP-UDL = UDH septets + SM septets
        .. udh .. body
    return to_hex(pdu)
end

--- 数值地址的普通 7bit 短信(无 UDH), 用于基线对照
function M.buildShort7bit(text, digits)
    local pdu = deliver_header(0x04, numeric_oa(digits or DEFAULT_OA_DIGITS), 0x00)
        .. string.char(#text)
        .. pack7bit(to_septets(text), 0)
    return to_hex(pdu)
end

--- UCS2 单条短信(无 UDH): text 为 UTF-8, UD 按大端存放 UCS2 码点
function M.buildShortUcs2(text, digits)
    local body = {}
    local i = 1
    while i <= #text do
        local b = string.byte(text, i)
        local cp
        if b < 0x80 then
            cp = b
            i = i + 1
        elseif b < 0xE0 then
            cp = ((b & 0x1F) << 6) + (string.byte(text, i + 1) & 0x3F)
            i = i + 2
        elseif b < 0xF0 then
            cp = ((b & 0x0F) << 12) + ((string.byte(text, i + 1) & 0x3F) << 6)
                + (string.byte(text, i + 2) & 0x3F)
            i = i + 3
        else
            error("sms_pdu: UCS2 构造不支持 4 字节 UTF-8 序列")
        end
        body[#body + 1] = string.char((cp >> 8) & 0xFF, cp & 0xFF)
    end
    body = table.concat(body)
    local pdu = deliver_header(0x04, numeric_oa(digits or DEFAULT_OA_DIGITS), 0x08)
        .. string.char(#body) .. body
    return to_hex(pdu)
end

--- 畸形 PDU: 声明的 TP-UDL 小于 UDH 实际占用
-- dcs = 0x04 (8bit) 或 0x08 (UCS2); udl 通常填 2
function M.buildMalformedUdl(dcs, udl)
    local pdu = deliver_header(0x44, numeric_oa(DEFAULT_OA_DIGITS), dcs)
        .. string.char(udl or 2)
        .. string.char(0x05, 0x00, 0x03, 0x01, 0x02, 0x01)  -- UDHL=5 的拼接 UDH, 占 6 字节
        .. "\x00\x41"
    return to_hex(pdu)
end

M.pack7bit = pack7bit
M.to_septets = to_septets
M.to_hex = to_hex
M.SCTS = SCTS

return M