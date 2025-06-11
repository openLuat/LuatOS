
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "yhm27xx_demo"
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
    sys.wait(200)
    yhm27xx.reqinfo(gpio_pin, sensor_addr)
    local result, data = sys.waitUntil("YHM27XX_REG", 200)
    local Data_reg={}
    if result then
        for i=1,9 do
            Data_reg[i] = data:byte(i)
        end
        log.info(string.format("yhm27xxx 寄存器0x00 功能:设置充电电压，   读取数据为：%X", Data_reg[1]))
        log.info(string.format("yhm27xxx 寄存器0x01 功能:设置充电电流,    读取数据为：%X" , Data_reg[2]))
        log.info(string.format("yhm27xxx 寄存器0x02 功能:设置模式，       读取数据为：%X" , Data_reg[3]))
        log.info(string.format("yhm27xxx 寄存器0x03 功能:配置寄存器,      读取数据为：%X" , Data_reg[4]))
        log.info(string.format("yhm27xxx        0x04(无含义) 读取数据为：%X" , Data_reg[5]))
        log.info(string.format("yhm27xxx 寄存器0x05 功能:状态寄存器1(只读),读取数据为：%X" , Data_reg[6]))
        log.info(string.format("yhm27xxx 寄存器0x06 功能:状态寄存器2(只读),读取数据为：%X" , Data_reg[7]))
        log.info(string.format("yhm27xxx 寄存器0x07 功能:状态寄存器3(只读),读取数据为：%X" , Data_reg[8]))
        log.info(string.format("yhm27xxx 寄存器0x08 功能:id寄存器(只读),   读取数据为：%X" , Data_reg[9]))
    end

end)

sys.run()
