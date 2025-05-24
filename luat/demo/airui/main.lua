--- 模块功能：airui demo
-- @module airui
-- @author ？？？
-- @release 2025.05.24

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airui_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

--加载sys库
_G.sys = require("sys")


local lcd_chip = "st7796"       -- "st7796" or "jd9261t_inited"
function lcd_init()
    sys.wait(500)
    gpio.setup(164, 1, gpio.PULLUP)
    gpio.setup(141, 1, gpio.PULLUP)

    sys.wait(1000)
    if lcd_chip == "st7796" then
        lcd.init("st7796", {
            port = lcd.HWID_0,        -- 使用的spi id 号
            pin_dc = 0xff,            -- 命令选择硬件，不设置
            pin_pwr = 9,              -- 背光控制管脚，默认打开背光，不设置
            pin_rst = 2,              -- 屏幕reset 管脚  
            direction = 1,            -- 屏幕方向 0: 0度 1:90度 2:180度 3:270度
            w = 480,                  -- 屏幕宽度
            h = 320,                  -- 屏幕高度
            xoffset = 0,              -- X轴偏移像素
            yoffset = 0,              -- Y轴偏移像素
            sleepcmd = 0x10,          -- LCD睡眠命令
            wakecmd = 0x11,           -- LCD唤醒命令
        })
    elseif lcd_chip == "jd9261t_inited" then
        lcd.init("jd9261t_inited", { 
            port = lcd.HWID_0,                  -- 使用的spi id 号
            pin_pwr = 160,                      -- 背光控制管脚
            pin_rst = 36,                       -- 屏幕reset 管脚
            direction = 0,                      -- 屏幕方向 0: 0度 1:90度 2:180度 3:270度
            w = 480,                            -- 屏幕宽度
            h = 480,                            -- 屏幕高度
            xoffset = 0,                        -- X轴偏移像素
            yoffset = 0,                        -- Y轴偏移像素
            interface_mode = lcd.QSPI_MODE,     -- 接口模式 qspi
            bus_speed = 70000000,               -- SPI总线速度
            flush_rate = 658,                   -- 刷新率
            vbp = 19, vfp = 108, vs = 2         -- VBP:垂直后沿, VFP:垂直前沿, VS:垂直同步
        })
    end

    gpio.setup(160, 1, gpio.PULLUP) -- 单独拉高背光

    if lcd_chip == "jd9261t_inited" then
        lcd.setupBuff(nil, true)        -- 开启buff缓存，更适合lvgl场景
        lcd.autoFlush(false)
    end
end

function tp_init()
    if tp then
        local function tp_callBack(tp_device, tp_data)
            log.info("TP", tp_data[1].x, tp_data[1].y, tp_data[1].event)
            sys.publish("TP", tp_device, tp_data)
        end

        local i2c_id = 0
        i2c.setup(i2c_id)

        if lcd_chip == "st7796" then
            tp_device = tp.init("gt911",{port=i2c_id, pin_int = gpio.WAKEUP0},tp_callBack)
        elseif lcd_chip == "jd9261t_inited" then
            tp_device = tp.init("jd9261t_inited", {port = i2c_id, pin_int = gpio.WAKEUP0}, tp_callBack)
        end

        lvgl.indev_drv_register("pointer", "touch", tp_device) -- 注册触摸屏驱动
    else
        log.info("TP", "not found")
    end
end

sys.taskInit(function()
    local uiJson = io.open("/luadb/ui.json")
    local ui = json.decode(uiJson:read("*a"))
    log.info("ui", ui, ui.pages[1].children[1].name)

    lcd_init()
    log.info("初始化lvgl", lvgl.init(ui.project_settings.resolution.width, ui.project_settings.resolution.height))
    tp_init()
    
    airui.init("/luadb/ui.json")
end)


sys.run()
