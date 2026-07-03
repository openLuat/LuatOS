--[[
@module  ota_manegement
@summary OTA 远程升级管理（基于 libfota3 + iot.openluat.com 平台）
@version 1.0
@date    2026.07.02
@description
    使用合宙官方 IoT 平台（iot.openluat.com）进行远程固件升级。
    基于 libfota3 库实现，支持自动定时检测、手动触发、进度反馈。

    触发机制：
      1. 自动检测：libfota3 内置定时器，支持时间戳持久化（跨重启延续）
      2. 手动触发：PWRKEY 短按事件 (PWRKEY_SHORT_PRESS) 立即检测

    配置持久化：
      - 使用 FSKV 存储 auto/interval 配置
      - Key: "ota_cfg"，类型: table {auto=bool, interval=number}

    依赖：
      - 全局变量 PRODUCT_KEY（main.lua 中配置）
      - libfota3 库
      - global_config 模块（需先初始化 fskv）

@usage
    local ota_manegement = require "ota_manegement"
    ota_manegement.init()

    -- 手动触发检测
    ota_manegement.check_now()

    -- 修改配置
    ota_manegement.config({auto = true, interval = 43200})

    -- 获取当前配置
    local cfg = ota_manegement.get_config()
]]

local libfota3 = require "libfota3"

local ota_manegement = {}

-- ========== 常量（文件开头） ==========
-- FSKV Key：统一存储 OTA 配置
local KV_KEY_OTA_CFG = "ota_cfg"

-- 内部状态：当前配置（内存缓存，避免频繁读 FSKV）
local current_config = {
    auto = true,           -- 默认开启自动检测
    interval = 86400       -- 默认检测间隔：24 小时（秒）
}

-- ========== 内部辅助函数 ==========

-- 从 FSKV 加载配置到内存
-- 不存在则使用默认值，不主动写入 FSKV（首次 config() 调用时才持久化）
local function load_config()
    local saved = fskv.get(KV_KEY_OTA_CFG)
    if type(saved) == "table" then
        -- 合并已保存的值，缺失字段用默认值补齐
        if saved.auto ~= nil then
            current_config.auto = saved.auto
        end
        if saved.interval ~= nil and saved.interval > 0 then
            current_config.interval = saved.interval
        end
        log.info("OTA", "从 FSKV 加载配置: auto=" .. tostring(current_config.auto)
                        .. " interval=" .. current_config.interval .. "s")
    else
        log.info("OTA", "FSKV 无 OTA 配置，使用默认值: auto=" .. tostring(current_config.auto)
                        .. " interval=" .. current_config.interval .. "s")
    end
end

-- 保存当前配置到 FSKV
local function save_config()
    local ok = fskv.set(KV_KEY_OTA_CFG, current_config)
    if ok then
        log.info("OTA", "配置已持久化到 FSKV")
    else
        log.info("OTA", "FSKV 写入失败，配置仅保留在内存")
    end
end

-- libfota3 状态回调：统一 INFO 级别日志
local function on_status(status, msg, percent)
    if percent then
        log.info("OTA", "[" .. status .. "] " .. tostring(msg) .. " " .. percent .. "%")
    else
        log.info("OTA", "[" .. status .. "] " .. tostring(msg))
    end
end

-- libfota3 确认回调：工厂固件无屏幕，自动确认下载和重启
local function on_confirm(action, info, callback)
    log.info("OTA", "自动确认: action=" .. tostring(action))
    callback(true)
end

-- PWRKEY 短按监听 task
-- 订阅 mypower.lua 发布的 PWRKEY_SHORT_PRESS 事件
local function pwrkey_listener_task()
    log.info("OTA", "PWRKEY 短按 OTA 监听 task 已启动")
    while true do
        sys.waitUntil("PWRKEY_SHORT_PRESS")
        log.info("OTA", "收到 PWRKEY 短按事件，触发 OTA 检测")
        libfota3.check_update()
    end
end

-- ========== 公开接口 ==========

--[[
@api ota_manegement.init()
@summary 初始化 OTA 管理模块
@return boolean 始终返回 true
@description
    流程：
      1. 从 FSKV 加载配置（auto/interval）
      2. 调用 libfota3.request() 启动自动检测
      3. 启动 PWRKEY 短按监听 task
    前置条件：global_config.init() 已调用（确保 fskv 已初始化）
]]
function ota_manegement.init()
    log.info("OTA", "初始化 OTA 管理模块")

    -- 1. 从 FSKV 加载配置
    load_config()

    -- 2. 检查 PRODUCT_KEY
    local project_key = _G.PRODUCT_KEY
    if not project_key or project_key == "" then
        log.info("OTA", "PRODUCT_KEY 未配置，OTA 功能不可用")
        return true
    end

    -- 3. 启动 libfota3
    libfota3.request({
        project_key = project_key,
        auto = current_config.auto,
        interval = current_config.interval,
        on_status = on_status,
        on_confirm = on_confirm
    })

    log.info("OTA", "libfota3 已启动: auto=" .. tostring(current_config.auto)
                    .. " interval=" .. current_config.interval .. "s")

    -- 4. 启动 PWRKEY 短按监听
    sys.taskInit(pwrkey_listener_task)

    log.info("OTA", "OTA 管理模块初始化完成")
    return true
end

--[[
@api ota_manegement.check_now()
@summary 立即触发一次 OTA 检测
@description 调用 libfota3.check_update()，与自动定时检测互斥
]]
function ota_manegement.check_now()
    log.info("OTA", "手动触发 OTA 检测")
    libfota3.check_update()
end

--[[
@api ota_manegement.config(opts)
@summary 设置 OTA 配置参数（全量透传 libfota3.config）
@param table opts 配置参数表，支持 libfota3.config 的所有字段，常用：
    - auto boolean       是否自动定时检测（持久化到 FSKV）
    - interval number    自动检测间隔秒数（持久化到 FSKV）
    - on_status function 状态回调
    - on_confirm function 确认回调
@description
    1. 提取 auto/interval 持久化到 FSKV（仅这两个字段需要跨重启保留）
    2. 全量透传给 libfota3.config() 更新运行时配置和定时器
@usage
    ota_manegement.config({auto = true, interval = 43200})  -- 12小时
    ota_manegement.config({auto = false})                   -- 关闭自动
]]
function ota_manegement.config(opts)
    if type(opts) ~= "table" then
        log.info("OTA", "config 参数无效，跳过")
        return
    end

    -- 提取 auto/interval 更新内存缓存（仅这两个字段需要持久化）
    local need_save = false
    if opts.auto ~= nil then
        current_config.auto = opts.auto
        need_save = true
    end
    if opts.interval ~= nil and opts.interval > 0 then
        current_config.interval = opts.interval
        need_save = true
    end

    -- 持久化到 FSKV（仅在 auto/interval 变化时写入）
    if need_save then
        save_config()
    end

    -- 全量透传给 libfota3 更新运行时配置和定时器
    libfota3.config(opts)
end

--[[
@api ota_manegement.get_config()
@summary 获取当前 OTA 配置
@return table {auto=bool, interval=number}
]]
function ota_manegement.get_config()
    return {
        auto = current_config.auto,
        interval = current_config.interval
    }
end

return ota_manegement
