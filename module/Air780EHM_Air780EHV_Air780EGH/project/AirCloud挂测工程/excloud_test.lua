--[[
@module  excloud_test
@summary excloud测试文件
@version 1.0
@date    2025.09.25
@author  王城钧
@usage
本demo演示的功能为：
演示excloud扩展库的使用。
]]
-- 导入excloud库
local excloud = require("excloud")
--加载AirSHT30_1000驱动文件
local air_sht30 = require "AirSHT30_1000"
--加载lbsLoc2库
local lbsLoc2 = require("lbsLoc2")

-- 注册回调函数
excloud.on(function(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. data.message)
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. data.header.sequence_num)

        -- 处理服务器下发的消息
        for _, tlv in ipairs(data.tlvs) do
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                log.info("收到控制命令: " .. tostring(tlv.value))

                -- 处理控制命令并发送响应
                local response_ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.ASCII,
                        value = "命令执行成功"
                    }
                }, false)

                if not response_ok then
                    log.info("发送控制响应失败: " .. err_msg)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功，流水号: " .. data.sequence_num)
        else
            log.info("发送失败: " .. data.error_msg)
        end
    end
end)
local getCellInfo1
local band1
local lat, lng
-- 定期轮训式
sys.taskInit(function()
    sys.wait(3000)
    while 1 do
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 30000)
        getCellInfo1 = mobile.getCellInfo()
        band1 = getCellInfo1[1].band
        log.info("驻留频段", band1, json.encode(getCellInfo1))
        lat, lng, t = lbsLoc2.request(5000, nil, nil, true) --需要经纬度和当前时间
        --(时间格式{"year":2024,"min":56,"month":11,"day":12,"sec":44,"hour":14})
        log.info("lbsLoc2", lat, lng, (json.encode(t or {})))  --打印经纬度和时间
        sys.wait(60000)
    end
end)
local temprature, humidity
sys.taskInit(function()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.wait(1000)
    -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        -- device_id = "862419074073247",   -- 设备ID (IMEI前14位)
        device_type = 1,                               -- 设备类型: 4G
        host = "124.71.128.165",                       -- 服务器地址
        port = 9108,                                   -- 服务器端口
        auth_key = "SIsRml1ImTsP6XR4lvRAQVuksbZZuUpO", -- 鉴权密钥
        transport = "tcp",                             -- 使用TCP传输
        auto_reconnect = true,                         -- 自动重连
        reconnect_interval = 10,                       -- 重连间隔(秒)
        max_reconnect = 5,                             -- 最大重连次数
        timeout = 30,                                  -- 超时时间(秒)
    })
    -- 配置MQTT连接参数
    -- local ok, err_msg = excloud.setup({
    --     device_type = 1,             -- 设备类型: 4G设备
    --     transport = "mqtt",          -- 使用MQTT传输协议
    --     host = "airtest.openluat.com",   -- MQTT服务器地址
    --     port = 1883,                 -- MQTT服务器端口
    --     auth_key = "VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi", -- 鉴权密钥(请替换为实际密钥)
    --     username = "root",    -- MQTT用户名(可选)
    --     password = "Luat123456", -- MQTT密码(可选)
    --     keepalive = 300,             -- 心跳间隔(秒)
    --     -- auto_reconnect = true,       -- 自动重连
    --     reconnect_interval = 10,     -- 重连间隔(秒)
    --     max_reconnect = 5,           -- 最大重连次数
    --     timeout = 30,                -- 超时时间(秒)
    --     qos = 1,                     -- MQTT QoS等级(0/1/2)
    --     -- retain = false,              -- MQTT retain标志
    --     -- clean_session = true,        -- MQTT clean session
    --     ssl = false                  -- 不使用SSL
    -- })

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")
    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end

    log.info("excloud服务已开启")
    -- 在主循环中定期上报数据
    while true do
        -- 每60秒上报一次数据
        sys.wait(60000)       
        -- 检查连接状态
        -- local status = excloud.status()
        -- if not status.is_connected or not status.is_authenticated then
        --     log.info("设备未连接或未认证，跳过数据上报")
        -- else

        -- 获取信号强度
        local rssi = mobile.csq()
        log.info("信号强度", rssi)

        -- 获取sim卡的iccid
        local iccid = mobile.iccid()
        log.info("iccid", iccid)

        -- 获取驻留频段
        local buff = zbuff.create(40)

        -- 获取驻留小区
        local cell_info = mobile.scell()
        local cell_id = cell_info.cid
        log.info("小区ID", cell_id)

        -- 获取环境温度
        --打开sht30硬件
        air_sht30.open(1)

        --读取温湿度数据
        temprature, humidity = air_sht30.read()
        log.info("温度", temprature, humidity)

        -- 获取cpu温度
        adc.open(adc.CH_CPU)              --打开adc.CH_CPU通道
        local data5 = adc.get(adc.CH_CPU) --获取adc.CH_CPU计算值，将获取到的值赋给data5
        -- adc.close(adc.CH_CPU)--关闭adc.CH_CPU通道
        log.info("CPU温度", data5)

        if not lat then
            lat = 0
        end
        
        if not lng then
            lng = 0
        end

        if not rssi then
            rssi = 0
        end

        if not cell_id then
            cell_id = 0
        end

        if not temprature then
            temprature = 0
        end

        if not humidity then
            humidity = 0
        end

        if not band1 then
            band1 = 0
        end

        if not iccid then
            iccid = ""
        end

        if not data5 then
            data5 = 0
        end

        local ok, err_msg = excloud.send({
            {
                --信号强度
                field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = rssi -- 信号强度
            },
            {
                --iccid
                field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,
                data_type = excloud.DATA_TYPES.ASCII,
                value = iccid -- sim卡iccid
            },
            {
                --驻留频段
                field_meaning = excloud.FIELD_MEANINGS.SERVING_CELL,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = band1 -- 驻留频段
            },
            {
                --驻留小区
                field_meaning = excloud.FIELD_MEANINGS.CELL_INFO,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = cell_id -- 驻留小区
            },
            {
                --环境温度
                field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = temprature -- 环境温度
            },
            {
                --环境湿度
                field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = humidity -- 环境湿度
            },
            {
                --cpu温度
                field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = data5 -- cpu温度
            },
            {
                --经度
                field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
                data_type = excloud.DATA_TYPES.ASCII,
                value = lng
            },
            {
                --纬度
                field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
                data_type = excloud.DATA_TYPES.ASCII,
                value = lat
            }
        }, false) -- 不需要服务器回复

        if not ok then
            log.info("发送数据失败: " .. err_msg)
        else
            log.info("数据发送成功")
        end
        -- end
    end
end)
