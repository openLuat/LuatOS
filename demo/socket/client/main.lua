--[[
socket客户端演示

包括但不限于以下模组
1. EC618系列 -- Air780E/Air780EG/Air600E/Air700E
2. ESP32系列 -- ESP32C3/ESP32S3/ESP32C2
3. Air105搭配W5500
4. 其他适配了socket层的bsp

支持的协议有: TCP/UDP/TLS-TCP/DTLS, 更高层级的协议,如http有单独的库

提示: 
1. socket支持多个连接的, 通常最多支持8个, 可通过不同的taskName进行区分
2. 支持与http/mqtt/websocket/ftp库同时使用, 互不干扰
3. 支持IP和域名, 域名是自动解析的, 但解析域名也需要耗时
4. 加密连接(TLS/SSL)需要更多内存, 这意味着能容纳的连接数会小很多, 同时也更慢

对于多个网络出口的场景, 例如Air780E+W5500组成4G+以太网:
1. 在socket.create函数设置网络适配器的id
2. 请到同级目录查阅更细致的demo

如需使用ipv6, 请查阅 demo/ipv6, 本demo只涉及ipv4
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "scdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"


--=============================================================
-- 测试网站 https://netlab.luatos.com/ 点击 打开TCP 获取测试端口号
-- 要按实际情况修改
local host = "112.125.89.8" -- 服务器ip或者域名, 都可以的
local port = 35721          -- 服务器端口号
local is_udp = false        -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false        -- 加密与否, 要看服务器的实际情况
--=============================================================

-- 处理未识别的网络消息
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

-- 统一联网函数
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持, 要根据实际情况修改ssid和password!!
        local ssid = "uiot"
        local password = "123456"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- EC618系列, 如Air780E/Air600E/Air700E
        -- mobile.simid(2) -- 自动切换SIM卡, 按需启用
        -- 模块默认会自动联网, 无需额外的操作
    elseif w5500 then
        -- w5500 以太网
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
    elseif socket then
        -- 适配了socket库也OK, 就当1秒联网吧
        sys.timerStart(sys.publish, 1000, "IP_READY")
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

-- 演示task
local function sockettest()
    -- 等待联网
    sys.waitUntil("net_ready")

    -- 开始正在的逻辑, 发起socket链接,等待数据/上报心跳
    local taskName = "sc"
    local topic = taskName .. "_txrx"
    local txqueue = {}
    sysplus.taskInitEx(sockettask, taskName, netCB, taskName, txqueue, topic)
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



function sockettask(d1Name, txqueue, rxtopic)
    -- 打印准备连接的服务器信息
    log.info("socket", host, port, is_udp and "UDP" or "TCP", is_tls and "TLS" or "RAW")

    -- 准备好所需要的接收缓冲区
    local rx_buff = zbuff.create(1024)
    local netc = socket.create(nil, d1Name)
    socket.config(netc, nil, is_udp, is_tls)
    log.info("任务id", d1Name)

    while true do
        -- 连接服务器, 15秒超时
        log.info("socket", "开始连接服务器")
        local result = libnet.connect(d1Name, 15000, netc, host, port)
        if result then
			log.info("socket", "服务器连上了")
			libnet.tx(d1Name, 0, netc, "helloworld")
        else
            log.info("socket", "服务器没连上了!!!")
		end
		while result do
            -- 连接成功之后, 先尝试接收
            -- log.info("socket", "调用rx接收数据")
			local succ, param = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
            -- 如果服务器有下发数据, used()就必然大于0, 进行处理
			if rx_buff:used() > 0 then
				log.info("socket", "收到服务器数据，长度", rx_buff:used())
                local data = rx_buff:query() -- 获取数据
                sys.publish(rxtopic, "downlink", data)
				rx_buff:del()
			end
            -- log.info("libnet", "调用wait开始等待消息")
            -- 等待事件, 例如: 服务器下发数据, 有数据准备上报, 服务器断开连接
			result, param, param2 = libnet.wait(d1Name, 15000, netc)
            log.info("libnet", "wait", result, param, param2)
			if not result then
                -- 网络异常了, 那就断开了, 执行清理工作
				log.info("socket", "服务器断开了", result, param)
				break
            elseif #txqueue > 0 then
                -- 有待上报的数据,处理之
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
            -- 循环尾部, 继续下一轮循环
		end
        -- 能到这里, 要么服务器断开连接, 要么上报(tx)失败, 或者是主动退出
		libnet.close(d1Name, 5000, netc)
		-- log.info(rtos.meminfo("sys"))
		sys.wait(30000) -- 这是重连时长, 自行调整
    end
end

sys.taskInit(sockettest)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

