PROJECT = "lcd_qspi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- require "co5300"
-- require "jd9261t"
-- require "sh8601z"



sys.taskInit(function()
    -- log.info("http.post2sssssssssssssss") -- 只返回code和headers
    -- sys.waitUntil("IP_READY")
    local test_cnt = 0

    pm.ioVol(0, 3300)
    gpio.setup(20,1)    --打开sh8601z LCD电源，根据板子实际情况修改
    gpio.setup(16,1)    --打开jd9261t LCD电源，根据板子实际情况修改
    gpio.setup(17,1)    --打开co5300 LCD电源，根据板子实际情况修改
    local code, headers, body = http.request("GET", "http://airtest.openluat.com:2900/download/test_qspi.jpg",nil,nil,{dst="/ram/test_qspi.jpg"}).wait()
    log.info("http.post", code, headers, body) -- 只返回code和headers
    local code, headers, body = http.request("GET", "http://airtest.openluat.com:2900/download/clock.jpg",nil,nil,{dst="/ram/clock.jpg"}).wait()
    log.info("http.post2", code, headers, body) -- 只返回code和headers
    -- co5300_init({port = lcd.HWID_0, pin_dc = -1, pin_pwr = -1, pin_rst = 36, w = 480, h = 480, interface_mode=lcd.QSPI_MODE,bus_speed=50000000, rb_swap = true})
    -- lcd.setupBuff(nil, false)
    -- lcd.autoFlush(false)
    -- lcd.user_done() --必须在初始化完成后，在正式显示之前
    -- while true do 
    lcd.init("st7735s")
    -- lcd.clear()
    lcd.showImage(0, 0, "/ram/clock.jpg")

    local data = io.readFile("/ram/clock.jpg")
    log.info("文件大小(ramfs)", #data)
    local data2 = io.readFile("/luadb/clock.jpg")
    log.info("文件大小(luadb)", #data2)
    log.info("是否相同", data == data2)
    log.info("md5", crypto.md5(data), crypto.md5(data2))
    -- lcd.showImage(0, 0, "/luadb/clock.jpg")
    -- lcd.flush()
    -- sys.wait(3000)
    -- lcd.showImage(0, 0, "/ram/test_qspi.jpg")
    -- lcd.flush()

    sys.wait(3000)
    -- end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

