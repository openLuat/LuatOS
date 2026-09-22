--[[
@module  file_transfer_ops
@summary 文件传输权限操作集（hzadb reg_op 注册，零修改 hzadb 通用库）
@version 1.0
@date    2026.09.22
@author  江访
@usage
本模块为 hzadb 协议栈注册带权限的 13 个文件系统操作，是「文件传输」应用的权限核心。
不调用 hzadb.fs() 全家桶，而是逐个 reg_op 注册自实现版本，路径策略如下：

1. 共享清单内可读（设备→PC，由 PC 经 Luatools 拉取）：
   目录条目 = 前缀共享（子路径可读），文件条目 = 精确共享
   例外：READ_DENY_PREFIXES（/luadb 等固件资源目录）读拦截优先于共享白名单，
   即使把 / 或 /luadb 加进共享清单也读不走（open读模式/read/file_sha1 一律 E_DENIED）
2. 接收目录内可写（PC→设备）：仅 receive_dirs 前缀内允许写/建/删
   共享清单内一律只读（写/删/建目录都拒绝）
3. 其余路径统一回应 E_DENIED；lsdir/stat/exists 同样拒绝（防文件名探测）
   唯一例外：共享/接收条目的**祖先目录**允许 lsdir/stat，且列表过滤为仅可见条目
   （否则 Luatools 端无法逐级导航到 /sd/photos 这样的深层共享目录）
   可见 = 共享清单内 or 接收目录内 or 二者的严格祖先

写语义与 hzadb.fs() 逐行对齐（offset 权威 + 补零 + 写后回读校验），
保证 Luatools 重传/乱序到达的写在顺序写 FS 上仍幂等（见《hzadb逻辑说明.md》§5.3）。

消息协议（发布）:
发布: FILE_TRANSFER_LOG       ({time, dir="D2P"|"P2D", path, size, result="ok"|"denied"|"io", op})
发布: FILE_TRANSFER_PROGRESS  ({dir="D2P"|"P2D", path, bytes})

本文件的对外接口有1个：
1、file_transfer_ops.install(cfg)：以 cfg 表为策略源注册全部操作（cfg.live 引用，改即时生效）
]]

local file_transfer_ops = {}

-- hzadb 通用库：仅用其协议栈（reg_op/错误码/回应封装），不用 hzadb.fs() 的默认操作集
local hzadb = require "hzadb"

-- 策略源：file_transfer_app 的配置表（live 引用）
-- 结构 { shared_items = { {path=, is_dir=}, ... }, receive_dirs = { "/download", ... } }
local cfg_ref = nil

-- 设备端文件句柄表，与 hzadb.fs() 一致：同时最多4个
local fds = {}
local MAXFD = 4

-- 顺序写 FS 补零上限（防异常空洞耗尽内存），与 hzadb.fs() 一致
local PAD_LIMIT = 64 * 1024
local ZEROS = string.rep("\0", 256)

-- LSDIR 单帧条目序列化预算与单次上限，与 hzadb.fs() 一致
local LSDIR_BUDGET = 470
local LSDIR_COUNT_MAX = 100

-- ==================== 策略判定 ====================

-- path 是否落在 root 目录之内（root 为 "/" 时匹配一切绝对路径）
local function path_under(path, root)
    if root == "/" or root == "" then
        return path:sub(1, 1) == "/"
    end
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- path 是否是 entry 的严格祖先（entry 在 path 之下且不等于 path）
local function is_strict_ancestor(path, entry)
    if path == "/" then
        return entry:sub(1, 1) == "/" and #entry > 1
    end
    return #entry > #path and entry:sub(1, #path + 1) == path .. "/"
end

-- 读拦截前缀：命中的一律禁止读（open读模式/read/file_sha1），
-- **优先级高于共享白名单**——即使把 / 或 /luadb 加入共享清单也读不走。
-- /luadb 是固件脚本/资源目录，与 hzadb.fs() 的 READ_DENY_PREFIXES 同款保护；
-- lsdir/stat/exists 不拦截（只暴露名字/大小，不泄露内容），写模式不受限（升级资源场景）
local READ_DENY_PREFIXES = { "/luadb" }

