--[[
@module  cfg_fetch
@summary 服务端配置获取模块（参考 iRTU 方式：db 持久化 + 后台异步获取）
@version 2.1
@date    2026.07.17
@usage
开机流程：
1. cfg_fetch.init() → 从文件系统加载持久化配置
2. 如果有本地配置 → 直接返回，应用使用
3. 后台异步请求服务端 → 有新版配置则持久化并重启
]]
local cfg_fetch = {}

local db = require("db")
local cfg

-- 配置文件路径
local CFG_PATH = "/luadb/air8201.cfg"

-- 当前参数版本
local param_ver = 0

-- 判断是否为有效定位版配置：必须含非空的 network.conf 通道定义
-- （采集版/未配置下发的 parameter_gnss 为 nil、空表或无 network，均返回 false）
local function has_valid_network(gnss)
    if type(gnss) ~= "table" then
        return false
    end
    local network = gnss.network
    if type(network) ~= "table" then
        return false
    end
    return type(network.conf) == "table" and #network.conf > 0
end

-- 初始化：从文件系统加载持久化配置
-- @return table|nil 返回配置表，nil 表示无本地配置
function cfg_fetch.init()
    cfg = db.new(CFG_PATH)
    local sheet = cfg:export()
    if type(sheet) == "table" and sheet.uconf then
        log.info("cfg_fetch", "从文件系统加载配置成功，param_ver:", sheet.param_ver)
        param_ver = sheet.param_ver or 0
        -- 应用配置中的 project_key
        if sheet.project_key then
            _G.PRODUCT_KEY = sheet.project_key
        end
        return sheet
    else
        log.info("cfg_fetch", "无本地持久化配置")
        return nil
    end
end

-- 获取最新配置（后台任务，参考 iRTU config_init）
-- 启动后等待网络就绪 → 请求服务端 → 有新版则持久化并重启
function cfg_fetch.start()
    sys.taskInit(function()
        -- 1. 等待网络就绪
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end

        -- 2. 请求服务端配置
        local url = "https://iot.openluat.com/api/dtu/device/"
                    .. mobile.imei()
                    .. "/param?product_name=" .. _G.PROJECT
                    .. "&param_ver=" .. param_ver
                    .. "&iccid=" .. mobile.iccid()
        log.info("cfg_fetch", "请求配置URL:", url)

        local muid = mobile.muid()
        log.info("cfg_fetch", "muid:", muid, "imei:", mobile.imei())
        local auth_str = mobile.imei() .. ":" .. muid
        local auth_b64 = crypto.base64_encode(auth_str, #auth_str)
        local headers = {
            ["User-Agent"] = "Mozilla/4.0",
            ["Accept"] = "*/*",
            ["Authorization"] = "Basic " .. auth_b64,
        }

        local code, head, body = http.request("GET", url, headers, nil, {timeout = 30000}).wait()
        log.info("cfg_fetch", "HTTP响应码:", code, "响应体长度:", body and #body)

        if tonumber(code) == 200 and body then
            log.info("cfg_fetch", "===== 服务端配置内容 =====")
            log.info("cfg_fetch", body)
            log.info("cfg_fetch", "==========================")

            local dat, res, err = json.decode(body)
            if dat and dat.code == 0 then
                -- 3. 仅定位版（下发含有效 network 通道的 parameter_gnss）才使用并更新配置；
                --    采集版/未配置（无 parameter_gnss 或为空表、无 network）忽略，不更新配置，
                --    设备保持默认 AirCloud 连接
                if not has_valid_network(dat.parameter_gnss) then
                    log.info("cfg_fetch", "下发内容无有效定位版配置（采集版/未配置），忽略，不更新配置")
                    sys.publish("CFG_FETCH_READY")
                    return
                end

                -- 4. 解析 parameter_gnss 并更新 config 模块（其余字段一律不使用）
                local config = require("config")
                config.load_from_server(dat.parameter_gnss, dat.parameter and dat.parameter.project_key)

                -- 5. 记录本次服务端返回的版本号（用于与本地版本比较，决定是否重启）
                local server_ver = tonumber(dat.parameter and dat.parameter.param_ver) or 0
                local old_ver = tonumber(param_ver) or 0

                -- 持久化到文件系统（参考 iRTU cfg:import）
                local save_sheet = {
                    uconf = true,                              -- 标志位：有本地配置
                    param_ver = server_ver,                    -- 参数版本
                    project_key = dat.parameter and dat.parameter.project_key,   -- MQTT 密钥
                    gnss = dat.parameter_gnss,                 -- 定位版配置
                }
                cfg:import(save_sheet)
                param_ver = server_ver
                log.info("cfg_fetch", "配置已持久化，param_ver:", param_ver)

                -- 6. 仅当配置版本有变化时才重启生效（参考 iRTU）
                -- 注意：必须比较"服务端版本 vs 本地旧版本"，不能只看服务端版本非nil，
                --       否则每次开机都会无条件重启，形成无限重启循环
                if server_ver ~= old_ver then
                    log.info("cfg_fetch", "===== 配置已更新（param_ver:" .. tostring(param_ver) .. "），1秒后重启使新配置生效 =====")
                    sys.wait(1000)
                    log.info("cfg_fetch", "===== 正在重启系统... =====")
                    rtos.reboot()
                else
                    log.info("cfg_fetch", "配置版本无变化（param_ver:", tostring(server_ver), "），无需重启")
                end
            elseif dat and dat.code == 1 then
                log.info("cfg_fetch", "没有新参数。已是最新参数")
            elseif dat and dat.code == 2 then
                log.info("cfg_fetch", "未付费，登录")
            end
        else
            log.warn("cfg_fetch", "HTTP请求失败:", code, body)
        end

        -- 6. 配置获取完成，发布消息（供其他模块监听）
        sys.publish("CFG_FETCH_READY")
    end)
end

return cfg_fetch
