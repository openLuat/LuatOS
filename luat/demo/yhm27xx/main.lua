
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "charge"
VERSION = "1.0.0"

sys = require("sys")
log.info("main", PROJECT, VERSION)

local gpio_pin = 152 
-- gpio.setup(gpio_pin, 1, gpio.PULLUP)
--yhm2712芯片地址
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
local set_4V    = 0xE0       --4V
local set_4V1   = 0xF0       --4.1V
local set_4V2   = 0x00       --4.2V
local set_4V225 = 0x10       --4.225V
local set_4V25  = 0x20       --4.25V
local set_4V275 = 0x30       --4.275V
local set_4V3   = 0x40       --4.3V
local set_4V325 = 0x50       --4.325V
local set_4V35  = 0x60       --4.35V
local set_4V375 = 0x70       --4.375V
local set_4V4   = 0x80       --4.4V
local set_4V425 = 0x90       --4.425V
local set_4V45  = 0xA0       --4.45V
local set_4V475 = 0xB0       --4.475V
local set_4V5   = 0xC0       --4.5V
local set_4V525 = 0xD0       --4.525V

--充电电流常用参数，默认充电电流为250mA，即0.5倍*500=250mA
local set_0I2 = 0x20        --0.2倍，0.2*500=100mA
local set_0I5 = 0x00        --0.5倍，0.5*500=250mA
local set_0I7 = 0x40        --0.7倍，0.7*500=350mA
local set_0I9 = 0x60        --0.9倍，0.9*500=450mA
local set_I = 0x80          --  1倍，1.0*500=500mA
local set_1I5 = 0xA0        --1.5倍，1.5*500=750mA
local set_2I = 0xC0         --  2倍，2.0*500=1000mA
local set_3I = 0xE0         --  3倍，3.0*500=1500mA

local V_table={
    ["224"] = "4.0V",
    ["240"] = "4.1V",
    ["0"] = "4.2V",
    ["16"] = "4.225V",
    ["32"] = "4.25V",
    ["48"] = "4.275V",
    ["64"] = "4.3V",
    ["80"] = "4.325V",
    ["96"] = "4.35V",
    ["112"] = "4.375V",
    ["128"] = "4.4V",
    ["144"] = "4.425V",
    ["160"] = "4.45V",
    ["176"] = "4.475V",
    ["192"] = "4.5V",
    ["208"] = "4.525V",
}

local I_table={
    ["32"] = "100mA",
    ["0"] = "250mA",
    ["64"] = "350mA",
    ["96"] = "450mA",
    ["128"] = "500mA",
    ["160"] = "750mA",
    ["192"] = "1000mA",
    ["224"] = "1500mA",
}

local charge_status_table={
    ["0"] = "放电模式",
    ["1"] = "预充电模式",
    ["2"] = "涓流充电",
    ["3"] = "恒流快速充电",
    ["4"] = "恒压快速充电",
    ["5"] = "恒压快速充电",
    ["6"] = "恒压快速充电",
    ["7"] = "充电完成",
}

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
    result,data = yhm27xx.cmd(gpio_pin, sensor_addr, I_ctrl_register, set_0I5)

    if result == true then
        log.info("yhm27xxx 设置电流成功")
    else
        log.info("yhm27xxx 设置电流失败")
    end

    log.info("读寄存器的值...")
    sys.wait(200)
    yhm27xx.reqinfo(gpio_pin, sensor_addr)
    local result, data = sys.waitUntil("YHM27XX_REG", 200)
    local Data_reg={}

    if result then
        for i=1,9 do
            Data_reg[i] = data:byte(i)
        end

        log.info("yhm27xxx 寄存器0x00 功能:设置充电电压，   读取数据为：", V_table[tostring(Data_reg[1])])
        log.info("yhm27xxx 寄存器0x00 功能:设置充电电流，   读取数据为：", I_table[tostring(Data_reg[2])])
        log.info("yhm27xxx 寄存器0x05 功能:充电状态寄存器(只读),读取数据为：" , charge_status_table[tostring((Data_reg[6] & 0xE0)>>5)])
    end

end)

sys.run()
