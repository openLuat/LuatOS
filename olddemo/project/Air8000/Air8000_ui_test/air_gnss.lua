local air_gnss = {}
function log_ui(...)
    lcd.clear()

    -- 把...拼成一个字符串,然后输出到UI
    local r = {}
    for i = 1, select('#', ...) do
        table.insert(r, tostring(select(i, ...)))
    end
    if #r == 0 then
        table.insert(r, "nil")
    end
    lcd.drawStr(50, 50, table.concat(r, "\t"))
    -- uart.write(1, "\r\n")
    log.info("log", table.concat(r, "\t"))
end



-- gnss的备电和gsensor的供电
local vbackup = gpio.setup(24, 0)
-- gnss的供电

local gpsPower = pm.power(pm.GPS, true)

local function gnss_pwr(on, vbak)

    log.info("GPS", "start")
    -- gnss的复位
    -- local gpsRst = gpio.setup(27, 1)

    local uartId = 2
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartId, 115200)
    libgnss.bind(2, 1)

    vbackup((vbak or on) and 1 or 0)

    gpsPower(on and 1 or 0)
    log_ui("vbackup power:", (vbak or on) and 1 or 0)

    log_ui("gpsPower power:", on and 1 or 0)
    sys.timerLoopStart(function()
    if libgnss.isFix() then
        libgnss.clear()
        sys.publish("GNSS_FIXED_TOPIC")
    end
end, 200)
end

local waitSeconds = 5 --热启动等待时间
local isHotStart = true --是否是热启动
local testCount = 100 --测试循环次数

function air_gnss.gnss_start()

    log_ui("start gnss test")
    -- 先给gps开机
    gnss_pwr(true, isHotStart)
    log_ui("gnss power on")
    -- 等待第一次定位成功
    sys.waitUntil("GNSS_FIXED_TOPIC")
    log_ui("gnss first fixed")

    local failCount = 0

    for i = 1, testCount do
        log_ui("gnss test count:", i)
        -- 关闭gps
        log_ui("gnss power off")
        gnss_pwr(false, isHotStart)
        sys.wait(1000)
        -- 打开gps
        log_ui("gnss power on")
        local closeTime = os.time()
        gnss_pwr(true, isHotStart)
        -- 等待定位成功
        sys.waitUntil("GNSS_FIXED_TOPIC")
        local fixedTime = os.time()
        -- 等待5s
        sys.wait(5000)
        -- 计算定位时间
        local diffTime = fixedTime - closeTime
        -- 如果定位时间小于waitSeconds,则认为定位成功
        if diffTime < waitSeconds then
            log_ui("gnss fixed time:", diffTime)
        else
            log_ui("gnss fixed time:", diffTime, "fail")
            failCount = failCount + 1
        end
        log_ui("gnss test success percent:", (i - failCount) / i * 100, "%", failCount, "/", i)
    
    end
end


return air_gnss
