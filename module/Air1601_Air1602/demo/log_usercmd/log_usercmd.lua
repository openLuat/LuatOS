--[[
日志口用户指令协议 v2 设备端协议栈
配合 PROTOCOL.md 与 host/luat_usercmd.py 使用

职责: 帧解析(magic/version/seq)、控制类去重回应、分发到脚本注册的处理函数。
协议栈本身不实现任何业务逻辑, 业务(如文件操作)由 reg_op / fs() 注册, 权限完全由脚本控制。

处理函数约定: fn(body) -> errno, resp_body, resp_flags(可选)
  body       请求体(不含7字节固定头)
  errno      0=成功, 非0=错误(库自动置 flags.ERR)
  resp_body  回应体
  resp_flags 可选, 附加 flags(如 LSDIR 翻页的 MORE 位)
]]

local uc = {}

local MAGIC = "\xC5\x5C"
local VERSION = 0x01
-- 单帧数据区上限, 必须与固件 am_log.c 的 rx 缓冲配套:
-- rx_cache1[512] -> payload<=486,  应用头12B(7固定+fd1+offset4) -> 数据区474
local MAX_CHUNK = 474

-- 子指令号 -> 处理函数名
local SUB_NAMES = {
    [1] = "open",
    [2] = "close",
    [3] = "write",
    [4] = "read",
    [5] = "lsdir",
    [6] = "mkdir",
    [7] = "rmdir",
    [8] = "remove",
    [9] = "stat",
    [10] = "exists",
}

-- 错误码, 与 PROTOCOL.md §2 一致
uc.E_OK      = 0
uc.E_NOENT   = 1
uc.E_DENIED  = 2
uc.E_IO      = 3
uc.E_BADREQ  = 4
uc.E_BADFD   = 5
uc.E_TOOLONG = 6
uc.E_BUSY    = 7

uc.VERSION = VERSION
uc.MAX_CHUNK = MAX_CHUNK

local ops = {}

-- 控制类去重缓存: (seq, 完整回应帧), 解决"执行成功但回应丢失, host 重发"导致的重复执行
local last_ctrl_seq = nil
local last_ctrl_resp = nil

local function pack_hdr(subcmd, flags, seq)
    return MAGIC .. string.char(VERSION, subcmd, flags) .. string.pack("<I2", seq)
end

--- 注册业务处理函数
-- @string name 操作名: open/close/write/read/lsdir/mkdir/rmdir/remove/stat/exists
-- @function fn 处理函数, 签名 fn(body) -> errno, resp_body, resp_flags(可选)
function uc.reg_op(name, fn)
    ops[name] = fn
end

local function dispatch(seq, subcmd, flags, body)
    if subcmd == 0 then
        -- HELLO: 清去重缓存 + 分片大小协商
        if #body < 6 then return end
        local nonce, propose = string.unpack("<I4I2", body)
        last_ctrl_seq = nil
        last_ctrl_resp = nil
        local chunk = propose
        if chunk > MAX_CHUNK then chunk = MAX_CHUNK end
        log.usercmd_write(pack_hdr(0, 0, seq) .. string.pack("<I4I2", nonce, chunk) .. string.char(VERSION))
        return
    end
    local is_data = (subcmd == 3) or (subcmd == 4)
    if not is_data and last_ctrl_seq == seq and last_ctrl_resp then
        log.usercmd_write(last_ctrl_resp)
        return
    end
    local name = SUB_NAMES[subcmd]
    local fn = name and ops[name]
    local errno, resp_body, resp_flags = uc.E_DENIED, "", 0
    if fn then
        local ok, e, b, fl = pcall(fn, body)
        if ok then
            errno = e or uc.E_IO
            resp_body = b or ""
            resp_flags = fl or 0
        else
            errno = uc.E_IO
            resp_body = ""
        end
    end
    if errno ~= 0 then
        resp_flags = resp_flags | 0x01
        -- 错误回应 body 首字节必须为 errno(协议§1), 由协议栈统一封装
        resp_body = string.char(errno & 0xFF) .. resp_body
    end
    local resp = pack_hdr(subcmd, resp_flags, seq) .. resp_body
    log.usercmd_write(resp)
    if not is_data then
        last_ctrl_seq = seq
        last_ctrl_resp = resp
    end
end

--- 启动协议栈(注册 log.set_usercmd_cb)
function uc.start()
    log.set_usercmd_cb(function(cmd, data)
        -- cmd 为 A5 帧 address 字段(v2 恒为0, 不使用); data 为 payload
        if #data < 7 then return end
        if data:sub(1, 2) ~= MAGIC then return end
        if data:byte(3) ~= VERSION then return end
        local subcmd = data:byte(4)
        local flags = data:byte(5)
        local seq = string.unpack("<I2", data, 6)
        dispatch(seq, subcmd, flags, data:sub(8))
    end)
end

local function check_path(path)
    if #path == 0 or #path > 127 then
        return false
    end
    if path:find("%z") then
        return false
    end
    return true
