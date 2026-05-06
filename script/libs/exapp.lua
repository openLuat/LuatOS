--[[
    exapp.lua - 扩展应用管理库
    @module exapp
    @summary 提供沙箱环境运行应用的能力，支持本地应用管理和云端应用市场
    @author 朱天华, 江访
    @version 1.0.2
    @date 2026.04.14
    @usage
    本文件为扩展应用管理库，提供完整的应用沙箱环境和云端应用市场功能，核心业务逻辑为：
    1. 沙箱环境隔离
       - 为每个应用创建独立的运行环境
       - 隔离全局变量、模块加载、文件访问
       - 自动清理应用退出后的资源

    2. 文件路径映射（将沙箱虚拟路径转换为实际文件系统路径）
       a. /luadb/icon.png
          -> 映射到 <应用路径>/icon.png（应用图标，特殊处理）
       b. /luadb/xxx.lua 或 /luadb/xxx.luac
          -> 按优先级搜索: <应用路径>/xxx.lua/luac -> <应用路径>/user/xxx.lua/luac -> <应用路径>/libs/xxx.lua/luac
       c. /luadb/xxx（非lua文件）
          -> 映射到 <应用路径>/res/xxx（资源文件目录）
       d. /ram/xxx
          -> 直接返回 /ram/xxx（内存文件系统，不做转换）
       e. /xxx（其他以/开头的路径）
          -> 映射到 <应用路径>/data/xxx（数据存储目录）

    3. 应用生命周期管理
       - 打开应用：创建沙箱环境，启动协程；每个应用的中的lua文件代码都在沙箱环境中运行
       - 关闭应用：发送关闭请求，清理资源
       - 异常处理：应用的task内代码运行异常，捕获应用异常，安全退出；全局环境运行的代码异常，会导致重启

    4. 扩展库支持
       - 自动识别 LuatOS 扩展库
       - 支持从全局环境和应用目录加载扩展库
       - 支持从应用目录加载自定义模块

    5. 本地应用管理（原始行为）
       - install/uninstall 仅操作内存表，不操作文件系统
       - init 扫描 /app_store/ 和 /sd/app_store/ 填充 installed_info（支持分页扫描，最多不限）

    6. 云端应用管理（新增功能）
       - 获取远程应用列表（分页）
       - 下载并安装应用（ZIP解压到 /app_store/<aid>/）
       - 安装成功后写入 install_time 到 meta.json（本地时间戳）
       - 卸载应用（删除目录）
       - 更新应用（先删后装）
       - 图标下载与缓存
       - 网络状态检测

    本文件的对外接口有：
    1. exapp.init() - 初始化应用管理库，扫描已安装应用
    2. exapp.get_app_list(params) - 获取远程应用列表
    3. exapp.install_remote_app(aid, url, app_name, category, sort) - 安装云端应用
    4. exapp.uninstall_remote_app(aid, category, sort) - 卸载云端应用
    5. exapp.update_remote_app(aid, url, app_name, category, sort) - 更新云端应用
    6. exapp.get_current_list() - 获取当前缓存的应用列表
    7. exapp.get_icon_path(aid, url) - 获取应用图标路径
    8. exapp.list_installed() - 获取已安装应用列表

    本文件发布的消息有：
    1. APP_STORE_LIST_UPDATED   - 应用列表更新（携带 apps 和分页信息）
    2. APP_STORE_ACTION_DONE    - 应用操作完成（安装/卸载/更新）
    3. APP_STORE_PROGRESS       - 下载安装进度
    4. APP_STORE_ERROR          - 错误通知
    5. APP_STORE_INSTALLED_UPDATED - 已安装应用列表更新
    6. APP_STORE_ICON_READY     - 图标下载完成

    本文件订阅的消息有：
    1. APP_STORE_GET_LIST       - 请求获取应用列表
    2. APP_STORE_INSTALL        - 请求安装应用
    3. APP_STORE_UNINSTALL      - 请求卸载应用
    4. APP_STORE_UPDATE         - 请求更新应用
    5. APP_STORE_SYNC_INSTALLED - 请求同步已安装应用信息

    使用示例：
        local exapp = require("exapp")

        -- 打开应用
        exapp.open("/app_store/app_hello/")

        -- 关闭应用（目前用户程序还用不到，exapp自动处理）
        exapp.close("/app_store/app_hello/")

        -- 获取已安装应用列表
        local apps, cnt = exapp.list_installed()

        -- 检查应用是否运行
        local running = exapp.is_running("/app_store/app_hello/")

    目录结构：
    /app_store/           -- 内置应用根目录
        app_hello/
            main.lua      -- 应用入口
            meta.json     -- 应用元信息
            icon.png      -- 应用图标
            user/         -- 用户模块
            libs/         -- 应用扩展库（存放全局环境中缺失的扩展库）
            res/          -- 资源文件
            data/         -- 数据存储
    /sd/app_store/        -- SD卡应用根目录（结构同上）

    注意事项：
    1. 文件访问会被自动映射到应用目录
    2. 应用异常可能会导致重启，也可能不会影响主线程和其他应用的运行，取决于异常代码的执行逻辑是在全局环境还是应用沙箱环境中
]]

-- ==============================================
-- 模块定义与全局变量
-- ==============================================

local exapp = {}

-- 应用管理表：记录每个正在运行的应用
-- key: app_path (如 "/app_store/app_hello/"), value: 应用信息
local app_registry = {}

-- 已安装应用信息表（统一数据源，由 init 扫描填充，云端安装/卸载会更新）
-- key: app_dir_name 应用目录名称 (如 "app_hello"), value: { cn_name, path, version, category, description, install_time }
-- 示例: { ["app_hello"] = { cn_name = "你好世界", path = "/app_store/app_hello/", version = "1.0.0", category = "demo", description = "示例应用", install_time = 1759161153 } }
local installed_info = {}

-- 已安装应用数量
local installed_cnt = 0

-- 云端应用列表缓存
local remote_app_list = {
    apps = {},
    category = "全部",
    sort = "recommend",
    page = 1,           -- 当前页码
    size = 10,          -- 每页数量
    total = 0,
    total_pages = 1,
    has_more = false, 
    query = ""
}

-- 已安装总数（用于分页显示）
local installed_total_count = 0

-- 图标缓存表
-- key: app_id, value: { path = local_path, timestamp = time(秒), size = bytes }
local icon_cache = {}

-- 云端应用配置
local APP_STORE_URL = "https://api.luatos.com/iot/appstore/list"
local APP_STORE_DOWNLOAD_REPORT_URL = "https://api.luatos.com/iot/appstore/download"
local PAGE_LIMIT = 10
local TEMP_DOWNLOAD_PATH = "/ram/app_%s.zip"
local APP_INSTALL_ROOT = "/app_store"

-- 网络状态
local network_ready = false

-- 设备信息缓存
local device_info = nil

--[[
    清理沙箱环境中的全局变量

    @param env table 沙箱环境表
    @return nil

    功能说明：
    - 遍历沙箱环境表，将所有引用设置为nil
    - 帮助垃圾回收器回收沙箱环境中的资源
]]
local function cleanup_sandbox_env(env)
    if not env then return end

    for k, v in pairs(env) do
        -- log.info("cleanup_sandbox_env", "cleared env:", k)
        env[k] = nil
    end
end

--[[
沙箱清理函数

@param app_path string 应用目录路径
@param my_env table 沙箱环境表
@param unsubscribe_all function 取消所有订阅的函数
@param mem_baseline number 沙箱创建前的内存基准值（KB）

    功能说明：
    - 取消所有订阅
    - 清除已加载的模块
    - 清理沙箱环境
    - 从应用注册表中移除
    - 触发垃圾回收
    - 检测内存泄漏（比较清理后内存与基准值）
]]
local function sandbox_cleanup(app_path, my_env, unsubscribe_all, mem_baseline)
    log.info("sandbox_cleanup", "start cleanup:", app_path)

    unsubscribe_all()

    if my_env and my_env.package and my_env.package.loaded then
        for module_name in pairs(my_env.package.loaded) do
            my_env.package.loaded[module_name] = nil
            log.info("sandbox_cleanup", "cleared module:", module_name)
        end
    end

    cleanup_sandbox_env(my_env)
    app_registry[app_path] = nil

    collectgarbage("collect")
    collectgarbage("collect")

    -- 检测内存泄漏：比较清理后内存与沙箱创建前的基准值
    if mem_baseline then
        local mem_after = collectgarbage("count")
        local mem_diff = mem_after - mem_baseline
        -- 内存泄漏阈值（KB），根据实际情况调整，因为系统中可能会有其他应用占用内存，所以此处统计并不准确，仅作为参考；
        -- 默认代码注释掉，有需要时再开启
        -- if mem_diff > 1 then
        --     log.warn("sandbox_cleanup", "potential memory leak:", app_path, "mem_diff:", mem_diff, "KB", "baseline:", mem_baseline, "KB", "after:", mem_after, "KB")
        -- else
        --     log.info("sandbox_cleanup", "cleanup completed:", app_path, "mem_diff:", mem_diff, "KB")
        -- end
    end
    log.info("sandbox_cleanup", "cleanup completed:", app_path)
end

-- 递归删除目录（用于云端卸载）
local function rmdir_recursive(dir)
    if not io.dexist(dir) then return true end
    local ret, list = io.lsdir(dir, 100, 0)
    if ret then
        for _, item in ipairs(list) do
            local full_path = dir .. "/" .. item.name
            if item.type == 1 then
                rmdir_recursive(full_path)
            else
                os.remove(full_path)
            end
        end
    end
    io.rmdir(dir)
    return true
end

