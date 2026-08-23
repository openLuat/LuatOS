--[[
@module  hw_default_font_drv
@summary LCD初始化和内置点阵字体驱动模块
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为LCD初始化和内置字体硬件驱动模块，核心业务逻辑为：
1、初始化SSD1306单色OLED屏（128x64分辨率，I2C接口）；
2、配置I2C硬件通信参数和显示参数；
3、设置内置字体显示模式；
4、显示开机信息；

本文件无对外接口，模块加载时自动执行初始化；

注意：
1、SSD1306 I2C 默认从机地址为 0x3C，u8g2 库内部已封装地址处理逻辑，无需用户额外配置；
2、I2C 引脚由模组硬件 I2C 通道决定，使用 i2c_id 选择对应通道，SCL/SDA 为该通道的固定引脚；
3、若使用软件 I2C，请将 mode 改为 "i2c_sw"，并通过 i2c_scl、i2c_sda 配置任意 GPIO；
]]

-- SSD1306 I2C 配置
-- i2c_id：硬件 I2C 通道编号
-- 在 Air780EHM/Air780EHV/Air780EGH 核心板上，使用硬件 I2C1
local i2c_id = 1

local function init()
    -- 初始化U8G2显示屏 - SSD1306, 128x64, 硬件 I2C
    -- u8g2.begin 配置项说明：
    --     ic        = "ssd1306"   主控芯片类型
    --     direction = 0           显示方向（0/90/180/270）
    --     mode      = "i2c_hw"    通信模式：硬件I2C
    --     i2c_id    = 1           硬件I2C通道编号
    -- 如果需要使用软件I2C，可参考如下配置：
    --    local result = u8g2.begin({ic = "ssd1306", direction = 0, mode = "i2c_sw", i2c_scl = 29, i2c_sda = 30})
    local result = u8g2.begin({
        ic = "ssd1306",        -- 主控IC类型
        direction = 0,         -- 显示方向
        mode = "i2c_hw",       -- 硬件I2C模式
        i2c_id = i2c_id        -- 硬件I2C通道编号
    })

    if result == 1 then
        log.info("u8g2", "SSD1306初始化成功")

        -- 设置字体显示模式为透明
        u8g2.SetFontMode(1)

        -- 显示开机信息
        u8g2.ClearBuffer()
        u8g2.SetFont(u8g2.font_opposansm12_chinese)
        u8g2.DrawUTF8("内置字体进入", 30, 30)
        u8g2.SendBuffer()
    else
        log.error("u8g2", "初始化失败，错误码:", result)
    end
end

init()
