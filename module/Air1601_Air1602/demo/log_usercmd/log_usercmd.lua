--[[
日志口用户指令协议 v2 设备端协议栈
配合 PROTOCOL.md 与 host/luat_usercmd.py 使用

职责: 帧解析(version/seq)、控制类去重回应、AUTH 挑战应答鉴权、分发到脚本注册的处理函数。
协议栈本身不实现任何业务逻辑, 业务(如文件操作)由 reg_op / fs() 注册, 权限完全由脚本控制。

处理函数约定: fn(body) -> errno, resp_body, resp_flags(可选)
  body       请求体(不含5字节固定头)
  errno      0=成功, 非0=错误(库自动置 flags.ERR)
  resp_body  回应体
  resp_flags 可选, 附加 flags(如 LSDIR 翻页的 MORE 位)
]]

local uc = {}

local VERSION = 0x01
-- 单帧数据区上限, 必须与固件 am_log.c 的 rx 缓冲配套:
-- rx_cache1[512] -> payload<=486,  应用头10B(5固定+fd1+offset4) -> 数据区476
local MAX_CHUNK = 476

-- 子指令号 -> 处理函数名 (0=HELLO 与 11=AUTH 为协议栈内建, 不在此表)
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
    [12] = "lsmount",
    [13] = "fsstat",
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
uc.E_NOSYS   = 8

uc.VERSION = VERSION
uc.MAX_CHUNK = MAX_CHUNK

local ops = {}

-- 鉴权状态(HMAC 挑战应答, 见 PROTOCOL.md §5.5): nil=未配置(不启用)
local auth_token = nil
local authed = false
local last_nonce = nil

--- 配置鉴权 token(可选), 开启后未鉴权连接仅允许 HELLO/AUTH
-- 须在 uc.start() 之前调用; token 8..64 字节, 生产建议 >=16 字节随机串
-- @string|nil token 传 nil/false 关闭鉴权
function uc.set_auth(token)
    if token == nil or token == false then
        auth_token = nil
        return uc
    end
    if type(token) ~= "string" or #token < 8 or #token > 64 then
        error("uc.set_auth: token must be a string of 8..64 bytes")
    end
    if crypto == nil or crypto.hmac_sha256 == nil then
        error("uc.set_auth: crypto.hmac_sha256 unavailable on this firmware")
    end
    auth_token = token
    return uc
end

-- 控制类去重缓存: (seq, 完整回应帧), 解决"执行成功但回应丢失, host 重发"导致的重复执行
local last_ctrl_seq = nil
local last_ctrl_resp = nil

local function pack_hdr(subcmd, flags, seq)
    return string.char(VERSION, subcmd, flags) .. string.pack("<I2", seq)
end

--- 注册业务处理函数
-- @string name 操作名: open/close/write/read/lsdir/mkdir/rmdir/remove/stat/exists/lsmount/fsstat
-- @function fn 处理函数, 签名 fn(body) -> errno, resp_body, resp_flags(可选)
function uc.reg_op(name, fn)
    ops[name] = fn
end

