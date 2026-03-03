local gpsMng = {}

local gps_uart_id = 2

libgnss.clear() -- 清空数据,兼初始化

uart.setup(gps_uart_id, 115200)

function exec_agnss()
    if http then
        -- AGNSS 已调通
        while 1 do
            local code, headers, body = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat").wait()
            -- local code, headers, body = http.request("GET", "http://nutzam.com/6228.bin").wait()
            log.info("gnss", "AGNSS", code, body and #body or 0)
            if code == 200 and body and #body > 1024 then
                -- uart.write(gps_uart_id, "$reset,0,h01\r\n")
                -- sys.wait(200)
                -- uart.write(gps_uart_id, body)
                for offset=1,#body,512 do
                    log.info("gnss", "AGNSS", "write >>>", #body:sub(offset, offset + 511))
                    uart.write(gps_uart_id, body:sub(offset, offset + 511))
                    sys.wait(100) -- 等100ms反而更成功
                end
                io.writeFile("/6228.bin", body)
                break
            end
            sys.wait(60*1000)
        end
    end
    sys.wait(20)
    -- 读取之前的位置信息
    local gnssloc = io.readFile("/gnssloc")
    if gnssloc then
        str = "$AIDPOS," .. gnssloc
        log.info("POS", str)
        uart.write(gps_uart_id, str .. "\r\n")
        str = nil
        gnssloc = nil
    else
        -- TODO 发起基站定位
        uart.write(gps_uart_id, "$AIDPOS,3432.70,N,10885.25,E,1.0\r\n")
    end
end
sys.taskInit(function()
    -- Air780EG工程样品的GPS的默认波特率是9600, 量产版是115200,以下是临时代码
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
    -- libgnss.on("raw", function(data)
    --     -- 默认不上报, 需要的话自行打开
    --     data = data:split("\r\n")
    --     if data == nil then
    --         return
    --     end
    -- end)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    -- libgnss.debug(true)
    -- 显示串口配置
    -- uart.write(gps_uart_id, "$CFGPRT,1\r\n")
    -- sys.wait(20)
    -- 增加显示的语句
    -- uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    -- sys.wait(20)
    -- uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    -- sys.wait(20)
    -- uart.write(gps_uart_id, "$CFGMSG,0,6,1\r\n") -- ZDA
    -- sys.wait(20)
    exec_agnss()
end)

sys.taskInit(function ()
    while true do
        log.info("nmea", "isFix", libgnss.isFix())
        sys.wait(10000)
    end

end)

--获取时间
function gpsMng.getTime()
    local tTime = libgnss.getZda()
    return (string.format("%02d%02d%02d%02d%02d%02d",tTime.year-2000,tTime.month,tTime.day,tTime.hour+8,tTime.min,tTime.sec)):fromHex()
end

return gpsMng