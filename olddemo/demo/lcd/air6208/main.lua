-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcd_tp_airui"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local lcd_use_buff = true

local rtos_bsp = rtos.bsp()
local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    return lcd.HWID_0, 7, 12, 14, 2 -- sdio模拟spi
end

local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()

-- air101 sdio模拟spi 驱动测试屏幕
lcd.init("nv3041a", {
    port = spi_id,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    pin_cs = pin_cs,
    bus_speed = 120 * 1000 * 1000,
    direction = 0,
    w = 480,
    h = 272,
    xoffset = 0,
    yoffset = 0,
    endianness_swap = true
}, spi_lcd)

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    if lcd_use_buff then
        lcd.setupBuff() -- 使用lua内存, 只需要选一种
    end

    local function tp_callBack(tp_device,tp_data)
        sys.publish("TP",tp_device,tp_data)
    end

    i2c_id = i2c.createSoft(pin.PB24, pin.PB25)
    tp_device = tp.init("gt911", {
        port = i2c_id,
        pin_rst = 37,
        pin_int = 38
    }, tp_callBack)

    local ret = airui.init(480, 272, airui.COLOR_FORMAT_RGB565)
    if not ret then
        log.error("airui", "init failed", ret)
        return
    end

    airui.indev_bind_touch(tp_device)

    -- 开关组件
    local sw = airui.switch({
        parent = airui.screen,
        checked = true, -- 初始状态，默认 false
        x = 40,
        y = 120,
        w = 120,
        h = 60, -- x, y, w, h
        style = "success", -- 预设样式，如 "danger"/"success"
        on_change = function(self) -- 状态变更回调
            log.info("switch", "state changed", self:get_state())
        end
    })

    local btn = airui.button({
        parent = airui.screen, -- 父对象，可选，默认当前屏幕
        text = "我是合宙AirUI",
        x = 280,
        y = 60,
        w = 160,
        h = 48,
        on_click = function(self)
            log.info("button", "clicked")
        end
    })

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
