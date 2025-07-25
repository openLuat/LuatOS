-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "modbus_slave_rtu"
VERSION = "1.0.0"
log.style(1)
log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

-- 开启调试模式
modbus.debug(1)
-- -- 关闭调试模式
-- modbus.debug(0)

--初始化通讯串口
local uartid = 1        -- 根据实际设备选取不同的uartid
local uart485Pin = 17   -- 用于控制485接收和发送的使能引脚
gpio.setup(16, 1)        --打开电源(开发板485供电脚是gpio16，用开发板测试需要开机初始化拉高gpio16)
uart.setup(uartid, 115200, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 2000)


-- 创建从站设备，可选择RTU、ASCII、TCP，此demo用作测试RTU
local slave_id = 1
mb_rtu_s = modbus.create_slave(modbus.MODBUS_RTU, slave_id, uartid,115200)


-- 添加一块寄存器内存区
registers = zbuff.create(1)
modbus.add_block(mb_rtu_s, modbus.REGISTERS, 0, 32, registers)
registers:clear()

-- 创建线圈数据区
ciols = zbuff.create(1)
modbus.add_block(mb_rtu_s, modbus.CIOLS, 0, 32, ciols)
ciols:clear()


-- 启动modbus从站
modbus.slave_start(mb_rtu_s)


local counter = 0
-- 修改和读取modbus值
function modify_data()
    counter = counter + 1  
    -- 写入寄存器数据 (16位无符号整数)
    registers:seek(0)
    for i=0,31 do
        registers:writeU16((counter + i) % 65536)  -- 写入递增数字，限制在0-65535
    end  
    -- 写入线圈数据 (1位布尔值)
    ciols:seek(0)
    for i=0,31 do
        ciols:writeU8((counter + i) % 2)  -- 交替写入0和1
    end
  
    -- 读取并打印部分数据用于调试
    registers:seek(0)
    ciols:seek(0)
    log.info("registers:", registers:readU16(), registers:readU16(), registers:readU16(), registers:readU16(), registers:readU16())
    log.info("ciols    :", ciols:readU8(), ciols:readU8(), ciols:readU8(), ciols:readU8(), ciols:readU8())
end
sys.timerLoopStart(modify_data,1000)

-- -- 测试停止modbus从站，将在从站启动两分钟后关闭
-- sys.timerStart(function()
--     modbus.slave_stop(mb_rtu_s)
--     log.info("Modbus", "2分钟时间到，停止Modbus从站")
-- end, 2 * 60 * 1000)  -- 2分钟（单位：毫秒）


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
