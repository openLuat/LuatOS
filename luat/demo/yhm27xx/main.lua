
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "charge"
VERSION = "1.0.0"

sys = require("sys")
log.info("main", PROJECT, VERSION)

local gpio_pin = 152 
-- gpio.setup(gpio_pin, 1, gpio.PULLUP)
local sensor_addr = 0x04
--电压控制寄存器地址
local V_ctrl_register = 0x00
--电流控制寄存器地址
local I_ctrl_register = 0x01
--模式寄存器地址
local mode_register = 0x02
--配置寄存器，默认为0x00
local config_register = 0x03
-------------------注意：0x04寄存器无含义
--状态寄存器
local status1_register = 0x05   --只读
local status2_register = 0x06   --只读
local status3_register = 0x07   --只读
--id寄存器
local id_register = 0x08        --只读
--充电电压常用参数,默认门限电压为4.35V
local set_4V = 0xE0         --4V
local set_4V25 = 0x20       --4.25V
local set_4V35 = 0x60       --4.35V
local set_4V45 = 0xA0       --4.45V
--充电电流常用参数，默认充电电流为0.5倍yhm27xx芯片SNS管脚的电流
local set_0I5 = 0x00        --0.5倍
local set_0I7 = 0x40        --0.7倍
local set_I = 0x80          --1倍
local set_1I5 = 0xA0        --1.5倍
local set_2I = 0xC0         --2倍

sys.taskInit(function()
    sys.wait(1000)
    local result, data = yhm27xx.cmd(gpio_pin, sensor_addr, id_register)
    -- log.info("yhm27xxx", result, data)
    if result == true and data ~= nil then
        log.info("yhm27xxx", "yhm27xx存在--")

        sys.wait(200)
        --设置充电电压为4V
        result,data = sensor.yhm27xx(gpio_pin, sensor_addr, V_ctrl_register, set_4V)
        if result == true then
            log.info("yhm27xxx 设置电压成功")
        else
            log.info("yhm27xxx 设置电压失败")
        end
        sys.wait(200)
        --充电电流设置为1倍
        result,data = yhm27xx.cmd(gpio_pin, sensor_addr, I_ctrl_register, set_I)

        if result == true then
            log.info("yhm27xxx 设置电流成功")
        else
            log.info("yhm27xxx 设置电流失败")
        end

        log.info("开始读所有寄存器的值")
        yhm27xx.reqinfo(gpio_pin, sensor_addr)
        sys.subscribe("YHM27XX_REG", function(data)
            -- log.info("yhm27xx", data and data:toHex())
            if data then
                Data_reg00 = data:byte(1)
                Data_reg01 = data:byte(2)
                Data_reg02 = data:byte(3)
                Data_reg03 = data:byte(4)
                Data_reg04 = data:byte(5)
                Data_reg05 = data:byte(6)
                Data_reg06 = data:byte(7)
                Data_reg07 = data:byte(8)
                Data_reg08 = data:byte(9)
                log.info("yhm27xxx 0x00 读取数据为：" , Data_reg00)
                log.info("yhm27xxx 0x01 读取数据为：" , Data_reg01)
                log.info("yhm27xxx 0x02 读取数据为：" , Data_reg02)
                log.info("yhm27xxx 0x03 读取数据为：" , Data_reg03)
                log.info("yhm27xxx 0x04(无含义) 读取数据为：" , Data_reg04)
                log.info("yhm27xxx 0x05 读取数据为：" , Data_reg05)
                log.info("yhm27xxx 0x06 读取数据为：" , Data_reg06)
                log.info("yhm27xxx 0x07 读取数据为：" , Data_reg07)
                log.info("yhm27xxx 0x08 读取数据为：" , Data_reg08)

            end
        end)

    else
        log.warn("yhm27xx", "yhm27xx不存在")
    end
end)

sys.run()
