local bot_asset = {}
--测试使用的配置Token，量产Token请找蚂蚁同学获取
BOT_CONFIG_TOKEN = "iBot-rawData&RUBDPmYzoj2ftkNLEUKBbLjYUNoVHtFZUj0fKTgF8fpkXZbQcbOaNkFuL69rPZ3M0g=="

-- 资产数据字段版本号(assetDataVersion)由蚂蚁定义，默认值为"ADV1.0"，无需修改
BOT_ASSET_DATA_VERSION = "ADV1.0"
-- 资产编号最大长度
BOT_ASSET_ID_MAX_SIZE = 64
-- 资产类型最大长度
BOT_ASSET_TYPE_MAX_SIZE = 64
-- 资产数据版本最大长度
BOT_ASSET_ADV_MAX_SIZE = 16
-- 业务数据包最大长度
BOT_USER_DATA_STRING_MAX_SIZE = 1024
-- 注册失败时最大重试次数
BOT_REG_RETRY_COUNT_MAX = 3

-- 通用资产配置数据结构
function bot_asset.configInfo()
    return {
        id = "",
        type = "",
        adv = ""
    }
end

-- 通用地理位置数据结构
function bot_asset.locationInfo()
    return {
        coordinateSystem = 0,
        longitude = 0.0,
        latitude = 0.0,
        altitude = 0.0,
        source = 0
    }
end

return bot_asset
