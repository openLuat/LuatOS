--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2026.02.05
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]



--[[
初始化LCD显示驱动；

@api lcd_drv.init()
@summary 配置并初始化LCD屏幕
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化LCD显示
local result = lcd_drv.init()
if result then
    log.info("LCD初始化成功")
else
    log.error("LCD初始化失败")
end
]]

_G.screen_w, _G.screen_h = 480, 800
_G.is_landscape = false

local function lcd_drv_init()
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    gpio.setup(28, 1) -- 28号GPIO引脚设置为输出模式
    gpio.set(28, 1)  -- 将28号GPIO引脚设置为
    -- 开启屏幕供电
    local result = lcd.init("st7796",
        {
            -- pin_pwr = 1,       -- 背光控制引脚GPIO端口号
            port = lcd.HWID_0, -- 驱动端口
            pin_rst = 36,      -- lcd复位引脚
            direction = 0,     -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 320,           -- lcd 水平分辨率
            h = 480,           -- lcd 竖直分辨率
            xoffset = 0,       -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,       -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
        })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        -- lcd.setupBuff(nil, true)
        -- lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载字体
        airui.font_load({
            type = "hzfont",  -- 字体类型，hzfont
            path = nil,       -- 字体路径，Air8000固件内置，无需填写
            size = 14,        -- 默认字体大写
            cache_size = 1024, --
            antialias = 1,    -- 字体抗锯齿等级，1-4级，级别越高抗锯齿效果越好，加载时间越长
        })

        airui.set_rotation(0)
        -- 查询当前固件内AirUI核心库版本
        local version_result = airui.version()

        -- 打印查询结果
        log.info("airui", "version -> " .. version_result)

        local rotation = airui.get_rotation()
        local phys_w, phys_h = lcd.getSize()
        if rotation == 0 or rotation == 180 then
            _G.screen_w, _G.screen_h = phys_w, phys_h
        else
            _G.screen_h, _G.screen_w = phys_w, phys_h
        end
        _G.is_landscape = (_G.screen_w > _G.screen_h)
    end

end

lcd_drv_init()