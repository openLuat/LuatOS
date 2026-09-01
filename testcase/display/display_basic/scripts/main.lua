PROJECT = "display_rgb_test"
VERSION = "1.0.0"
local sys = require("sys")

sys.taskInit(function()
    log.info("display", "start init")

    local ret, err = display.init("st7701s", {
        w = 480,
        h = 854,
        interface = "rgb",
        pclk_polarity = 1, -- 时钟极性，1为高电平，0为低电平
        pin_scl = 23,      -- SPI 时钟引脚（初始化通信）
        pin_sdi = 2,       -- SPI 数据引脚
        pin_cs = 22,       -- SPI 片选引脚
        pin_rst = 15,      -- 复位引脚
    })

    log.info("display", "init ret", ret, err)

    -- 背光：PWM 通道3, 1kHz, 占空比100%（高电平持续导通）
    local ok = pwm.open(3, 1000, 100)
    log.info("display", "pwm backlight", ok)

    -- 验证 90° 旋转：DMA2D ROT_ANT 旋转通道（flush 时整帧走旋转分支）
    log.info("display", "setRotation 1", display.setRotation(1))

    local colors = {
        { name = "red",    color = 0xF800 },
        { name = "green",  color = 0x07E0 },
        { name = "blue",   color = 0x001F },
        { name = "yellow", color = 0xFFE0 },
        { name = "white",  color = 0xFFFF },
    }

    while true do
        for _, c in ipairs(colors) do
            display.fill(0, 0, 480, 480, c.color)
            display.flush()
            log.info("display", "fill", c.name)
            sys.wait(500)
        end
    end
end)

sys.run()
