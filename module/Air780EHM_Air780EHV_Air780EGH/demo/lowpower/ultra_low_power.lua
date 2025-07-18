local server_ip = "112.125.89.8" 
local server_port = 47523 -- 换成自己的
local period = 3 * 60 * 60 * 1000 -- 3小时唤醒一次

local reason, slp_state = pm.lastReson() -- 获取唤醒原因
log.info("wakeup state", pm.lastReson())
local libnet = require "libnet"

local d1Name = "D1_TASK"
local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function testTask(ip, port)
    local txData
    if reason == 0 then
        txData = "normal wakeup"
    elseif reason == 1 then
        txData = "timer wakeup"
    elseif reason == 2 then
        txData = "pad wakeup"
    elseif reason == 3 then
        txData = "uart1 wakeup"
    end
    if slp_state > 0 then
        mobile.flymode(0, false) -- 退出飞行模式，进入psm+前进入飞行模式，唤醒后需要主动退出
    end

    --gpio.close(32)

    local netc, needBreak
    local result, param, is_err
    netc = socket.create(nil, d1Name)
    socket.debug(netc, false)
    socket.config(netc) 
    local retry = 0
    while retry < 3 do
        log.info(rtos.meminfo("sys"))
        result = libnet.waitLink(d1Name, 0, netc)
        result = libnet.connect(d1Name, 5000, netc, ip, port)
        if result then
            log.info("服务器连上了")
            result, param = libnet.tx(d1Name, 15000, netc, txData)
            if not result then
                log.info("服务器断开了", result, param)
                break
            else
                needBreak = true
            end
        else
            log.info("服务器连接失败")
        end
        libnet.close(d1Name, 5000, netc)
        retry = retry + 1
        if needBreak then
            break
        end
    end

    uart.setup(1, 9600) -- 配置uart1，外部唤醒用
    
    -- 配置GPIO以达到最低功耗的目的
	gpio.close(23) 
    gpio.close(45) 
    gpio.close(46) --这里pwrkey接地才需要，不接地通过按键控制的不需要

    pm.dtimerStart(3, period) -- 启动深度休眠定时器

    mobile.flymode(0, true) -- 启动飞行模式，规避可能会出现的网络问题
    pm.power(pm.WORK_MODE, 3) -- 进入极致功耗模式

    sys.wait(15000) -- demo演示唤醒时间是三十分钟，如果15s后模块重启，则说明进入极致功耗模式失败，
    log.info("进入极致功耗模式失败，尝试重启")
    rtos.reboot()
end
sysplus.taskInitEx(testTask, d1Name, netCB, server_ip, server_port)
