
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "nimbledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
local sys = require "sys"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
else
    log.warn("wdt", "not wdt found!!!")
end



leds = {}
if rtos.bsp() == "air101" then -- 与w800/805等价
    leds["a"] = gpio.setup(24, 0, gpio.PULLUP) -- PB_08,输出模式
    leds["b"] = gpio.setup(25, 0, gpio.PULLUP) -- PB_09,输出模式
    leds["c"] = gpio.setup(26, 0, gpio.PULLUP) -- PB_10,输出模式
elseif rtos.bsp() == "air103" then -- 与w806等价
    leds["a"] = gpio.setup(16, 0, gpio.PULLUP) -- PB0,输出模式
    leds["b"] = gpio.setup(17, 0, gpio.PULLUP) -- PB1,输出模式
    leds["c"] = gpio.setup(18, 0, gpio.PULLUP) -- PB2,输出模式
end

-- 注册一个命令列表
cmds = {
    led = function(id, val)
        local led = leds[id]
        if led then
            led(val == "on" and 1 or 0)
        end
    end,
    reboot = function()
        sys.taskInit(function()
            log.info("ble", "cmd reboot, after 5s")
            sys.wait(5000)
            rtos.reboot()
        end)
    end,
}

-- 监听BLE主适配的状态变化
if nimble then


    sys.subscribe("BLE_STATE_INC", function(state)
        log.info("ble", "ble state changed", state)
        if state == 1 then
            nimble.server_init()
        else
            nimble.server_deinit()
        end
    end)
    
    -- 监听GATT服务器的WRITE_CHR
    sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
        -- info 是个table, 但当前没有数据
        log.info("ble", "data got!!", data:toHex())
        if data:len() == 0 then
            return
        end
        local cmd = data:split(",")
        if cmd[1] and cmds[cmd[1]] then
            cmds[cmd[1]](table.unpack(cmd, 2))
        else
            log.info("ble", "unkown cmd", json.encode(cmd))
        end
    end)

    
    -- TODO 支持传数据(read)和推送数据(notify)

    -- 配合微信小程序 "BLE蓝牙开发助手"
    -- 1. 若开发板无天线, 将手机尽量靠近芯片也能搜到
    -- 2. 该小程序是开源的, 每次write会自动分包为16字节

    sys.taskInit(function()
        sys.wait(2000)
        nimble.debug(6)
        nimble.init()
    end)
else
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            log.warn("ble", "this demo need nimble lib")
        end
    end)
end




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
