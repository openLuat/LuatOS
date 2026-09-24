--[[
@module  factory_report
@summary 《工业模组出厂固件规划》要求的 AirCloud 周期上报任务（默认 180 秒）

依据：
  · 文档 §1「数据自动采集上报到 AirCloud」+ §3.1「通用数据格式」
  · 官方参考工程 module/Air780EPM/project/Air8780_factory/app/aircloud/aircloud_app.lua（v1.2.0）

上报字段（全部按官方口径，见 excloud.FIELD_MEANINGS）：
  必填（每次上报都有）：
    782  SIGNAL_STRENGTH_4G   INTEGER  mobile.csq()
    1293 CUSTOM_DEVICE_ID     ASCII    hmeta.devid()
    1294 CUSTOM_PROJECT_NAME  ASCII    PROJECT 全局变量
    1280 TIMESTAMP            INTEGER  os.time()
  可选（有数据才插入）：
    263  ENV_TEMPERATURE      FLOAT    ADC 读 CPU 内部温度（原始值 ÷ 1000）
    513  GNSS_LATITUDE        FLOAT    LBS 基站定位（location.get_lbs_location）
    512  GNSS_LONGITUDE       FLOAT    LBS 基站定位

关键约束（用户 2026-09-23 指示）：
  · 本任务**独立于现有业务**：只走 AirCloud TLV 通道，不参与、不修改 active_mode
    的上报节奏与内容，避免与既有上报互相干扰。
  · 上报周期默认 180s；可由下行 `cycle:N`（CONTROL_COMMAND tag 19）修改，
    写入 fskv 断电不丢失（文档 §3.2 要求）。

对外接口：
  factory_report.start()        - 启动任务（由 app.lua 调用）
  factory_report.get_cycle()    - 读取当前上报周期（秒）
  factory_report.set_cycle(sec) - 设置上报周期（≥5 秒），写入 fskv，下一轮生效
]]

local factory_report = {}

-- 默认上报周期（秒）：文档 §1「180秒上报一次」
local DEFAULT_CYCLE = 180
-- 最小上报周期（秒）：文档 §3.2「最小值5秒」
local MIN_CYCLE = 5
-- fskv 键名（断电不丢失）
local KV_CYCLE = "factory_cycle"

-- ============================================================
-- 上报周期（fskv 持久化）
-- ============================================================

--[[
读取当前上报周期（秒）
优先取 fskv 中的下发值；无值/非法时返回默认 180
@return number 周期秒数
]]
function factory_report.get_cycle()
    local ok, v = pcall(function() return fskv.get(KV_CYCLE) end)
    v = ok and tonumber(v) or nil
    if v and v >= MIN_CYCLE then return v end
    return DEFAULT_CYCLE
end

--[[
设置上报周期并写入 fskv（断电不丢）

@param seconds number 周期秒数，小于 MIN_CYCLE(5) 视为非法
@return boolean 成功返回 true
@return string|nil 失败原因
]]
function factory_report.set_cycle(seconds)
    local s = tonumber(seconds)
    if not s or s < MIN_CYCLE then
        return false, "无效的上报频率值: " .. tostring(seconds) .. "（最小 " .. MIN_CYCLE .. " 秒）"
    end
    local ok, err = pcall(function() return fskv.set(KV_CYCLE, s) end)
    if not ok then
        return false, "写入 fskv 失败: " .. tostring(err)
    end
    log.info("factory_report", "上报周期已设置为", s, "秒（已写入 fskv）")
    return true
end

-- ============================================================
-- 数据采集
-- ============================================================

--[[
读取 CPU 内部温度（官方 Air8780_factory 口径：adc.CH_CPU 原始值 ÷ 1000，单位 ℃）
读不到返回 nil（可选字段，不插即可）
@return number|nil
]]
local function read_cpu_temp()
    local temp = nil
    pcall(function()
        adc.open(adc.CH_CPU)
        local raw = adc.get(adc.CH_CPU)
        adc.close(adc.CH_CPU)
        if raw and raw > 0 then temp = raw / 1000 end
    end)
    return temp
