--[[
@module  file_transfer_app
@summary 文件传输业务层（hzadb服务管理/共享清单/传输记录）
@version 1.0
@date    2026.09.22
@author  江访
@usage
本模块为「文件传输」内置应用的业务层，核心业务逻辑为：
1、启动 hzadb 协议栈（fs/mem/netdrv 操作集 + 可选鉴权），作为 Luatools 文件传输的设备端通道；
2、管理共享清单（设备→PC 的读授权白名单）与接收目录（PC→设备 的写目标），fskv 持久化；
3、传输记录环形缓冲（最近 50 条），供传输记录卡展示。

权限策略不在本模块实现，由 file_transfer_ops 以本模块的配置表为策略源执行；
配置表为 live 引用，共享清单变更即时生效，无需重启服务。

消息协议（订阅/发布）:
订阅: FILE_TRANSFER_LOG ({time, dir, path, size, result, op})   → 记录入环形缓冲
发布: FILE_TRANSFER_STATUS ({hzadb_ok, auth_enabled, auth_on, shared_count, receive_dirs})
      启动完成/配置变更时各发布一次

本文件的对外接口有9个：
1、file_transfer_app.get_cfg：读配置表（只读约定）
2、file_transfer_app.add_shared：添加共享条目（文件或目录）
3、file_transfer_app.remove_shared：移除共享条目
4、file_transfer_app.add_receive_dir：添加接收目录（PC→设备写授权）
5、file_transfer_app.remove_receive_dir：移除接收目录
6、file_transfer_app.get_records：取传输记录列表（新在前）
7、file_transfer_app.clear_records：清空传输记录
8、file_transfer_app.get_status：取服务状态
9、file_transfer_app.save_auth：配置鉴权开关与token（即时生效）
]]

local file_transfer_app = {}

-- hzadb 通用库：协议栈 + mem/netdrv 状态指令；文件操作集由 file_transfer_ops 提供
local hzadb = require "hzadb"
local file_transfer_ops = require "file_transfer_ops"

-- ==================== 配置常量 ====================

local FSKV_KEY = "file_transfer_cfg"

-- 传输记录环形缓冲上限
local RECORD_MAX = 50

-- 默认接收目录 = 各存储根（2026-09-23 起"默认全放通"：开箱传哪都行，选择器可收窄白名单）
local DEFAULT_RECEIVE_DIRS = { "/", "/sd", "/little_flash", "/ram" }
-- 旧版默认接收目录（load_cfg 迁移用：命中旧默认则换新默认，用户自定义的保留）
local OLD_DEFAULT_RECEIVE_DIRS = { "/download", "/sd/download", "/little_flash/download" }

-- ==================== 运行状态 ====================

-- 配置表（策略源，file_transfer_ops 持 live 引用）
-- 共享清单为空（安全默认：先授权后可读）；接收目录默认各存储根
local cfg = {
    shared_items = {},
    receive_dirs = { "/", "/sd", "/little_flash", "/ram" },
    auth_enabled = false,
    auth_token = "",
}

-- 服务状态
local status = {
    hzadb_ok = false,      -- 协议栈是否已接管日志口
    auth_enabled = false,  -- 配置上是否开启鉴权
    auth_on = false,       -- 鉴权是否实际生效（token合法且set_auth成功）
    shared_count = 0,      -- 共享条目数
    receive_dirs = {},     -- 接收目录（展示用）
}

-- 传输记录环形缓冲（新记录插头部）
local records = {}

-- ==================== 私有函数 ====================

-- 禁传目录判定（/luadb 固件脚本/资源区，不可下载也不可上传，与 ops 的 DENY_PREFIXES 一致）
local function is_deny_path(path)
    return path == "/luadb" or path:sub(1, 8) == "/luadb/"
end

-- 发布服务状态（窗口状态卡刷新）
local function publish_status()
    status.auth_enabled = cfg.auth_enabled
    status.shared_count = #(cfg.shared_items or {})
    status.receive_dirs = cfg.receive_dirs
    sys.publish("FILE_TRANSFER_STATUS", status)
end

-- 两目录列表是否逐项相同（顺序敏感，均为固定顺序的短列表）
local function same_dirs(a, b)
    if type(a) ~= "table" or #a ~= #b then return false end
    for i, p in ipairs(b) do
        if a[i] ~= p then return false end
    end
    return true
end

