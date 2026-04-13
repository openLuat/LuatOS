--[[
@module exmux
@summary I2C和SPI设备管理扩展库
@version 1.0.0
@date 2026.04.02
@author 陈取德
@usage
在I2C和SPI这类通讯应用中，总线需要增加上拉才能正常通讯，并且每个I2C或者SPI设备的建议电路设计上，都会给总线增加上拉电阻到LDO
因为在设备上电时同步给总线上拉是正常的使用逻辑，但是LDO会有个特性，当EN使能关闭时，LDO会接地放电，如果I2C和SPI通过电阻接到了这个LDO上，就会被下拉到地
导致同条总线上的其他设备通讯失败，并且还存在另外一种情况，类似ES8311或者CH390H这种芯片，他们在不关断时，管脚因为内置下拉电阻，等于I2C或者SPI总线拉低到地了
也会造成同路总线上其他设备因为总线的电压不足，导致通讯失败
所以本库提供了一个I2C和SPI设备管理功能，用于统一管理I2C和SPI设备的电源和片选引脚，确保通讯正常
并且内置了目前合宙在售的Air780系列和Air8000系列开发板的硬件配置，用户可以根据开发板型号自动加载对应配置或者自定义配置
在使用时，调用open和close接口，即可确保I2C和SPI通讯正常

应用场景
-- 本库针对上述问题提供解决方案，支持不同版本的开发板：
-- 1. 支持Air780系列和Air8000系列开发板的硬件配置
-- 2. 提供开发板版本自适应功能，自动加载对应配置，确保I2C和SPI通讯正常
-- 3. 支持用户自定义设备配置，灵活适配不同硬件环境
-- 4. 提供设备分组的打开和关闭接口，统一管理外设电源和片选
-- 5. 对GPIO大于100的引脚操作增加延迟，确保硬件稳定
-- 6. 提供状态管理机制，避免重复操作导致的硬件问题

使用示例：
HARDWARE_ENV的可选值有：
"DEV_BOARD_8000_V2.0"
"DEV_BOARD_780_V1.2"
"DEV_BOARD_780_V1.3"

-- 使用开发板版本初始化
exmux.setup("DEV_BOARD_8000_V2.0")

-- 或使用自定义配置初始化
ex_device_param = {
    i2c1 = {
        pwr1 = 2,     -- 设备电源使能
        pwr2 = 20,    -- 设备电源使能
        pwr3 = 23     -- 设备电源使能
    },
    spi1 = {
        pwr1 = 1,     -- 设备电源使能
        cs1 = 8,      -- 片选引脚
        pwr2 = 3,     -- 设备电源使能
        cs2 = 9       -- 片选引脚
    }
}
exmux.setup(ex_device_param)

-- 打开I2C1分组（自动打开相关电源和片选，确保通讯正常）
exmux.open("i2c1")

-- 关闭SPI1分组（关闭相关电源和片选，降低功耗）
exmux.close("spi1")
]]

local exmux = {}

-- 开发板配置表
local DEV_BOARD_param = {
    -- Air780 V1.2开发板配置
    ["DEV_BOARD_780_V1.2"] = {
        i2c1 = {
            pwr1 = 2,     -- Camera电源
            pwr2 = 23,    -- Gsensor电源
            pwr_result = 0
        },
        spi1 = {
            pwr_result = 0
        }
    },
    -- Air780 V1.3开发板配置
    ["DEV_BOARD_780_V1.3"] = {
        i2c1 = {
            pwr1 = 2,     -- Camera电源
            pwr2 = 20,    -- ES8311电源
            pwr3 = 23,    -- Gsensor电源
            pwr4 = 29,    -- LCD电源
            pwr_result = 0
        },
        spi0 = {
            pwr1 = 20,    -- CH390H电源
            cs1 = 8,      -- CH390H片选
            pwr_result = 0
        }
    },
    -- Air8000 V2.0开发板配置
    ["DEV_BOARD_8000_V2.0"] = {
        i2c0 = {
            pwr1 = 164,   -- ES8311电源
            pwr2 = 24,    -- Gsensor电源
            pwr3 = 141,    -- LCD电源
            pwr_result = 0
        },
        spi1 = {
            pwr1 = 140,   -- CH390H电源
            cs1 = 12,      -- CH390H片选
            cs2 = 20,     -- SD卡槽片选
            pwr_result = 0
        }
    }
}