--[[
    应用任务主函数
    
    @param app_path string 应用目录路径，如 "/app_store/app_hello/"
    
    功能说明：
    1. 创建沙箱环境，隔离应用的log、require、sys等全局变量
    2. 自定义log函数，自动添加应用目录前缀
    3. 自定义require函数，支持从应用目录加载模块
    4. 禁用sys.run()，防止应用接管系统控制权
    5. 加载并执行应用的main.lua
    6. 等待应用关闭请求，执行垃圾回收
]]
local function app_task(app_path)
    collectgarbage("collect")
    collectgarbage("collect")

    -- 记录沙箱创建前的内存基准值（KB），用于检测内存泄漏
    local mem_baseline = collectgarbage("count")

    -- 保存全局原版函数引用
    local global_log = log
    local global_sys = sys

    -- 从app_path提取app_dir_name，用于fskv键名隔离
    -- /app_store/app_hello/ -> app_hello
    -- /sd/app_store/myapp/ -> myapp
    local app_dir_name = app_path:match("/app_store/([^/]+)/?$") or app_path:match("/sd/app_store/([^/]+)/?$")
    local fskv_key_prefix = app_dir_name and (app_dir_name .. "_") or "wanrning!!!_"

    -- ==============================================
    -- 【核心：沙箱订阅管理器】自动记录 + 自动清理
    -- 功能：记录应用的所有订阅，应用退出时自动取消
    -- ==============================================
    local sandbox_subscriptions = {}

    -- 订阅消息，同时记录到订阅列表
    local function sandbox_subscribe(topic, func)
        if not topic or type(func) ~= "function" then return end
        global_sys.subscribe(topic, func)
        table.insert(sandbox_subscriptions, { topic = topic, func = func })
    end

    -- 取消订阅，同时从订阅列表中移除
    local function sandbox_unsubscribe(topic, func)
        if not topic then return end
        global_sys.unsubscribe(topic, func)
        for i = #sandbox_subscriptions, 1, -1 do
            local sub = sandbox_subscriptions[i]
            if sub.topic == topic and sub.func == func then
                table.remove(sandbox_subscriptions, i)
                break
            end
        end
    end

    -- 取消所有订阅（应用退出时调用）
    local function unsubscribe_all()
        for _, sub in ipairs(sandbox_subscriptions) do
            global_sys.unsubscribe(sub.topic, sub.func)
        end
        sandbox_subscriptions = {}
    end

    -- ==============================================
    -- 创建沙箱专用的log对象
    -- 功能：自动给所有log函数调用添加应用目录前缀
    -- ==============================================
    local sandbox_log = setmetatable({}, {
        __index = function(_, k)
            local v = global_log[k]
            if type(v) == "function" then
                return function(...)
                    return v("["..app_path.."]", ...)
                end
            end
            return v
        end
    })

    -- ==============================================
    -- 创建自定义环境表
    -- ==============================================
    local my_env = setmetatable({
        log = sandbox_log,
        package = { loaded = {} }
    }, { __index = _G })

    -- ==============================================
    -- 创建沙箱专用的exapp对象
    -- 功能：提供应用内的关闭接口
    -- ==============================================
    my_env.exapp = {}

    -- 关闭当前应用
    my_env.exapp.close = function()
        my_env.log.info("exapp.close", "closing app:", app_path)
        sys.publish(app_path .. "_close_req", "yes")
    end

    -- ==============================================
    -- 自定义require函数
    -- 功能：支持从应用目录加载模块，并保持环境隔离
    --
    -- 加载顺序：
    -- 1. 检查是否已在沙箱环境中加载过
    -- 2. 如果是扩展库，从全局环境加载
    -- 3. 从应用目录的 user/ 或 libs/ 子目录加载
    -- ==============================================

    -- LuatOS 扩展库模块名称列表
    -- 这些模块从全局环境加载，不需要在应用目录中提供
    local EXT_LIBS = {
        "air153C_wtd", "airlbs", "dhcpsrv", "dnsproxy",
        "exaudio", "excamera", "exchg", "excloud", "exeasyui", "exfotawifi",
        "exgnss", "exlcd", "exmodbus", "exnetif", "exremotecam", "exremotefile",
        "exril_5101", "extalk", "extp", "exvib", "exvib1", "exwin",
        "httpdns", "httpplus", "lbsLoc", "lbsLoc2",
        "libfota", "libfota2", "libnet", "netLed", "udpsrv", "xmodem", "sys"
    }
    local EXT_LIBS_SET = {}
    for _, v in ipairs(EXT_LIBS) do EXT_LIBS_SET[v] = true end

    my_env.require = function(name)
        my_env.log.info("require enter: " .. name)

        if my_env.package.loaded[name] then
            return my_env.package.loaded[name]
        end

        -- 检查是否属于 LuatOS 扩展库
        -- 处理顺序：_G[name] -> 实时require -> _G[name] -> 应用目录加载
        if EXT_LIBS_SET[name] then
            local global_mod = _G[name]
            if global_mod then
                my_env.package.loaded[name] = global_mod
                my_env.log.info("require from _G: " .. name)
                return global_mod
            end

            -- 实时在全局环境中 require
            local ok, result = pcall(require, name)
            if ok then
                my_env.package.loaded[name] = result
                my_env.log.info("require from global require: " .. name)
                return result
            end
        end

        -- 从应用目录加载模块
        -- 搜索顺序：user/name.lua -> user/name.luac -> libs/name.lua -> libs/name.luac
        local chunk, err
        local search_paths = {
            app_path.."user/"..name..".lua",
            app_path.."user/"..name..".luac",
            app_path.."libs/"..name..".lua",
            app_path.."libs/"..name..".luac"
        }

        for _, path in ipairs(search_paths) do
            if io.exists(path) then
                chunk, err = loadfile(path)
                if not chunk then
                    my_env.log.info("loadfile from path: " .. path, chunk, err)
                else
                    break
                end
            end
        end
        
        if not chunk then
            error("require failed: " .. name)
        end

        -- 设置模块的环境为沙箱环境，使模块内的全局变量访问都在沙箱内
        debug.setupvalue(chunk, 1, my_env)

        -- 执行模块代码，获取模块返回值
        local mod = chunk()

        -- 缓存已加载的模块
        my_env.package.loaded[name] = mod

        return mod
    end

    -- ==============================================
    -- 【核心辅助函数】路径解析与权限检查
    -- ==============================================

    --[[
        解析文件路径（只读操作）

        将沙箱内的虚拟路径转换为实际文件系统路径，实现应用的隔离访问

        @param string path 沙箱内传入的虚拟路径
        @return string|nil 解析后的实际路径，失败返回nil

        路径映射规则：
        1. /luadb/xxx.lua 或 /luadb/xxx.luac
           -> 按优先级搜索: <app_path>/xxx.lua, <app_path>/user/xxx.lua, <app_path>/libs/xxx.lua
        2. /luadb/xxx (非lua文件)
           -> 映射到 <app_path>/res/xxx
        3. /luadb/icon.png
           -> 特殊处理：优先使用应用目录下的 icon.png
        4. /ram/xxx
           -> 直接返回，保持不变（内存文件系统）
        5. /xxx (其他路径)
           -> 映射到 <app_path>/data/xxx

        示例：
           /luadb/main.lua      -> /app_store/app_hello/main.lua
           /luadb/logo.png  -> /app_store/app_hello/res/logo.png
           /ram/test.bin -> /ram/test.bin
           /config/settings.json -> <app_path>/data/config/settings.json
    ]]
    local function resolve_file_path(path)
        -- 参数类型检查，非字符串直接返回nil
        if type(path) ~= "string" then return nil end

        -- 路径前缀校验：必须以 /luadb/ 或 / 开头，否则拒绝访问
        if path:sub(1, 7) ~= "/luadb/" and path:sub(1, 1) ~= "/" then
            my_env.log.error("resolve_file_path", "path must start with /luadb/ or /:", path)
            return nil
        end

        -- 特殊处理：icon.png 请求
        -- 优先使用应用目录下的 icon.png，如果不存在则报错
        if path == "/luadb/icon.png" then
            local icon_path = app_path .. "icon.png"
            if io.exists(icon_path) then return icon_path end
            my_env.log.error("resolve_file_path", "icon.png not found:", icon_path)
            return nil
        end

        -- 特殊处理：meta.json 请求
        -- 优先使用应用目录下的 meta.json，如果不存在则报错
        if path == "/luadb/meta.json" then
            local meta_path = app_path .. "meta.json"
            if io.exists(meta_path) then return meta_path end
            my_env.log.error("resolve_file_path", "meta.json not found:", meta_path)
            return nil
        end

        -- 处理 /luadb/ 前缀的路径
        -- 这是应用沙箱的核心：/luadb/ 映射到应用根目录
        if path:sub(1, 7) == "/luadb/" then
            if path:sub(8, 11) == "res/" then
                -- 去掉前缀，获取相对路径
                local relative_path = path:sub(12)
                -- 在 res/ 目录查找
                local res_path = app_path .. "res/" .. relative_path
                if io.exists(res_path) then return res_path end
            else
                -- 去掉前缀，获取相对路径
                local relative_path = path:sub(8)

                -- Lua脚本文件搜索：按优先级在多个目录查找
                -- 搜索顺序：根目录 -> user/目录 -> libs/目录
                if path:sub(-4) == ".lua" or path:sub(-5) == ".luac" then
                    local search_paths = {
                        app_path .. relative_path,
                        app_path .. "user/" .. relative_path,
                        app_path .. "libs/" .. relative_path
                    }
                    for _, p in ipairs(search_paths) do
                        if io.exists(p) then return p end
                    end
                else
                    -- 非Lua文件默认在 res/ 目录查找
                    local res_path = app_path .. "res/" .. relative_path
                    if io.exists(res_path) then return res_path end
                end
            end
            -- 文件未找到，记录错误日志
            my_env.log.error("resolve_file_path", "file not found:", path)
            return nil
        end

        -- 处理 /ram/ 前缀的路径
        -- 内存文件系统路径直接透传，不做转换
        if path:sub(1, 5) == "/ram/" then
            return path
        end

        -- 处理其他 / 开头的路径
        -- 映射到 <app_path>/data/ 目录（数据存储区）
        if path:sub(1, 1) == "/" then
            return app_path.."data" .. path
        end

        -- 无法识别的路径格式
        my_env.log.error("resolve_file_path", "unresolvable path:", path)
        return nil
    end

    --[[
        目录路径解析函数（针对目录的映射）

        功能说明：
        - 将沙箱中的虚拟目录路径映射到实际的应用目录路径
        - 路径必须以 / 结尾

        路径映射规则（* 表示0个或多个字符）：
        1. "/luadb/*" 映射为 app_path..*
        2. "/ram/*" 不做映射处理，直接返回传入的参数
        3. "/*" 映射为 app_path.."data/"..*

        @param path string 虚拟目录路径，必须以 / 结尾
        @return string|nil 解析后的实际路径，解析失败返回 nil

        使用示例：
        local real_path = resolve_dir_path("/luadb/res/")
        -- 映射为: /app_store/app_xxx/res/
    ]]
    local function resolve_dir_path(path)
        -- 参数类型检查，非字符串直接返回 nil
        if type(path) ~= "string" then
            return nil
        end

        -- 检查路径第一个字符是否为 /
        if path:sub(1, 1) ~= "/" then
            my_env.log.error("resolve_dir_path", "path must start with /:", path)
            return nil
        end

        -- 检查路径最后一个字符是否为 /
        if path:sub(-1) ~= "/" then
            my_env.log.error("resolve_dir_path", "path must end with /:", path)
            return nil
        end

        -- 处理 /luadb/ 前缀的路径
        -- 映射规则：/luadb/* -> app_path..*
        if path:sub(1, 7) == "/luadb/" then
            -- 去掉 /luadb/ 前缀，获取相对路径（保留末尾的 /）
            local relative_path = path:sub(8)
            -- 拼接应用目录下的实际路径
            return app_path .. relative_path
        end

        -- 处理 /ram/ 前缀的路径
        -- 映射规则：/ram/* 不做映射，直接返回
        if path:sub(1, 5) == "/ram/" then
            return path
        end

        -- 处理其他 / 开头的路径
        -- 映射规则：/* -> app_path.."data/"..*
        if path:sub(1, 1) == "/" then
            -- 去掉开头的 /，获取相对路径（保留末尾的 /）
            local relative_path = path:sub(2)
            -- 映射到应用目录下的 data/ 目录
            return app_path .. "data/" .. relative_path
        end

        -- 无法识别的路径格式
        my_env.log.error("resolve_dir_path", "unresolvable path:", path)
        return nil
    end

    -- 检查写入权限
    -- 规则：
    -- 1. /ram/ 目录允许写入
    -- 2. 只允许写入应用目录内的文件
    -- 3. 禁止写入 libs/、user/、res/ 目录（只读资源）
    -- 4. 禁止写入 main.lua、meta.json、icon.png（受保护文件）
    -- 返回 true 表示有权限，false 表示无权限
    local function check_write_permission(resolved_path)
        -- /ram/ 目录允许写入
        if resolved_path:sub(1, 5) == "/ram/" then
            return true
        end

        -- 只允许写入应用目录内的文件
        if resolved_path:sub(1, #app_path) ~= app_path then
            my_env.log.error("check_write_permission", "no permission, operation not allowed:", resolved_path)
            return false
        end

        local relative_path = resolved_path:sub(#app_path + 1)

        -- 禁止写入 libs/、user/、res/ 目录（只读资源）
        if relative_path:sub(1, 5) == "libs/" or
           relative_path:sub(1, 5) == "user/" or
           relative_path:sub(1, 5) == "res/" then
            my_env.log.error("check_write_permission", "no permission, libs/user/res directories are read-only:", resolved_path)
            return false
        end

        -- 禁止写入受保护文件
        local filename = relative_path:match("([^/]+)$")
        if filename == "main.lua" or filename == "meta.json" or filename == "icon.png" then
            my_env.log.error("check_write_permission", "no permission, protected file:", resolved_path)
            return false
        end

        return true
    end

    -- 解析路径并检查写权限（组合函数）
    -- 先解析路径，再检查写权限，任一步骤失败则返回 nil
    -- 当 path 最后一个字符是 / 时，使用 resolve_dir_path 进行目录映射
    local function resolve_write_path(path)
        local resolved
        if path:sub(-1) == "/" then
            resolved = resolve_dir_path(path)
        else
            resolved = resolve_file_path(path)
        end
        if not resolved then return nil end
        if not check_write_permission(resolved) then return nil end
        return resolved
    end

    -- 浅拷贝表（用于复制配置表，避免修改原始表）
    local function copy_table(t, cache)
        if type(t) ~= "table" then return t end
        cache = cache or {}
        if cache[t] then return cache[t] end
        local new = {}
        cache[t] = new
        for k, v in pairs(t) do
            new[copy_table(k, cache)] = copy_table(v, cache)
        end
        return new
    end

    -- 解析路径数组
    -- 批量转换路径数组中的每个路径
    -- check_write 为 true 时检查写权限，否则只做路径转换
    local function resolve_path_array(paths, check_write)
        if type(paths) ~= "table" then return nil end

        local resolved = {}
        for i, path in ipairs(paths) do
            local p = check_write and resolve_write_path(path) or resolve_file_path(path)
            if not p then return nil end
            resolved[i] = p
        end
        return resolved
    end

    -- ==============================================
    -- 【核心包装器工厂】用于快速创建沙箱函数
    -- ==============================================

    -- 安全获取全局库，如果不存在则返回空表
    local function safe_get_global(name)
        local global = _G[name]
        return global or {}
    end

    -- 包装单路径参数函数
    -- 用法：适用于 ftp.push, ftp.pull, fota.file, xmodem.send 等
    -- 参数：orig_func - 原始函数
    --       path_index - 路径参数的位置（从1开始）
    --       check_write - 是否检查写权限
    --       fail_return - 失败时的返回值（默认false）
    local function wrap_single_path(orig_func, path_index, check_write, fail_return)
        if not orig_func then
            return function(...) return fail_return or false end
        end
        return function(...)
            local args = {...}
            local path = args[path_index]

            if type(path) == "string" then
                local resolved = check_write and resolve_write_path(path) or resolve_file_path(path)
                if not resolved then return fail_return or false end

                local new_args = {}
                for i, v in ipairs(args) do
                    new_args[i] = (i == path_index) and resolved or v
                end
                return orig_func(unpack(new_args))
            end

            return orig_func(...)
        end
    end

    -- 包装配置表路径函数
    -- 用法：适用于 http.request, airui.image, airui.font_load 等
    -- 参数：orig_func - 原始函数
    --       path_key - 配置表中路径参数的键名
    --       config_index - 配置表参数的位置（默认1）
    --       check_write - 是否检查写权限
    --       fail_return - 失败时的返回值
    local function wrap_config_path(orig_func, path_key, config_index, check_write, fail_return)
        if not orig_func then
            return function(...) return fail_return or false end
        end
        config_index = config_index or 1
        return function(...)
            local args = {...}
            local config = args[config_index]

            if type(config) == "table" and type(config[path_key]) == "string" then
                local resolved = check_write and resolve_write_path(config[path_key]) or resolve_file_path(config[path_key])
                if not resolved then return fail_return or false end

                local new_config = copy_table(config)
                new_config[path_key] = resolved
                return orig_func(new_config, select(config_index + 1, ...))
            end

            return orig_func(...)
        end
    end

    -- 包装双路径参数函数
    -- 用法：适用于 os.rename, ymodem.create 等
    -- 参数：orig_func - 原始函数
    --       path1_index - 第一个路径参数的位置
    --       path2_index - 第二个路径参数的位置
    --       check_write1 - 第一个路径是否检查写权限
    --       check_write2 - 第二个路径是否检查写权限
    --       fail_return - 失败时的返回值
    local function wrap_dual_path(orig_func, path1_index, path2_index, check_write1, check_write2, fail_return)
        if not orig_func then
            return function(...) return fail_return or false end
        end
        return function(...)
            local args = {...}
            local path1 = args[path1_index]
            local path2 = args[path2_index]

            if type(path1) == "string" and type(path2) == "string" then
                local resolved1 = check_write1 and resolve_write_path(path1) or resolve_file_path(path1)
                local resolved2 = check_write2 and resolve_write_path(path2) or resolve_file_path(path2)
                if not resolved1 or not resolved2 then return fail_return or false end

                local new_args = {}
                for i, v in ipairs(args) do
                    if i == path1_index then new_args[i] = resolved1
                    elseif i == path2_index then new_args[i] = resolved2
                    else new_args[i] = v end
                end
                return orig_func(unpack(new_args))
            end

            return orig_func(...)
        end
    end

    -- ==============================================
    -- 【沙箱库定义】使用包装器快速创建沙箱函数
    -- ==============================================

    -- io 库
    -- 功能：包装所有 io 函数，支持路径转换和写权限检查
    my_env.io = setmetatable({}, { __index = _G.io })

    -- 打开文件，根据模式检查读/写权限
    my_env.io.open = function(path, mode)
        local resolved = resolve_file_path(path)
        if not resolved then return nil end
        if mode and (mode:find("w") or mode:find("a")) then
            if not check_write_permission(resolved) then return nil end
        end
        return io.open(resolved, mode)
    end

    -- 检查文件是否存在
    my_env.io.exists = function(path)
        local resolved = resolve_file_path(path)
        return resolved and io.exists(resolved) or false
    end

    -- 获取文件大小
    my_env.io.fileSize = function(path)
        local resolved = resolve_file_path(path)
        return resolved and io.fileSize(resolved) or nil
    end

    -- 读取文件内容
    my_env.io.readFile = function(path)
        local resolved = resolve_file_path(path)
        return resolved and io.readFile(resolved) or nil
    end

    -- 写入文件内容（需要写权限）
    my_env.io.writeFile = function(path, data)
        local resolved = resolve_write_path(path)
        return resolved and io.writeFile(resolved, data) or nil
    end

    -- 创建目录（需要写权限）
    my_env.io.mkdir = function(path)
        local resolved = resolve_write_path(path)
        return resolved and io.mkdir(resolved) or nil
    end

    -- 删除目录（需要写权限）
    my_env.io.rmdir = function(path)
        local resolved = resolve_write_path(path)
        return resolved and io.rmdir(resolved) or nil
    end

    -- 列出目录内容
    -- 使用 resolve_dir_path 进行目录映射，确保目录路径正确解析
    my_env.io.lsdir = function(path, ...)
        local resolved = resolve_dir_path(path)
        if resolved then
            local success, data = io.lsdir(resolved, ...)
            if success and type(data) == "table" and path:sub(1,7) == "/luadb/" then
                local new_data = {}
                for i, item in ipairs(data) do
                    if item.name ~= "data" then
                        table.insert(new_data, item)
                    end
                end
                return success, new_data
            else
                return success, data
            end
        end
        return nil
    end

    -- fs 库
    -- 功能：包装 fs.fsize，复用 io.fileSize
    my_env.fs = setmetatable({}, { __index = _G.fs })
    my_env.fs.fsize = my_env.io.fileSize

    -- audio 库
    -- 功能：包装 audio.play 和 audio.record，支持音频文件路径转换
    my_env.audio = setmetatable({}, { __index = _G.audio })

    -- 播放音频，支持单个路径或路径数组
    my_env.audio.play = function(id, ...)
        local args = {...}
        if #args == 0 then return audio.play(id) end

        local path_or_table = args[1]

        -- 单个路径：转换后播放
        if type(path_or_table) == "string" then
            local resolved = resolve_file_path(path_or_table)
            if not resolved then return false end
            return audio.play(id, resolved, select(2, ...))
        end

        -- 路径数组：批量转换后播放
        if type(path_or_table) == "table" then
            local resolved = resolve_path_array(path_or_table, false)
            if not resolved then return false end
            return audio.play(id, resolved, select(2, ...))
        end

        return audio.play(id, ...)
    end

    -- 录音，第5个参数为保存路径（需要写权限）
    my_env.audio.record = function(...)
        local args = {...}
        if type(args[5]) == "string" then
            local resolved = resolve_write_path(args[5])
            if not resolved then return false end
            return audio.record(args[1], args[2], args[3], args[4], resolved, select(6, ...))
        end
        return audio.record(...)
    end

    -- camera 库
    -- 功能：包装 camera.capture，支持拍照保存路径转换
    my_env.camera = setmetatable({}, { __index = _G.camera })

    -- 拍照，第2个参数为保存路径（需要写权限）
    my_env.camera.capture = function(...)
        local args = {...}
        if type(args[2]) == "string" then
            local resolved = resolve_write_path(args[2])
            if not resolved then return false end
            return camera.capture(args[1], resolved, select(3, ...))
        end
        return camera.capture(...)
    end

    -- http 库
    -- 功能：包装 http.request，支持下载路径转换
    my_env.http = setmetatable({}, { __index = _G.http })

    -- 处理 opts.dst 参数，将沙箱路径转换为实际路径
    my_env.http.request = function(...)
        local args = {...}
        local opts = args[5]
        if type(opts) == "table" and type(opts.dst) == "string" then
            local resolved = resolve_write_path(opts.dst)
            if not resolved then return -7 end
            local new_opts = copy_table(opts)
            new_opts.dst = resolved
            return http.request(args[1], args[2], args[3], args[4], new_opts, select(6, ...))
        end
        return http.request(...)
    end

    -- httpplus 库
    -- 功能：包装 httpplus.request，支持上传/下载路径转换
    my_env.httpplus = setmetatable({}, { __index = _G.httpplus })

    -- 处理 opts.files 和 opts.bodyfile 参数，将沙箱路径转换为实际路径
    my_env.httpplus.request = function(...)
        local args = {...}
        local opts = args[1]
        if type(opts) ~= "table" then return httpplus.request(...) end

        local new_opts = copy_table(opts)
        local need_resolve = false

        if type(opts.files) == "table" then
            local resolved = {}
            for field, path in pairs(opts.files) do
                if type(path) ~= "string" then return -7 end
                local p = resolve_write_path(path)
                if not p then return -7 end
                resolved[field] = p
            end
            new_opts.files = resolved
            need_resolve = true
        end

        if type(opts.bodyfile) == "string" then
            local resolved = resolve_write_path(opts.bodyfile)
            if not resolved then return -7 end
            new_opts.bodyfile = resolved
            need_resolve = true
        end

        if need_resolve then
            return httpplus.request(new_opts)
        end
        return httpplus.request(...)
    end

    -- ftp 库
    -- 功能：包装 ftp.pull 和 ftp.push，支持路径转换
    local ftp_lib = safe_get_global("ftp")
    my_env.ftp = setmetatable({}, { __index = ftp_lib })
    my_env.ftp.pull = wrap_single_path(ftp_lib.pull, 1, false, false)
    my_env.ftp.push = wrap_single_path(ftp_lib.push, 1, true, false)

    -- fota 库
    -- 功能：包装 fota.file，支持路径转换
    local fota_lib = safe_get_global("fota")
    my_env.fota = setmetatable({}, { __index = fota_lib })
    my_env.fota.file = wrap_single_path(fota_lib.file, 1, false, false)

    -- ymodem 库
    -- 功能：包装 ymodem.create，支持路径转换
    local ymodem_lib = safe_get_global("ymodem")
    my_env.ymodem = setmetatable({}, { __index = ymodem_lib })

    -- 处理目录和文件名参数，将沙箱路径转换为实际路径
    my_env.ymodem.create = function(...)
        local args = {...}
        if type(args[1]) == "string" and type(args[2]) == "string" then
            local full_path = args[1] .. args[2]
            local resolved = resolve_write_path(full_path)
            if not resolved then return false end
            local new_dir = resolved:match("^(.*/)[^/]+$")
            return ymodem_lib.create and ymodem_lib.create(new_dir, args[2])
        end
        return ymodem_lib.create and ymodem_lib.create(...) or false
    end

    -- xmodem 库
    -- 功能：包装 xmodem.send，支持路径转换
    local xmodem_lib = safe_get_global("xmodem")
    my_env.xmodem = setmetatable({}, { __index = xmodem_lib })
    my_env.xmodem.send = wrap_single_path(xmodem_lib.send, 3, false, false)

    -- airui 库
    -- 功能：包装 airui.image 和 airui.animimg，支持图片路径转换
    --[[
        airui.image 沙箱包装说明：
        1. 调用时：检查参数中的 src 字段，做路径转换（/luadb/xxx -> <app_path>/xxx）
        2. 返回值：创建一个 wrapper table，元表拦截 set_src 方法做路径转换，其他方法正常代理
        3. 原理：
           - 返回 wrapper 而不是 raw_obj，因为 wrapper 可以自定义元表
           - 访问 set_src 时：拦截并转换路径
           - 访问其他方法时：从原始 userdata 获取，绑定正确的 self
           - 原始 userdata 的 __index 可能是函数或表，需要分别处理
    ]]
    local airui_lib = safe_get_global("airui")
    my_env.airui = setmetatable({}, { __index = airui_lib })
    my_env.airui.image = function(...)
        local args = {...}
        -- 参数转换：检查第一个参数是否为 table 且包含 src 字段
        -- 将沙箱路径 /luadb/xxx 转换为实际路径 <app_path>/xxx
        if type(args[1]) == "table" and type(args[1].src) == "string" then
            local new_config = copy_table(args[1])
            new_config.src = resolve_file_path(args[1].src)
            if not new_config.src then return false end
            args[1] = new_config
        end

        -- 调用原始 airui.image 获取 userdata 对象
        local raw_obj = airui_lib.image(unpack(args))
        if type(raw_obj) ~= "userdata" then return raw_obj end

        -- 保存原始 userdata 的元表，用于后续代理其他方法
        local orig_mt = debug.getmetatable(raw_obj)
        local orig_index = orig_mt and orig_mt.__index

        -- 创建 wrapper 对象，通过元表拦截方法调用
        local wrapper = {}
        local wrapper_mt = {
            -- __index 拦截属性/方法访问
            __index = function(_, key)
                -- 特殊处理 set_src：沙箱内传入 /luadb/xxx，需要转换为实际路径
                if key == "set_src" then
                    return function(_, src)
                        local resolved = resolve_file_path(src)
                        if not resolved then return false end
                        return raw_obj:set_src(resolved)
                    end
                end

                -- 代理其他方法：从原始 userdata 的元表获取
                if orig_index then
                    local v
                    -- orig_index 可能是函数（如 Lua 元方法）或 table（如类方法表）
                    if type(orig_index) == "function" then
                        v = orig_index(raw_obj, key)
                    elseif type(orig_index) == "table" then
                        v = orig_index[key]
                    end

                    -- 如果是函数，需要包装一下：
                    -- 原始调用：img:set_opacity(255) -> v(img, 255)
                    -- 包装后：v(raw_obj, 255)，因为原始函数期望的 self 是 raw_obj 而不是 wrapper
                    if type(v) == "function" then
                        local raw = raw_obj
                        return function(self, ...) return v(raw, ...) end
                    end
                    return v
                end
            end
        }
        setmetatable(wrapper, wrapper_mt)
        return wrapper
    end
    my_env.airui.font_load = wrap_config_path(airui_lib.font_load, "path", 1, false, false)

    --[[
        airui.animimg 沙箱包装说明：
        与 airui.image 类似，但处理的是文件路径数组（frames）
        1. 调用时：检查参数中的 frames 字段，做路径数组转换
        2. 返回值：创建 wrapper，元表拦截 set_src 做路径数组转换，其他方法正常代理
    ]]
    my_env.airui.animimg = function(...)
        local args = {...}
        local config = args[1]
        local raw_obj

        -- 参数转换：检查第一个参数是否为 table 且包含 frames 字段（文件路径数组）
        if type(config) == "table" and type(config.frames) == "table" then
            local resolved = resolve_path_array(config.frames, false)
            if not resolved then return false end
            local new_config = copy_table(config)
            new_config.frames = resolved
            raw_obj = airui_lib.animimg(new_config)
        else
            raw_obj = airui_lib.animimg(...)
        end

        if type(raw_obj) ~= "userdata" then return raw_obj end

        -- 保存原始 userdata 的元表，用于后续代理其他方法
        local orig_mt = debug.getmetatable(raw_obj)
        local orig_index = orig_mt and orig_mt.__index

        -- 创建 wrapper 对象，通过元表拦截方法调用
        local wrapper = {}
        local wrapper_mt = {
            __index = function(_, key)
                -- 特殊处理 set_src：接收文件路径数组，做路径数组转换
                if key == "set_src" then
                    return function(_, frames)
                        if type(frames) == "table" then
                            local resolved = resolve_path_array(frames, false)
                            if not resolved then return false end
                            return raw_obj:set_src(resolved)
                        end
                        return raw_obj:set_src(frames)
                    end
                end

                -- 代理其他方法：从原始 userdata 的元表获取
                if orig_index then
                    local v
                    if type(orig_index) == "function" then
                        v = orig_index(raw_obj, key)
                    elseif type(orig_index) == "table" then
                        v = orig_index[key]
                    end

                    if type(v) == "function" then
                        local raw = raw_obj
                        return function(self, ...) return v(raw, ...) end
                    end
                    return v
                end
            end
        }
        setmetatable(wrapper, wrapper_mt)
        return wrapper
    end

    -- excloud 库
    -- 功能：包装 excloud.upload_image 和 excloud.upload_audio，支持路径转换
    local function airui_round_value(v)
        if type(v) ~= "number" then return v end
        if v >= 0 then
            return math.floor(v + 0.5)
        end
        return math.ceil(v - 0.5)
    end

    local function airui_load_app_resolution()
        local meta_path = app_path .. "meta.json"
        local content = io.readFile(meta_path)
        if not content then
            return 480, 800, nil
        end
        local ok, meta = pcall(json.decode, content)
        if not ok or type(meta) ~= "table" or type(meta.resolution) ~= "string" then
            return 480, 800, nil
        end
        local w, h = meta.resolution:match("(%d+)[xX%*](%d+)")
        w = tonumber(w)
        h = tonumber(h)
        if not w or not h or w <= 0 or h <= 0 then
            return 480, 800, nil
        end
        local display_zoom = meta.display_zoom
        if type(display_zoom) ~= "string" then
            display_zoom = nil
        end
        return w, h, display_zoom
    end

    local function airui_load_screen_status()
        local size = airui_lib.status and airui_lib.status() or nil
        if type(size) == "table" then
            local rotation = tonumber(size.rotation) or 0
            local w = tonumber(size.w) or 480
            local h = tonumber(size.h) or 800
            return rotation, w, h
        end
        -- 回退方案：使用 lcd.getSize() 和 airui.get_rotation()
        local lcd = _G.lcd
        if lcd and lcd.getSize then
            local phys_w, phys_h = lcd.getSize()
            local rotation = airui_lib.get_rotation and airui_lib.get_rotation() or 0
            -- 根据旋转计算实际显示宽高
            local screen_w, screen_h
            if rotation == 0 or rotation == 180 then
                screen_w, screen_h = phys_w, phys_h
            else
                screen_w, screen_h = phys_h, phys_w
            end
            return rotation, screen_w, screen_h
        end
        -- 最终回退：默认值
        return 0, 480, 800
    end

    local function airui_init_adapt_ctx()
        local ui_w, ui_h, display_zoom = airui_load_app_resolution()
        local rotation, screen_w, screen_h = airui_load_screen_status()
        local ctx = {
            ui_w = ui_w,
            ui_h = ui_h,
            screen_w = screen_w,
            screen_h = screen_h,
            rotation = rotation,
            display_zoom = display_zoom,
            ratio_x = ui_w / screen_w,
            ratio_y = ui_h / screen_h,
            scale_x = screen_w / ui_w,
            scale_y = screen_h / ui_h
        }
        ctx.scale_min = math.min(ctx.scale_x, ctx.scale_y)
        -- 如果应用声明了 display_zoom: "adaptive"，则禁用 exapp 的缩放适配
        if display_zoom == "adaptive" then
            ctx.adapt_enabled = false
        else
            ctx.adapt_enabled = not (ctx.ui_w == ctx.screen_w and ctx.ui_h == ctx.screen_h)
        end
        my_env.log.info("exapp.airui", app_path, "ui", ctx.ui_w, ctx.ui_h, "screen", ctx.screen_w, ctx.screen_h,
            "rotation", ctx.rotation, "display_zoom", display_zoom, "scale", ctx.scale_x, ctx.scale_y, "adapt", ctx.adapt_enabled)
        return ctx
    end

    local airui_ctx = airui_init_adapt_ctx()

    local function airui_scale_x(v)
        if type(v) ~= "number" or not airui_ctx.adapt_enabled then return v end
        local result = airui_round_value(v * airui_ctx.scale_x)
        -- my_env.log.info("exapp.airui.scale", app_path, "scale_x", v, "*", airui_ctx.scale_x, "=", result)
        return result
    end

    local function airui_scale_y(v)
        if type(v) ~= "number" or not airui_ctx.adapt_enabled then return v end
        local result = airui_round_value(v * airui_ctx.scale_y)
        -- my_env.log.info("exapp.airui.scale", app_path, "scale_y", v, "*", airui_ctx.scale_y, "=", result)
        return result
    end

    local function airui_scale_min(v)
        if type(v) ~= "number" or not airui_ctx.adapt_enabled then return v end
        local result = airui_round_value(v * airui_ctx.scale_min)
        -- my_env.log.info("exapp.airui.scale", app_path, "scale_min", v, "*", airui_ctx.scale_min, "=", result)
        return result
    end

    local function airui_adapt_w(v)
        if type(v) ~= "number" or not airui_ctx.adapt_enabled then return v end
        if v == airui_ctx.ui_w then
            -- my_env.log.info("exapp.airui.adapt", app_path, "adapt_w fullscreen", v, "->", airui_ctx.screen_w)
            return airui_ctx.screen_w
        end
        return airui_scale_x(v)
    end

    local function airui_adapt_h(v)
        if type(v) ~= "number" or not airui_ctx.adapt_enabled then return v end
        if v == airui_ctx.ui_h then
            -- my_env.log.info("exapp.airui.adapt", app_path, "adapt_h fullscreen", v, "->", airui_ctx.screen_h)
            return airui_ctx.screen_h
        end
        return airui_scale_y(v)
    end

    local function airui_scale_array(arr, scaler)
        if type(arr) ~= "table" then return arr end
        local out = {}
        for i, v in ipairs(arr) do
            out[i] = scaler(v)
        end
        return out
    end

    local function airui_style_scale(style)
        if type(style) ~= "table" then return style end
        local out = copy_table(style)
        local min_keys = {
            radius = true, border_width = true, pad = true, pad_top = true, pad_bottom = true,
            pad_left = true, pad_right = true, header_pad = true, header_height = true,
            header_font_size = true, content_pad = true, close_btn_radius = true,
            font_size = true, cell_font_size = true, cell_border_width = true,
            point_radius = true, bar_group_gap = true, bar_series_gap = true,
            bar_radius = true, tabbar_size = true, tab_font_size = true, line_width = true
        }
        for k, v in pairs(out) do
            if min_keys[k] and type(v) == "number" then
                out[k] = airui_scale_min(v)
            elseif k == "pivot" and type(v) == "table" then
                out[k] = { x = airui_scale_x(v.x), y = airui_scale_y(v.y) }
            elseif k == "col_width" then
                if type(v) == "number" then
                    out[k] = airui_scale_x(v)
                elseif type(v) == "table" then
                    out[k] = airui_scale_array(v, airui_scale_x)
                end
            elseif k == "row_height" then
                if type(v) == "number" then
                    out[k] = airui_scale_y(v)
                elseif type(v) == "table" then
                    out[k] = airui_scale_array(v, airui_scale_y)
                end
            elseif (k == "style" or k == "page_style") and type(v) == "table" then
                out[k] = airui_style_scale(v)
            end
        end
        return out
    end

    local function airui_default_config(component_name, config)
        -- 根据组件类型提供默认值
        local defaults = {}
        if component_name == "image" then
            -- image.zoom默认值256
            if config.zoom == nil then
                defaults.zoom = 256
            end
        elseif component_name == "qrcode" then
            -- qrcode.size默认值160
            if config.size == nil then
                defaults.size = 160
            end
        elseif component_name == "keyboard" then
            -- keyboard.preview_height默认值40
            if config.preview_height == nil then
                defaults.preview_height = 40
            end
        elseif component_name == "chart" then
            -- chart.bar_group_gap默认值2, bar_series_gap默认值2, bar_radius默认值0
            if config.bar_group_gap == nil then
                defaults.bar_group_gap = 2
            end
            if config.bar_series_gap == nil then
                defaults.bar_series_gap = 2
            end
            if config.bar_radius == nil then
                defaults.bar_radius = 0
            end
        elseif component_name == "label" then
            -- label.w默认值100, label.h默认值40, label.font_size默认值14
            if config.w == nil then
                defaults.w = 100
            end
            if config.h == nil then
                defaults.h = 40
            end
            if config.font_size == nil then
                defaults.font_size = 14
            end
        elseif component_name == "button" then
            -- button.w默认值100, button.h默认值40, button.font_size默认值14
            if config.w == nil then
                defaults.w = 100
            end
            if config.h == nil then
                defaults.h = 40
            end
            if config.font_size == nil then
                defaults.font_size = 14
            end
            -- button.style.radius默认值10, button.style.border_width默认值2
            if config.style == nil then
                config.style = {}
            end
            if config.style.radius == nil then
                defaults.style = defaults.style or {}
                defaults.style.radius = 10
            end
            if config.style.border_width == nil then
                defaults.style = defaults.style or {}
                defaults.style.border_width = 2
            end
        elseif component_name == "container" then
            -- container.radius默认值0
            if config.radius == nil then
                defaults.radius = 0
            end
        elseif component_name == "tabview" then
            -- tabview.page_style.tabbar_size默认值40
            if config.page_style == nil then
                config.page_style = {}
            end
            if config.page_style.tabbar_size == nil then
                defaults.page_style = defaults.page_style or {}
                defaults.page_style.tabbar_size = 40
            end
        elseif component_name == "table" then
            -- table默认列宽和行高（根据w/h/rows/cols动态生成）
            local w = config.w or 200
            local h = config.h or 120
            local rows = config.rows or 4
            local cols = config.cols or 3
            if config.col_width == nil then
                -- 生成均匀列宽数组
                local col_width = math.floor(w / cols + 0.5)
                defaults.col_width = {}
                for i = 1, cols do
                    defaults.col_width[i] = col_width
                end
            end
            if config.row_height == nil then
                -- 生成均匀行高数组
                local row_height = math.floor(h / rows + 0.5)
                defaults.row_height = {}
                for i = 1, rows do
                    defaults.row_height[i] = row_height
                end
            end
        end
        return defaults
    end

    local function airui_merge_defaults(config, defaults)
        if type(config) ~= "table" then config = {} end
        if type(defaults) ~= "table" then return config end
        for k, v in pairs(defaults) do
            if config[k] == nil then
                config[k] = copy_table(v)
            elseif type(config[k]) == "table" and type(v) == "table" then
                config[k] = airui_merge_defaults(config[k], v)
            end
        end
        return config
    end

    local function airui_resolve_paths(component_name, config)
        if type(config) ~= "table" then return config end
        local new_config = copy_table(config)
        if component_name == "image" or component_name == "lottie" or component_name == "video" then
            if type(new_config.src) == "string" then
                new_config.src = resolve_file_path(new_config.src)
                if not new_config.src then return nil end
            end
        elseif component_name == "animimg" then
            if type(new_config.frames) == "table" then
                new_config.frames = resolve_path_array(new_config.frames, false)
                if not new_config.frames then return nil end
            end
        end
        return new_config
    end

    local function airui_adapt_config(component_name, config)
        if type(config) ~= "table" then return config end
        local new_config = copy_table(config)
        new_config = airui_merge_defaults(new_config, airui_default_config(component_name, config))
        -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "adapt_enabled", airui_ctx.adapt_enabled, "input", config, "merged", new_config)
        if not airui_ctx.adapt_enabled then
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "bypass adapt")
            return new_config
        end
        -- 基础参数：x、y、w、h、font_size
        if type(new_config.x) == "number" then
            local old_x = new_config.x
            new_config.x = airui_scale_x(new_config.x)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "x", old_x, "->", new_config.x)
        end
        if type(new_config.y) == "number" then
            local old_y = new_config.y
            new_config.y = airui_scale_y(new_config.y)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "y", old_y, "->", new_config.y)
        end
        if type(new_config.w) == "number" then
            local old_w = new_config.w
            new_config.w = airui_adapt_w(new_config.w)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "w", old_w, "->", new_config.w)
        end
        if type(new_config.h) == "number" then
            local old_h = new_config.h
            new_config.h = airui_adapt_h(new_config.h)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "h", old_h, "->", new_config.h)
        end
        if type(new_config.font_size) == "number" then
            local old_fs = new_config.font_size
            new_config.font_size = airui_scale_min(new_config.font_size)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "font_size", old_fs, "->", new_config.font_size)
        end
        -- 图片大小参数
        if type(new_config.zoom) == "number" then
            local old_zoom = new_config.zoom
            new_config.zoom = airui_scale_min(new_config.zoom)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "zoom", old_zoom, "->", new_config.zoom)
        end
        -- 二维码大小参数
        if type(new_config.size) == "number" then
            local old_size = new_config.size
            new_config.size = airui_scale_min(new_config.size)
            -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "size", old_size, "->", new_config.size)
        end
        -- 其他通用参数：radius, border_width, tabbar_size, bar_radius, bar_group_gap, bar_series_gap
        local scale_min_params = {"radius", "border_width", "tabbar_size", "bar_radius", "bar_group_gap", "bar_series_gap", "preview_height"}
        for _, param in ipairs(scale_min_params) do
            if type(new_config[param]) == "number" then
                local old_val = new_config[param]
                new_config[param] = airui_scale_min(new_config[param])
                -- my_env.log.info("exapp.airui.adapt", app_path, component_name, param, old_val, "->", new_config[param])
            end
        end
        -- 表格参数：col_width, row_height
        if type(new_config.col_width) == "number" then
            new_config.col_width = airui_scale_x(new_config.col_width)
        elseif type(new_config.col_width) == "table" then
            new_config.col_width = airui_scale_array(new_config.col_width, airui_scale_x)
        end
        if type(new_config.row_height) == "number" then
            new_config.row_height = airui_scale_y(new_config.row_height)
        elseif type(new_config.row_height) == "table" then
            new_config.row_height = airui_scale_array(new_config.row_height, airui_scale_y)
        end
        -- 样式参数：style, page_style
        if type(new_config.style) == "table" then
            new_config.style = airui_style_scale(new_config.style)
        end
        if type(new_config.page_style) == "table" then
            new_config.page_style = airui_style_scale(new_config.page_style)
        end
        -- pivot参数：x按scale_x，y按scale_y
        if type(new_config.pivot) == "table" then
            local pivot = new_config.pivot
            if type(pivot.x) == "number" then
                pivot.x = airui_scale_x(pivot.x)
            end
            if type(pivot.y) == "number" then
                pivot.y = airui_scale_y(pivot.y)
            end
        end
        -- 其他参数暂不处理
        -- my_env.log.info("exapp.airui.adapt", app_path, component_name, "output", new_config)
        return new_config
    end

    local function airui_userdata_member(raw_obj, orig_index, key)
        if not orig_index then return nil end
        if type(orig_index) == "function" then
            return orig_index(raw_obj, key)
        elseif type(orig_index) == "table" then
            return orig_index[key]
        end
        return nil
    end

    local function airui_wrap_component(component_name, raw_obj)
        if type(raw_obj) ~= "userdata" then return raw_obj end
        local orig_mt = debug.getmetatable(raw_obj)
        local orig_index = orig_mt and orig_mt.__index
        local wrapper = {}
        setmetatable(wrapper, {
            __index = function(_, key)
                if key == "__raw" then return raw_obj end
                if key == "set_src" and (component_name == "image" or component_name == "lottie" or component_name == "video") then
                    return function(_, src)
                        local resolved = resolve_file_path(src)
                        if not resolved then return false end
                        return raw_obj:set_src(resolved)
                    end
                end
                if key == "set_src" and component_name == "animimg" then
                    return function(_, frames)
                        if type(frames) == "table" then
                            local resolved = resolve_path_array(frames, false)
                            if not resolved then return false end
                            return raw_obj:set_src(resolved)
                        end
                        return raw_obj:set_src(frames)
                    end
                end
                if key == "set_pos" then
                    return function(_, x, y) return raw_obj:set_pos(airui_scale_x(x), airui_scale_y(y)) end
                end
                if key == "move" then
                    return function(_, dx, dy) return raw_obj:move(airui_scale_x(dx), airui_scale_y(dy)) end
                end
                if key == "set_font_size" then
                    return function(_, size) return raw_obj:set_font_size(airui_scale_min(size)) end
                end
                if key == "set_zoom" then
                    return function(_, zoom) return raw_obj:set_zoom(airui_scale_min(zoom)) end
                end
                if key == "set_size" and component_name == "qrcode" then
                    return function(_, size) return raw_obj:set_size(airui_scale_min(size)) end
                end
                if key == "set_col_width" and component_name == "table" then
                    return function(_, col, width) return raw_obj:set_col_width(col, airui_scale_x(width)) end
                end
                if key == "set_row_height" and component_name == "table" then
                    return function(_, row, height) return raw_obj:set_row_height(row, airui_scale_y(height)) end
                end
                if key == "set_cell_style" and component_name == "table" then
                    return function(_, axis, index, style) return raw_obj:set_cell_style(axis, index, airui_style_scale(style)) end
                end
                if (key == "set_style" or key == "set_stype") and
                    (component_name == "button" or component_name == "table" or component_name == "spinner" or component_name == "win") then
                    return function(_, style)
                        local method = airui_userdata_member(raw_obj, orig_index, key)
                        if type(method) ~= "function" then return false end
                        return method(raw_obj, airui_style_scale(style))
                    end
                end
                if key == "set_bar_gap" and component_name == "chart" then
                    return function(_, group_gap, series_gap)
                        return raw_obj:set_bar_gap(airui_scale_min(group_gap), airui_scale_min(series_gap))
                    end
                end
                if key == "set_bar_radius" and component_name == "chart" then
                    return function(_, radius) return raw_obj:set_bar_radius(airui_scale_min(radius)) end
                end
                if key == "get_content" and component_name == "tabview" then
                    return function(_, index) return airui_wrap_component("container", raw_obj:get_content(index)) end
                end
                if key == "add_tab" and component_name == "tabview" then
                    return function(_, title, content)
                        if type(content) == "table" and content.__raw then
                            content = content.__raw
                        end
                        return airui_wrap_component("container", raw_obj:add_tab(title, content))
                    end
                end
                if key == "get_keyboard" and component_name == "textarea" then
                    return function(_) return airui_wrap_component("keyboard", raw_obj:get_keyboard()) end
                end
                if key == "get_target" and component_name == "keyboard" then
                    return function(_) return airui_wrap_component("textarea", raw_obj:get_target()) end
                end
                if key == "attach_keyboard" and component_name == "textarea" then
                    return function(_, keyboard)
                        if type(keyboard) == "table" and keyboard.__raw then
                            keyboard = keyboard.__raw
                        end
                        return raw_obj:attach_keyboard(keyboard)
                    end
                end
                if key == "set_target" and component_name == "keyboard" then
                    return function(_, textarea)
                        if type(textarea) == "table" and textarea.__raw then
                            textarea = textarea.__raw
                        end
                        return raw_obj:set_target(textarea)
                    end
                end
                local v = airui_userdata_member(raw_obj, orig_index, key)
                if type(v) == "function" then
                    return function(_, ...) return v(raw_obj, ...) end
                end
                return v
            end
        })
        return wrapper
    end

    local function airui_install_constructor(component_name)
        local orig_func = airui_lib[component_name]
        if type(orig_func) ~= "function" then
            my_env.log.info("exapp.airui.install", app_path, component_name, "no original function")
            return
        end
        my_env.airui[component_name] = function(...)
            -- my_env.log.info("exapp.airui.constructor", app_path, component_name, "called with", ...)
            local args = {...}
            if type(args[1]) == "table" then
                -- 如果parent是包装对象，提取原始对象
                if args[1].parent then
                    if type(args[1].parent) == "table" and args[1].parent.__raw then
                        args[1].parent = args[1].parent.__raw
                    end
                end
                -- 如果keyboard是包装对象，提取原始对象（textarea等需要绑定键盘）
                if args[1].keyboard then
                    if type(args[1].keyboard) == "table" and args[1].keyboard.__raw then
                        args[1].keyboard = args[1].keyboard.__raw
                    end
                end
                -- 如果target是包装对象，提取原始对象（keyboard创建时可指定target）
                if args[1].target then
                    if type(args[1].target) == "table" and args[1].target.__raw then
                        args[1].target = args[1].target.__raw
                    end
                end
                local new_config = airui_resolve_paths(component_name, args[1])
                -- my_env.log.info("exapp.airui.constructor", app_path, component_name, "after path resolve", new_config)
                if args[1] and not new_config then
                    -- my_env.log.warn("exapp.airui.constructor", app_path, component_name, "path resolve failed")
                    return false
                end
                args[1] = airui_adapt_config(component_name, new_config)
                -- my_env.log.info("exapp.airui.constructor", app_path, component_name, "after adapt", args[1])
            end
            local raw_obj = orig_func(unpack(args))
            -- my_env.log.info("exapp.airui.constructor", app_path, component_name, "raw_obj type", type(raw_obj))
            if type(raw_obj) ~= "userdata" then return raw_obj end
            return airui_wrap_component(component_name, raw_obj)
        end
    end

    for _, component_name in ipairs({
        "label", "image", "animimg", "button", "container", "bar", "dropdown",
        "switch", "table", "keyboard", "textarea", "tabview", "chart",
        "qrcode", "win", "msgbox", "shape", "spinner", "video", "lottie"
    }) do
        airui_install_constructor(component_name)
    end

    my_env.airui.font_load = wrap_config_path(airui_lib.font_load, "path", 1, false, false)

    local excloud_lib = safe_get_global("excloud")
    my_env.excloud = setmetatable({}, { __index = excloud_lib })
    my_env.excloud.upload_image = wrap_single_path(excloud_lib.upload_image, 1, false, false)
    my_env.excloud.upload_audio = wrap_single_path(excloud_lib.upload_audio, 1, false, false)

    -- exaudio 库
    -- 功能：包装 exaudio.play_start，支持音频文件路径转换
    local exaudio_lib = safe_get_global("exaudio")
    my_env.exaudio = setmetatable({}, { __index = exaudio_lib })

    -- 处理 config.content 参数，支持单个路径或路径数组
    my_env.exaudio.play_start = function(...)
        local args = {...}
        local config = args[1]

        if type(config) == "table" and config.type == 0 then
            local new_config = copy_table(config)

            if type(config.content) == "string" then
                local resolved = resolve_file_path(config.content)
                if not resolved then return false end
                new_config.content = resolved
            elseif type(config.content) == "table" then
                local resolved = resolve_path_array(config.content, false)
                if not resolved then return false end
                new_config.content = resolved
            end

            return exaudio_lib.play_start(new_config)
        end

        return exaudio_lib.play_start(...)
    end

    my_env.exaudio.record_start = wrap_config_path(exaudio_lib.record_start, "path", 1, true, false)

    -- excamera 库
    -- 功能：包装 excamera.open 和 excamera.video，支持视频文件路径转换
    local excamera_lib = safe_get_global("excamera")
    my_env.excamera = setmetatable({}, { __index = excamera_lib })

    -- 处理 config.save_path 参数，将沙箱路径转换为实际路径
    my_env.excamera.open = function(...)
        local args = {...}
        local config = args[1]

        if type(config) == "table" and type(config.save_path) == "string" then
            if config.save_path:lower() ~= "zbuff" then
                local resolved = resolve_write_path(config.save_path)
                if not resolved then return false end
                local new_config = copy_table(config)
                new_config.save_path = resolved
                return excamera_lib.open(new_config)
            end
        end

        return excamera_lib.open(...)
    end

    my_env.excamera.video = wrap_single_path(excamera_lib.video, 1, true, false)

    -- os 库
    -- 功能：包装 os.remove 和 os.rename，支持路径转换
    my_env.os = setmetatable({}, { __index = _G.os })
    my_env.os.remove = wrap_single_path(os.remove, 1, true, nil)
    my_env.os.rename = wrap_dual_path(os.rename, 1, 2, false, true, nil)

    -- sys 库
    -- 功能：禁用 sys.run()，使用沙箱专用的订阅管理
    my_env.sys = setmetatable({}, { __index = _G.sys })

    -- 禁用 sys.run()，防止应用接管系统控制权
    my_env.sys.run = function()
        my_env.log.info("sys.run() disabled in sandbox")
    end

    -- 使用沙箱专用的订阅管理函数
    my_env.sys.subscribe = sandbox_subscribe
    my_env.sys.unsubscribe = sandbox_unsubscribe

    -- ==============================================
    -- fskv 库（键名隔离）
    -- 功能：为每个应用的 fskv 键自动添加前缀，避免键名冲突
    -- 例如：应用 app_hello 的键 "config" 实际存储为 "app_hello_config"
    -- ==============================================

    -- 为键添加应用前缀
    local function wrap_fskv_key(key)
        return fskv_key_prefix .. key
    end

    my_env.fskv = setmetatable({}, { __index = _G.fskv })

    -- 设置键值对，键名自动添加前缀
    my_env.fskv.set = function(key, value, ...)
        local wrapped_key = wrap_fskv_key(key)
        return _G.fskv.set(wrapped_key, value, ...)
    end

    -- 设置哈希表键值对，键名自动添加前缀
    my_env.fskv.sett = function(key, value, ...)
        local wrapped_key = wrap_fskv_key(key)
        local wrapped_skey = wrap_fskv_key(skey)
        return _G.fskv.sett(wrapped_key, wrapped_skey, ...)
    end

    -- 获取键值，键名自动添加前缀
    my_env.fskv.get = function(key)
        local wrapped_key = wrap_fskv_key(key)
        return _G.fskv.get(wrapped_key)
    end

    -- 删除键，键名自动添加前缀
    my_env.fskv.del = function(key, ...)
        local wrapped_key = wrap_fskv_key(key)
        return _G.fskv.del(wrapped_key, ...)
    end

    -- 遍历键，只返回当前应用前缀的键（去掉前缀后返回）
    my_env.fskv.next = function(iter)
        while true do
            local key = _G.fskv.next(iter)
            if not key then
                return nil
            end
            -- 只返回当前应用前缀的键
            if key:find("^" .. fskv_key_prefix, 1) then
                local original_key = key:sub(#fskv_key_prefix + 1)
                return original_key
            end
        end
    end

    -- 清空当前应用的所有键值对
    my_env.fskv.clear = function()
        local iter = _G.fskv.iter()
        local keys_to_delete = {}
        -- 收集所有当前应用前缀的键
        while true do
            local key = _G.fskv.next(iter)
            if not key then
                break
            end
            if key:find("^" .. fskv_key_prefix, 1) then
                table.insert(keys_to_delete, key)
            end
        end
        -- 删除收集到的键
        for _, key in ipairs(keys_to_delete) do
            _G.fskv.del(key)
        end
    end

    -- ==============================================
    -- exwin 库（窗口管理）
    -- 功能：跟踪应用打开的窗口，窗口全部关闭时自动退出应用
    -- ==============================================
    local sandbox_win_ids = {}
    local global_exwin = exwin

    -- 检查窗口数量，如果为0则自动退出应用
    local function check_and_exit_if_no_windows()
        if #sandbox_win_ids == 0 then
            my_env.log.info("exwin", "window count is 0, auto exit app")
            my_env.exapp.close()
        end
    end

    my_env.exwin = setmetatable({}, { __index = global_exwin })

    -- 打开窗口，记录窗口ID
    my_env.exwin.open = function(config)
        local win_id = global_exwin.open(config)
        if win_id then
            table.insert(sandbox_win_ids, win_id)
            my_env.log.info("exwin.open", "window opened, ID:", win_id, "window count:", #sandbox_win_ids)
        end
        return win_id
    end

    -- 关闭窗口，从记录中移除，检查是否需要退出应用
    my_env.exwin.close = function(win_id)
        global_exwin.close(win_id)
        for i, id in ipairs(sandbox_win_ids) do
            if id == win_id then
                table.remove(sandbox_win_ids, i)
                break
            end
        end
        my_env.log.info("exwin.close", "window closed, ID:", win_id, "window count:", #sandbox_win_ids)
        check_and_exit_if_no_windows()
    end

    -- 返回首页，清空窗口记录，检查是否需要退出应用
    my_env.exwin.return_idle = function()
        global_exwin.return_idle()
        sandbox_win_ids = {}
        my_env.log.info("exwin.return_idle", "returned to home, window count:", #sandbox_win_ids)
        check_and_exit_if_no_windows()
    end

    -- ==============================================
    -- 【应用执行】加载并运行应用主文件
    -- ==============================================

    -- 设置当前文件环境为沙箱环境
    local _ENV = my_env

    -- 加载并执行应用的主文件main.lua
    local f, err = loadfile(app_path.."main.lua")

    -- 加载失败，记录错误并清理沙箱
    if not f then
        my_env.log.error("app_task", "failed to load main.lua:", err)
        sandbox_cleanup(app_path, my_env, unsubscribe_all, mem_baseline)
        return
    end

    -- 设置主文件的环境为沙箱环境
    debug.setupvalue(f, 1, _ENV)

    -- 异常处理函数：记录错误信息
    local function error_handler(err_msg)
        my_env.log.error("app_task", "app runtime error:", app_path, err_msg)
        return err_msg
    end

    -- 使用xpcall包装应用执行，捕获异常后安全清理
    local ok, result = xpcall(f, error_handler)

    -- 应用异常退出，执行清理
    if not ok then
        my_env.log.error("app_task", "app crashed, starting cleanup:", app_path, result)
        sandbox_cleanup(app_path, my_env, unsubscribe_all, mem_baseline)
        return
    end

    my_env.log.info("app_task", "waitUntil close_req event", app_path)

    -- 等待应用关闭请求
    local ret, rdata = sys.waitUntil(app_path .."_close_req")
    if rdata == "yes" then
        sandbox_cleanup(app_path, my_env, unsubscribe_all, mem_baseline)
        log.info("app co quit", app_path)
    end
end

--[[
通过文件系统启动应用

@param app_path string 应用目录路径，如 "/app_store/app_hello/"
@return number 协程ID

功能说明：
    - 创建一个新的协程来运行应用
    - 应用在独立的沙箱环境中运行
    - 返回协程ID，可用于后续管理

使用示例：
local co_id = exapp.open("/app_store/app_hello/")
]]
function exapp.open(app_path)
    if app_registry[app_path] then
        log.info("exapp.open", "app already running:", app_path)
        return true
    end

    -- 检查并创建data目录
    local data_dir = app_path .. "data/"
    if not io.dexist(data_dir) then
        local ret = io.mkdir(data_dir)
        if ret then
            log.info("exapp.open", "created data directory:", data_dir)
        else
            log.warn("exapp.open", "failed to create data directory:", data_dir)
        end
    end

    app_registry[app_path] = true
    log.info("exapp.open", "app started:", app_path)

    sys.taskInit(app_task, app_path)

    return true
end

--[[
    关闭指定应用
    
    @param app_path string 应用目录路径
    
    功能说明：
    - 发送关闭请求给应用协程
    - 应用协程会执行清理操作后退出
]]
function exapp.close(app_path)
    if not app_registry[app_path] then
        log.info("exapp.close", "app not running:", app_path)
        return
    end

    sys.publish(app_path .. "_close_req", "yes")
    log.info("exapp.close", "close request sent:", app_path)
end

--[[
检查应用是否正在运行

@param app_path string 应用目录路径
@return boolean 是否正在运行
]]
function exapp.is_running(app_path)
    return app_registry[app_path] ~= nil
end

--[[
获取所有正在运行的应用列表

@return table 应用目录路径列表
]]
function exapp.list_running()
    local list = {}
    for app_path, _ in pairs(app_registry) do
        table.insert(list, app_path)
    end
    return list
end

--[[
安装应用

@param app_path string 应用目录路径
@param app_info table 应用信息
@return boolean 是否成功
]]
function exapp.install(app_path, app_info)
    if installed_info[app_path] then
        log.info("exapp.install", "app already installed:", app_path)
        return false
    end

    installed_info[app_path] = app_info
    log.info("exapp.install", "app installed:", app_path)
    return true
end

--[[
卸载应用

@param app_path string 应用目录路径
@return boolean 是否成功
]]
function exapp.uninstall(app_path)
    if app_registry[app_path] then
        log.info("exapp.uninstall", "app is running, close first:", app_path)
        exapp.close(app_path)
    end

    installed_info[app_path] = nil
    log.info("exapp.uninstall", "app uninstalled:", app_path)
    return true
end

--[[
获取已安装应用列表

返回值示例:
{
    ["pac_man"] = {
        cn_name = "吃豆人",
        path = "/app_store/pac_man/",
        version = "1.0.0",
        category = "游戏",
        description = "经典吃豆人游戏",
        install_time = 1759161153
    },
    ["app_hello"] = {
        cn_name = "你好世界",
        path = "/app_store/app_hello/",
        version = "1.0.0",
        category = "工具",
        description = "示例应用",
        install_time = nil
    }
}

遍历示例:
local apps, cnt = exapp.list_installed()
for app_dir_name, app_info in pairs(apps) do
    log.info("app_dir_name:", app_dir_name)
    log.info("cn_name:", app_info.cn_name)
    log.info("path:", app_info.path)
    log.info("version:", app_info.version)
    log.info("category:", app_info.category)
    log.info("description:", app_info.description)
    log.info("install_time:", app_info.install_time)
end

获取单个应用:
local app_info = exapp.get_info("pac_man")

@return table 应用信息列表
]]
function exapp.list_installed()
    return installed_info, installed_cnt
end

--[[
获取应用信息

@param app_dir_name string 应用目录名称，例如 "pac_man"
@return table|nil 应用信息
]]
function exapp.get_info(app_dir_name)
    return installed_info[app_dir_name]
end


--[[
    扫描应用目录（支持分页，最多不限）

    @param base_dir string 基础目录路径，如 "/app_store/"
    @return number 发现的应用数量

    功能说明：
    - 分页遍历指定目录下的所有子目录（每次最多50个，循环直到没有更多）
    - 读取每个子目录的 meta.json 文件
    - 解析应用信息并保存到 installed_info，同时记录 install_time
]]
local function scan_app_dir(base_dir)
    local cnt = 0
    local max_per_page = 50   -- 每次最多扫描50个目录
    local offset = 0
    local has_more = true

    while has_more do
        local ret, dirs = io.lsdir(base_dir, max_per_page, offset)
        if not ret then
            log.error("exapp.init", "failed to list directory:", base_dir, dirs)
            break
        end

        -- 如果没有返回任何条目，说明没有更多了
        if not dirs or #dirs == 0 then
            break
        end

        for _, app_dir in ipairs(dirs) do
            -- 跳过文件，只处理目录
            if app_dir.type == 1 then
                -- 检查 meta.json 是否存在
                local meta_path = base_dir .. app_dir.name .. "/meta.json"
                if not io.exists(meta_path) then
                    log.warn("exapp.init", "app missing meta.json:", app_dir.name)
                    goto continue
                end

                -- 读取 meta.json 内容
                local meta_content = io.readFile(meta_path)
                if not meta_content then
                    log.error("exapp.init", "failed to read meta.json:", meta_path)
                    goto continue
                end

                -- 解析 JSON
                local ok, meta_data = pcall(json.decode, meta_content)
                if not ok then
                    log.error("exapp.init", "failed to parse meta.json:", app_dir.name, meta_data)
                    goto continue
                end

                -- 保存应用信息，包含 install_time
                local app_dir_name = app_dir.name
                installed_info[app_dir_name] = {
                    cn_name = meta_data.app_name_cn or "unknown",
                    path = base_dir .. app_dir.name .. "/",
                    version = meta_data.version or "1.0.0",
                    category = meta_data.category or "unknown",
                    description = meta_data.description or "unknown",
                    icon_path = base_dir .. app_dir.name .. "/icon.png",
                    installed = true,
                    has_update = false,
                    zip_size_kb = meta_data.zip_size_kb,
                    origin_size_kb = meta_data.origin_size_kb,
                    total_downloads = meta_data.total_downloads,
                    install_time = meta_data.install_time
                }
                log.info("exapp.init", "found app:", app_dir_name, installed_info[app_dir_name].cn_name)
                cnt = cnt + 1
                ::continue::
            end
        end

        -- 如果本次返回的数量小于 max_per_page，说明已经到底了
        if #dirs < max_per_page then
            has_more = false
        else
            offset = offset + max_per_page
        end
    end

    return cnt
end

--[[
初始化应用管理库，扫描设备上的已安装应用
    功能说明：
    - 扫描 /app_store/ 目录下的应用（支持分页）
    - 扫描 /sd/app_store/ 目录下的应用（如果存在）
    - 将应用信息保存到 installed_info

@api exapp.init()

@return bool
初始化成功返回true，失败返回false（目前总是返回true）

@usage
-- 在应用启动时调用初始化
exapp.init()
]]
function exapp.init()
    log.info("exapp.init", "start scanning apps")
    -- 清空已安装应用信息
    installed_info = {}

    installed_cnt = 0

    -- 扫描内置应用目录
    installed_cnt = installed_cnt + scan_app_dir("/app_store/")

    -- 扫描SD卡应用目录（如果存在）
    if io.dexist("/sd/app_store/") then
        installed_cnt = installed_cnt + scan_app_dir("/sd/app_store/")
    end
    installed_total_count = installed_cnt
    log.info("exapp.init", "scan completed, found", installed_cnt, "apps")
    sys.publish("APP_STORE_INSTALLED_UPDATED", installed_info)
    return true
end

-- ==============================================
-- 云端应用管理功能
-- ==============================================

-- 获取设备信息
local function get_device_info()
    if device_info then return device_info end
    local model = rtos.bsp()

    -- 获取固件ID（示例期望104，实际根据硬件获取）
    local firmware_id
    if rtos.get_firmware_id then
        firmware_id = rtos.get_firmware_id()
    else
        _, firmware_id = rtos.version(true)
    end
    if not firmware_id or firmware_id == 0 then
        firmware_id = 104 -- 设计示例默认值，实际应通过API获取
    end

    -- 获取最小固件版本（转为数字，如 "V2024" -> 2024）
    local version_str, _ = rtos.version(true)
    local min_firmware_version = tonumber(version_str:match("%d+")) or 2010
    if min_firmware_version == 0 then min_firmware_version = 2010 end

    -- 获取物理屏幕宽高
    local phys_w, phys_h = lcd.getSize()
    local rotation = airui.get_rotation()

    -- 根据旋转计算实际显示宽高（参考calc_layout）
    local disp_w, disp_h
    if rotation == 0 or rotation == 180 then
        disp_w, disp_h = phys_w, phys_h
    else
        disp_w, disp_h = phys_h, phys_w
    end

    -- 分辨率字符串格式：宽x高（显示分辨率）
    local resolution = disp_w .. "x" .. disp_h

    device_info = {
        model = model,
        firmware_id = firmware_id,
        min_firmware_version = min_firmware_version,
        resolution = resolution,
    }
    return device_info
end

-- 构建请求参数
local function build_request_params(category, sort, page, size, query)
    local params = get_device_info()
    params.categ = category or ""
    params.sort = sort or "recommend"
    params.page = page or 1
    params.size = size or PAGE_LIMIT
    if type(query) == "string" and query ~= "" then
        params.query = query
    end
    local aids = {}
    local vers = {}
    for aid, info in pairs(installed_info) do
        table.insert(aids, aid)
        table.insert(vers, info.version)
    end
    params.aids = aids
    params.ver = vers
    params.binary = true
    return params
end

-- HTTP请求
local function http_request(params)
    local body = json.encode(params)
    -- 修复空数组问题
    local function fix_empty_array(field, body_str)
        local pattern1 = string.format('"%s":{}', field)
        local pattern2 = string.format('"%s": {}', field)
        local replacement = string.format('"%s":[]', field)
        body_str = body_str:gsub(pattern1, replacement)
        body_str = body_str:gsub(pattern2, replacement)
        return body_str
    end
    if type(params.aids) == "table" and next(params.aids) == nil then
        body = fix_empty_array("aids", body)
    end
    if type(params.ver) == "table" and next(params.ver) == nil then
        body = fix_empty_array("ver", body)
    end

    -- 发送 HTTP 请求
    local code, headers, resp_body = http.request("POST", APP_STORE_URL, {
        ["Content-Type"] = "application/json"
    }, body, { timeout = 10000 }).wait()

    log.info("http_body", json.encode(body))

    -- 处理通信异常（code < 0）
    if code < 0 then
        local err_map = {
            [-1] = "HTTP底层异常，请联系技术支持",
            [-2] = "服务器响应头部错误",
            [-3] = "服务器响应体错误",
            [-4] = "连接服务器失败，请检查网络或地址",
            [-5] = "连接提前断开",
            [-6] = "接收数据错误",
            [-7] = "下载文件错误",
            [-8] = "请求超时",
            [-9] = "FOTA更新包不合法",
        }
        local err_msg = err_map[code] or ("通信异常，错误码: " .. tostring(code))
        return nil, err_msg, 0
    end

    -- 处理 HTTP 状态码非 200
    if code ~= 200 then
        return nil, string.format("未获取列表，服务器返回错误响应码（%d）", code), 0
    end

    -- 响应体为空
    if not resp_body then
        return nil, "服务器返回空响应", 0
    end

    -- 解析 JSON
    local ok, resp = pcall(json.decode, resp_body)
    if not ok or type(resp) ~= "table" then
        return nil, "JSON解析失败: " .. tostring(resp_body), 0
    end

    -- 处理业务错误（code ≠ 0）
    if resp.code ~= 0 then
        -- 根据协议，value 为字符串，直接作为错误描述
        local err_msg = resp.value or ("服务器错误码: " .. tostring(resp.code))
        return nil, err_msg, 0
    end

    -- 成功解析应用列表
    if type(resp.value) == "table" and type(resp.value.records) == "table" then
        local total = tonumber(resp.value.total) or 0
        local current = tonumber(resp.value.current) or 1
        local pages = tonumber(resp.value.pages) or 1
        local size = tonumber(resp.value.size) or PAGE_LIMIT
        return resp.value.records, nil, total, current, pages, size
    else
        -- 兼容旧格式
        local total = resp.total or 0
        return resp.value, nil, total, 1, math.max(1, math.ceil(total / PAGE_LIMIT)), PAGE_LIMIT
    end
end

-- 丰富应用列表（合并已安装状态）
local function enrich_app_list(server_apps)
    for _, app in ipairs(server_apps) do
        -- 兼容服务端新格式：appname 替换 aid，新增 icon_binary 字段
        if not app.aid then
            app.aid = app.appname or app.app_name
        end
        -- 处理 icon_binary：将base64编码的图标二进制数据解码并保存到/ram目录
        if app.icon_binary and app.icon_binary ~= "" then
            -- 检查icon_binary数据量，避免解码时耗尽内存
            if #app.icon_binary <= 131072 then
                local ok, decoded = pcall(string.fromBase64, app.icon_binary)
                if ok and decoded and #decoded > 0 then
                    local icon_path = string.format("/ram/icon_%s.png", app.aid)
                    -- /* 原有下载图标逻辑（注释保留）
                    -- download_icon(app.aid, app.icon)
                    -- */
                    local wf_ok, wf_err = io.writeFile(icon_path, decoded)
                    if wf_ok then
                        log.info("exapp", "icon saved:", icon_path, #decoded)
                    else
                        log.warn("exapp", "io.writeFile failed:", wf_err)
                        local f = io.open(icon_path, "wb")
                        if f then
                            f:write(decoded)
                            f:close()
                            log.info("exapp", "icon saved via io.open:", icon_path, #decoded)
                        end
                    end
                    app.icon_path = icon_path
                end
            else
                log.warn("exapp", "icon_binary too large for", app.aid, "size:", #app.icon_binary)
            end
            app.icon_binary = nil
        end

        local aid = tostring(app.aid)
        local local_info = installed_info[aid]

        -- 处理服务器返回的 ins 字段（如果存在）
        if app.ins ~= nil then
            app.installed = (app.ins == true)
        end

        -- 覆盖本地安装状态（更准确）
        if local_info then
            app.installed = true
            app.has_update = (app.ver and app.ver ~= "" and app.ver ~= local_info.version)
            app.path = local_info.path
            app.icon_path = local_info.icon_path
        else
            -- 如果没有本地信息，确保installed字段有值
            if app.installed == nil then
                app.installed = false
            end
            app.has_update = false
        end

        -- 确保大小字段存在（服务器返回的字段名）
        app.zip_size_kb = app.zip_size_kb or app.zip_size
        app.origin_size_kb = app.origin_size_kb or app.origin_size
    end
    return server_apps
end

--[[
获取云端应用列表

@api exapp.get_app_list(params)

@table params 请求参数表
@string params.category 应用分类，默认为"全部"
@string params.sort 排序方式，默认为"recommend"
@number params.page 页码（从1开始），默认为1
@number params.size 每页数量，默认为PAGE_LIMIT（10）
@string params.query 搜索关键词，默认为空字符串

@return bool
成功发起请求返回true，网络未就绪返回false

@usage
-- 获取第一页应用列表，每页10个，按推荐排序
exapp.get_app_list({category="全部", sort="recommend", page=1, size=10})

-- 搜索应用
exapp.get_app_list({query="游戏", page=1, size=10})

-- 获取已安装应用列表（本地查询，不需要网络）
exapp.get_app_list({category="已安装", page=1, size=10})
]]
function exapp.get_app_list(params)
    if not network_ready then
        sys.publish("APP_STORE_ERROR", "网络未就绪")
        return false
    end

    local category = params.category or "全部"
    local sort = params.sort or "recommend"
    local page = params.page or 1
    local size = params.size or PAGE_LIMIT
    local query = params.query or ""

    if category == "已安装" then
    local installed_list = {}
        for aid, info in pairs(installed_info) do
            table.insert(installed_list, {
                aid = aid,
                title = info.cn_name or aid,
                desc = info.description or "",
                installed = true,
                has_update = false,
                path = info.path,
                version = info.version,
                icon_path = info.icon_path,
                zip_size_kb = info.zip_size_kb,
                origin_size_kb = info.origin_size_kb,
                install_time = info.install_time
            })
        end
        -- 稳定排序：按 install_time 升序，无时间戳的排最后，相同时间戳按 aid 排序
        table.sort(installed_list, function(a, b)
            local ta = a.install_time
            local tb = b.install_time
            if ta == nil and tb == nil then
                return a.aid < b.aid
            elseif ta == nil then
                return false
            elseif tb == nil then
                return true
            else
                if ta == tb then
                    return a.aid < b.aid
                end
                return ta < tb
            end
        end)
        -- 分页显示：根据 page/size 进行切片
        local start_index = (page - 1) * size
        local sliced = {}
        local total = #installed_list
        installed_total_count = total
        for i = start_index + 1, math.min(start_index + size, total) do
            if installed_list[i] then
                table.insert(sliced, installed_list[i])
            end
        end
        local has_more_now = (start_index + #sliced) < total
        local total_pages_now = math.max(1, math.ceil(total / size))
        remote_app_list.apps = sliced
        -- 同步当前分页状态
        remote_app_list.page = page
        remote_app_list.size = size
        remote_app_list.has_more = has_more_now
        remote_app_list.total = total
        remote_app_list.total_pages = total_pages_now

        sys.publish("APP_STORE_LIST_UPDATED", sliced, {
            has_more = has_more_now,
            page = page,
            size = size,
            total_pages = total_pages_now,
            total = total
        })
        return true
    end

    sys.taskInit(function()
        local request_params = build_request_params(category, sort, page, size, query)
        local apps, err, total, current_page, total_pages, page_size = http_request(request_params)
        if not apps then
            sys.publish("APP_STORE_ERROR", err)
            return
        end
        apps = enrich_app_list(apps)
        remote_app_list.apps = apps
        remote_app_list.category = category
        remote_app_list.sort = sort
        remote_app_list.page = page
        remote_app_list.size = size
        remote_app_list.total = total
        remote_app_list.total_pages = total_pages or math.max(1, math.ceil(total / size))
        remote_app_list.has_more = page < total_pages
        sys.publish("APP_STORE_LIST_UPDATED", apps, {
            has_more = remote_app_list.has_more,
            page = page,
            size = size,
            total_pages = remote_app_list.total_pages,
            total = total,
            current = current_page or page
        })
    end)
    return true
end

function exapp.refresh_app_list()
    return exapp.get_app_list({
        category = remote_app_list.category,
        sort = remote_app_list.sort,
        page = 1,
        size = PAGE_LIMIT,
        query = remote_app_list.query or ""
    })
end

--[[
获取当前缓存的应用列表

@api exapp.get_current_list()

@return table, bool
返回应用列表和是否有更多应用的标志

@usage
-- 获取当前显示的应用列表
local apps, has_more = exapp.get_current_list()
]]
function exapp.get_current_list()
    return remote_app_list.apps, remote_app_list.has_more
end

-- 下载文件
local function download_file(url, dest_path, aid)
    log.info("exapp", "downloading", url, "->", dest_path)
    -- 尝试从服务器返回字段获取 zip 大小信息（若服务端支持）
    local app_entry = nil
    if remote_app_list and remote_app_list.apps then
        for _, it in ipairs(remote_app_list.apps) do
            if tostring(it.aid) == tostring(aid) then app_entry = it; break end
        end
    end
    local expected_size_kb = 0
    if app_entry and (type(app_entry.zip_size_kb) == "string" or type(app_entry.zip_size_kb) == "number") then
        local z = tonumber(tostring(app_entry.zip_size_kb)) or 0
        if z > 0 then expected_size_kb = z end
    end
    -- 读取 /ram 的可用空间（单位 KB）
    local ram_free_kb = 0
    local ram_stat = io.fsstat and io.fsstat("/ram") or nil
    if type(ram_stat) ~= "table" then ram_stat = nil end
    if ram_stat and type(ram_stat.free_kb) == "number" then ram_free_kb = ram_stat.free_kb end
    if expected_size_kb > 0 and ram_free_kb > 0 and expected_size_kb > ram_free_kb then
        log.error("exapp", "not enough memory to download app", aid, expected_size_kb, ram_free_kb)
        sys.publish("APP_STORE_ERROR", "内存空间不足无法安装")
        return false
    end
    local code = http.request("GET", url, nil, nil, {
        dst = dest_path,
        timeout = 60000,
        callback = function(total, received)
            if total > 0 then
                local percent = math.floor(received * 100 / total)
                sys.publish("APP_STORE_PROGRESS", aid, percent, string.format("下载中 %d%%", percent))
            end
        end
    }).wait()
    if code == 200 then
        -- 额外校验：对比实际下载大小与服务端给出的 zip_size（若可用）
        if app_entry and type(app_entry.zip_size_kb) ~= "nil" then
            local actual_kb = 0
            local fsz = io.fileSize(dest_path)
            if fsz then actual_kb = math.floor(fsz / 1024) end
            local expected = tonumber(tostring(app_entry.zip_size_kb)) or 0
            if expected > 0 and actual_kb > 0 then
                local diff = math.abs(actual_kb - expected)
                local diff_percent = math.abs(actual_kb - expected) / expected * 100
                -- 允许10%差异或最多20KB差异，取较大值（对小文件更宽松）
                if diff > math.max(expected * 0.10, 20) then
                    log.warn("exapp", "download size mismatch for", aid, actual_kb, expected, "diff:", diff, "KB", string.format("%.1f", diff_percent), "%")
                    if io.exists(dest_path) then os.remove(dest_path) end
                    return false
                elseif diff > 0 then
                    log.info("exapp", "download size minor mismatch for", aid, actual_kb, expected, "diff:", diff, "KB", string.format("%.1f", diff_percent), "%")
                end
            end
        end
        return true
    else
        log.error("exapp", "download failed", code)
        -- 下载失败，清理已下载的文件
        if dest_path and io.exists(dest_path) then os.remove(dest_path) end
        return false
    end
end

-- 计算目录大小，单位 KB（简单实现，递归统计）
local function dir_size_kb(dir_path)
    local total = 0
    local ret, list = io.lsdir(dir_path, 100, 0)
    if not ret or not list then return total end
    for _, item in ipairs(list) do
        local full = dir_path .. (dir_path:sub(-1) == "/" and "" or "/") .. item.name
        if item.type == 1 then
            total = total + dir_size_kb(full)
        else
            local fsz = io.fileSize(full) or 0
            total = total + fsz / 1024
        end
    end
    return total
end

-- 解压ZIP
local function extract_zip(zip_path, dest_dir)
    log.info("exapp", "extracting", zip_path, "->", dest_dir)
    local success = miniz.unzip(zip_path, dest_dir)
    return success
end

-- 向服务器报告下载安装结果
local function report_download_result(aid, error_msg)
    log.info("exapp", "reporting download result", aid, error_msg or "success")
    local data = { app_id = tostring(aid) }
    -- 只有传入非空的 error_msg 时才添加该字段
    if error_msg and error_msg ~= "" then
        data.error_msg = error_msg
    end
    local body = json.encode(data)
    -- 异步发送，不等待结果
    sys.taskInit(function()
        local code, headers, resp_body = http.request("POST", APP_STORE_DOWNLOAD_REPORT_URL, {
            ["Content-Type"] = "application/json"
        }, body, { timeout = 10000 }).wait()
        if code == 200 then
            log.info("exapp", "download report success for", aid)
        else
            log.warn("exapp", "download report failed", code, resp_body)
        end
    end)
end

--[[
安装云端应用

@api exapp.install_remote_app(aid, url, app_name, category, sort)

@string aid 应用ID
@string url 应用下载URL
@string app_name 应用名称（用于显示）
@string category 应用分类
@string sort 排序方式

@return nil
无返回值，通过消息通知操作结果：
1. APP_STORE_PROGRESS - 下载安装进度
2. APP_STORE_ACTION_DONE - 安装完成（成功/失败）
3. APP_STORE_ERROR - 错误信息
4. 安装完成后会自动发布APP_STORE_INSTALLED_UPDATED消息更新已安装列表
5. 安装成功后会将 install_time（本地时间戳）写入 meta.json 并更新 installed_info

@usage
-- 安装应用
exapp.install_remote_app("app_hello", "https://example.com/app.zip", "Hello App", "工具", "recommend")
]]
function exapp.install_remote_app(aid, url, app_name, category, sort)
    if not network_ready then
        sys.publish("APP_STORE_ERROR", "网络未就绪")
        return
    end

    if installed_info[aid] then
        sys.publish("APP_STORE_ERROR", "应用已安装")
        sys.publish("APP_STORE_ACTION_DONE", aid, "install", false)
        report_download_result(aid, "应用已安装")
        return
    end

    sys.taskInit(function()
        local root_path = APP_INSTALL_ROOT
        if not io.dexist(root_path) then
            io.mkdir(root_path)
        end

        local temp_path = string.format(TEMP_DOWNLOAD_PATH, aid)
        sys.publish("APP_STORE_PROGRESS", aid, 0, "开始下载")

        -- 预下载容量校验：若zip_size_kb大于 /ram 空间，直接失败
        -- (在 download_file 中还会再做一次详细校验)

        -- 进行下载前对 zip_size 的容量校验，若不通过则直接退出
        if not download_file(url, temp_path, aid) then
            sys.publish("APP_STORE_ERROR", "下载失败")
            sys.publish("APP_STORE_ACTION_DONE", aid, "install", false)
            report_download_result(aid, "下载失败")
            return
        end

        sys.publish("APP_STORE_PROGRESS", aid, 0, "解压中")
        if not extract_zip(temp_path, root_path .. "/") then
            -- 解压失败，清理下载的压缩包和目标目录
            os.remove(temp_path)
            -- 如果已经解压出目录，尝试清理部分数据
            if io.dexist(root_path .. "/" .. aid) then
                rmdir_recursive(root_path .. "/" .. aid)
            end
            os.remove(temp_path)
            sys.publish("APP_STORE_ERROR", "解压失败，请检查存储空间！")
            sys.publish("APP_STORE_ACTION_DONE", aid, "install", false)
            report_download_result(aid, "解压失败")
            return
        end

        os.remove(temp_path)

        local app_path = root_path .. "/" .. aid .. "/"
        -- 安装后容量校验：估算解压后的占用大小，是否超过目标分区剩余空间
        local app_dir_kb = 0
        if io.dexist(app_path) or io.exists(app_path) then
            app_dir_kb = dir_size_kb(app_path) or 0
        end
        local dest_parent = root_path
        local parent_stat = io.fsstat and io.fsstat(dest_parent) or nil
        if type(parent_stat) ~= "table" then parent_stat = nil end
        local dest_free_kb = 0
        if parent_stat and type(parent_stat.free_kb) == "number" then dest_free_kb = parent_stat.free_kb end
        if app_dir_kb > 0 and dest_free_kb > 0 and app_dir_kb > dest_free_kb then
            -- 文件系统空间不足，清理已下载/解压的内容
            if io.dexist(app_path) then rmdir_recursive(app_path) end
            if io.exists(temp_path) then os.remove(temp_path) end
            sys.publish("APP_STORE_ERROR","文件系统空间不足无法进行安装")
            sys.publish("APP_STORE_ACTION_DONE", aid, "install", false)
            report_download_result(aid, "文件系统空间不足无法进行安装")
            return
        end
        if io.dexist(app_path) then
            local meta_path = app_path .. "meta.json"
            if io.exists(meta_path) then
                local meta_content = io.readFile(meta_path)
                if meta_content then
                    local ok, meta_data = pcall(json.decode, meta_content)
                    if ok then
                        -- 写入安装时间戳（本地 UTC 时间戳）
                        local install_time = os.time()
                        meta_data.install_time = install_time
                        -- 从 remote_app_list.apps 中找到当前 aid 对应的记录
                        local app_entry = nil
                        if remote_app_list and remote_app_list.apps then
                            for _, it in ipairs(remote_app_list.apps) do
                                if tostring(it.aid) == tostring(aid) then
                                    app_entry = it
                                    break
                                end
                            end
                        end
                        
                        if app_entry then
                            meta_data.origin_size_kb = app_entry.origin_size_kb or meta_data.origin_size_kb
                            meta_data.total_downloads = app_entry.total_downloads or meta_data.total_downloads
                        end
                        
                        local new_content = json.encode(meta_data)
                        io.writeFile(meta_path, new_content)

                        installed_info[aid] = {
                            cn_name = meta_data.app_name_cn or app_name or aid,
                            path = app_path,
                            version = meta_data.version or "1.0.0",
                            category = meta_data.category or category or "unknown",
                            description = meta_data.description or "",
                            icon_path = app_path .. "icon.png",
                            installed = true,
                            has_update = false,
                            zip_size_kb = meta_data.zip_size_kb,
                            origin_size_kb = meta_data.origin_size_kb,
                            total_downloads = meta_data.total_downloads,
                            install_time = install_time
                        }
                        installed_cnt = installed_cnt + 1
                        installed_total_count = installed_cnt
                        sys.publish("APP_STORE_INSTALLED_UPDATED", installed_info)
                    end
                end
            end
        end

        sys.publish("APP_STORE_ACTION_DONE", aid, "install", true)
        sys.publish("APP_STORE_PROGRESS", aid, 100, "安装完成")
        report_download_result(aid, nil)

        -- 刷新当前列表（仅一次请求，使用当前UI正确的分页参数）
        exapp.get_app_list({
            category = remote_app_list.category,
            sort = remote_app_list.sort,
            page = 1,
            size = remote_app_list.size or PAGE_LIMIT,
            query = remote_app_list.query or ""
        })
    end)
end

--[[
卸载云端应用

@api exapp.uninstall_remote_app(aid, category, sort)

@string aid 应用ID
@string category 应用分类（用于刷新列表）
@string sort 排序方式（用于刷新列表）

@return nil
无返回值，通过消息通知操作结果：
1. APP_STORE_ACTION_DONE - 卸载完成（成功/失败）
2. APP_STORE_ERROR - 错误信息
3. 卸载完成后会自动发布APP_STORE_INSTALLED_UPDATED消息更新已安装列表

@usage
-- 卸载应用
exapp.uninstall_remote_app("app_hello", "工具", "recommend")
]]
function exapp.uninstall_remote_app(aid, category, sort)
    if not installed_info[aid] then
        sys.publish("APP_STORE_ERROR","应用未安装")
        sys.publish("APP_STORE_ACTION_DONE", aid, "uninstall", false)
        return
    end

    local app_info = installed_info[aid]
    local target_path = app_info.path

    if not target_path or not io.dexist(target_path) then
        sys.publish("APP_STORE_ERROR", "应用目录不存在")
        sys.publish("APP_STORE_ACTION_DONE", aid, "uninstall", false)
        return
    end

    sys.publish("APP_STORE_PROGRESS", aid, 0, "卸载中")
    local success = rmdir_recursive(target_path)

    if success then
        installed_info[aid] = nil
        installed_cnt = installed_cnt - 1
        installed_total_count = installed_cnt
        sys.publish("APP_STORE_INSTALLED_UPDATED", installed_info)
        sys.publish("APP_STORE_ACTION_DONE", aid, "uninstall", true)
        sys.publish("APP_STORE_PROGRESS", aid, 100, "卸载完成")

        -- 卸载完成后刷新当前列表（仅一次请求）
        exapp.get_app_list({
            category = remote_app_list.category,
            sort = remote_app_list.sort,
            page = 1,
            size = remote_app_list.size or PAGE_LIMIT,
            query = remote_app_list.query or ""
        })
    else
        sys.publish("APP_STORE_ERROR", "卸载失败")
        sys.publish("APP_STORE_ACTION_DONE", aid, "uninstall", false)
    end
end

--[[
更新云端应用

@api exapp.update_remote_app(aid, url, app_name, category, sort)

@string aid 应用ID
@string url 新版本应用下载URL
@string app_name 应用名称（用于显示）
@string category 应用分类
@string sort 排序方式

@return nil
无返回值，通过消息通知操作结果：
1. APP_STORE_PROGRESS - 下载安装进度
2. APP_STORE_ACTION_DONE - 更新完成（成功/失败）
3. APP_STORE_ERROR - 错误信息
4. 更新完成后会自动发布APP_STORE_INSTALLED_UPDATED消息更新已安装列表

@usage
-- 更新应用
exapp.update_remote_app("app_hello", "https://example.com/app_v2.zip", "Hello App V2", "工具", "recommend")
]]
function exapp.update_remote_app(aid, url, app_name, category, sort)
    if not installed_info[aid] then
        sys.publish("APP_STORE_ERROR", "应用未安装，无法更新")
        sys.publish("APP_STORE_ACTION_DONE", aid, "update", false)
        report_download_result(aid, "应用未安装，无法更新")
        return
    end

    local old_path = installed_info[aid].path
    sys.publish("APP_STORE_PROGRESS", aid, 0, "准备更新")

    if rmdir_recursive(old_path) then
        installed_info[aid] = nil
        installed_cnt = installed_cnt - 1
        exapp.install_remote_app(aid, url, app_name, category, sort)
    else
        sys.publish("APP_STORE_ERROR", "卸载旧版本失败")
        sys.publish("APP_STORE_ACTION_DONE", aid, "update", false)
        report_download_result(aid, "卸载旧版本失败")
    end
end

-- 图标下载与缓存
local function download_icon(aid, url)
    if not url or url == "" then return nil end
    if icon_cache[aid] and io.exists(icon_cache[aid].path) then
        return icon_cache[aid].path
    end

    local ext = url:match("%.([^%.]+)$") or "png"
    local local_path = string.format("/ram/icon_%s.%s", aid, ext)

    if io.exists(local_path) then
        icon_cache[aid] = { path = local_path, timestamp = os.time(), size = io.fileSize(local_path) }
        return local_path
    end

    sys.taskInit(function()
        log.info("exapp", "downloading icon", url, "->", local_path)
        local code = http.request("GET", url, nil, nil, { dst = local_path, timeout = 10000 }).wait()
        if code == 200 then
            icon_cache[aid] = { path = local_path, timestamp = os.time(), size = io.fileSize(local_path) }
            sys.publish("APP_STORE_ICON_READY", aid, local_path)
        else
            log.error("exapp", "icon download failed", code)
        end
    end)
    return nil
end

--[[
获取应用图标路径

@api exapp.get_icon_path(aid, url)

@string aid 应用ID
@string url 图标URL（可选）

@return string|nil
返回图标本地文件路径，如果图标未缓存且无URL则返回nil

@usage
-- 获取应用图标路径
local icon_path = exapp.get_icon_path("app_hello", "https://example.com/icon.png")
if icon_path then
    -- 使用图标路径
end
]]
function exapp.get_icon_path(aid, url)
    if icon_cache[aid] and io.exists(icon_cache[aid].path) then
        return icon_cache[aid].path
    end
    if url and url ~= "" then
        return download_icon(aid, url)
    end
    return nil
end

-- 清理过期的图标缓存（默认 1 小时）
function exapp.clear_icon_cache(max_age)
    max_age = max_age or 3600
    local now = os.time()
    local cleaned = 0
    for aid, cache in pairs(icon_cache) do
        if now - cache.timestamp > max_age then
            os.remove(cache.path)
            icon_cache[aid] = nil
            cleaned = cleaned + 1
        end
    end
    log.info("exapp", "cleared", cleaned, "expired icons")
    return cleaned
end

-- 检查网络是否就绪
function exapp.is_network_ready()
    return network_ready
end

-- 等待网络就绪（超时毫秒）
function exapp.wait_network_ready(timeout)
    timeout = timeout or 30000
    local ret = sys.waitUntil("IP_READY", timeout)
    return ret ~= nil
end

-- 获取系统状态
-- { network_ready = true, installed_count = 5, running_count = 1, remote_total = 100 }
function exapp.get_status()
    return {
        network_ready = network_ready,
        installed_count = installed_cnt,
        running_count = #exapp.list_running(),
        remote_total = remote_app_list.total
    }
end

exapp.init()

-- ==============================================
-- 消息订阅（用于兼容 app_store_win 的消息协议）
-- ==============================================

sys.taskInit(function()
    sys.waitUntil("IP_READY", 30000)
    network_ready = true
    log.info("exapp", "network ready")
end)

sys.subscribe("APP_STORE_GET_LIST", function(category, sort, page_param, size_param, query_param)
    local page = page_param or 1
    local size = size_param or PAGE_LIMIT
    local q = query_param or remote_app_list.query or ""
    if page < 1 then page = 1 end
    remote_app_list.category = category or remote_app_list.category
    remote_app_list.sort = sort or remote_app_list.sort
    remote_app_list.page = page
    remote_app_list.size = size
    remote_app_list.query = q
    exapp.get_app_list({
        category = remote_app_list.category,
        sort = remote_app_list.sort,
        page = page,
        size = size,
        query = q
    })
end)

sys.subscribe("APP_STORE_INSTALL", function(aid, url, app_name, category, sort)
    exapp.install_remote_app(aid, url, app_name, category, sort)
end)

sys.subscribe("APP_STORE_UNINSTALL", function(aid, category, sort)
    exapp.uninstall_remote_app(aid, category, sort)
end)

sys.subscribe("APP_STORE_UPDATE", function(aid, url, app_name, category, sort)
    exapp.update_remote_app(aid, url, app_name, category, sort)
end)

sys.subscribe("APP_STORE_SYNC_INSTALLED", function()
    sys.publish("APP_STORE_INSTALLED_UPDATED", installed_info)
end)

log.info("exapp", "loaded (complete version with cloud features, install_time support, paginated scan)")
return exapp