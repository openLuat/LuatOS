-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "modbus_slave_tcp"
VERSION = "1.0.0"
log.style(1)
log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

log.info("ch390", "打开LDO供电")
gpio.setup(20, 1)  --打开lan供电
require "lan"

-- 创建从站设备，可选择RTU、ASCII、TCP，此demo仅用作测试TCP。设置该从站端口号为6000，网卡适配器序列号为socket.LWIP_ETH。
local slave_id = 1
mb_tcp_s = modbus.create_slave(modbus.MODBUS_TCP, slave_id, 6000, socket.LWIP_ETH)


-- 创建寄存器数据区
registers = zbuff.create(1)
modbus.add_block(mb_tcp_s, modbus.REGISTERS, 0, 32, registers)
registers:clear()
-- 创建线圈数据区
ciols = zbuff.create(1)
modbus.add_block(mb_tcp_s, modbus.CIOLS, 0, 32, ciols)
ciols:clear()


-- 启动modbus从站
modbus.slave_start(mb_tcp_s)
log.info("start modbus slave")


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


-- -- 测试停止modbus从站，从站将在开启两分钟后关闭
-- sys.timerStart(function()
--     modbus.slave_stop(mb_rtu_s)
--     log.info("Modbus", "2分钟时间到，停止Modbus从站")
-- end, 120000)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
