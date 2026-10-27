--[[
@module  hzadb_app
@summary hzadb 设备端应用功能模块（安装指令集 + 鉴权 + 启动 + 心跳 + 启动信息）
@version 1.0
@date    2026.10.27
@usage
本文件为 hzadb demo 的设备端应用功能模块，核心业务逻辑为：
1、安装标准操作集：hzadb.fs() 装 13 条文件系统指令（open/close/write/read/lsdir/mkdir/
   rmdir/remove/stat/exists/lsmount/fsstat/file_sha1），hzadb.mem() 装内存状态指令，
   hzadb.netdrv() 装网络状态指令；
2、可选 HMAC 挑战应答鉴权：配置 AUTH_TOKEN 后，未鉴权的连接只能先走 HELLO/AUTH，
   避免别人插上日志口就能读写设备文件；
3、可选只读模式：READ_ONLY=true 时用 hzadb.reg_op 覆盖写类指令，一律回 E_DENIED，
   演示"开放哪些能力、哪些路径可写"完全由应用脚本决定（库本身不带任何业务逻辑）；
4、启动协议栈，并打印启动信息（协议栈版本、挂载点、根分区空间、固件能力自检），
   出问题时看一眼日志就知道是"固件没开宏"还是"库没打包进去"；
5、心跳日志：每 HEARTBEAT_MS 打一条，用来验证命令帧与普通日志帧在同一根日志线上共存
   时不会互相干扰（这是日志口复用成命令通道后最容易被忽略的一点）。

对外接口：
1、hzadb_app.start()：安装指令集并启动协议栈，返回 true 表示日志口已被接管；
   返回 false 有两种原因——固件没开 LUAT_USE_LOG_USER_CMD，或配了 AUTH_TOKEN 但鉴权开启失败
   （后者会直接放弃启动，避免"以为有鉴权"却在无鉴权状态下对外开放）
2、hzadb_app.get_status()：查询运行状态（是否就绪/协议栈版本/鉴权/只读）

注意：hzadb 依赖固件的 log.set_usercmd_cb / log.usercmd_write，需要固件打开
LUAT_USE_LOG_USER_CMD；截至 2026-09-22 只有 Air1601/Air1602 固件提供该能力。
其它型号上 hzadb.start() 会返回 false，本模块只打一条 warn、不影响心跳和其它业务。
]]

-- 加载 hzadb 设备端协议栈（通用库，位于 script/libs/hzadb.lua，
-- Luatools 勾选"添加默认lib"时会一起打包；本目录不再自带协议栈）
local hzadb = require "hzadb"

local M = {}

-- ==================== 可配置项 ====================

-- 鉴权 token：留空表示不鉴权（开箱即用）
-- 生产环境建议 >=16 字节随机串，并和上位机保持一致；8..64 字节，超出 set_auth 会报错
local AUTH_TOKEN = ""

-- 只读演示：true 时覆盖写类指令，一律回 E_DENIED
-- 用来演示"权限由脚本控制"；真实产品里应按路径白名单判断，而不是一刀切
local READ_ONLY = false

-- 心跳日志周期（毫秒），填 0 关闭
-- 作用：验证"命令帧 + 日志帧"共用一根日志线时，上位机收发不受日志影响
local HEARTBEAT_MS = 5000

-- ==================== 运行状态 ====================

local status = {
    ready    = false,            -- 协议栈是否已接管日志口
    version  = hzadb.version(),  -- 协议栈版本（年月日时分）
    auth     = false,            -- 鉴权是否生效
    readonly = READ_ONLY,        -- 是否只读模式
}

-- ==================== 内部函数 ====================