-- fskv 加载配置（fskv 挂载晚于 require，统一在启动任务里调用）
local function load_cfg()
    local ok = pcall(fskv.init)
    if not ok then
        log.warn("file_transfer", "fskv.init 失败, 使用默认配置")
        return
    end
    local saved = fskv.get(FSKV_KEY)
    if type(saved) ~= "table" then
        return
    end
    if type(saved.shared_items) == "table" then
        cfg.shared_items = saved.shared_items
    end
    if type(saved.receive_dirs) == "table" and #saved.receive_dirs > 0 then
        -- v2 迁移：命中旧默认三处 download 目录则换新默认（各存储根，全放通）；用户自定义列表原样保留
        if same_dirs(saved.receive_dirs, OLD_DEFAULT_RECEIVE_DIRS) then
            log.info("file_transfer", "接收目录迁移: 旧默认 -> 各存储根(全放通)")
            cfg.receive_dirs = DEFAULT_RECEIVE_DIRS
        else
            cfg.receive_dirs = saved.receive_dirs
        end
    end
    if type(saved.auth_enabled) == "boolean" then
        cfg.auth_enabled = saved.auth_enabled
    end
    if type(saved.auth_token) == "string" then
        cfg.auth_token = saved.auth_token
    end
    log.info("file_transfer", "配置已加载, 共享条目", #cfg.shared_items)
end

-- fskv 保存配置
local function save_cfg()
    local ok = pcall(fskv.set, FSKV_KEY, {
        shared_items = cfg.shared_items,
        receive_dirs = cfg.receive_dirs,
        auth_enabled = cfg.auth_enabled,
        auth_token = cfg.auth_token,
    })
    if not ok then
        log.warn("file_transfer", "fskv.set 失败, 配置未持久化")
    end
end

-- 传输记录入环形缓冲（订阅 FILE_TRANSFER_LOG）
local function on_transfer_log(entry)
    table.insert(records, 1, entry)
    while #records > RECORD_MAX do
        table.remove(records)
    end
end

-- 启动任务：加载配置 → 注册权限操作集 → 启动 hzadb → 发布状态
local function file_transfer_task_func()
    -- 等 fskv 就绪（fskv 挂载晚于 require 的时序问题，ui_theme 已踩过坑）
    sys.wait(800)
    load_cfg()
    status.shared_count = #(cfg.shared_items or {})
    status.receive_dirs = cfg.receive_dirs

    -- 注册带权限的文件操作集（覆盖 hzadb.fs() 的默认实现；本应用不调用 hzadb.fs）
    file_transfer_ops.install(cfg)

    -- 鉴权（可选）：配置开启且 token 合法时生效；无效 token 回退关闭
    if cfg.auth_enabled and type(cfg.auth_token) == "string"
        and #cfg.auth_token >= 8 and #cfg.auth_token <= 64 then
        local ok, err = pcall(hzadb.set_auth, cfg.auth_token)
        status.auth_on = ok and true or false
        if ok then
            log.info("file_transfer", "鉴权已启用, token长度", #cfg.auth_token, ", 上位机须输入同款token")
        else
            log.warn("file_transfer", "set_auth失败, 鉴权未生效(固件缺crypto.hmac_sha256?)", err)
        end
    else
        status.auth_on = false
        if cfg.auth_enabled then
            log.warn("file_transfer", "token非法(需8..64字节), 鉴权未生效")
        else
            log.info("file_transfer", "鉴权未启用; 上位机若强制鉴权, 请在设备端配置同款token")
        end
    end

    -- mem/netdrv 状态指令（不含文件内容，无权限风险）
    hzadb.mem()
    hzadb.netdrv()

    -- 接管日志口；固件没开 LUAT_USE_LOG_USER_CMD 时返回 false，降级为仅配置页可用
    status.hzadb_ok = hzadb.start() and true or false
    if status.hzadb_ok then
        log.info("file_transfer", "hzadb 服务就绪, lib", hzadb.VERSION)
    else
        log.warn("file_transfer", "日志口用户指令未启用(固件需打开 LUAT_USE_LOG_USER_CMD), 传输服务不可用")
    end

    status.auth_enabled = cfg.auth_enabled
    publish_status()
end

sys.subscribe("FILE_TRANSFER_LOG", on_transfer_log)
sys.taskInit(file_transfer_task_func)

-- ==================== 对外接口 ====================

--[[
读配置表（只读约定：修改请走 add_shared/remove_shared/save_auth）
@api file_transfer_app.get_cfg()

@return table
含义：配置表，字段 shared_items/receive_dirs/auth_enabled/auth_token

@usage
local cfg = file_transfer_app.get_cfg()
]]
function file_transfer_app.get_cfg()
    return cfg
end

--[[
添加共享条目（设备→PC 读授权）；同路径重复添加自动去重；
@api file_transfer_app.add_shared(path, is_dir)

@string path
含义：共享文件或目录的完整路径；
取值范围：如 /sd/photos 或 /report.pdf，不超过127字节；
是否必选：必须传入，不允许为空或者nil

@boolean is_dir
含义：是否目录（true=前缀共享子路径，false=仅该文件）；
取值范围：true/false；
是否必选：必须传入

@return boolean
含义：是否添加成功（false=路径非法或已存在）

@usage
file_transfer_app.add_shared("/sd/photos", true)
]]
function file_transfer_app.add_shared(path, is_dir)
    if type(path) ~= "string" or #path == 0 or #path > 127 then
        return false
    end
    -- /luadb 禁传目录不进共享清单（ops 层也会拦，这里提前拒绝避免无效配置）
    if is_deny_path(path) then
        log.warn("file_transfer", "固件资源目录禁止共享", path)
        return false
    end
    for _, it in ipairs(cfg.shared_items) do
        if it.path == path then
            return false
        end
    end
    table.insert(cfg.shared_items, { path = path, is_dir = is_dir and true or false })
    save_cfg()
    publish_status()
    return true
end

--[[
移除共享条目
@api file_transfer_app.remove_shared(path)

@string path
含义：要移除的共享条目路径；
取值范围：共享清单内已有路径；
是否必选：必须传入，不允许为空或者nil

@return boolean
含义：是否移除成功（false=路径不在清单内）

@usage
file_transfer_app.remove_shared("/sd/photos")
]]
function file_transfer_app.remove_shared(path)
    for i, it in ipairs(cfg.shared_items) do
        if it.path == path then
            table.remove(cfg.shared_items, i)
            save_cfg()
            publish_status()
            return true
        end
    end
    return false
end

--[[
取传输记录列表（新记录在前，最多50条）
@api file_transfer_app.get_records()

@return table
含义：记录数组，条目 {time, dir, path, size, result, op}

@usage
local records = file_transfer_app.get_records()
]]
function file_transfer_app.get_records()
    return records
end

--[[
清空传输记录
@api file_transfer_app.clear_records()

@return nil
含义：无返回值

@usage
file_transfer_app.clear_records()
]]
function file_transfer_app.clear_records()
    records = {}
end

--[[
添加接收目录（PC→设备写授权，即时生效）；同路径重复添加自动去重；
@api file_transfer_app.add_receive_dir(path)

@string path
含义：接收目录完整路径；
取值范围：如 /sd/download，不超过127字节；
是否必选：必须传入，不允许为空或者nil

@return boolean
含义：是否添加成功（false=路径非法或已存在）

@usage
file_transfer_app.add_receive_dir("/sd/upload")
]]
function file_transfer_app.add_receive_dir(path)
    if type(path) ~= "string" or #path == 0 or #path > 127 then
        return false
    end
    -- /luadb 禁传目录不进接收目录（ops 层也会拦，这里提前拒绝避免无效配置）
    if is_deny_path(path) then
        log.warn("file_transfer", "固件资源目录禁止作接收目录", path)
        return false
    end
    for _, p in ipairs(cfg.receive_dirs) do
        if p == path then
            return false
        end
    end
    table.insert(cfg.receive_dirs, path)
    save_cfg()
    publish_status()
    return true
end

--[[
移除接收目录（清空后 PC→设备写全部拒绝）；
@api file_transfer_app.remove_receive_dir(path)

@string path
含义：要移除的接收目录完整路径；
取值范围：接收目录列表内已有路径；
是否必选：必须传入，不允许为空或者nil

@return boolean
含义：是否移除成功（false=路径不在列表内）

@usage
file_transfer_app.remove_receive_dir("/sd/upload")
]]
function file_transfer_app.remove_receive_dir(path)
    for i, p in ipairs(cfg.receive_dirs) do
        if p == path then
            table.remove(cfg.receive_dirs, i)
            save_cfg()
            publish_status()
            return true
        end
    end
    return false
end

--[[
取服务状态
@api file_transfer_app.get_status()

@return table
含义：{hzadb_ok, auth_enabled, auth_on, shared_count, receive_dirs}

@usage
local st = file_transfer_app.get_status()
]]
function file_transfer_app.get_status()
    return status
end

--[[
配置鉴权开关与token，保存后即时生效（hzadb.set_auth 动态启停鉴权门控）；
开启鉴权时 token 为8..64字节，生产建议>=16字节随机串；token 以明文存fskv（防误连场景）；
@api file_transfer_app.save_auth(enabled, token)

@boolean enabled
含义：是否开启鉴权；
取值范围：true/false；
是否必选：必须传入

@string or nil token
含义：鉴权token；
取值范围：8..64字节字符串；enabled为false时可传nil；
是否必选：enabled为true时必选

@return boolean
含义：是否配置成功（false=token非法或set_auth失败）

@usage
file_transfer_app.save_auth(true, "0123456789abcdef")
file_transfer_app.save_auth(false)
]]
function file_transfer_app.save_auth(enabled, token)
    if enabled then
        if type(token) ~= "string" or #token < 8 or #token > 64 then
            return false
        end
        local ok = pcall(hzadb.set_auth, token)
        if not ok then
            return false
        end
        cfg.auth_enabled = true
        cfg.auth_token = token
        status.auth_on = true
    else
        -- 传nil关闭鉴权门控
        pcall(hzadb.set_auth, nil)
        cfg.auth_enabled = false
        cfg.auth_token = ""
        status.auth_on = false
    end
    save_cfg()
    publish_status()
    return true
end

return file_transfer_app
