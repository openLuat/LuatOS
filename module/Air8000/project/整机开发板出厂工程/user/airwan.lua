local airwan = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false
local wan_state = false
local wifi_net_state = "未打开"
local bytes = 0
local ms_duration = 0
local bandwidth = 0
local event = ""


local function start_wan()
    sys.wait(500)
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP)     --打开ch390供电
    sys.wait(2000)
    local result = spi.setup(
        1,--spi_id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    netdrv.dhcp(socket.LWIP_ETH, true)

    iperf.client(socket.LWIP_ETH, "192.168.4.1")
    wifi_net_state = "创建完成,iperf 客户端创建完成"
end

local function stop_wan()
   
end
sys.subscribe("IPERF_REPORT", function(bytes, ms_duration, bandwidth)
    log.info("iperf", bytes, ms_duration, bandwidth)
    bytes = bytes
    ms_duration = ms_duration
    bandwidth = bandwidth
end)
function airwan.run()       
    log.info("airwan.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"以太网WAN状态:"..wifi_net_state )
        if wan_state then
            lcd.drawStr(0,120,"bytes:" .. bytes )
            lcd.drawStr(0,140,"ms_duration:" .. ms_duration )
            lcd.drawStr(0,160,"bandwidth:" .. bandwidth )
            lcd.drawStr(0,180,"空间 LUA:" .. rtos.meminfo() .. ",SYS:" .. rtos.meminfo("sys") )
            lcd.drawStr(0,200, event)
        end

        lcd.showImage(20,360,"/luadb/back.jpg")
        if wan_state then
            lcd.showImage(130,370,"/luadb/stop.jpg")
        else
            lcd.showImage(130,370,"/luadb/start.jpg")
        end
        

        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束
            return true
        end
    end
end

local function start_wan_task()
    wan_state = true
    start_wan()
end


local function stop_wan_task()
    -- stop_wan()
    wan_state = false
end
function airwan.start_wan() 
    start_wan()
end

function airwan.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if wan_state then
            sysplus.taskInitEx(stop_wan_task, "stop_wan_task")
        else
            sysplus.taskInitEx(start_wan_task , "start_wan_task")
        end
    end
end

return airwan