end

--[[
组装本次上报的 TLV 列表（严格按官方字段顺序与类型）
@return table TLV 数组
]]
local function build_tlv()
    local excloud = require("excloud")
    local FM, DT = excloud.FIELD_MEANINGS, excloud.DATA_TYPES
    local active_mode = require("active_mode")

    local data = {
        -- 必填
        { field_meaning = FM.SIGNAL_STRENGTH_4G,   data_type = DT.INTEGER, value = mobile.csq() or 0 },
        { field_meaning = FM.CUSTOM_DEVICE_ID,     data_type = DT.ASCII,   value = active_mode.get_device_uid() },
        { field_meaning = FM.CUSTOM_PROJECT_NAME,  data_type = DT.ASCII,   value = PROJECT or "unknown" },
        { field_meaning = FM.TIMESTAMP,            data_type = DT.INTEGER, value = os.time() },
    }

    -- 可选：CPU 温度
    local cpu_temp = read_cpu_temp()
    if cpu_temp then
        table.insert(data, { field_meaning = FM.ENV_TEMPERATURE, data_type = DT.FLOAT, value = cpu_temp })
    end

    -- 可选：LBS 基站定位（独立于 GPS，与官方一致）
    local ok, loc = pcall(function()
        local location = require("location")
        return location.get_lbs_location()
    end)
    if ok and type(loc) == "table" and loc.lat and loc.lng then
        table.insert(data, { field_meaning = FM.GNSS_LATITUDE,  data_type = DT.FLOAT, value = loc.lat })
        table.insert(data, { field_meaning = FM.GNSS_LONGITUDE, data_type = DT.FLOAT, value = loc.lng })
    else
        log.warn("factory_report", "LBS 定位失败，本次不带上报经纬度（不影响其它字段）")
    end

    return data
end

-- ============================================================
-- 主任务
-- ============================================================

--[[
周期上报任务（独立协程，与现有业务互不干扰）

流程：等网络 → 等云连接 → 循环 { 采集 → TLV 上报 → 按当前周期休眠 }
周期每轮重新读取，故下发的 cycle:N 能在下一轮自动生效。
]]
local function report_task()
    log.info("factory_report", "启动工业模组周期上报任务（默认", DEFAULT_CYCLE, "秒）")

    -- 1. 等待网络就绪（不设超时上限：网络恢复后自动开始，符合"数据自动采集上报"）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("factory_report", "网络已就绪")

    local create = require("create")

    while true do
        -- 2. 等云平台连接成功（每次循环都确认，断线时不会发送失败还空转）
        if not sys.waitUntil("CLOUD_CONNECTED", 60000) then
            log.warn("factory_report", "等待云平台连接超时，稍后重试")
            sys.wait(10000)
            -- 连接状态可能已丢失，回到网络等待
            while not socket.adapter(socket.dft()) do
                sys.waitUntil("IP_READY", 1000)
            end
        end

        -- 3. 采集并上报（上报失败不影响下一轮）
        local ok, err = pcall(function()
            local tlv = build_tlv()
            create.send_aircloud(tlv)
            log.info("factory_report", "周期上报完成（字段数", #tlv, "），下次间隔", factory_report.get_cycle(), "秒")
        end)
        if not ok then
            log.error("factory_report", "周期上报异常:", tostring(err))
        end

        -- 4. 按当前周期休眠（每轮重读，支持下行 cycle:N 动态改频）
        sys.wait(factory_report.get_cycle() * 1000)
    end
end

--[[
启动周期上报（由 app.lua 调用）
幂等：重复调用只启动一次
]]
function factory_report.start()
    if factory_report._started then return end
    factory_report._started = true
    sys.taskInit(report_task)
end

return factory_report
