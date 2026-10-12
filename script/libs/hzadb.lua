--[[
合宙adb (hzadb) - 日志口用户指令协议 v2 设备端协议栈(通用库版)
由 olddemo/demo/hzadb/log_usercmd.lua 迁移而来, 协议见 olddemo/demo/hzadb/PROTOCOL.md

通过日志口扩展用户指令, 无需额外 UART 即可收发文件、查询设备状态。
协议具备: 版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商、
open/read/write/close 文件模型、可选 HMAC 挑战应答鉴权、挂载点枚举(LSMOUNT)、
文件系统空间查询(FSSTAT)、文件指纹(FILE_SHA1)、内存状态(MEMINFO)、网络状态(NETSTAT)。

依赖:
- log.usercmd_write / log.set_usercmd_cb (固件需打开 LUAT_USE_LOG_USER_CMD)
- crypto.md_file (file_sha1 指令, fs() 安装时按需检测)
- rtos.meminfo (meminfo 指令)
- netdrv / socket (netstat 指令, 按适配器探测)

职责: 帧解析(version/seq)、控制类去重回应、AUTH 挑战应答鉴权、分发到脚本注册的处理函数。
协议栈本身不实现任何业务逻辑, 业务由 reg_op / fs() / mem() / netdrv() 按需安装, 权限完全由脚本控制。

最小使用示例:
    local hzadb = require "hzadb"
    hzadb.fs()          -- 文件系统指令 + file_sha1(默认拦截 /luadb 的读文件请求)
    hzadb.mem()         -- 内存状态指令(rtos.meminfo)
    hzadb.netdrv()      -- 网络状态指令(netdrv 适配器状态)
    hzadb.set_auth("0123456789abcdef") -- 可选: 开启 HMAC 挑战应答鉴权
    hzadb.start()       -- 接管日志口, 返回 false 表示固件未开启 LUAT_USE_LOG_USER_CMD
    hzadb.version()     -- 库版本号, 年月日时分, 例如 "202609221555"

处理函数约定: fn(body) -> errno, resp_body, resp_flags(可选)
  body       请求体(不含5字节固定头)
  errno      0=成功, 非0=错误(库自动置 flags.ERR)
  resp_body  回应体
  resp_flags 可选, 附加 flags(如 LSDIR 翻页的 MORE 位)
]]

local hzadb = {}

--- 库版本号, 年月日时分, 与协议版本(PROTO_VERSION)无关
hzadb.VERSION = "202609221555"

local PROTO_VERSION = 0x01
-- 单帧数据区上限, 必须与固件 am_log.c 的 rx 缓冲配套:
-- 厂商新固件 rx_cache1[1064] -> 反转义后 24B帧头+payload, 应用头10B(5固定+fd1+offset4),
-- 数据区 chunk=1024 时 24+10+1024=1058<=1064 (转义流缓冲 2128B 装得下最坏 2122B)
local MAX_CHUNK = 1024

-- 协议版本号, 见 PROTOCOL.md §1, 当前 0x01
hzadb.PROTO_VERSION = PROTO_VERSION
hzadb.MAX_CHUNK = MAX_CHUNK

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
    [14] = "file_sha1", -- 文件指纹, 由 fs() 安装
    [15] = "meminfo",   -- 内存状态, 由 mem() 安装
    [16] = "netstat",   -- 网络状态, 由 netdrv() 安装
}

-- 错误码, 与 PROTOCOL.md §2 一致
hzadb.E_OK      = 0 -- 成功
hzadb.E_NOENT   = 1 -- not found
hzadb.E_DENIED  = 2 -- denied(脚本拒绝执行该操作)
hzadb.E_IO      = 3 -- io error
hzadb.E_BADREQ  = 4 -- bad request(格式/参数非法)
hzadb.E_BADFD   = 5 -- bad fd
hzadb.E_TOOLONG = 6 -- path too long
hzadb.E_BUSY    = 7 -- busy
hzadb.E_NOSYS   = 8 -- nosys(子指令不存在: 旧固件或未安装)

local ops = {}

-- 鉴权状态(HMAC 挑战应答, 见 PROTOCOL.md §5.5): nil=未配置(不启用)
local auth_token = nil
local authed = false
local last_nonce = nil

