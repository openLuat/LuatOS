--[[
IPv6服务端演示, 仅EC618系列支持, 例如Air780E/Air600E/Air780UG/Air700E
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ipv6_client"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"

-- 处理未识别的网络消息
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

-- 演示task
function ipv6test()
    -- 仅EC618系列支持, 例如Air780E/Air600E/Air780UG/Air700E
    if rtos.bsp() ~= "EC618" then
        while 1 do
            log.info("ipv6", "only Air780E/Air600E/Air780UG/Air700E supported")
            sys.wait(1000)
        end
    end

    -- 启用IPv6, 默认关闭状态,必须在驻网前开启
    -- 注意, 启用IPv6, 联网速度会慢2~3秒
    mobile.ipv6(true)

    log.info("ipv6", "等待联网")
    sys.waitUntil("IP_READY")
    log.info("ipv6", "联网完成")
    sys.wait(100)

    -- 打印一下本地ip, 一般只有ipv6才可能是公网ip, ipv4基本不可能
    -- 而且ipv6不一样是外网ip, 这是运营商决定的, 模块无能为力
    ip, mask, gw, ipv6 = socket.localIP()
    log.info("本地IP地址", ip, ipv6)
	if not ipv6 then
		log.info("没有IPV6地址，无法演示")
		-- return
	end

    -- 这里给个演示用的ddns, 临时自建的, 仅供测试
    http.request("GET", "http://81.70.22.216:8280/update?secret=luatos&domain=864040064024194.dyndns&addr=" .. ipv6).wait()
    log.info("DDNS", "已映射", mobile.imei() .. ".dyndns.u8g2.com")
    log.info("shell", "telnet -6 " .. mobile.imei() .. ".dyndns.u8g2.com 14000")

    -- 开始正在的逻辑, 发起socket链接,等待数据/上报心跳
    local taskName = "ipv6client"
    local topic = taskName .. "_txrx"
    local txqueue = {}
    sysplus.taskInitEx(ipv6task, taskName, netCB, taskName, txqueue, topic)
    while 1 do
        local result, tp, data = sys.waitUntil(topic, 30000)
        if not result then
            -- 等很久了,没数据上传/下发, 发个日期心跳包吧
            table.insert(txqueue, string.char(0))
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "uplink" then
            -- 上行数据, 主动上报的数据,那就发送呀
            table.insert(txqueue, data)
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "downlink" then
            -- 下行数据,接收的数据, 从ipv6task来的
            -- 其他代码可以通过 sys.publish()
            log.info("socket", "收到下发的数据了", #data)
        end
    end
end



function ipv6task(d1Name, txqueue, rxtopic)
    -- 本地监听的端口
    local port = 14000


    local rx_buff = zbuff.create(1024)
    local netc = socket.create(nil, d1Name)
    socket.config(netc, 14000)
    log.info("任务id", d1Name)

    while true do
        log.info("socket", "开始监控")
        local result = libnet.listen(d1Name, 0, netc)
        if result then
			log.info("socket", "监听成功")
            result = socket.accept(netc, nil)    --只支持1对1
            if result then
			    log.info("客户端连上了")
            end
        else
            log.info("socket", "监听失败!!")
		end
		while result do
            -- log.info("socket", "调用rx接收数据")
			local succ, param = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("socket", "收到服务器数据，长度", rx_buff:used())
                local data = rx_buff:query() -- 获取数据
                sys.publish(rxtopic, "downlink", data)
				rx_buff:del()
			end
            -- log.info("libnet", "调用wait开始等待消息")
			result, param, param2 = libnet.wait(d1Name, 15000, netc)
            log.info("libnet", "wait", result, param, param2)
			if not result then
                -- 网络异常了
				log.info("socket", "服务器断开了", result, param)
				break
            elseif #txqueue > 0 then
                while #txqueue > 0 do
                    local data = table.remove(txqueue, 1)
                    if not data then
                        break
                    end
                    result,param = libnet.tx(d1Name, 15000, netc,data)
                    log.info("libnet", "发送数据的结果", result, param)
                    if not result then
                        log.info("socket", "数据发送异常", result, param)
                        break
                    end
                end
            end
		end
		libnet.close(d1Name, 5000, netc)
		-- log.info(rtos.meminfo("sys"))
		sys.wait(5000)
    end
end

sys.taskInit(ipv6test)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

