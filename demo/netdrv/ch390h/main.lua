-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

sys.taskInit(function ()
    sys.wait(3000)
    local result = spi.setup(
        0,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    print("open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        print("spi open error",result)
        return
    end

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spiid=0,cs=8})
    netdrv.dhcp(socket.LWIP_ETH, true)
end)


sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(100)
        log.info("http", http.request("GET", "https://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

-- http://iot.openluat.com/api/site/firmware_upgrade?project_key=4MQAVweO8au0KQqxm4eHWnzV4ppiAZ5x&imei=864536072623240&device_key=&firmware_name=v6tracker_LuatOS-SoC_Air201&version=2002.1.5&model=Air780EPS_A13
-- http://iot.openluat.com/api/site/firmware_upgrade?project_key=epeGacglnQylV5jSKybIj1Dvqk6vm6nu&firmware_name=StudentCard_LuatOS-SoC_Air201&version=2002.1.4&imei=864536072623240