--- 配置鉴权 token(可选), 开启后未鉴权连接仅允许 HELLO/AUTH
-- 须在 hzadb.start() 之前调用; token 8..64 字节, 生产建议 >=16 字节随机串
-- @string|nil token 传 nil/false 关闭鉴权
-- @return table 返回 hzadb 自身, 便于链式调用
-- @usage
-- hzadb.set_auth("0123456789abcdef")
function hzadb.set_auth(token)
    if token == nil or token == false then
        auth_token = nil
        return hzadb
    end
    if type(token) ~= "string" or #token < 8 or #token > 64 then
        error("hzadb.set_auth: token must be a string of 8..64 bytes")
    end
    if crypto == nil or crypto.hmac_sha256 == nil then
        error("hzadb.set_auth: crypto.hmac_sha256 unavailable on this firmware")
    end
    auth_token = token
    return hzadb
end

-- 控制类去重缓存: (seq, 完整回应帧), 解决"执行成功但回应丢失, host 重发"导致的重复执行
local last_ctrl_seq = nil
local last_ctrl_resp = nil

local function pack_hdr(subcmd, flags, seq)
    return string.char(PROTO_VERSION, subcmd, flags) .. string.pack("<I2", seq)
end

--- 注册业务处理函数
-- @string name 操作名: open/close/write/read/lsdir/mkdir/rmdir/remove/stat/exists/lsmount/fsstat/file_sha1/meminfo/netstat
-- @function fn 处理函数, 签名 fn(body) -> errno, resp_body, resp_flags(可选)
-- @return table 返回 hzadb 自身, 便于链式调用
-- @usage
-- hzadb.reg_op("custom", function(body)
--     return hzadb.E_OK, "hello"
-- end)
function hzadb.reg_op(name, fn)
    ops[name] = fn
    return hzadb
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
        log.usercmd_write(pack_hdr(0, 0, seq) .. string.pack("<I4I2", nonce, chunk) .. string.char(PROTO_VERSION) .. string.pack("<I2", caps))
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
        errno, resp_body, resp_flags = hzadb.E_DENIED, "", 0
    elseif subcmd == 11 then
        -- AUTH: HMAC 挑战应答, 协议栈内建(不经 reg_op), 见 PROTOCOL.md §5.5
        resp_flags = 0
        if not auth_token then
            errno, resp_body = hzadb.E_OK, string.char(0) -- 未配置 token, 无需鉴权
        elseif not last_nonce then
            errno, resp_body = hzadb.E_BADREQ, ""         -- 未先 HELLO, 无可用挑战
        else
            local maclen = string.byte(body, 1) or 0
            local mac = body:sub(2, 1 + maclen)
            local expect = crypto.hmac_sha256(string.pack("<I4", last_nonce), auth_token)
            -- 大小写不敏感: 不同移植的 hex 大小写不一(host 用 python 小写 hexdigest)
            if maclen == 64 and mac:lower() == expect:lower() then
                authed = true
                errno, resp_body = hzadb.E_OK, string.char(1)
            else
                errno, resp_body = hzadb.E_DENIED, ""
            end
        end
    else
        local name = SUB_NAMES[subcmd]
        local fn = name and ops[name]
        errno, resp_body, resp_flags = hzadb.E_NOSYS, "", 0
        if fn then
            local ok, e, b, fl = pcall(fn, body)
            if ok then
                errno = e or hzadb.E_IO
                resp_body = b or ""
                resp_flags = fl or 0
            else
                errno = hzadb.E_IO
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
-- @return boolean true=已接管; false=固件没开 LUAT_USE_LOG_USER_CMD, 功能不可用(脚本可继续跑, 只是收不到指令)
-- @usage
-- if not hzadb.start() then
--     log.warn("hzadb", "firmware without LUAT_USE_LOG_USER_CMD")
-- end
function hzadb.start()
    if type(log.set_usercmd_cb) ~= "function" then
        log.warn("hzadb", "固件未开启 LUAT_USE_LOG_USER_CMD, 日志口用户指令不可用")
        return false
    end
    log.set_usercmd_cb(function(cmd, data)
        -- cmd 为 A5 帧 address 字段(恒为0, 不使用); data 为 payload(无 MAGIC)
        if #data < 5 then return end
        if data:byte(1) ~= PROTO_VERSION then return end
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

-- 默认读拦截前缀: 对这些路径下的"读文件"请求(open 读模式 / read / file_sha1)回应 E_DENIED
-- lsdir / stat / exists / 写操作不受影响。如需修改, 直接改此表后重新调用 hzadb.fs()
local READ_DENY_PREFIXES = {"/luadb"}

-- 判断路径是否命中读拦截前缀(恰好等于前缀, 或前缀 + "/")
local function is_read_denied(path)
    for _, prefix in ipairs(READ_DENY_PREFIXES) do
        if path == prefix or path:sub(1, #prefix + 1) == prefix .. "/" then
            return true
        end
    end
    return false
end

--- 一键安装标准文件系统操作集(io/os 实现)
-- 含 open/close/write/read/lsdir/mkdir/rmdir/remove/stat/exists/lsmount/fsstat/file_sha1 共 13 个指令
-- 默认拦截对 /luadb 的读文件请求(见 READ_DENY_PREFIXES), lsdir/stat/exists/写操作不拦截
-- 设备端可同时打开最多 4 个文件句柄
-- @return table 返回 hzadb 自身, 便于链式调用
function hzadb.fs()
    local fds = {}
    local MAXFD = 4

    local function alloc_fd(f, path)
        for i = 1, MAXFD do
            if not fds[i] then
                fds[i] = {f = f, path = path}
                return i
            end
        end
        return nil
    end

    hzadb.reg_op("open", function(body)
        local mode = string.byte(body, 1)
        local path = body:sub(2)
        if not check_path(path) then
            return hzadb.E_TOOLONG, ""
        end
        -- 读拦截: 读模式(mode=0)打开被保护路径, 直接拒绝(写模式仍可操作, 便于升级资源)
        if mode == 0 and is_read_denied(path) then
            return hzadb.E_DENIED, ""
        end
        local mode_s = ({[0] = "rb", [1] = "w+b", [2] = "a+b", [3] = "r+b"})[mode]
        if not mode_s then
            return hzadb.E_BADREQ, ""
        end
        local f = io.open(path, mode_s)
        if not f then
            return hzadb.E_NOENT, ""
        end
        local fd = alloc_fd(f, path)
        if not fd then
            f:close()
            return hzadb.E_BUSY, ""
        end
        return hzadb.E_OK, string.char(fd)
    end)

    hzadb.reg_op("close", function(body)
        local fd = string.byte(body, 1)
        local slot = fds[fd]
        if not slot then
            return hzadb.E_BADFD, string.pack("<I4", 0)
        end
        fds[fd] = nil
        local size = slot.f:seek("end") or 0
        local ok = pcall(function() slot.f:close() end)
        if not ok then
            return hzadb.E_IO, string.pack("<I4", 0)
        end
        return hzadb.E_OK, string.pack("<I4", size)
    end)

    -- 顺序写 FS(ramfs) 不支持写入未分配区域: offset>size 时 seek 被忽略、数据落到 EOF.
    -- 这里先补零补到 offset 再写, 使重传/乱序到达的写保持幂等; PAD_LIMIT 防止异常空洞耗尽内存
    local PAD_LIMIT = 64 * 1024
    local ZEROS = string.rep("\0", 256)

    hzadb.reg_op("write", function(body)
        if #body < 5 then
            return hzadb.E_BADREQ, ""
        end
        local fd = string.byte(body, 1)
        local offset = string.unpack("<I4", body, 2)
        local ack = string.char(fd) .. string.pack("<I4", offset)
        local slot = fds[fd]
        if not slot then
            return hzadb.E_BADFD, ack
        end
        local f = slot.f
        local data = body:sub(6) -- fd(1)+offset(4) 之后, 数据从第6字节开始
        local size = f:seek("end")
        if not size then
            return hzadb.E_IO, ack
        end
        if offset > size then
            if offset - size > PAD_LIMIT then
                return hzadb.E_BADREQ, ack
            end
            f:seek("set", size)
            local pad = offset - size
            while pad > 0 do
                local n = pad < 256 and pad or 256
                if not f:write(ZEROS:sub(1, n)) then
                    return hzadb.E_IO, ack
                end
                pad = pad - n
            end
        end
        if not f:seek("set", offset) or not f:write(data) then
            return hzadb.E_IO, ack
        end
        -- 落盘校验: 部分 FS 对越界写会静默丢弃(seek 不生效), 必须回读大小确认
        local after = f:seek("end")
        if not after or after < offset + #data then
            return hzadb.E_IO, ack
        end
        return hzadb.E_OK, ack
    end)

    hzadb.reg_op("read", function(body)
        local fd = string.byte(body, 1)
        local offset, len = string.unpack("<I4I2", body, 2)
        local slot = fds[fd]
        if not slot then
            return hzadb.E_BADFD, ""
        end
        -- 读拦截兜底: 以写模式打开的 fd 也可能对被保护路径发起 read, 一律拒绝
        if is_read_denied(slot.path) then
            return hzadb.E_DENIED, ""
        end
        local f = slot.f
        f:seek("set", offset)
        local data = f:read(len) or ""
        return hzadb.E_OK, string.char(fd) .. string.pack("<I4I2", offset, #data) .. data
    end)

    hzadb.reg_op("lsdir", function(body)
        local plen = string.byte(body, 1)
        if #body < 1 + plen + 6 then
            return hzadb.E_BADREQ, string.pack("<I4I2", 0, 0)
        end
        local path = body:sub(2, 1 + plen)
        local offset, count = string.unpack("<I4I2", body, 2 + plen)
        if not check_path(path) then
            return hzadb.E_TOOLONG, string.pack("<I4I2", 0, 0)
        end
        if count > 100 then count = 100 end -- io.lsdir 单次上限
        local ok, list = io.lsdir(path, count, offset)
        if not ok or type(list) ~= "table" then
            return hzadb.E_NOENT, string.pack("<I4I2", 0, 0)
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
        return hzadb.E_OK, string.pack("<I4I2", remaining, total) .. table.concat(parts), more
    end)

    hzadb.reg_op("mkdir", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        if io.mkdir(body) then
            return hzadb.E_OK, ""
        end
        return hzadb.E_IO, ""
    end)

    hzadb.reg_op("rmdir", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        if io.rmdir(body) then
            return hzadb.E_OK, ""
        end
        return hzadb.E_IO, ""
    end)

    hzadb.reg_op("remove", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        if os.remove(body) then
            return hzadb.E_OK, ""
        end
        return hzadb.E_NOENT, ""
    end)

    hzadb.reg_op("stat", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        if io.exists(body) then
            return hzadb.E_OK, string.char(0) .. string.pack("<I4", io.fileSize(body) or 0)
        end
        if io.dexist(body) then
            return hzadb.E_OK, string.char(1) .. string.pack("<I4", 0)
        end
        return hzadb.E_NOENT, ""
    end)

    hzadb.reg_op("exists", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        local ex = io.exists(body) or io.dexist(body)
        return hzadb.E_OK, string.char(ex and 1 or 0)
    end)

    hzadb.reg_op("lsmount", function(_body)
        if io.lsmount == nil then
            return hzadb.E_NOSYS, ""
        end
        local list = io.lsmount()
        if type(list) ~= "table" then
            return hzadb.E_IO, ""
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
        return hzadb.E_OK, string.pack("<I2", total) .. table.concat(parts)
    end)

    hzadb.reg_op("fsstat", function(body)
        if not check_path(body) then
            return hzadb.E_TOOLONG, ""
        end
        if io.fsstat == nil then
            return hzadb.E_NOSYS, ""
        end
        local ok, tb, ub, bs, fst = io.fsstat(body)
        if not ok then
            return hzadb.E_NOENT, ""
        end
        tb, ub, bs, fst = tb or 0, ub or 0, bs or 0, fst or ""
        -- total/used 折算为字节, 便于 host 直接使用
        return hzadb.E_OK, string.pack("<III", tb * bs, ub * bs, bs) .. string.char(#fst) .. fst
    end)

    -- 文件指纹: 固件 crypto.md_file 流式计算, 不占 Lua 内存; 回应 40 字节 ASCII hex
    hzadb.reg_op("file_sha1", function(body)
        local path = body
        if not check_path(path) then
            return hzadb.E_TOOLONG, ""
        end
        -- 读拦截: 指纹属于对文件的读访问, 与 read 同一策略
        if is_read_denied(path) then
            return hzadb.E_DENIED, ""
        end
        if crypto == nil or crypto.md_file == nil then
            return hzadb.E_NOSYS, ""
        end
        local ok, hex = pcall(crypto.md_file, "SHA1", path)
        if not ok or type(hex) ~= "string" or #hex ~= 40 then
            return hzadb.E_NOENT, ""
        end
        -- 各移植 hex 大小写不一, 统一回小写(host 侧按小写 hexdigest 处理, 与 AUTH 策略一致)
        return hzadb.E_OK, hex:lower()
    end)

    return hzadb
end

--- 一键安装内存状态指令(meminfo, 子指令 15)
-- 回应 9×u32 LE: sys total/used/max, lua total/used/max, psram total/used/max
-- 某类内存不可用(老固件无该参数)时对应字段填 0
-- @return table 返回 hzadb 自身, 便于链式调用
function hzadb.mem()
    hzadb.reg_op("meminfo", function(_body)
        if rtos == nil or rtos.meminfo == nil then
            return hzadb.E_NOSYS, ""
        end
        local fields = {}
        for _, tp in ipairs({"sys", "lua", "psram"}) do
            local ok, total, used, max = pcall(rtos.meminfo, tp)
            if ok and type(total) == "number" then
                fields[#fields + 1] = string.pack("<III", total, used or 0, max or 0)
            else
                fields[#fields + 1] = string.pack("<III", 0, 0, 0)
            end
        end
        return hzadb.E_OK, table.concat(fields)
    end)
    return hzadb
end

-- "192.168.1.1" -> u32(大端序的数值语义), 打包进回应时按 <I4 小端
local function ipv4_to_u32(ip)
    if type(ip) ~= "string" then return 0 end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return 0 end
    return (tonumber(a) * 16777216 + tonumber(b) * 65536 + tonumber(c) * 256 + tonumber(d)) & 0xFFFFFFFF
end

--- 一键安装网络状态指令(netstat, 子指令 16)
-- 遍历 socket.LWIP_STA / LWIP_AP / LWIP_ETH / LWIP_GP 中存在的适配器,
-- 每个适配器回应: u8 id + u8 flags(bit0=link, bit1=ready, bit2=napt) + u32 ipv4(LE, 未配置为0)
-- 请求 body 为空; 回应首字节为适配器数量
-- @return table 返回 hzadb 自身, 便于链式调用
function hzadb.netdrv()
    hzadb.reg_op("netstat", function(_body)
        if netdrv == nil then
            return hzadb.E_NOSYS, ""
        end
        -- 候选适配器: 存在的 socket.LWIP_* 常量才去查询(不同平台常量集不同)
        local candidates = {}
        if socket ~= nil then
            local seen = {}
            for _, k in ipairs({"LWIP_STA", "LWIP_AP", "LWIP_ETH", "LWIP_GP"}) do
                local v = socket[k]
                if type(v) == "number" and not seen[v] then
                    seen[v] = true
                    candidates[#candidates + 1] = v
                end
            end
        end
        local parts = {string.char(0)} -- 占位 count, 最后回填
        local count = 0
        for _, id in ipairs(candidates) do
            local flags = 0
            local ok, v = pcall(netdrv.link, id)
            if ok and v then flags = flags | 0x01 end
            ok, v = pcall(netdrv.ready, id)
            if ok and v then flags = flags | 0x02 end
            ok, v = pcall(netdrv.napt, id)
            if ok and v then flags = flags | 0x04 end
            local ipv4 = 0
            ok, v = pcall(netdrv.ipv4, id)
            if ok and type(v) == "string" then
                ipv4 = ipv4_to_u32(v)
            end
            parts[#parts + 1] = string.char(id & 0xFF, flags) .. string.pack("<I4", ipv4)
            count = count + 1
        end
        parts[1] = string.char(count & 0xFF)
        return hzadb.E_OK, table.concat(parts)
    end)
    return hzadb
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202606300102"
@usage
hzadb.version()
]]
function hzadb.version()
    return hzadb.VERSION
end

return hzadb
