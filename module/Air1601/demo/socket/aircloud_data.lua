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


-- 定时发送json数据的回调函数
local function send_aircloud_data()
    sys.waitUntil("CONNECTION_SUCCESS") -- 等待服务器连接成功的消息，确保在连接成功后才开始发送数据
    -- 按照aircloud平台的格式定义要发送的数据
    -- 不需要的变量可以删除，或者注释掉；需要的变量可以增加，或者修改；只要保证field_meaning、data_type、value这三个字段的定义和格式满足aircloud平台的要求即可；
    -- 具体的field_meaning赋值可以参考本目录下的FIELD_MEANINGS.md文件；
    -- 具体的data_type赋值可以参考https://docs.openluat.com/osapi/ext/excloud/#31 中的数据类型常量；
    local send_data = {
    {
        field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, -- 字段含义：时间戳
        data_type = excloud.DATA_TYPES.INTEGER, -- 数据类型：整数
        value = os.time() -- 当前时间戳
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