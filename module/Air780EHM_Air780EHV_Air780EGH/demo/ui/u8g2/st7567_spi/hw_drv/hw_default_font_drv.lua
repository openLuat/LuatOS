--[[
@module  hw_default_font_drv
@summary LCD初始化和内置点阵字体驱动模块
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为LCD初始化和内置字体硬件驱动模块，核心业务逻辑为：
1、初始化ST7567单色点阵屏（128x64分辨率）；
2、配置SPI通信参数和显示参数；
3、设置内置字体显示模式；
4、显示开机信息并开启背光；

本文件无对外接口，模块加载时自动执行初始化；
]]

-- ST7567 SPI引脚配置
local spi_id, spi_res, spi_dc, spi_cs = 0, 24, 10, 9

local function init()
    -- 初始化U8G2显示屏 - ST7567, 128x64
    local result = u8g2.begin(
        {
            ic = "custom",        -- 使用自定义IC
            direction = 0,        -- 显示方向
            mode = "spi_hw_4pin", -- SPI硬件4线模式
            spi_id = spi_id,      -- SPI端口号
            spi_res = spi_res,    -- 复位引脚
            spi_dc = spi_dc,      -- 数据/命令选择引脚
            spi_cs = spi_cs       -- 片选引脚
        },
        {
            width = 128, -- 分辨率宽度，128像素
            height = 64, -- 分辨率高度，64像素

            -- 初始化命令表，根据ST7567芯片手册配置
            initcmd = {
                0xE2,        -- 系统复位
                0x82,        -- 设置偏压比
                0x2F,        -- 电源控制（开启内部电荷泵）
                0x26,        -- 电阻比率设置
                0xF8, 0x00,  -- 设置显示偏移（垂直偏移量为0）
                0x81, 0x09,  -- 设置对比度（0x09为对比度值）
                0x40,        -- 设置显示起始行（第0行）
                0xC8,        -- COM扫描方向（反向）
                0xA4,        -- 正常显示模式
                0xAF,        -- 开启显示
            },
            sleepcmd = 0xAE, -- 休眠命令
            wakecmd = 0xAF,  -- 唤醒命令
        }
    )

    if result == 1 then
        -- SPI接口屏幕才能获取初始化成功后屏幕的长宽，I2C接口无法获取的屏幕初始化成功后的长宽
        local width = u8g2.GetDisplayWidth()
        local height = u8g2.GetDisplayHeight()
        log.info("u8g2", "ST7567初始化成功" .. width .. "x" .. height)

        -- 设置字体显示模式为透明
        u8g2.SetFontMode(1)

        -- 显示开机信息
        u8g2.ClearBuffer()
        u8g2.SetFont(u8g2.font_opposansm12_chinese)
        u8g2.DrawUTF8("内置字体进入", 30, 30)
        u8g2.SendBuffer()

        -- 打开背光，若采用GPIO控制
    else
        log.error("u8g2", "初始化失败，错误码:", result)
    end
end

init()
