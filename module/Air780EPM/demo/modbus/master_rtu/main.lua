-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "modbus_master_rtu"
VERSION = "1.0.0"
log.style(1)
log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")


--初始化通讯串口
local uartid = 1        -- 根据实际设备选取不同的uartid
local uart485Pin = 24   -- 用于控制485接收和发送的使能引脚
gpio.setup(1, 1)        --打开电源(开发板485供电脚是gpio1，用开发板测试需要开机初始化拉高gpio1)
uart.setup(uartid, 115200, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 2000)


-- 创建主站设备，RTU模式
mb_rtu = modbus.create_master(modbus.MODBUS_RTU, uartid,5000,3000,2)
-- 创建主站设备，ASCII模式
-- mb_rtu = modbus.create_master(modbus.MODBUS_ASCII, uartid)

-- 为主站添加从站，从站ID为1

mb_slave1 = modbus.add_slave(mb_rtu, 1)
-- 为主站添加从站，从站ID为2
-- mb_slave2 = modbus.add_slave(mb_rtu, 2)

-- 为从站1创建数据存储区，并创建通讯消息
slave1_msg1_buf = zbuff.create(1)
mb_slave1_msg1 = modbus.create_msg(mb_rtu, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf)
-- mb_slave1_msg1 = modbus.create_msg(mb_rtu, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf,1,modbus.EXEC)
slave1_msg1_buf:clear()





-- slave1_msg2_buf = zbuff.create(1)
-- mb_slave1_msg2 = modbus.create_msg(mb_rtu, mb_slave1, modbus.CIOLS, modbus.WRITE, 0, 10, slave1_msg2_buf)
-- slave1_msg2_buf:clear()

-- 为从站2创建数据存储区，并创建通讯消息
-- slave2_msg1_buf = zbuff.create(1)
-- mb_slave2_msg1 = modbus.create_msg(mb_rtu, mb_slave2, modbus.REGISTERS, modbus.WRITE, 0, 10, slave2_msg1_buf)
-- slave2_msg1_buf:clear()

-- slave2_msg2_buf = zbuff.create(1)
-- mb_slave2_msg2 = modbus.create_msg(mb_rtu, mb_slave2, modbus.CIOLS, modbus.WRITE, 0, 10, slave2_msg2_buf)
-- slave2_msg2_buf:clear()

-- 启动Modubs设备
modbus.master_start(mb_rtu)

-- modbus.set_comm_interval_time(mb_rtu, 5000)

-- modbus.set_comm_timeout(mb_rtu, 3000)

-- modbus.set_comm_resend_count(mb_rtu,2)

sys.timerLoopStart(function()
    local status = modbus.get_all_slave_state(mb_rtu)
    log.info("modbus", status)
end, 5000)

sys.timerLoopStart(function()
    local status = modbus.get_slave_state(mb_slave1)
    log.info("modbus1", status)
end, 5000)

-- sys.timerLoopStart(function()
--     local status = modbus.get_slave_state(mb_slave2)
--     log.info("modbus2", status)
-- end, 5000)


-- sys.timerLoopStart(function()
--     local status=modbus.exec(mb_rtu, mb_slave1_msg1)
--     log.info("msg",status)
-- end,5000)

-- modbus.set_msg_comm_period(mb_slave1_msg1, 2)

-- sys.timerStart(function()
--     local status = modbus.remove_slave(mb_rtu, mb_slave1)
--     log.info("modbus", "slave remove after 3 minutes")
--     log.info("remove", status)
    
--     -- 移除从站后，5秒后重新启动Modbus主站
--     sys.timerStart(function()
--         modbus.master_start(mb_rtu)
--         log.info("modbus", "Modbus master restarted after slave removal")
--     end, 5000)
-- end, 180000) 



-- 修改和读取modbus值
addvar = 0
function modify_data()
    -- 获取变量值
    slave1_msg1_buf:seek(0)
    log.info("slave1 reg: ", slave1_msg1_buf:readU16(), slave1_msg1_buf:readU16(),
                             slave1_msg1_buf:readU16(), slave1_msg1_buf:readU16())

    -- slave2_msg1_buf:seek(0)
    -- log.info("slave2 reg: ", slave2_msg1_buf:readU16(), slave2_msg1_buf:readU16(),
    --                          slave2_msg1_buf:readU16(), slave2_msg1_buf:readU16())

    -- 写入变量值
    -- slave2_msg1_buf:seek(0)
    -- slave2_msg1_buf:writeU16(addvar)
    -- slave2_msg1_buf:writeU16(addvar)
    -- slave2_msg1_buf:writeU16(addvar)
    -- slave2_msg1_buf:writeU16(addvar)
    -- slave2_msg1_buf:writeU16(addvar)
    -- slave2_msg1_buf:writeU16(addvar)
    -- addvar=addvar+1
	
	-- 每周期值取反
    -- slave1_msg2_buf:seek(0)
	-- slave1_msg2_buf:writeU8(addvar%2)
	-- slave1_msg2_buf:writeU8(addvar%2)
	-- slave1_msg2_buf:writeU8(addvar%2)
	-- slave1_msg2_buf:writeU8(addvar%2)
	-- slave1_msg2_buf:writeU8(addvar%2)
end
sys.timerLoopStart(modify_data,1000)


-- sys.timerStart(function()
--     modbus.master_stop(mb_rtu)
--     log.info("modbus", "Modbus stopped after 2 minutes")
-- end, 120000) 


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
