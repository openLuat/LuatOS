--[[
@module  prodmeta
@summary 使用 OTP 按 key=value 格式存储产品元数据
@version 1.0
@date    2026.07.16
@tag     LUAT_USE_OTP
@usage
local prodmeta = require("prodmeta")
-- 写入,应该尽量使用短的 key 和 value, 以节省空间
prodmeta.set("PROD", "Air8302")
prodmeta.set("PCB", "V1.2")
-- 读取
log.info("prodmeta", prodmeta.get("PROD"), prodmeta.get("PCB"))
-- 全部读取
local t = prodmeta.get_all()
log.info("prodmeta", json.encode(t))
]]
local prodmeta = {}
local otp = otp
local hmeta = hmeta

-- 平台相关默认配置
local cfg = {
    zone = 1,
    max_len = 256,
    append_only = true
}

local function detect_platform()
    if not hmeta then return nil end
    local chip = (hmeta.chip and hmeta.chip()) or ""
    chip = tostring(chip):upper()

    -- 移芯 EC618 / EC7xx 系列：OTP 支持整 zone 擦除，可重写
    if chip:find("EC618") or chip:find("EC7") or chip:find("EC716") then
        return "ec"
    end

    -- Beken BK7258 / BK7236：OTP2 USERDATA1/2 可用，zone 0 被 hmeta/muid 占用
    if chip:find("BK7258") or chip:find("BK7236") then
        return "bk"
    end

    -- 国芯 CCM4211 / Air1601 / Air1602：用户 OTP 共 144 B，zone 参数被忽略
    if chip:find("CCM4211") then
        return "ccm"
    end

    return nil
end

local platform = detect_platform()

if platform == "ec" then
    cfg.zone = 1
    cfg.max_len = 256
    cfg.append_only = false
elseif platform == "bk" then
    cfg.zone = 1
    cfg.max_len = 256
    cfg.append_only = true
elseif platform == "ccm" then
    cfg.zone = 1
    cfg.max_len = 144
    cfg.append_only = true
end

-- 去除尾部 0x00 / 0xFF
local function trim_tail(s)
    if not s or #s == 0 then return "" end
    local last = #s
    while last > 0 do
        local b = s:byte(last)
        if b == 0x00 or b == 0xFF then
            last = last - 1
        else
            break
        end
    end
    return s:sub(1, last)
end

-- 解析 key=value,key2=value2，后面的同名 key 覆盖前面的
local function parse(s)
    local t = {}
    if not s or #s == 0 then return t end
    for part in s:gmatch("([^,]+)") do
        local k, v = part:match("^([^=]+)=(.*)$")
        if k and v then
            t[k] = v
        end
    end
    return t
end

-- 序列化 table 为 key=value,key2=value2
local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        k = tostring(k):gsub("[,=]", "")
        v = tostring(v):gsub("[,=]", "")
        if #k > 0 then
            table.insert(parts, k .. "=" .. v)
        end
    end
    return table.concat(parts, ",")
end

-- 按 4 字节对齐填充，C 层 otp.write 要求长度为 4 的倍数
local function pad4(s, max)
    local len = #s
    if len > max then return nil end
    local pad = 4 - (len % 4)
    if pad == 4 then pad = 0 end
    if len + pad > max then return nil end
    return s .. string.rep("\xFF", pad)
end

local function read_raw()
    if not otp then return nil, "otp module not found" end
    local data = otp.read(cfg.zone, 0, cfg.max_len)
    if not data then return nil, "otp read failed" end
    return trim_tail(data)
end

local function write_raw(s)
    if not otp then return false, "otp module not found" end
    local padded = pad4(s, cfg.max_len)
    if not padded then return false, "data too long" end
    return otp.write(cfg.zone, padded, 0)
end

--[[
设置一个 key-value。
移芯平台会重写整个 zone；非移芯平台在尾部追加，重复 key 以最后一次解析为准。
@api prodmeta.set(key, value)
@string key
@string value
@return bool 成功返回 true, 失败返回 false, reason
]]
function prodmeta.set(key, value)
    key = tostring(key or "")
    value = tostring(value or "")
    if #key == 0 then return false, "key empty" end

    local data = read_raw() or ""
    local t = parse(data)

    -- 与最新值一致，无需重复写入
    if t[key] == value then return true end

    if cfg.append_only then
        local append = key .. "=" .. value
        local sep = (#data > 0) and "," or ""
        local new_data = data .. sep .. append
        if #new_data > cfg.max_len then
            return false, "otp full"
        end
        return write_raw(new_data)
    else
        t[key] = value
        local new_data = serialize(t)
        if #new_data > cfg.max_len then
            return false, "data too long"
        end
        otp.erase(cfg.zone)
        return write_raw(new_data)
    end
end

--[[
获取指定 key 的值
@api prodmeta.get(key)
@string key
@return string 值，不存在返回 nil
]]
function prodmeta.get(key)
    local t = prodmeta.get_all()
    return t[key]
end

--[[
获取所有 key-value
@api prodmeta.get_all()
@return table
]]
function prodmeta.get_all()
    local data = read_raw() or ""
    return parse(data)
end

--[[
清空所有数据（仅移芯平台有效）
@api prodmeta.clear()
@return bool 成功返回 true, 失败返回 false, reason
]]
function prodmeta.clear()
    if cfg.append_only then
        return false, "append-only platform"
    end
    if not otp then return false, "otp module not found" end
    return otp.erase(cfg.zone)
end

--[[
获取当前平台配置
@api prodmeta.info()
@return table {platform, zone, max_len, append_only}
]]
function prodmeta.info()
    return {
        platform = platform or "unknown",
        zone = cfg.zone,
        max_len = cfg.max_len,
        append_only = cfg.append_only
    }
end

--[[
获取库文件版本信息
@return string 版本号
@usage
prodmeta.version()
]]
function prodmeta.version()
    return "2026071601"
end

log.debug("prodmeta", "version -> " .. prodmeta.version() .. ", platform -> " .. (platform or "unknown"))

return prodmeta
