
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnss_udp"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- GNSS数据从uart2输入, 通常的波特率是9600,这里写的是115200
-- 9600读取太慢了, 最好能设置到115200
uart.on(2, "recv", function(id, len)
    local data = uart.read(2, 1024)
    --log.info("uart2", data)
    libgnss.parse(data)
end)
uart.setup(2, 115200) -- 如果没数据,那就改成9600试试吧

-- 定时打印一下最新的坐标
sys.timerLoopStart(function()
    log.info("GPS", libgnss.getIntLocation())
end, 2000) -- 两秒打印一次

-- 联网上报任务
sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            sys.wait(2000)
            -- 以下地址luatos提供的一个测试服务
            local netc = socket.udp()
            --netc:host("devtrack.luatos.io")
            netc:host("39.105.203.30")
            netc:port(9170)
            netc:on("connect", function(id, re)
                log.info("udp", "connect ok", id, re)
                if re then
                    -- 连接成功, 发送注册包
                    netc:send(nbiot.imei() .. "#" .. string.char(0x01, 0x03) .. nbiot.iccid())
                end
            end)
            netc:on("recv", function(id, data)
                -- 服务器会下发点数据,当前就"OK"两个字节,没什么左右
                log.info("udp", "recv", #data, data)
            end)
            if (netc:start()) == 0 then
                while netc:closed() == 0 do
                    sys.waitUntil("NETC_END_" .. netc:id(), 30000)
                    if (netc:closed()) == 0 then
                        -- 定位成功,发送定位信息
                        if libgnss.isFix() then
                            local data = nbiot.imei() .. "#" .. string.char(0x01, 0x01)
                            local lat, lng, speed = libgnss.getIntLocation()
                            log.info("udp", "send gnss loc", lat, lng)
                            data = data .. pack.pack(">bIIIHHbbbHH", 0x01, os.time(), lng, lat, 0 ,0 ,speed/1000, 0, 0, 0, 0)
                            log.info("udp", data:toHex())
                            netc:send(data)
                        -- 定位失败, 就发个心跳吧
                        else
                            log.info("udp", "send heartbeat")
                            netc:send(nbiot.imei() .. "#" .. string.char(0x01, 0x02))
                        end
                    end
                end
            end
            netc:clean()
            netc:close()
            log.info("udp", "all close, sleep 30s")
            sys.wait(300000)
        else
            sys.wait(1000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
