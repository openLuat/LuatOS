--[[
demo说明:
wifi信息: 修改 wlan.connect
]]
_G.sys = require("sys")

log.info("main", "simple modbus relay demo")

log.info("mac", wlan.get_mac())
wlan.connect("uiot", "12345678") -- wifi信息在这里, 如果想用airkiss, 看app/playit/main.lua
-- airkiss.auto(27) -- 预留的功能,未完成 

-- 联网后自动同步时间
sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!! send ntp")
    sys.taskInit(function()
        sys.wait(3000)
        socket.ntpSync()
    end)
end)

_G.net_link = nil

-- 串口1准备一下
uart.setup(1, 115200)
uart.on(1, "receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart", data:toHex())
    local s = _G.net_link
    if s ~= nil then
        s:send(data)
    end
    --sys.publish("net_send", data)
end)

-- 设置好GPIO的初始化状态
gpio.setup(21, 0)
gpio.setup(22, 0)
gpio.setup(23, 0)
_G.use_netled = 1 -- 启用1, 关闭0

sys.taskInit(function()
    while 1 do
        --log.info("wlan", "ready?", wlan.ready())
        if wlan.ready() then
            --log.info("netled", "net ready, slow")
            gpio.set(21, 1 * use_netled)
            sys.wait(1900)
            gpio.set(21, 0)
            sys.wait(100)
        else
            --log.info("netled", "net not ready, fast")
            gpio.set(21, 1 * use_netled)
            sys.wait(100)
            gpio.set(21, 0)
            sys.wait(100)
        end
    end
end)

sys.subscribe("net_recv", function(id, re, s)
    local hex = re:toHex()
    log.info("recv", id, hex, #re, re)
    uart.write(1, re)
    if #re > 7 then
        local addr,opt,index,val = string.unpack(">bbHH", re)
        log.info("modbus", addr,opt,index,val)
        if addr == 3 and opt == 6 then
            if index == 1 then
                gpio.set(22, 0)
            elseif index == 2 then
                gpio.set(22, 1)
            elseif index == 3 then
                _G.use_netled = val
            end
            s:send(re) -- 原样返回
        else
            s:send(string.char(0))
        end
    end
end)


sys.taskInit(function()
    -- 等待联网成功
    sys.waitUntil("WLAN_READY", 30000)
    while 1 do
        log.info("main", "socket loop")
        if wlan.ready() then -- TODO 感觉wlan.ready()不是很准确,还得研究一下
            collectgarbage("collect")
            local s = socket.tcp()
            s:host("modbus.git4.cn") -- 改成服务器ip或者域名
            s:port(19001) -- 改成服务器端口
            s:on("connect", function(id, re)
                -- 连接成功后, 发注册包 {imei:"AABBCCDDEEFF",csq:-66}
                log.info("netc", "connect result", re)
                if re then
                    local jdata = json.encode({imei=wlan.get_mac(),csq=wlan.rssi()})
                    log.info("send reg", jdata)
                    s:send(jdata)
                    _G.net_link = s
                end
            end)

            s:on("recv", function(id, re)
                if #re > 0 then
                    sys.publish("net_recv", id, re, s)
                end
            end)
            --log.info("netc", "info", s)
            -- 启动tcp独立线程(系统级的)
            if s:start() == 0 then
                -- 启动成功后, 连接中断时必然有NETC_END_XX事件
                -- 因为是长连接, 就这样等着就差不多了
                local tcount = 0
                while s:closed() == 0 do
                    sys.waitUntil("NETC_END_" .. s:id(), 3000)
                    -- 定时发个心跳什么的
                    tcount = tcount + 1
                    if tcount == 20 then
                        log.info("netc", "heartbeat ping")
                        s:send(string.char(0))
                        tcount = 0
                    end
                end
            else
                log.info("netc", "netc start fail!!")
            end
            -- 一定要清理好, 不然内存泄漏, 模块内存少啊!!!
            _G.net_link = nil
            s:clean()
            collectgarbage("collect")
            --sys_memdump()
            sys.wait(2000) -- 没连上, 或者断开了? 等2秒重试
        else
            log.info("wifi", "wifi NOT ready yet")
            sys.waitUntil("WLAN_READY", 30000)
        end
    end
end)


sys.run()
