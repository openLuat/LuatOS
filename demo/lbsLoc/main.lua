
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lbsLocdemo"
VERSION = "1.0.0"

--注意:因使用了sys.wait()所有api需要在协程中使用

--[[注意：此处的PRODUCT_KEY仅供演示使用，不保证一直能用，量产项目中一定要使用自己在iot.openluat.com中创建的项目productKey]]
PRODUCT_KEY = ""

--[[本demo需要lbsLoc库与libnet库, 库位于script\libs, 需require]]
local lbsLoc = require("lbsLoc")

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用lbsLoc库需要下列语句]]
_G.sysplus = require("sysplus")


-- 功能:获取基站对应的经纬度后的回调函数
-- 参数:-- result：number类型，0表示成功，1表示网络环境尚未就绪，2表示连接服务器失败，3表示发送数据失败，4表示接收服务器应答超时，5表示服务器返回查询失败；为0时，后面的5个参数才有意义
		-- lat：string类型，纬度，整数部分3位，小数部分7位，例如031.2425864
		-- lng：string类型，经度，整数部分3位，小数部分7位，例如121.4736522
        -- addr：目前无意义
        -- time：string类型或者nil，服务器返回的时间，6个字节，年月日时分秒，需要转为十六进制读取
            -- 第一个字节：年减去2000，例如2017年，则为0x11
            -- 第二个字节：月，例如7月则为0x07，12月则为0x0C
            -- 第三个字节：日，例如11日则为0x0B
            -- 第四个字节：时，例如18时则为0x12
            -- 第五个字节：分，例如59分则为0x3B
            -- 第六个字节：秒，例如48秒则为0x30
        -- locType：numble类型或者nil，定位类型，0表示基站定位成功，255表示WIFI定位成功
local function getLocCb(result, lat, lng, addr, time, locType)
    log.info("testLbsLoc.getLocCb", result, lat, lng)
    -- 获取经纬度成功
    if result == 0 then
        log.info("服务器返回的时间", time:toHex())
        log.info("定位类型,基站定位成功返回0", locType)
    end
    -- 广播给其他需要定位数据的task
    -- sys.publish("lbsloc_result", result, lat, lng)
end

sys.taskInit(function()
    sys.waitUntil("IP_READY", 30000)
    while 1 do
        lbsLoc.request(getLocCb)
        sys.wait(60000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
