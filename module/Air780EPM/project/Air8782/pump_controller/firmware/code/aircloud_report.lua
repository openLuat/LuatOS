--[[
@module  aircloud_report
@summary 上行数据上报（AirCloud TLV 封装 + 上报策略）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.3 与 network-communication-protocol.md 9.3：
1. 订阅 PUMP_DATA_READY，缓存最新运行数据；
2. 上报策略：
   - 运行状态(devstate)变化 或 故障(devstate==5) → 立即上报（need_reply=true）；
   - 鉴权成功后立即上报一次（need_reply=false）；
   - 之后每 report_cycle(60s) 心跳上报一次（need_reply=false）；
3. 按 network-communication-protocol.md 9.3 的字段映射封装 TLV。
本模块无对外接口，直接 require "aircloud_report" 即加载运行。
]]

local config_app    = require("config_app")
local msg_bus       = require("msg_bus")
local excloud_app   = require("excloud_app")

local F  = config_app.FIELD
local DT = config_app.DATA_TYPES

-- 上报字段定义（key=运行数据字段；field=AirCloud 字段编号；dt=数据类型）
local REPORT_FIELDS = {
    { key = "outHz",     field = F.outHz,     dt = DT.FLOAT },
    { key = "setHz",     field = F.setHz,     dt = DT.FLOAT },
    { key = "muV",       field = F.muV,       dt = DT.FLOAT },
    { key = "outV",      field = F.outV,      dt = DT.FLOAT },
    { key = "outA",      field = F.outA,      dt = DT.FLOAT },
    { key = "outkw",     field = F.outkw,     dt = DT.FLOAT },
    { key = "nbTemp",    field = F.nbTemp,    dt = DT.INTEGER }, -- 256 温度
    { key = "H",         field = F.H,         dt = DT.INTEGER },
    { key = "devstate",  field = F.devstate,  dt = DT.INTEGER }, -- 265 工作状态
    { key = "oneHz",     field = F.oneHz,     dt = DT.FLOAT },
    { key = "oneA",      field = F.oneA,      dt = DT.FLOAT },
    { key = "twoHz",     field = F.twoHz,     dt = DT.FLOAT },
    { key = "twoA",      field = F.twoA,      dt = DT.FLOAT },
    { key = "threeHz",   field = F.threeHz,   dt = DT.FLOAT },
    { key = "threeA",    field = F.threeA,    dt = DT.FLOAT },
    { key = "timestamp", field = F.timestamp, dt = DT.INTEGER }, -- 1280 时间戳
}

-- 上报缓存
local latest_data  = nil -- 最新运行数据
local last_devstate = nil -- 上次运行状态

-- 组装 TLV 列表（跳过采集失败的字段）
local function build_tlvs(data)
    local tlvs = {}
    for _, f in ipairs(REPORT_FIELDS) do
        local v = data[f.key]
        if v ~= nil then
            tlvs[#tlvs + 1] = {
                field_meaning = f.field,
                data_type     = f.dt,
                value         = v,
            }
        end
    end
    return tlvs
end

-- 上报（need_reply：事件上报为 true，心跳为 false）
local function report(data, need_reply)
    local tlvs = build_tlvs(data)
    if #tlvs == 0 then
        return
    end
    local ok, err = excloud_app.send_tlv(tlvs, need_reply)
    if not ok then
        log.warn("aircloud_report", "上报失败", err)
    else
        log.info("aircloud_report", need_reply and "事件上报" or "心跳上报", "字段数", #tlvs)
    end
end

-- 订阅采集数据：判定即时上报
-- 仅在运行状态"发生变化"时立即上报（含首次、含变到故障）——边沿触发；
-- 持续处于同一状态（例如一直处于故障 5）不再逐帧重复上报，改由心跳周期（report_cycle）上报。
local function on_pump_data(data)
    latest_data = data

    local ds = data.devstate
    if ds ~= nil and ds ~= last_devstate then
        last_devstate = ds
        report(data, true) -- 状态变化（含首次、含变到故障）→ 立即上报
    end
end

-- 上报任务：鉴权成功后“立即上报一次”，之后每 report_cycle(10s) 上报最新数据
local function heartbeat_task()
    sys.waitUntil(msg_bus.AIRCLOUD_READY)
    log.info("aircloud_report", "鉴权成功，启动上报（立即首报 + 每", config_app.report_cycle, "秒）")

    -- 等待首帧数据（最多 report_cycle 秒），以便鉴权成功后能立即上报一次
    local waited = 0
    while latest_data == nil and waited < config_app.report_cycle do
        sys.wait(1000)
        waited = waited + 1
    end

    while true do
        if latest_data then
            report(latest_data, false)
        end
        sys.wait(config_app.report_cycle * 1000)
    end
end

sys.subscribe(msg_bus.PUMP_DATA_READY, on_pump_data)
sys.taskInit(heartbeat_task)