local function is_read_denied(path)
    for _, prefix in ipairs(READ_DENY_PREFIXES) do
        if path == prefix or path:sub(1, #prefix + 1) == prefix .. "/" then
            return true
        end
    end
    return false
end

-- 读授权：共享清单内（目录前缀/文件精确）或接收目录内（下载后可读回校验）
local function is_readable(path)
    for _, it in ipairs((cfg_ref and cfg_ref.shared_items) or {}) do
        local p = it.path
        if p and #p > 0 then
            if path == p then return true end
            if it.is_dir and path:sub(1, #p + 1) == p .. "/" then return true end
        end
    end
    for _, root in ipairs((cfg_ref and cfg_ref.receive_dirs) or {}) do
        if path_under(path, root) then return true end
    end
    return false
end

-- 写授权：仅接收目录内（共享清单只读）
local function is_writable(path)
    for _, root in ipairs((cfg_ref and cfg_ref.receive_dirs) or {}) do
        if path_under(path, root) then return true end
    end
    return false
end

-- path 是否是共享/接收条目的严格祖先（仅供 lsdir/stat 导航）
local function leads_to_visible(path)
    for _, it in ipairs((cfg_ref and cfg_ref.shared_items) or {}) do
        local p = it.path
        if p and is_strict_ancestor(path, p) then return true end
    end
    for _, root in ipairs((cfg_ref and cfg_ref.receive_dirs) or {}) do
        if is_strict_ancestor(path, root) then return true end
    end
    return false
end

-- 浏览可见性：可读 or 可写 or 是二者的严格祖先
local function is_visible(path)
    return is_readable(path) or is_writable(path) or leads_to_visible(path)
end

-- ==================== 工具函数 ====================

-- 路径合法性：1..127 字节且不含 \0（与 hzadb.fs() 一致）
local function check_path(path)
    return #path > 0 and #path <= 127 and not path:find("%z")
end

-- 发布传输记录条目（reason 仅拒绝时填，直接展示给用户排查）
local function publish_log(dir, path, size, result, op, reason)
    sys.publish("FILE_TRANSFER_LOG", {
        time = os.time(), dir = dir, path = path,
        size = size or 0, result = result, op = op, reason = reason,
    })
end

-- 发布传输进度（bytes 为该方向累计已传字节）
local function publish_progress(dir, path, bytes)
    sys.publish("FILE_TRANSFER_PROGRESS", { dir = dir, path = path, bytes = bytes })
end

-- 分配最小空闲句柄槽
local function alloc_fd(f, path, mode)
    for i = 1, MAXFD do
        if not fds[i] then
            fds[i] = { f = f, path = path, mode = mode, bytes = 0 }
            return i
        end
    end
    return nil
end

-- ==================== 13 个操作处理函数 ====================

-- OPEN：读模式要求可读路径，写/追加/读写模式要求接收目录内
local function op_open(body)
    local mode = string.byte(body, 1)
    local path = body:sub(2)
    if not check_path(path) then
        return hzadb.E_TOOLONG, ""
    end
    local mode_s = ({ [0] = "rb", [1] = "w+b", [2] = "a+b", [3] = "r+b" })[mode]
    if not mode_s then
        return hzadb.E_BADREQ, ""
    end
    if mode == 0 then
        -- 读拦截优先：/luadb 等固件资源目录禁止下载，即使在共享清单内
        if is_read_denied(path) then
            publish_log("D2P", path, 0, "denied", "open", "固件资源目录禁止读取")
            return hzadb.E_DENIED, ""
        end
        if not is_readable(path) then
            publish_log("D2P", path, 0, "denied", "open", "未共享,不在接收目录")
            return hzadb.E_DENIED, ""
        end
    else
        -- mode 1/2/3 带写能力，一律按写授权（共享只读）
        if not is_writable(path) then
            publish_log("P2D", path, 0, "denied", "open", "仅接收目录可写")
            return hzadb.E_DENIED, ""
        end
    end
    local f = io.open(path, mode_s)
    if not f then
        return hzadb.E_NOENT, ""
    end
    local fd = alloc_fd(f, path, mode)
    if not fd then
        f:close()
        return hzadb.E_BUSY, ""
    end
    return hzadb.E_OK, string.char(fd)
end

-- CLOSE：按方向与结果发布记录（写方向 size 为最终文件大小）
local function op_close(body)
    local fd = string.byte(body, 1)
    local slot = fds[fd]
    if not slot then
        return hzadb.E_BADFD, string.pack("<I4", 0)
    end
    fds[fd] = nil
    local size = slot.f:seek("end") or 0
    local ok = pcall(slot.f.close, slot.f)
    if not ok then
        publish_log(slot.mode == 0 and "D2P" or "P2D", slot.path, size, "io", "close")
        return hzadb.E_IO, string.pack("<I4", 0)
    end
    if slot.mode == 0 then
        if slot.bytes > 0 then
            publish_log("D2P", slot.path, slot.bytes, "ok", "close")
        end
    else
        publish_log("P2D", slot.path, size, "ok", "close")
    end
    return hzadb.E_OK, string.pack("<I4", size)
end

-- WRITE：offset 权威语义 + 补零 + 写后回读校验（与 hzadb.fs() 逐行对齐）
local function op_write(body)
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
    -- fd 复核：打开后策略变化也要拦（共享只读、接收目录外不写）
    if not is_writable(slot.path) then
        publish_log("P2D", slot.path, offset, "denied", "write", "仅接收目录可写")
        return hzadb.E_DENIED, ack
    end
    local f = slot.f
    local data = body:sub(6)
    local size = f:seek("end")
    if not size then
        return hzadb.E_IO, ack
    end
    if offset > size then
        -- 先补零到 offset 再写：顺序写 FS（ramfs 等）不支持跳跃写未分配区域
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
    -- 落盘校验：部分 FS 对越界写静默丢弃，回读大小确认
    local after = f:seek("end")
    if not after or after < offset + #data then
        return hzadb.E_IO, ack
    end
    slot.bytes = slot.bytes + #data
    publish_progress("P2D", slot.path, slot.bytes)
    return hzadb.E_OK, ack
end

-- READ：短读即 EOF；fd 复核读授权
local function op_read(body)
    local fd = string.byte(body, 1)
    local offset, len = string.unpack("<I4I2", body, 2)
    local slot = fds[fd]
    if not slot then
        return hzadb.E_BADFD, ""
    end
    if is_read_denied(slot.path) then
        publish_log("D2P", slot.path, offset, "denied", "read", "固件资源目录禁止读取")
        return hzadb.E_DENIED, ""
    end
    if not is_readable(slot.path) then
        publish_log("D2P", slot.path, offset, "denied", "read", "未共享,不在接收目录")
        return hzadb.E_DENIED, ""
    end
    local f = slot.f
    f:seek("set", offset)
    local data = f:read(len) or ""
    slot.bytes = slot.bytes + #data
    if #data > 0 then
        publish_progress("D2P", slot.path, slot.bytes)
    end
    return hzadb.E_OK, string.char(fd) .. string.pack("<I4I2", offset, #data) .. data
end

-- LSDIR：祖先目录放行但过滤条目；预算截断置 MORE 供 host 翻页
local function op_lsdir(body)
    local plen = string.byte(body, 1)
    if #body < 1 + plen + 6 then
        return hzadb.E_BADREQ, string.pack("<I4I2", 0, 0)
    end
    local path = body:sub(2, 1 + plen)
    local offset, count = string.unpack("<I4I2", body, 2 + plen)
    if not check_path(path) then
        return hzadb.E_TOOLONG, string.pack("<I4I2", 0, 0)
    end
    if not is_visible(path) then
        publish_log("D2P", path, 0, "denied", "lsdir", "路径未授权")
        return hzadb.E_DENIED, string.pack("<I4I2", 0, 0)
    end
    if count > LSDIR_COUNT_MAX then count = LSDIR_COUNT_MAX end
    local ok, list = io.lsdir(path, count, offset)
    if not ok or type(list) ~= "table" then
        return hzadb.E_NOENT, string.pack("<I4I2", 0, 0)
    end
    -- 条目过滤：祖先目录只露出共享/接收子树，其余名字不进列表
    -- 注意过滤发生在 host 分页 offset 之后，remaining/MORE 语义与 hzadb.fs() 一致
    local base = path
    if base ~= "/" then
        base = base:match("^(.+)/$") or base
    end
    local parts, total, n = {}, 0, 0
    local cut = false
    for _, e in ipairs(list) do
        local entry_path = (path == "/") and ("/" .. e.name) or (base .. "/" .. e.name)
        if is_visible(entry_path) then
            local name = e.name or ""
            local eb = string.char(e.type or 0) .. string.pack("<I4", e.size or 0) .. string.char(#name) .. name
            if total + #eb > LSDIR_BUDGET then
                cut = true
                break
            end
            parts[#parts + 1] = eb
            total = total + #eb
            n = n + 1
        end
    end
    local more = 0
    if n > 0 and (cut or n == count) then more = 0x02 end
    local remaining = more == 0x02 and count or 0
    return hzadb.E_OK, string.pack("<I4I2", remaining, total) .. table.concat(parts), more
end

-- MKDIR：仅接收目录内
local function op_mkdir(body)
    if not check_path(body) then
        return hzadb.E_TOOLONG, ""
    end
    if not is_writable(body) then
        publish_log("P2D", body, 0, "denied", "mkdir", "仅接收目录可写")
        return hzadb.E_DENIED, ""
    end
    if io.mkdir(body) then
        return hzadb.E_OK, ""
    end
    return hzadb.E_IO, ""
end

-- RMDIR：仅接收目录内
local function op_rmdir(body)
    if not check_path(body) then
        return hzadb.E_TOOLONG, ""
    end
    if not is_writable(body) then
        publish_log("P2D", body, 0, "denied", "rmdir", "仅接收目录可写")
        return hzadb.E_DENIED, ""
    end
    if io.rmdir(body) then
        return hzadb.E_OK, ""
    end
    return hzadb.E_IO, ""
end

-- REMOVE：仅接收目录内（共享只读，不可删）
local function op_remove(body)
    if not check_path(body) then
        return hzadb.E_TOOLONG, ""
    end
    if not is_writable(body) then
        publish_log("P2D", body, 0, "denied", "remove", "仅接收目录可写")
        return hzadb.E_DENIED, ""
    end
    if os.remove(body) then
        return hzadb.E_OK, ""
    end
    return hzadb.E_NOENT, ""
end

-- STAT：浏览可见性（含祖先，防探测约束见文件头）
local function op_stat(body)
    if not check_path(body) then
        return hzadb.E_TOOLONG, ""
    end
    if not is_visible(body) then
        return hzadb.E_DENIED, ""
    end
    if io.exists(body) then
        return hzadb.E_OK, string.char(0) .. string.pack("<I4", io.fileSize(body) or 0)
    end
    if io.dexist(body) then
        return hzadb.E_OK, string.char(1) .. string.pack("<I4", 0)
    end
    return hzadb.E_NOENT, ""
end

-- EXISTS：浏览可见性
local function op_exists(body)
    if not check_path(body) then
        return hzadb.E_TOOLONG, ""
    end
    if not is_visible(body) then
        return hzadb.E_DENIED, ""
    end
    local ex = io.exists(body) or io.dexist(body)
    return hzadb.E_OK, string.char(ex and 1 or 0)
end

-- LSMOUNT：不含文件内容，始终放行（与 hzadb.fs() 一致）
local function op_lsmount(_body)
    if io.lsmount == nil then
        return hzadb.E_NOSYS, ""
    end
    local list = io.lsmount()
    if type(list) ~= "table" then
        return hzadb.E_IO, ""
    end
    local parts, total = {}, 0
    for _, e in ipairs(list) do
        local mpath = e.path or ""
        local fst = e.fs or ""
        local eb = string.char(#mpath) .. mpath .. string.char(#fst) .. fst
        if total + #eb > LSDIR_BUDGET then break end
        parts[#parts + 1] = eb
        total = total + #eb
    end
    return hzadb.E_OK, string.pack("<I2", total) .. table.concat(parts)
end

-- FSSTAT：不含文件内容，始终放行（与 hzadb.fs() 一致）
local function op_fsstat(body)
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
    return hzadb.E_OK, string.pack("<III", tb * bs, ub * bs, bs) .. string.char(#fst) .. fst
end

-- FILE_SHA1：属于读访问，与 read 同一策略
local function op_file_sha1(body)
    local path = body
    if not check_path(path) then
        return hzadb.E_TOOLONG, ""
    end
    if is_read_denied(path) then
        publish_log("D2P", path, 0, "denied", "file_sha1", "固件资源目录禁止读取")
        return hzadb.E_DENIED, ""
    end
    if not is_readable(path) then
        publish_log("D2P", path, 0, "denied", "file_sha1", "未共享,不在接收目录")
        return hzadb.E_DENIED, ""
    end
    if crypto == nil or crypto.md_file == nil then
        return hzadb.E_NOSYS, ""
    end
    local ok, hex = pcall(crypto.md_file, "SHA1", path)
    if not ok or type(hex) ~= "string" or #hex ~= 40 then
        return hzadb.E_NOENT, ""
    end
    return hzadb.E_OK, hex:lower()
end

--[[
以 cfg 表为策略源注册全部 13 个文件系统操作；
cfg 为 live 引用：共享清单/接收目录变更后无需重新 install；
@api file_transfer_ops.install(cfg)

@table cfg
含义：策略源配置表，字段 shared_items（{{path=, is_dir=}, ...}）与 receive_dirs（{"...", ...}）；
取值范围：file_transfer_app 的配置表；
是否必选：必须传入，不允许为空或者nil

@return table
含义：返回 file_transfer_ops 自身

@usage
file_transfer_ops.install(cfg)
]]
function file_transfer_ops.install(cfg)
    cfg_ref = cfg
    hzadb.reg_op("open", op_open)
    hzadb.reg_op("close", op_close)
    hzadb.reg_op("write", op_write)
    hzadb.reg_op("read", op_read)
    hzadb.reg_op("lsdir", op_lsdir)
    hzadb.reg_op("mkdir", op_mkdir)
    hzadb.reg_op("rmdir", op_rmdir)
    hzadb.reg_op("remove", op_remove)
    hzadb.reg_op("stat", op_stat)
    hzadb.reg_op("exists", op_exists)
    hzadb.reg_op("lsmount", op_lsmount)
    hzadb.reg_op("fsstat", op_fsstat)
    hzadb.reg_op("file_sha1", op_file_sha1)
    log.info("file_transfer_ops", "权限操作集已注册, 共享条目", #(cfg.shared_items or {}),
             "接收目录", #((cfg.receive_dirs or {})))
    return file_transfer_ops
end

return file_transfer_ops
