local airlan = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false
local lan_state = false
local number = 0
local bytes = ""
local ms_duration = ""
local bandwidth = ""
local lan_net_state = "未打开"
local event = ""


local function start_lan()
    sys.wait(500)
    log.info("ch390", "打开LDO供电")
    lan_net_state = "打开LDO供电"
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
    sys.wait(3000)
    local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4,mark, gw)
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end

    sys.wait(2000)
    dhcpsrv.create({adapter=socket.LWIP_ETH})
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    netdrv.napt(socket.LWIP_GP)
    log.info("启动iperf服务器端")
    lan_net_state = "以太网服务创建成功,启动iperf服务器端"
    iperf.server(socket.LWIP_ETH)
end

local function stop_lan()
   
end
sys.subscribe("IPERF_REPORT", function(bytes, ms_duration, bandwidth)
    log.info("iperf", bytes, ms_duration, bandwidth)
end)
function airlan.run()       
    log.info("airlan.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
    run_state = true
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"以太网LAN状态:"..lan_net_state )
        if lan_state then
            lcd.drawStr(0,120,"bytes:" .. bytes )
            lcd.drawStr(0,140,"ms_duration:" .. ms_duration )
            lcd.drawStr(0,160,"bandwidth:" .. bandwidth )
            lcd.drawStr(0,180,"空间 LUA:" .. rtos.meminfo() .. ",SYS:" .. rtos.meminfo("sys") )
            lcd.drawStr(0,200, event)
        end

        lcd.showImage(20,360,"/luadb/back.jpg")
        if lan_state then
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

local function start_lan_task()
    lan_state = true
    start_lan()
end


local function stop_lan_task()
    -- stop_lan()
    lan_state = false
end
function airlan.start_lan() 
    start_lan()
end

function airlan.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if lan_state then
            sysplus.taskInitEx(stop_lan_task, "stop_lan_task")
        else
            sysplus.taskInitEx(start_lan_task , "start_lan_task")
        end
    end
end

return airlan