end

--- 一键安装标准文件系统操作集(io/os 实现)
-- 设备端可同时打开最多 4 个文件句柄
function uc.fs()
    local fds = {}
    local MAXFD = 4

    local function alloc_fd(f)
        for i = 1, MAXFD do
            if not fds[i] then
                fds[i] = f
                return i
            end
        end
        return nil
    end

    uc.reg_op("open", function(body)
        local mode = string.byte(body, 1)
        local path = body:sub(2)
        if not check_path(path) then
            return uc.E_TOOLONG, ""
        end
        local mode_s = ({[0] = "rb", [1] = "w+b", [2] = "a+b", [3] = "r+b"})[mode]
        if not mode_s then
            return uc.E_BADREQ, ""
        end
        local f = io.open(path, mode_s)
        if not f then
            return uc.E_NOENT, ""
        end
        local fd = alloc_fd(f)
        if not fd then
            f:close()
            return uc.E_BUSY, ""
        end
        return uc.E_OK, string.char(fd)
    end)

    uc.reg_op("close", function(body)
        local fd = string.byte(body, 1)
        local f = fds[fd]
        if not f then
            return uc.E_BADFD, string.pack("<I4", 0)
        end
        fds[fd] = nil
        local size = f:seek("end") or 0
        local ok = pcall(function() f:close() end)
        if not ok then
            return uc.E_IO, string.pack("<I4", 0)
        end
        return uc.E_OK, string.pack("<I4", size)
    end)

    uc.reg_op("write", function(body)
        local fd = string.byte(body, 1)
        local offset = string.unpack("<I4", body, 2)
        local f = fds[fd]
        if not f then
            return uc.E_BADFD, string.char(fd) .. string.pack("<I4", offset)
        end
        local data = body:sub(6) -- fd(1)+offset(4) 之后, 数据从第6字节开始
        f:seek("set", offset)
        local w = f:write(data)
        if not w then
            return uc.E_IO, string.char(fd) .. string.pack("<I4", offset)
        end
        return uc.E_OK, string.char(fd) .. string.pack("<I4", offset)
    end)

    uc.reg_op("read", function(body)
        local fd = string.byte(body, 1)
        local offset, len = string.unpack("<I4I2", body, 2)
        local f = fds[fd]
        if not f then
            return uc.E_BADFD, ""
        end
        f:seek("set", offset)
        local data = f:read(len) or ""
        return uc.E_OK, string.char(fd) .. string.pack("<I4I2", offset, #data) .. data
    end)

    uc.reg_op("lsdir", function(body)
        local plen = string.byte(body, 1)
        if #body < 1 + plen + 6 then
            return uc.E_BADREQ, string.pack("<I4I2", 0, 0)
        end
        local path = body:sub(2, 1 + plen)
        local offset, count = string.unpack("<I4I2", body, 2 + plen)
        if not check_path(path) then
            return uc.E_TOOLONG, string.pack("<I4I2", 0, 0)
        end
        if count > 100 then count = 100 end -- io.lsdir 单次上限
        local ok, list = io.lsdir(path, count, offset)
        if not ok or type(list) ~= "table" then
            return uc.E_NOENT, string.pack("<I4I2", 0, 0)
        end
        local parts, total, n = {}, 0, 0
        for _, e in ipairs(list) do
            local name = e.name or ""
            local eb = string.char(e.type or 0) .. string.pack("<I4", e.size or 0) .. string.char(#name) .. name
            if total + #eb > 470 then break end -- 上行单帧预算, 与 host 侧 read_chunk 无关
            parts[#parts + 1] = eb
            total = total + #eb
            n = n + 1
        end
        local more = 0
        if n == count and n > 0 then more = 0x02 end -- flags.MORE: 满页说明可能还有, host 继续翻
        local remaining = more == 0x02 and count or 0
        return uc.E_OK, string.pack("<I4I2", remaining, total) .. table.concat(parts), more
    end)

    uc.reg_op("mkdir", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        if io.mkdir(body) then
            return uc.E_OK, ""
        end
        return uc.E_IO, ""
    end)

    uc.reg_op("rmdir", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        if io.rmdir(body) then
            return uc.E_OK, ""
        end
        return uc.E_IO, ""
    end)

    uc.reg_op("remove", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        if os.remove(body) then
            return uc.E_OK, ""
        end
        return uc.E_NOENT, ""
    end)

    uc.reg_op("stat", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        if io.exists(body) then
            return uc.E_OK, string.char(0) .. string.pack("<I4", io.fileSize(body) or 0)
        end
        if io.dexist(body) then
            return uc.E_OK, string.char(1) .. string.pack("<I4", 0)
        end
        return uc.E_NOENT, ""
    end)

    uc.reg_op("exists", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        local ex = io.exists(body) or io.dexist(body)
        return uc.E_OK, string.char(ex and 1 or 0)
    end)
end

return uc
