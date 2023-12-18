local bot_asset = require("bot_asset")

local bot_app_ebike = {}

-- EBike 数据上报格式
local ebike_pub_data_fmt = [[
{
  "assetId": "%s",
  "vehStatus": %d,
  "mileage": %d,
  "batteryCap": %d,
  "soh": %d,
  "soc": %d,
  "voltage": %d,
  "temperature": %d,
  "fullChargeCycles": %d,
  "batteryStatus": %d,
  "dataTime": "%s",
  "coordinateSystem": %d,
  "longitude": %f,
  "latitude": %f,
  "altitude": %f,
  "source": %d
}
]]

-- EBike 资产类型code
local asset_type_code_ebike = {
    EBICYCLE_TYPE_OTHERS  = 1011,           -- 其他
    EBICYCLE_TYPE_BICYCLE = 1012,           -- 单车
    EBICYCLE_TYPE_PEDELEC = 1013            -- 助力车
}

-- EBike 数据结构
local function create_asset_data()
    return {
        vehStatus = 0,                      -- 车辆状态           
        mileage = 0,                        -- 单次里程，单位：米
        batteryCap = 0,                     -- 电池剩余容量，单位：mAh
        soh = 0,                            -- 电池健康状态，取值范围:[0-100]
        soc = 0,                            -- 电池电量，取值范围:[0-100]
        voltage = 0,                        -- 电池电压，单位:0.01V 
        temperature = 0,                    -- 电池温度，单位:0.01℃
        fullChargeCycles = 0,               -- 累计充放电次数
        batteryStatus = 0,                  -- 电池状态，0-搁置，1-充电，2-放电，3-预留
        dataTime = "",                      -- 数据采集时间，"20211103173632"表示2021/11/03 17:36:32
        location = bot_asset.locationInfo() -- 地理位置信息
    }
end

local function user_asset_id_get()
    -- 资产编号，作为资产的唯一标识, 根据实际修改， "BOT-TEST" 仅用于测试 
    -- 需用户按实际情况填写
    return "BOT-TEST"
end


function bot_app_ebike.user_asset_config_get()
    local asset_config = bot_asset.configInfo()

    -- /***************** 以下信息需用户按实际情况填写 *******************************/

    local asset_id = user_asset_id_get()
    local asset_type_code = asset_type_code_ebike.EBICYCLE_TYPE_PEDELEC
    -- 表示资产型号, 内容为自定义字符串(且不能带有符号"-")
    local asset_model = "WD215"

    -- /***************** 以上信息需用户按实际情况填写 *******************************/

    asset_config.id = asset_id
    asset_config.type = tostring(asset_type_code) .. "-" .. asset_model
    asset_config.adv = BOT_ASSET_DATA_VERSION

    return asset_config
end


function bot_app_ebike.user_asset_data_get()
    local ebike_data = create_asset_data()

    -- /***************** 以下信息需用户按实际情况填写 *******************************/ 

    -- /* ！！！必填项，详细说明请参考项目信息表 */
    -- /* 业务数据，需要填入实际运行数据，缺省字段请不要删除，int型默认传入: -1，string默认传入: "-" */
    ebike_data.vehStatus = 12               -- /* 车辆状态 */
    ebike_data.mileage = 5000               -- /* 单次里程，单位：米 */
    ebike_data.batteryCap = 20000           -- /* 电池剩余容量，单位：mAh */
    ebike_data.soh = 90                     -- /* 电池健康状态，取值范围:[0-100] */
    ebike_data.soc = 90                     -- /* 电池电量，取值范围:[0-100] */
    ebike_data.voltage = 3000               -- /* 电池电压，单位:0.01V */
    ebike_data.temperature = 3000           -- /* 电池温度，单位:0.01℃ */
    ebike_data.fullChargeCycles = 12        -- /* 累计充放电次数 */
    ebike_data.batteryStatus = 1            -- /* 电池状态，0-搁置，1-充电，2-放电，3-预留 */
    ebike_data.dataTime = "20221027173632"  -- /* 数据采集时间，"20211103173632"表示2021/11/03 17:36:32 */

    -- /* 非必填项 */
    -- /* 地理位置信息，若没有地理位置信息数据，请不要删除字段，默认传入：-1 */
    ebike_data.location.coordinateSystem = 2    --  /* 坐标系，1-WGS_84，2-GCJ_02 */
    ebike_data.location.longitude = 121.5065267 -- /* 经度 */
    ebike_data.location.latitude = 31.2173088   -- /* 纬度 */
    ebike_data.location.altitude = 30.04        -- /* 海拔高度 */
    ebike_data.location.source = 0              -- /* 定位源 */

    -- /***************** 以上信息需用户按实际情况填写 *******************************/

    -- /* 此处为信息组包，用户无需关注 */
    local data = string.format(ebike_pub_data_fmt,
        user_asset_id_get(),
        ebike_data.vehStatus,
        ebike_data.mileage,
        ebike_data.batteryCap,
        ebike_data.soh,
        ebike_data.soc,
        ebike_data.voltage,
        ebike_data.temperature,
        ebike_data.fullChargeCycles,
        ebike_data.batteryStatus,
        ebike_data.dataTime,
        ebike_data.location.coordinateSystem,
        ebike_data.location.longitude,
        ebike_data.location.latitude,
        ebike_data.location.altitude,
        ebike_data.location.source
    )

    print("bot user data: " .. data, "len " .. #data)

    return data
end

return bot_app_ebike