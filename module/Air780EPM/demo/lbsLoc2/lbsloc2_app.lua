--[[
@module  lbsloc2_app.lua
@summary lbsloc2单基站定位应用
@version 1.0
@date    2025.08.13
@author  王城钧
@usage
本文件为lbsloc2“单基站”定位功能演示，核心业务逻辑为：
1. 等待网络就绪  
2. 循环获取基站信息
3. 请求定位 

本文件没有对外接口，直接在main.lua中require "lbsloc2_app"就可以加载运行；
]]

-- 加载lbsloc2库
local lbsLoc2 = require("lbsLoc2")

-- lbsloc2循环定位函数
local function lbsloc2_task_func()
    while not socket.adapter(socket.dft()) do
            log.warn("lbsloc2_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("lbsloc2_task_func", "recv IP_READY", socket.dft())

    while true do 
        mobile.reqCellInfo(15)--进行基站扫描，超时时间为15s
        sys.waitUntil("CELL_INFO_UPDATE", 3000)--等到扫描成功，超时时间3S
        log.info("扫描出的基站信息", json.encode(mobile.getCellInfo())) -- 打印基站信息
        local lat, lng, t = lbsLoc2.request(5000)--仅需要基站定位给出的经纬度
        --local lat, lng, t = lbsLoc2.request(5000,nil,nil,true)--需要经纬度和当前时间
        --(时间格式{"year":2024,"min":56,"month":11,"day":12,"sec":44,"hour":14})
        log.info("lbsLoc2", lat, lng, (json.encode(t or {})))--打印经纬度和时间
        sys.wait(60000) -- 1分钟定位一次
    end
end

sys.taskInit(lbsloc2_task_func)


