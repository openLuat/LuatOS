--[[
连到gps.nutz.cn 19002 端口, irtu的自定义包格式
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "scdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"

if pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

adc.open(adc.CH_VBAT)

--=============================================================
-- 本TCP演示是连接到 gps.nutz.cn 19002 端口, irtu的自定义包格式
-- 网页是 https://gps.nutz.cn/ 输入IMEI号可参考当前位置
-- 微信小程序是 irtu寻物, 点击IMEI号, 扫描模块的二维码可查看当前位置和历史轨迹
local host = "gps.nutz.cn"  -- 服务器ip或者域名, 都可以的
local port = 19002          -- 服务器端口号
local is_udp = false        -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false        -- 加密与否, 要看服务器的实际情况
--=============================================================

-- 处理未识别的网络消息
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local socket_ready = false
local taskName = "sc"
local topic = taskName .. "_txrx"
log.info("socket", "event topic", topic)

-- 演示task
local function sockettest()
    sys.waitUntil("IP_READY")

    -- 开始正在的逻辑, 发起socket链接,等待数据/上报心跳
    local txqueue = {}
    sysplus.taskInitEx(sockettask, taskName, netCB, taskName, txqueue, topic)
    while 1 do
        local result, tp, data = sys.waitUntil(topic, 30000)
        -- log.info("event", result, tp, data)
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
        sysplus.cleanMsg(d1Name)
        local result = libnet.connect(d1Name, 15000, netc, host, port)
        if result then
			log.info("socket", "服务器连上了")
            local tmp = {imei=mobile.imei(),iccid=mobile.iccid()}
			libnet.tx(d1Name, 0, netc, json.encode(tmp))
            socket_ready = true
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
                    -- log.info("libnet", "发送数据的结果", result, param)
                    if not result then
                        log.info("socket", "数据发送异常", result, param)
                        break
                    end
                end
            end
            -- 循环尾部, 继续下一轮循环
		end
        socket_ready = false
        -- 能到这里, 要么服务器断开连接, 要么上报(tx)失败, 或者是主动退出
		libnet.close(d1Name, 5000, netc)
		-- log.info(rtos.meminfo("sys"))
		sys.wait(3000) -- 这是重连时长, 自行调整
    end
end

sys.taskInit(sockettest)


sys.taskInit(function()
    sys.waitUntil("IP_READY")
    local stat_t = 0
    local buff = zbuff.create(64)
    while true do
        if socket_ready then
            -- 发送设备状态  >b7IHb  ==  1*7+4+2+1 = 14
            if os.time() - stat_t > 30 then
                -- 30秒上报一次
                local vbat = adc.get(adc.CH_VBAT)
                buff:seek(0)
                buff:pack(">b7IHb", 0x55, 0, 0, 0, 0, 0, 0, 0, vbat, mobile.csq())
                sys.publish(topic, "uplink", buff:query())
                stat_t = os.time()
                sys.wait(100)
            end
            -- 发送位置信息 >b2i3H2b3 == 1*2+4*3+2*2+1*3 == 2+12+4+3 = 21
            if true then
                local rmc = libgnss.getRmc(1)
                local gsa = libgnss.getGsa()
                local gsv = libgnss.getGsv()
                -- log.info("socket", "rmc", rmc.lat, rmc.lng, rmc.alt, rmc.course, rmc.speed)
                buff:seek(0)
                buff:pack(">b2i3H2b3", 0xAA, libgnss.isFix() and 1 or 0,
                        os.time(),
                        rmc and rmc.lng or 0,
                        rmc and rmc.lat or 0,
                        0, -- rmc and rmc.alt or 0,
                        math.floor(rmc and rmc.course or 0),
                        math.floor(rmc and rmc.speed or 0),
                        gsa and #gsa.sats or 0, -- msg.sateCno
                        gsv and gsv.total_sats or 0 -- msg.sateCnt
                )
                sys.publish(topic, "uplink", buff:query())
            end
            sys.wait(1000)
        else
            sys.wait(100)
        end
    end
end)
