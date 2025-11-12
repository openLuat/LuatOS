--[[
@module httpdns_task
@summary httpdns 功能模块
@version 1.0
@date    2025.10.29
@author  拓毅恒
@usage
用法实例

启动 HTTPDNS 功能
- 运行 httpdnstask 任务，等待网络就绪后循环查询域名。
- 示例中分别使用阿里DNS和腾讯DNS解析 “air32.cn” 与 “openluat.com”。
- 解析结果通过 log.info 打印到串口。

注：本demo无需额外配置，直接在 main.lua 中 require "httpdns_task" 即可加载运行。
]]

httpdns = require "httpdns"

local function httpdnstask()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("httpdns", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态
        sys.waitUntil("IP_READY", 1000)
    end
    
    -- 检测到了IP_READY消息
    log.info("httpdns", "recv IP_READY", socket.dft())
    log.info("已联网")
    while true do
        sys.wait(1000)
        -- 通过阿里DNS获取结果
        local ip = httpdns.ali("air32.cn")
        log.info("httpdns", "air32.cn", ip)


        -- 通过腾讯DNS获取结果
        local ip = httpdns.tx("openluat.com")
        log.info("httpdns", "openluat.com", ip)
    end
end

sys.taskInit(httpdnstask)