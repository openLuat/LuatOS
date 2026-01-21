--[[
@module  excloud_test
@summary excloud测试文件
@version 1.0
@usage
本demo演示的功能为：
演示excloud扩展库的使用。
]]
-- 导入excloud库
local excloud = require("excloud")
--加载lbsLoc2库
-- local lbsLoc2 = require("lbsLoc2")
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
-- local getCellInfo1
-- local band1
-- local lat, lng
-- -- 定期轮训式
-- sys.taskInit(function()
--     sys.wait(3000)
--     while 1 do
--         mobile.reqCellInfo(15)
--         sys.waitUntil("CELL_INFO_UPDATE", 30000)
--         getCellInfo1 = mobile.getCellInfo()
--         band1 = getCellInfo1[1].band
--         log.info("驻留频段", band1, json.encode(getCellInfo1))
--         lat, lng, t = lbsLoc2.request(5000, nil, nil, true) --需要经纬度和当前时间
--         --(时间格式{"year":2024,"min":56,"month":11,"day":12,"sec":44,"hour":14})
--         log.info("lbsLoc2", lat, lng, (json.encode(t or {})))  --打印经纬度和时间
--         sys.wait(60000)
--     end
-- end)
-- local temprature, humidity
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

        local http_result = json.encode(excloud_message.http_test)
        log.info("http_test",http_result)
        local ok, err_msg = excloud.send({
            {
             
                --固件版本
                field_meaning = excloud.FIELD_MEANINGS.FIRMWARE_VERSION,--固件版本号
                data_type = excloud.DATA_TYPES.ASCII,
                value = rtos.version() -- 信号强度
            },
            {
                --iccid
                field_meaning = excloud.FIELD_MEANINGS.MODULE_VERSION,
                data_type = excloud.DATA_TYPES.ASCII,
                value = rtos.bsp() -- sim卡iccid
            },
            {
                --固件错误信息
                field_meaning = excloud.FIELD_MEANINGS.LUA_CORE_ERROR ,
                data_type = excloud.DATA_TYPES.ASCII,
                value = json.encode(excloud_message.device_status.error_message) --
            },
            {
                --http_test测试结果
                field_meaning = excloud.FIELD_MEANINGS.HTTP_TEST,
                data_type = excloud.DATA_TYPES.ASCII,
                value = http_result
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