local function dispatch(seq, subcmd, flags, body)
    if subcmd == 0 then
        -- HELLO: 清去重缓存 + 分片大小协商 + 记录鉴权挑战(nonce)
        if #body < 6 then return end
        local nonce, propose = string.unpack("<I4I2", body)
        last_ctrl_seq = nil
        last_ctrl_resp = nil
        last_nonce = nonce
        authed = false
        local chunk = propose
        if chunk > MAX_CHUNK then chunk = MAX_CHUNK end
        local caps = 0
        if auth_token then caps = 1 end
        log.usercmd_write(pack_hdr(0, 0, seq) .. string.pack("<I4I2", nonce, chunk) .. string.char(VERSION) .. string.pack("<I2", caps))
        return
    end
    local is_data = (subcmd == 3) or (subcmd == 4)
    if not is_data and last_ctrl_seq == seq and last_ctrl_resp then
        log.usercmd_write(last_ctrl_resp)
        return
    end
    local errno, resp_body, resp_flags
    if auth_token and not authed and subcmd ~= 11 then
        -- 鉴权门控: 未鉴权仅允许 HELLO/AUTH(含数据类), 不执行业务
        errno, resp_body, resp_flags = uc.E_DENIED, "", 0
    elseif subcmd == 11 then
        -- AUTH: HMAC 挑战应答, 协议栈内建(不经 reg_op), 见 PROTOCOL.md §5.5
        resp_flags = 0
        if not auth_token then
            errno, resp_body = uc.E_OK, string.char(0) -- 未配置 token, 无需鉴权
        elseif not last_nonce then
            errno, resp_body = uc.E_BADREQ, ""         -- 未先 HELLO, 无可用挑战
        else
            local maclen = string.byte(body, 1) or 0
            local mac = body:sub(2, 1 + maclen)
            local expect = crypto.hmac_sha256(string.pack("<I4", last_nonce), auth_token)
            -- 大小写不敏感: 不同移植的 hex 大小写不一(host 用 python 小写 hexdigest)
            if maclen == 64 and mac:lower() == expect:lower() then
                authed = true
                errno, resp_body = uc.E_OK, string.char(1)
            else
                errno, resp_body = uc.E_DENIED, ""
            end
        end
    else
        local name = SUB_NAMES[subcmd]
        local fn = name and ops[name]
        errno, resp_body, resp_flags = uc.E_NOSYS, "", 0
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
-- @return true=已接管; false=固件没开 LUAT_USE_LOG_USER_CMD, 功能不可用(脚本可继续跑, 只是收不到指令)
function uc.start()
    if type(log.set_usercmd_cb) ~= "function" then
        log.warn("usercmd", "固件未开启 LUAT_USE_LOG_USER_CMD, 日志口用户指令不可用")
        return false
    end
    log.set_usercmd_cb(function(cmd, data)
        -- cmd 为 A5 帧 address 字段(恒为0, 不使用); data 为 payload(无 MAGIC)
        if #data < 5 then return end
        if data:byte(1) ~= VERSION then return end
        local subcmd = data:byte(2)
        local flags = data:byte(3)
        local seq = string.unpack("<I2", data, 4)
        dispatch(seq, subcmd, flags, data:sub(6))
    end)
    return true
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

    -- 顺序写 FS(ramfs) 不支持写入未分配区域: offset>size 时 seek 被忽略、数据落到 EOF.
    -- 这里先补零补到 offset 再写, 使重传/乱序到达的写保持幂等; PAD_LIMIT 防止异常空洞耗尽内存
    local PAD_LIMIT = 64 * 1024
    local ZEROS = string.rep("\0", 256)

    uc.reg_op("write", function(body)
        if #body < 5 then
            return uc.E_BADREQ, ""
        end
        local fd = string.byte(body, 1)
        local offset = string.unpack("<I4", body, 2)
        local ack = string.char(fd) .. string.pack("<I4", offset)
        local f = fds[fd]
        if not f then
            return uc.E_BADFD, ack
        end
        local data = body:sub(6) -- fd(1)+offset(4) 之后, 数据从第6字节开始
        local size = f:seek("end")
        if not size then
            return uc.E_IO, ack
        end
        if offset > size then
            if offset - size > PAD_LIMIT then
                return uc.E_BADREQ, ack
            end
            f:seek("set", size)
            local pad = offset - size
            while pad > 0 do
                local n = pad < 256 and pad or 256
                if not f:write(ZEROS:sub(1, n)) then
                    return uc.E_IO, ack
                end
                pad = pad - n
            end
        end
        if not f:seek("set", offset) or not f:write(data) then
            return uc.E_IO, ack
        end
        -- 落盘校验: 部分 FS 对越界写会静默丢弃(seek 不生效), 必须回读大小确认
        local after = f:seek("end")
        if not after or after < offset + #data then
            return uc.E_IO, ack
        end
        return uc.E_OK, ack
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
        local cut = false
        for _, e in ipairs(list) do
            local name = e.name or ""
            local eb = string.char(e.type or 0) .. string.pack("<I4", e.size or 0) .. string.char(#name) .. name
            if total + #eb > 470 then
                cut = true -- 预算截断: 本条及之后必须靠 host 翻页取回(否则静默丢条目)
                break
            end
            parts[#parts + 1] = eb
            total = total + #eb
            n = n + 1
        end
        -- flags.MORE: 预算截断或满页都说明可能还有, host 以 offset+n 继续翻页
        local more = 0
        if n > 0 and (cut or n == count) then more = 0x02 end
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

    uc.reg_op("lsmount", function(_body)
        if io.lsmount == nil then
            return uc.E_NOSYS, ""
        end
        local list = io.lsmount()
        if type(list) ~= "table" then
            return uc.E_IO, ""
        end
        local parts, total = {}, 0
        for _, e in ipairs(list) do
            local path = e.path or ""
            local fst = e.fs or ""
            local eb = string.char(#path) .. path .. string.char(#fst) .. fst
            if total + #eb > 470 then break end -- 上行单帧预算, 与 LSDIR 一致
            parts[#parts + 1] = eb
            total = total + #eb
        end
        return uc.E_OK, string.pack("<I2", total) .. table.concat(parts)
    end)

    uc.reg_op("fsstat", function(body)
        if not check_path(body) then
            return uc.E_TOOLONG, ""
        end
        if io.fsstat == nil then
            return uc.E_NOSYS, ""
        end
        local ok, tb, ub, bs, fst = io.fsstat(body)
        if not ok then
            return uc.E_NOENT, ""
        end
        tb, ub, bs, fst = tb or 0, ub or 0, bs or 0, fst or ""
        -- total/used 折算为字节, 便于 host 直接使用
        return uc.E_OK, string.pack("<III", tb * bs, ub * bs, bs) .. string.char(#fst) .. fst
    end)
end

return uc
