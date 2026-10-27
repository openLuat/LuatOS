--[[
@module location
@summary 定位模块：GPS 常开 + WiFi 扫描 + 基站定位（lbsLoc2/AirLBS）
对外接口：
  location.init()             初始化 GNSS 参数与 WiFi
  location.start_find_gps()   打开常开 GPS（DEFAULT 模式）
  location.close()            关闭常开 GPS（进低功耗前调用）
  location.get_lbs_location() 基站/WiFi 定位，返回 {lat,lng} 或 nil
]]

local location = {}
local config = require("config")
local airlbs = require("airlbs")
local lbsLoc2 = require("lbsLoc2")
local exgnss = require("exgnss")

-- 定位状态缓存（仅 LBS 需要；GPS 实时读取 exgnss，不缓存）
local location_state = {
    last_lbs_time = 0,
    last_lbs_data = nil,
    first_wifi_scan = false,
    gps_started = false,
}

-- 板级 GNSS 参数来自 board.profile：
--   Air8202  volgpio=nil → exgnss 走 pm.power(pm.GPS) 供电
--   Air8201G volgpio=21  → 内置 GNSS，GPIO 使能
--   Air8201H volgpio=25  → 外置 GNSS 芯片，GPIO 使能
function location.init()
    log.info("location", "初始化定位模块")
    local gnss_cfg = (config.BOARD and config.BOARD.gnss) or {}
    exgnss.setup({
        gnssmode = 1,
        agps_enable = true,
        debug = true,
        gnss_volgpio = gnss_cfg.volgpio,
        uart = gnss_cfg.uart,
        uartbaud = gnss_cfg.baud,
    })
    wlan.init()
    log.info("location", "定位模块初始化完成")
end

-- 打开常开 GPS（开机寻宠模式调用，后台持续定位）
function location.start_find_gps()
    if not location_state.gps_started then
        location_state.gps_started = true
        exgnss.open(exgnss.DEFAULT, {tag = "gps_find"})
        log.info("location", "GPS 已开启（常开）")
    end
end

-- 关闭常开 GPS（mode/tag 必须与 open 一致，exgnss 才会真正断电）
function location.close()
    log.info("location", "关闭定位")
    if location_state.gps_started then
        location_state.gps_started = false
        exgnss.close(exgnss.DEFAULT, {tag = "gps_find"})
    end
end

-- 基站/WiFi 定位（免费 lbsLoc2 / 付费 AirLBS 双模式）
-- @return table|nil {lat, lng}
function location.get_lbs_location()
    local airlbs_mode = config.AIRLBS_CONFIG and config.AIRLBS_CONFIG.MODE or 0

    -- 缓存有效期内直接返回
    if location_state.last_lbs_data and (os.time() - location_state.last_lbs_time) < config.LOCATION_CONFIG.CACHE_DURATION then
        return location_state.last_lbs_data
    end

    -- 付费模式：AirLBS 多基站 + WiFi 混合定位
    if airlbs_mode == 1 then
        local project_id = config.AIRLBS_CONFIG.PROJECT_ID
        local project_key = config.AIRLBS_CONFIG.PROJECT_KEY
        if not project_id or project_id == "" or not project_key or project_key == "" then
            log.warn("location", "AirLBS项目ID或密钥未配置，无法使用付费模式")
            return nil
        end

        -- 首次扫描前等待联网并对时（WiFi 扫描结果需要时间戳）
        local wifi_info = nil
        if not location_state.first_wifi_scan then
            while not socket.adapter(socket.dft()) do
                sys.waitUntil("IP_READY", 1000)
            end
            socket.sntp()
            sys.waitUntil("NTP_UPDATE", 1000)
            sys.wait(4000)
            location_state.first_wifi_scan = true
        end
        wlan.scan()
        local ok = sys.waitUntil("WLAN_SCAN_DONE", config.LOCATION_CONFIG.WIFI_TIMEOUT * 1000)
        local results = wlan.scanResult()
        if ok and results and #results > 0 then
            wifi_info = {}
            for i = 1, math.min(#results, 30) do
                table.insert(wifi_info, results[i])
            end
            log.info("location", "WiFi扫描结果数:", #wifi_info)
        end

        local request_args = {
            project_id = project_id,
            project_key = project_key,
            timeout = config.LOCATION_CONFIG.LBS_TIMEOUT * 1000,
        }
        if wifi_info then request_args.wifi_info = wifi_info end

        log.info("location", "请求AirLBS付费定位, project_id:", project_id)
        local result, data = airlbs.request(request_args)
        if result and data then
            local lat = tonumber(data.lat)
            local lng = tonumber(data.lng)
            if lat and lng then
                log.info("location", "AirLBS付费定位成功:", lat, lng)
                local result_data = {lat = lat, lng = lng}
                location_state.last_lbs_time = os.time()
                location_state.last_lbs_data = result_data
                return result_data
            end
        end
        log.warn("location", "AirLBS付费定位失败")
        return nil
    end

    -- 免费模式：lbsLoc2 单基站定位
    log.info("location", "请求lbsLoc2免费定位")
    local lat, lng = lbsLoc2.request(config.LOCATION_CONFIG.LBS_TIMEOUT * 1000)
    if lat and lng then
        lat = tonumber(lat)
        lng = tonumber(lng)
        log.info("location", "lbsLoc2免费定位成功:", lat, lng)
        local result = {lat = lat, lng = lng}
        location_state.last_lbs_time = os.time()
        location_state.last_lbs_data = result
        return result
    end

    log.warn("location", "lbsLoc2免费定位失败")
    return nil
end

return location
