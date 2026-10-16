--[[
@module  network_airlink
@summary airlink多网融合模块
@version 1.0
@date    2026.07.27
@usage
本demo通过AirLink SPI模式实现Air1601外挂Air6205 WiFi模块联网功能。

主要功能：
1. 初始化WiFi虚拟网卡（SPI模式）
2. Air1601与Air6205进行数据交互
3. 通过HTTP GET请求测试网络连接

使用示例：
require("network_airlink")
]]

--============================================================
-- 全局配置参数
--============================================================

-- AirLink SPI 配置
local AIRLINK_SPI_ID = 2           -- SPI ID: SPI2
local AIRLINK_SPI_CS_PIN = 4       -- CS引脚gpio号: GPIO4
local AIRLINK_SPI_RDY_PIN = 13     -- RDY引脚gpio号: GPIO13
local AIRLINK_SPI_SPEED = 20 * 1000000 -- SPI速度：20MHz

-- WiFi配置（请根据实际WiFi热点修改）
local WIFI_SSID = "书房"       -- WiFi名称
local WIFI_PASSWORD = "12345678" -- WiFi密码

-- 测试配置
local HTTP_URL = "https://httpbin.air32.cn/bytes/2048"
local HTTP_INTERVAL = 10000 -- HTTP请求间隔：10秒
local HTTP_TIMEOUT = 9000   -- HTTP超时：9秒
local SDATA_INTERVAL = 1000 -- 数据发送间隔：1秒

--============================================================
-- 模块加载
--============================================================

local exnetif = require "exnetif"

--============================================================
-- 网络初始化
--============================================================

-- 初始化网络，使得Air1601可以外挂Air6205模块实现WiFi联网功能。
local function init_airlink_net()
    -- 配置airlink WiFi单网卡（SPI模式）
    -- Air6205仅支持2.4G WiFi，不支持5G WiFi
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,             -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_SPI_MASTER, -- airlink工作模式：SPI主机模式
                airlink_spi_id = AIRLINK_SPI_ID,        -- airlink使用的SPI接口ID
                airlink_cs_pin = AIRLINK_SPI_CS_PIN,    -- airlink使用的片选引脚gpio号
                airlink_rdy_pin = AIRLINK_SPI_RDY_PIN,  -- airlink使用的rdy引脚gpio号
                airlink_spi_speed = AIRLINK_SPI_SPEED,  -- airlink使用的SPI速度
                ssid = WIFI_SSID,                       -- WiFi名称
                password = WIFI_PASSWORD                -- WiFi密码
            }
        }
    })
    -- 注意：airlink_wifi使用socket.LWIP_STA作为网卡标识（由exnetif内部硬编码），
    -- 不支持airlink_adapter自定义网卡标识
end

--============================================================
-- 数据收发
--============================================================

-- Air1601发送数据信息给Air6205模块。
local function airlink_sdata_Air6205()
    -- 设置网络时间同步。
    -- socket.sntp()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(SDATA_INTERVAL)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

--============================================================
-- 测试函数
--============================================================

-- HTTP GET请求测试，用于判断Air1601的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(HTTP_INTERVAL)
        -- 检查WiFi网卡是否就绪
        log.info("网卡状态", netdrv.ready(socket.LWIP_STA))
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", HTTP_URL)
        local code, headers, body = http.request("GET", HTTP_URL, nil, nil, {
            timeout = HTTP_TIMEOUT,
            adapter = socket.LWIP_STA
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
            sys.publish("打印网卡信息", "succeeded")
        else
            log.error("HTTP请求失败", "错误码", code)
            sys.publish("打印网卡信息", "failed")
        end
    end
end

--============================================================
-- 事件订阅
--============================================================

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

--============================================================
-- 启动入口
--============================================================

-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 开启airlink
sys.taskInit(init_airlink_net)

-- HTTP GET请求测试
sys.taskInit(http_get_test)

-- Air1601发送数据信息给Air6205模块。
sys.taskInit(airlink_sdata_Air6205)