-- 设备配置表
local ex_device_param = {}

-- 初始化IO管理配置表
-- @param param string or table 开发板版本号或自定义配置表
-- @return boolean 初始化是否成功
function exmux.setup(param)
    if type(param) == "string" then
        -- 使用开发板版本初始化
        local board_config = DEV_BOARD_param[param]
        if not board_config then
            log.info("exmux", "不支持的开发板版本: " .. param)
            return false
        end
        
        ex_device_param = board_config
        
        log.info("exmux", "开发板 " .. param .. " 初始化成功")
        return true
    elseif type(param) == "table" then
        -- 使用自定义配置表初始化
        ex_device_param = {}
        
        -- 处理配置表格式
        for group_name, group_config in pairs(param) do
            if type(group_config) == "table" then
                ex_device_param[group_name] = group_config
                -- 确保每个分组都有pwr_result字段
                if not ex_device_param[group_name].pwr_result then
                    ex_device_param[group_name].pwr_result = 0
                end
            end
        end
        
        log.info("exmux", "自定义配置表初始化成功")
        return true
    else
        log.info("exmux", "参数类型错误，需要string或table")
        return false
    end
end

-- 打开外设分组的所有开关
-- 必须在TASK中调用
-- @param name string 分组名称，可选值："i2c0"、"i2c1"、"spi0"、"spi1"
function exmux.open(name)
    local group_config = ex_device_param[name]
    if not group_config then
        log.info("exmux", "未找到分组: " .. name)
        return false
    end
    
    -- 检查状态标识
    if group_config.pwr_result == 1 then
        log.info("exmux", "该分组设备已经打开: " .. name)
        return true
    end
    
    -- 遍历分组内的所有引脚，全部拉高
    for pin_name, pin_value in pairs(group_config) do
        if pin_name ~= "pwr_result" and type(pin_value) == "number" then
            gpio.setup(pin_value, 1)
            log.info("exmux", "设置引脚 " .. pin_name .. " (" .. pin_value .. ") 为高电平")
            
            -- 如GPIO大于100，增加不少于5ms的延迟
            if pin_value > 100 then
                sys.wait(5)
            end
        end
    end
    
    -- 更新状态标识
    group_config.pwr_result = 1
    log.info("exmux", "分组 " .. name .. " 打开成功")
    return true
end

-- 关闭外设分组的所有开关
-- 必须在TASK中调用
-- @param name string 分组名称，可选值："i2c0"、"i2c1"、"spi0"、"spi1"
function exmux.close(name)
    local group_config = ex_device_param[name]
    if not group_config then
        log.info("exmux", "未找到分组: " .. name)
        return false
    end
    
    -- 检查状态标识
    if group_config.pwr_result == 0 then
        log.info("exmux", "该分组设备已经关闭: " .. name)
        return true
    end
    
    -- 遍历分组内的所有引脚，全部拉低
    for pin_name, pin_value in pairs(group_config) do
        if pin_name ~= "pwr_result" and type(pin_value) == "number" then
            gpio.setup(pin_value, 0)
            log.info("exmux", "设置引脚 " .. pin_name .. " (" .. pin_value .. ") 为低电平")
            
            -- 如GPIO大于100，增加不少于5ms的延迟
            if pin_value > 100 then
                sys.wait(5)
            end
        end
    end
    
    -- 更新状态标识
    group_config.pwr_result = 0
    log.info("exmux", "分组 " .. name .. " 关闭成功")
    return true
end

return exmux