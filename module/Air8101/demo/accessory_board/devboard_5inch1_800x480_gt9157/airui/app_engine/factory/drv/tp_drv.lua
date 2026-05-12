-- nconv: var2-4 fn2-5 tag-short
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

function tp_drv.init()
    -- 初始化软件I2C，接口i2c.createSoft(scl, sda, delay)
    -- 参数说明：
    -- 0: SCL引脚编号
    -- 1: SDA引脚编号
    local result = i2c.createSoft(8, 5)

    if type(result) ~= "userdata" then
        log.error("tp_drv.init i2c.createSoft error")
        return false
    end
    
    local r = tp.init("gt9157", { port = result, pin_rst = 9, pin_int = 6 })
    log.info("tp", r)
    if not _G.model_str:find("PC") then
        -- 绑定触摸设备到AirUI输入设备
        airui.device_bind_touch(r)
    else
        if not r then
            log.error("ui", "触摸初始化失败")
        else
            -- 绑定触摸设备到AirUI输入设备
           airui.device_bind_touch(r)
        end
    end
end

return tp_drv
