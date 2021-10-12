
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "udpuart"
VERSION = "1.0.0"

--[[
    这个demo演示一个简易的DTU功能, 数据的两端分别是UDP服务器器和UART
]]

-- sys库是标配
_G.sys = require("sys")


-- 把串口配置好
sys.subscribe("uart_write", function(data)
    uart.write(2, data)
end)

uart.on(2, "receive", function(id, len)
    local data = uart.read(id, 1024)
    log.info("uart", "receive", data)
    sys.publish("uart_recv", data) -- 对应socket任务里面的sys.waitUntil
end)
uart.setup(2, 115200)

-- socket任务
sys.taskInit(function()
    while 1 do
        -- 先判断是否联网
        if socket.isReady() then
            sys.wait(1000) -- 稍微等一下,成功率高
            local netc = socket.udp() -- 如果改成socket.tcp() 这就是TCP的demo了,写法没什么区别
            -- 服务器信息, 使用域名的话还需要进行解析,有概率失败, 推荐使用ip
            netc:host("nutz.cn") -- 必须是公网域名/公网ip, 内网ip是连不上的!!!!
            netc:port(17888)
            -- 监听连接成功的事件, udp并未真正的连接建立过程, 所以通常都会成功
            netc:on("connect", function(id, re)
                log.info("udp", "connect ok", id, re)
                if re then
                    netc:send("reg," .. nbiot.imei() .. "," .. nbiot.iccid()) -- 加个前缀方便服务器识别数据,非必须
                end
            end)
            -- 监听数据接收的事件, 服务器需要下发数据
            netc:on("recv", function(id, data)
                log.info("udp", "recv", #data, data)
                sys.publish("uart_write", data) -- 发布消息, 对应UART函数里面的 sys.subscribe("uart_write", function()...)
            end)
            -- 监听事件配好了,开始真正的连接(udp无连接过程,但还是需要启动一下)
            if netc:start() == 0 then
                -- 一直循环, 直至连接中断
                while netc:closed() == 0 do
                    -- 监听  连接关闭, 或者uart数据接收,或者超时
                    local re, data = sys.waitUntil({"NETC_END_" .. netc:id(), "uart_recv"}, 30000)
                    if netc:closed() == 0 then
                        -- 仅uart数据接收时会有data数据,且类型为string
                        if type(data) == "string" then
                            netc:send("data," .. nbiot.imei() .. "," .. data) -- 这里加前缀"data," 只是为了方便识别.非必须
                        end
                    end
                end
            end
            -- 必须清理连接上下文,确保关闭和清理掉系统资源
            netc:clean()
            netc:close()
            log.info("udp", "all close, sleep 30s")
            sys.wait(30000) -- 毕竟是NBIOT, 断开后建议休眠长一些
        else
            sys.wait(1000) -- 等联网
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
