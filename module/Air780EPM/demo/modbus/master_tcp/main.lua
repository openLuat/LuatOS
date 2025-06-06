-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "modbus_master_tcp"
VERSION = "1.0.0"
log.style(1)
log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

--初始化网络
log.info("ch390", "打开LDO供电")
gpio.setup(20, 1)  --打开lan供电

mcu.hardfault(0) -- 死机后停机，一般用于调试状态
require "lan"


-- 创建主站设备，TCP模式
mb_tcp = modbus.create_master(modbus.MODBUS_TCP, socket.LWIP_ETH)

-- 为主站添加从站，从站ID为1，ip地址为 192.168.0.104，端口号为 6000
mb_slave1 = modbus.add_slave(mb_tcp, 1, "192.168.4.100", 6001)
-- 为主站添加从站，从站ID为2，ip地址为 192.168.0.104，端口号为 6001
-- mb_slave2 = modbus.add_slave(mb_tcp, 2, "192.168.4.100", 6002)

-- 为从站1创建数据存储区，并创建通讯消息
slave1_msg1_buf = zbuff.create(1)
-- mb_slave1_msg1 = modbus.create_msg(mb_tcp, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf,1,modbus.EXEC)
mb_slave1_msg1 = modbus.create_msg(mb_tcp, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf)
slave1_msg1_buf:clear()

-- slave1_msg2_buf = zbuff.create(1)
-- mb_slave1_msg2 = modbus.create_msg(mb_tcp, mb_slave1, modbus.CIOLS, modbus.WRITE, 0, 10, slave1_msg2_buf)
-- slave1_msg2_buf:clear()

-- 为从站2创建数据存储区，并创建通讯消息
-- slave2_msg1_buf = zbuff.create(1)
-- mb_slave2_msg1 = modbus.create_msg(mb_tcp, mb_slave2, modbus.REGISTERS, modbus.WRITE, 0, 10, slave2_msg1_buf)
-- slave2_msg1_buf:clear()

-- 启动Modubs设备
modbus.master_start(mb_tcp)
log.info("start modbus master")

sys.timerLoopStart(function()
    local status = modbus.get_all_slave_state(mb_tcp)
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

-- modbus.set_comm_interval_time(mb_tcp,2000)

-- modbus.set_comm_timeout(mb_tcp, 3000)

-- modbus.set_comm_resend_count(mb_tcp,3)

-- modbus.set_msg_comm_period(mb_slave1_msg1, 2)

-- modbus.set_comm_reconnection_time(mb_tcp, 6000)

-- sys.timerLoopStart(function()
--     local status=modbus.exec(mb_tcp, mb_slave1_msg1)
--     log.info("msg",status)
-- end,5000)

-- sys.timerStart(function()
--     local status = modbus.remove_slave(mb_tcp, mb_slave2)
--     log.info("modbus", "slave remove after 3 minutes")
--     log.info("remove", status)
    
--     -- 移除从站后，5秒后重新启动Modbus主站
--     sys.timerStart(function()
--         modbus.master_start(mb_tcp)
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
--     modbus.master_stop(mb_tcp)
--     log.info("modbus", "Modbus stopped after 2 minutes")
-- end, 120000) 

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
