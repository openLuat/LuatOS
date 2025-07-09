-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "libnetifdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
-- sys = require "sys"
libnetif = require "libnetif"
-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)                     -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 测试tcp连接
-- require "tcp_test"

sys.taskInit(function()
    sys.wait(10000)
    --设置网络优先级
    libnetif.setPriorityOrder({
        -- {
        --     ETHERNET = {
        --         pwrpin = 140,
        --         ping_ip = "112.125.89.8",
        --     }
        -- },
        {
            WIFI = {
                ssid = "test",
                password = "HZ88888888",
                ping_ip = "112.125.89.8"
            }
        },
        { LWIP_GP = true
        }
    })
    --设置多网融合功能
    -- libnetif.setproxy(socket.LWIP_AP, socket.LWIP_GP, "test", "HZ88888888", nil)
    -- libnetif.setproxy(socket.LWIP_ETH, socket.LWIP_GP, nil, nil, 140)
end)


 

sys.taskInit(function()
    while 1 do
        sys.wait(6000)
        log.info("http",
            http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
