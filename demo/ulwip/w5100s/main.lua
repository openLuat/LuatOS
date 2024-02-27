
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ulwip"
VERSION = "1.0.0"

--[[
本demo是尝试对接W5100

W5100的文档
https://www.wiznet.io/wp-content/uploads/wiznethome/Chip/W5100/Document/W5100_DS_V128E.pdf
https://d1.amobbs.com/bbs_upload782111/files_29/ourdev_555431.pdf

接线方式:
1. 5V -> VCC
2. GND -> GND
3. SCK -> PB05
4. MISO -> PB06
5. MOSI -> PB07
6. CS -> PB04

本demo的现状:
1. 一定要为W5100s稳定供电
2. 确保w5100s与模块的物理连接是可靠的
3. 当前使用轮询方式读取W5100s的状态, 未使用中断模式
]]

-- sys库是标配
_G.sys = require("sys")
require "sysplus"

SPI_ID = 0
spi.setup(SPI_ID, nil, 0, 0, 8, 10*1000*1000)
PIN_CS = gpio.setup(pin.PB04, 1, gpio.PULLUP)

TAG = "w5100s"
local mac = "0C1234567890"
local adapter_index = socket.LWIP_ETH

w5100s = require "w5100s"
sys.taskInit(function()
    sys.wait(1000)
    if wlan and wlan.connect then
        wlan.init()
    end
    w5100s.init("w5100s", {
        spi_id = SPI_ID,
        pin_cs = PIN_CS,
        mac = mac,
        adapter = adapter_index,
        dft = true
    })
    w5100s.start()

    while 1 do
        sys.wait(3000)
        log.info("发起http请求")
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=adapter_index, timeout=15000, debug=true}).wait()
        -- local code, headers, body = http.request("GET", "http://www.baidu.com/", nil, nil, {adapter=adapter_index, timeout=15000, debug=true}).wait()
        -- local code, headers, body = http.request("GET", "http://192.168.1.6:8000/get", nil, nil, {adapter=adapter_index, timeout=5000, debug=true}).wait()
        log.info("ulwip", "http", code, json.encode(headers or {}), body)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
