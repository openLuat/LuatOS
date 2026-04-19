--[[
@module  aircloud_data
@summary 网络驱动设备功能模块
@version 1.0
@date    2026年3月26日
@author  黄何
@usage
本文件为aircloud数据处理模块，核心业务逻辑为：根据aircloud服务器要求的格式，构建要发送的数据结构，并且定时发送给tcp client socket的发送功能模块；
1、构建要发送的数据结构，数据结构为一个table，table中每一个元素也是一个table，每个元素的字段含义如下：

    field_meaning：字段含义，必须按照aircloud平台的要求进行定义，
        aircloud平台要求的字段含义可以参考excloud中参数描述，使用时直接将excloud.FIELD_MEANINGS中定义的字段含义赋值给field_meaning即可；
        如果需要发送自定义数据，无法在excloud.FIELD_MEANINGS中找到合适的字段含义，可以将field_meaning赋值为0，表示自定义数据，此时data_type和value的定义和格式也必须满足aircloud平台的要求；

    data_type：数据类型，必须按照aircloud平台的要求进行定义，
        aircloud平台要求的数据类型可以参考excloud.DATA_TYPES这个table中的定义，使用时直接将excloud.DATA_TYPES中定义的数据类型赋值给data_type即可；

value：数据值，按照field_meaning定义的字段含义和data_type定义的数据类型，构建对应的数据值；

2、定时发送构建好的数据结构给tcp client socket的发送功能模块；

本文件没有对外接口，使用时直接在main.lua中require "aircloud_data"就可以加载运行；
]] 
local excloud = require "excloud"

-- 注意：目前硬件还未支持此功能，当前不能使用
-- 获取VBAT电压的函数
-- local function vabt_vaule()
--     adc.open(adc.CH_VBAT) -- 打开adc.CH_VBAT通道
--     local vabt_vaule = adc.get(adc.CH_VBAT) -- 获取adc.CH_VBAT计算值
--     adc.close(adc.CH_VBAT) -- 关闭adc.CH_VBAT通道
--     log.info("VBAT", vabt_vaule / 1000) -- 打印adc.CH_VBAT计算值，单位：毫伏
--     return vabt_vaule / 1000 or 3.300 -- 如果获取到的值为nil，则返回3300   
-- end

-- 定时发送json数据的回调函数
local function send_aircloud_data()
    sys.waitUntil("CONNECTION_SUCCESS") -- 等待服务器连接成功的消息，确保在连接成功后才开始发送数据
    -- 按照aircloud平台的格式定义要发送的数据
    -- 不需要的变量可以删除，或者注释掉；需要的变量可以增加，或者修改；只要保证field_meaning、data_type、value这三个字段的定义和格式满足aircloud平台的要求即可；
    -- 具体的field_meaning赋值可以参考本目录下的FIELD_MEANINGS.md文件；
    -- 具体的data_type赋值可以参考https://docs.openluat.com/osapi/ext/excloud/#31 中的数据类型常量；
    local send_data = {
    -- 注意：mobile库相关的aircloud协议的TLV数据还不支持，目前还不能用
    -- {
    --     field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, -- 字段含义：4G信号强度
    --     data_type = excloud.DATA_TYPES.INTEGER, -- 数据类型：整数
    --     value = mobile.csq() or 0 -- 信号强度
    -- }, 
    -- {
    --     field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID, -- 字段含义：SIM卡的ICCID号
    --     data_type = excloud.DATA_TYPES.ASCII, -- 数据类型：ASCII字符串
    --     value = mobile.iccid() or "" -- SIM卡ICCID
    -- }, 
    {
        field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, -- 字段含义：时间戳
        data_type = excloud.DATA_TYPES.INTEGER, -- 数据类型：整数
        value = os.time() -- 当前时间戳
    }, 
    -- {
    --     field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID, -- 字段含义：设备号
    --     data_type = excloud.DATA_TYPES.ASCII, -- 数据类型：ASCII字符串
    --     value = mobile.imei() or "" -- 设备IMEI（4G模块）
    -- }, 
    {
        field_meaning = excloud.FIELD_MEANINGS.VOLTAGE, -- 字段含义：电压
        data_type = excloud.DATA_TYPES.INTEGER, -- 数据类型：整数
        value = vabt_vaule() -- vbat电压值
    }, 
    {
        field_meaning = 0, -- 自定义数据，使用0作为field_meaning
        data_type = excloud.DATA_TYPES.UNICODE, -- 数据类型：Unicode字符串
        value = "用户utf-8格式自定义数据"
    }}
    while 1 do
        sys.wait(30000) -- 每隔30秒发送一次数据
        -- 打印构建的数据结构，用于调试
        log.info("send_data structure:", json.encode(send_data))

        local send_data_string = json.encode(send_data)
        sys.publish("SEND_DATA_REQ", "Aircloud_main", send_data_string)
    end

end
sys.taskInit(send_aircloud_data)