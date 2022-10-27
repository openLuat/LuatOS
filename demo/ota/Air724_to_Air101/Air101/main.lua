-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "101_UPDATE"
VERSION = "0.0.1"

-- ota流程就是把update.bin放在根目录(esp为"/spiffs/" 其余为"/")，重启后会自动升级.
-- update.bin制作方法:luatools中点击生成量产文件,将 SOC量产及远程升级文件 目录中的XXX.ota文件更名为update.bin即可
log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 10000) -- 10s喂一次狗
end

-- 本demo实现了一个简单的串口数据接收对101进行升级，未对同一串口的其他数据进行区分，仅供参考
-- 注意！！！724串口电平为1.8V，Air101串口电平为3.3V，需要电平转换
--[[
    硬件连接
    Air724UG        Air101

    UART1_TX ------ U1_RX   (PB_07)

    UART1_RX ------ U1_TX   (PB_06)

    GND      ------ GND
]]


local updatePath = "/update.bin" -- 升级数据写入目录

local uartid = 1 -- 根据实际设备选取不同的uartid

-- 初始化
local result = uart.setup(uartid, 115200, 8, 1)

-- 收取数据会触发回调, 这里的"receive" 是固定值
local updateSwitch -- 判断是否接收到了升级文件标识
local checkUniqueId = true -- 等待触发升级
local rdbuf = "" -- 一个串口数据临时缓存
local totalSize, stepSize = 0, 0 -- 升级文件总长度和每次接收的升级文件长度
local updateDataTb = {} -- 升级文件数据临时存放表
sys.taskInit(function()
    while true do
        sys.wait(1000)
        log.info("测试", checkUniqueId)
    end
end)
local function clearRdbuf() rdbuf = "" end
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        -- 如果是air302, len不可信, 传1024
        -- s = uart.read(id, 1024)
        s = uart.read(id, len)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            sys.timerStopAll(clearRdbuf)
            log.info("uart", "receive", id, #s, s)
            if checkUniqueId then
                rdbuf = rdbuf .. s
                local h, t = string.find(rdbuf, "CHECK_UNIQUE_ID\r\n")
                if h then
                    checkUniqueId = false
                    log.info("触发升级，将当前版本号、imei和bsp发送给Air724")
                    uart.write(uartid,"###VER:" .. VERSION .. "BSP:" .. PROJECT.. "_LuatOS-SoC_"..string.upper(rtos.version().."_"..rtos.bsp()) .."IMEI:" .. mcu.unique_id():toHex() .. "&&&")
                    rdbuf = rdbuf:sub(t + 1)
                else
                    rdbuf = rdbuf .. s
                    sys.timerStart(clearRdbuf, 5000)
                end
            else
                if not updateSwitch then
                    rdbuf = rdbuf .. s
                    -- 实现了一个简单的接收数据格式，724发来的升级文件开头有###和&&&的特殊字符，特殊字符中间带有升级文件总长度
                    local h, t = string.find(rdbuf, "###%d+&&&")
                    if h then
                        totalSize = string.match(rdbuf, "###(%d+)&&&")
                        totalSize = tonumber(totalSize)
                        updateSwitch = true
                        rdbuf = rdbuf:sub(t + 1)
                        if rdbuf ~= "" then
                            table.insert(updateDataTb, rdbuf)
                            stepSize = stepSize + #rdbuf
                        end
                        rdbuf = ""
                    else
                        sys.timerStart(clearRdbuf, 5000)
                    end
                else
                    if stepSize < totalSize then
                        if stepSize + #s >= totalSize then
                            table.insert(updateDataTb,
                                         s:sub(1, totalSize - stepSize))
                            stepSize = stepSize +
                                           #s:sub(1, totalSize - stepSize)
                            updateSwitch = false
                            checkUniqueId = true
                            sys.publish("UPDATE_RECV_END")
                        else
                            table.insert(updateDataTb, s)
                            stepSize = stepSize + #s
                        end
                    elseif stepSize >= totalSize then
                        table.insert(updateDataTb,
                                     s:sub(1, stepSize - totalSize))
                        -- s = s:sub(stepSize + 1)
                        checkUniqueId = true
                        updateSwitch = false
                        sys.publish("UPDATE_RECV")
                    end
                end
                log.info("uart recv", s)
            end
        end
    until s == ""
end)

-- 订阅升级文件接收完成的消息，将升级文件写入/目录后，重启
sys.subscribe("UPDATE_RECV_END", function()
    -- 将接收的升级数据写入文件，然后重启
    local file = io.open(updatePath, "wb")
    file:write(table.concat(updateDataTb))
    file:close()
    log.info("重启")
    rtos.reboot()
end)

-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id) log.info("uart", "sent", id) end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
