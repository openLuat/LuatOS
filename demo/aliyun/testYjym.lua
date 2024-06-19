
local sys = require "sys"
local aliyun = require "aliyun"

--根据自己的服务器修改以下参数
-- 阿里云资料：https://help.aliyun.com/document_detail/147356.htm?spm=a2c4g.73742.0.0.4782214ch6jkXb#section-rtu-6kn-kru
local tPara = {
    -- 一机一密
    -- 设备名名称, 必须唯一
    DeviceName = "azNhIbNNTdsVwY2mhZno",
    -- 产品key, 在产品详情页面
    ProductKey = "a1YFuY6OC1e",     --产品key
    --设备密钥,一型一密就不填, 一机一密(预注册)必须填
    DeviceSecret = "5iRxTePbEMguOuZqltZrJBR0JjWJSdA7", --设备secret
    -- 填写实例id，在实例详情页面, 如果是旧的公共实例, 请填RegionId参数
    InstanceId = "",
    RegionId = "cn-shanghai",
    --是否使用ssl加密连接
    mqtt_isssl = false,
}

-- 等待联网, 然后初始化aliyun库
sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.waitUntil("net_ready")

    log.info("已联网", "开始初始化aliyun库")
    aliyun.setup(tPara)
end)