--[[
打印挂载点与根分区空间；

@api hzadb_app.print_storage()
@summary 启动时打一次，既方便人工确认，也便于判断上位机该往哪个路径传文件
@return nil
]]
local function print_storage()
    -- 挂载点枚举：上位机 LSDIR/LSMOUNT 指令看到的就是这些路径
    if io.lsmount then
        local parts = {}
        for _, m in ipairs(io.lsmount()) do
            parts[#parts + 1] = (m.path == "" and "/" or m.path) .. ":" .. tostring(m.fs)
        end
        log.info("hzadb_app", "挂载点", table.concat(parts, " "))
    else
        log.warn("hzadb_app", "固件没有 io.lsmount，LSMOUNT 指令会回 E_NOSYS")
    end

    -- 根分区空间：上位机 FSSTAT "/" 看到的数字与这里一致
    if io.fsstat then
        local ok, tb, ub, bs, fst = io.fsstat("/")
        if ok then
            log.info("hzadb_app", "根分区", fst,
                string.format("%d/%d bytes, block %d", ub * bs, tb * bs, bs))
        end
    else
        log.warn("hzadb_app", "固件没有 io.fsstat，FSSTAT 指令会回 E_NOSYS")
    end
end

--[[
只读保护：覆盖写类指令；

@api hzadb_app.install_readonly_guard()
@summary 演示"设备端可以按需裁剪能力"：把写类子指令重新注册成直接回 E_DENIED
@return nil
]]
local function install_readonly_guard()
    -- hzadb.reg_op 是按"子指令名"覆盖注册，后注册的会替换掉 fs() 装进去的标准实现，
    -- 所以这里必须在 hzadb.fs() 之后再调用才有效
    local function deny()
        log.warn("hzadb_app", "只读模式，已拒绝写请求")
        return hzadb.E_DENIED
    end
    hzadb.reg_op("write", deny)
    hzadb.reg_op("mkdir", deny)
    hzadb.reg_op("rmdir", deny)
    hzadb.reg_op("remove", deny)
    log.info("hzadb_app", "只读模式已开启：write/mkdir/rmdir/remove 一律回 E_DENIED")
end

--[[
启动心跳日志任务；

@api hzadb_app.start_heartbeat()
@summary 按 HEARTBEAT_MS 周期打日志，验证命令帧与日志帧共存
@return nil
]]
local function start_heartbeat()
    if not HEARTBEAT_MS or HEARTBEAT_MS <= 0 then
        log.info("hzadb_app", "心跳日志已关闭(HEARTBEAT_MS=0)")
        return
    end
    sys.timerLoopStart(function()
        log.info("hzadb_app", "heartbeat", "lib", status.version,
            status.ready and "usercmd已接管" or "usercmd不可用")
    end, HEARTBEAT_MS)
end

--[[
启动 hzadb 服务；

@api hzadb_app.start()
@summary 安装指令集 → 可选只读保护 → 可选鉴权 → 启动协议栈 → 起心跳
@return boolean 日志口已被接管返回 true；固件未开 LUAT_USE_LOG_USER_CMD、
                或配了 AUTH_TOKEN 但鉴权开启失败，都返回 false

@usage
if hzadb_app.start() then
    log.info("main", "上位机可以连了")
end
]]
function M.start()
    -- ########## 1、打印启动信息 + 固件能力自检 ##########
    log.info("hzadb_app", "协议栈版本", status.version,
        "协议版本", hzadb.PROTO_VERSION, "单片上限", hzadb.MAX_CHUNK .. "B")

    -- 这里单独判断一次固件能力：start() 内部也会判断，但提前打印更直观，
    -- 能区分"固件没开 LUAT_USE_LOG_USER_CMD"和"库没打包进脚本"两种失败
    local cmd_ok = (type(log.set_usercmd_cb) == "function")
    if cmd_ok then
        log.info("hzadb_app", "固件 usercmd 通道 可用")
    else
        log.warn("hzadb_app", "固件 usercmd 通道 不可用",
            "(需固件打开 LUAT_USE_LOG_USER_CMD，仅 Air1601/Air1602 提供)")
    end

    print_storage()

    -- ########## 2、安装标准操作集 ##########
    -- fs() 默认拦截对 /luadb 的读文件请求（防止别人把固件脚本读走），
    -- lsdir/stat/exists 和写操作不受影响；要改拦截范围改库里的 READ_DENY_PREFIXES
    hzadb.fs()      -- 文件系统 13 条指令
    hzadb.mem()     -- MEMINFO：sys/lua/psram 三组 total/used/max
    hzadb.netdrv()  -- NETSTAT：适配器数量 + 每个适配器的 link/ready/napt 与 IPv4
    log.info("hzadb_app", "标准操作集安装完成 fs/mem/netdrv")

    -- ########## 3、只读保护（可选） ##########
    if READ_ONLY then
        install_readonly_guard()
    end

    -- ########## 4、鉴权（可选） ##########
    -- 必须在 start() 之前调用，HELLO 时通过 caps 位告知上位机"需要鉴权"
    if AUTH_TOKEN and #AUTH_TOKEN > 0 then
        local ok, err = pcall(hzadb.set_auth, AUTH_TOKEN)
        status.auth = ok and true or false
        if status.auth then
            log.info("hzadb_app", "鉴权已开启，token 长度", #AUTH_TOKEN,
                "上位机需用同款 token 调用 auth()")
        else
            -- 常见原因：token 长度不在 8..64，或固件没有 crypto.hmac_sha256
            -- 这种情况绝不能继续 start()：否则日志口会在"以为有鉴权"的状态下裸奔
            log.error("hzadb_app", "鉴权开启失败(token 需 8..64 字节, 且固件需带 crypto)",
                "已放弃启动协议栈，避免无鉴权对外开放", err)
            return false
        end
    else
        log.info("hzadb_app", "鉴权未开启(AUTH_TOKEN 为空)，任何能打开日志口的工具都能读写文件")
    end

    -- ########## 5、启动协议栈 ##########
    -- start() 会注册 log.set_usercmd_cb 回调，之后日志口收到的协议帧都交给 hzadb 分发
    status.ready = hzadb.start() and true or false
    if status.ready then
        log.info("hzadb_app", "hzadb 服务就绪：日志口已被接管",
            status.readonly and "只读" or "读写", status.auth and "鉴权" or "无鉴权")
    else
        log.warn("hzadb_app", "hzadb 未启动：固件未开启 LUAT_USE_LOG_USER_CMD",
            "心跳与其它业务继续运行，不影响日志查看")
    end

    -- ########## 6、心跳日志 ##########
    start_heartbeat()
    return status.ready
end

--[[
查询运行状态；

@api hzadb_app.get_status()
@summary 返回状态表，业务层/测试脚本可据此判断服务是否可用
@return table 状态表 {ready, version, auth, readonly}

@usage
local st = hzadb_app.get_status()
log.info("hzadb", "ready", st.ready, "auth", st.auth)
]]
function M.get_status()
    return status
end

return M
