--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]]



--[[
初始化触摸面板驱动；

@api tp_drv.init()
@summary 配置并初始化GT911触摸控制器
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化触摸面板
local result = tp_drv.init()
if result then
    log.info("触摸面板初始化成功")
else
    log.error("触摸面板初始化失败")
end
]]
local tp_drv = {}

local rst_pin = 3

function tp_drv.init()
    gpio.setup(rst_pin, 0) -- 设置GPIO4为输出模式，输出低电平

    gpio.close(rst_pin)    -- 关闭GPIO4功能，恢复高阻态

    local i2c_id = 1
    i2c.setup(i2c_id)
    local result = tp.init("gt911", { port = i2c_id, pin_rst = 3, pin_int = 51, int_type = tp.FALLING })
    log.info("tp.init", result)

    if _G.model_str:find("PC") then
        log.info("PC", "已启用鼠标点击功能")
    else
        if not result then
            log.error("ui_main", "触摸初始化失败")
        else
            -- 绑定触摸设备到AirUI输入设备
            airui.device_bind_touch(result)
            log.info("设备", "触摸初始化成功")
        end
    end

end

return tp_drv
