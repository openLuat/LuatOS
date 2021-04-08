
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
本DEMO需要V0005或2020-12-14及之后的源码才支持
]]

--[[
显示屏为佳显 1.54寸,200x200,快刷屏
硬件接线
显示屏SPI          --> Air302 SPI
显示屏 Pin_BUSY        (GPIO18)
显示屏 Pin_RES         (GPIO7)
显示屏 Pin_DC          (GPIO9)
显示屏 Pin_CS          (GPIO16)
]]

_G.pm_sleep_sec = 3600

--//-----------------------------------------------------
-- 非预期唤醒监测函数, TODO 在固件内实现
-- 如需使用ctiot, 那么lpmem的前1800字节将被ctiot使用, 请把偏移量往后移动
function pm_enter_hib_mode(sec)

    lpmem.write(512, pack.pack(">HI", 0x5AA5, os.time()))
    pm.dtimerStart(0, sec*1000)
    pm.request(pm.HIB) 
    log.info("pm check",pm.check())
    sys.wait(300*1000)
end

function pm_wakeup_time_check ()
    log.info("pm", pm.lastReson())
    if pm.lastReson() == 1 then
        local tdata = lpmem.read(512, 6) -- 0x5A 0xA5, 然后一个32bit的int
        local _, mark, tsleep = pack.unpack(tdata, ">HI")
        if mark == 0x5AA5 then
            local tnow = os.time()
            log.info("pm", "sleep time", tsleep, tnow)
			--下面的3600S根据休眠时间设置，最大可以设置休眠时间-12S。
            if tnow - tsleep < (pm_sleep_sec - 12) then
                pm.request(pm.HIB) -- 建议休眠
                return -- 是提前唤醒, 继续睡吧
            end
        end
    end
    return true
end
--//----------------------------------------------------------------


function eink154_update()
    -- 访问天气服务,稍后开放设备位置的设置
    http.get("http://www.luatos.com/api/public/weather?imei=" .. nbiot.imei(), {timeout = 5000}, function(code,headers,data)
        log.info("http show", code, data)
        if data then
            objnow = json.decode(data)
        end
        sys.publish("HTTP_OK")
    end) 
    sys.waitUntil("HTTP_OK", 6000)

    -- 获取失败,就不更新了
    if not objnow then return end

    -- 读取本地时间, 接了SHT30
    i2c.setup(0)
    local re, H, T = i2c.readSHT30(0)
    if re then
        log.info("sht30", H, T)
    end
    i2c.close(0)

    -- 设置视窗大小
    eink.setWin(200, 200, 0)

    -- 获取电池电量
    adc.open(1)
    local _, bat = adc.read(1)
    adc.close(1)
    log.debug("Bat:", bat+0)

    -- 显示标题Title
    eink.bat(170, 2, tonumber(bat))
    eink.print(0, 2, objnow.cityEn, 0, 12)
    eink.print(70, 2, objnow.date, 0, 12)

    -- 今天 天气
    eink.weather_icon(10, 20, 100, objnow.wea_img)
    eink.print(60,  30, objnow.tem .. "C", 0, 24)        
    eink.print(60,  55, objnow.tem2 .. "C~" .. objnow.tem1 .. "C", 0, 12)

    -- 刷新时间
    local t = os.date("%H:%M")
    eink.print(100, 45, t, 12)

    -- 室内温湿度
    eink.print(40,  85, tostring(T) .. "C/".. tostring(H) .."%", 0, 24)

    -- 明天 天气
    local str = objnow.data[1].date
    str = string.sub(str,6,string.len(str))
    eink.print(15, 130, str, 0, 12)
    eink.weather_icon(10, 140, 101, objnow.data[1].wea_img)
    eink.print(10, 188, objnow.data[1].tem2 .. "C~" .. objnow.data[1].tem1 .. "C", 0, 12)
    
    -- 后天 天气
    str = objnow.data[2].date
    str = string.sub(str,6,string.len(str))
    eink.print(80, 130, str, 0, 12)
    eink.weather_icon(75, 140, 102, objnow.data[2].wea_img)
    eink.print(75, 188, objnow.data[2].tem2 .. "C~" .. objnow.data[2].tem1 .. "C", 0, 12)

    -- 大后天 天气
    str = objnow.data[3].date
    str = string.sub(str,6,string.len(str))
    eink.print(145, 130, str, 0, 12)
    eink.weather_icon(140, 140, 103, objnow.data[3].wea_img)
    eink.print(140, 188, objnow.data[3].tem2 .. "C~" .. objnow.data[3].tem1 .. "C", 0, 12)

    -- 刷屏幕
    eink.show()
end



sys.taskInit(function()

    -- 先检查是否为想要的唤醒
    if not pm_wakeup_time_check() then
        sys.wait(10*60*1000)
    end

    if not socket.isReady() then
        while not socket.isReady() do
            sys.waitUntil("NET_READY", 1000)
            log.info("wait net ready")
        end
    end
    -- 初始化必要的参数
    log.info("eink", "begin setup")
    eink.setup(1, 0)
    log.info("eink", "end setup")

    -- 稍微等一会,免得墨水屏没初始化完成
    sys.wait(1000)
    while 1 do
        log.info("e-paper 1.54", "Testing Go\r\n")
        eink154_update()
        log.info("e-paper 1.54", "Testing End\r\n")

        sys.wait(500) -- 稍微等一会
        pm_enter_hib_mode(pm_sleep_sec) -- 一小时一次够了吧
        --sys.wait(300000)
    end
end)

sys.run()
