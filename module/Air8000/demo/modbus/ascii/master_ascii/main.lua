-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "modbus_master_ascii"
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


-- 创建主站设备，ASCII模式
-- 设置通讯间隔时间，主站将按每隔 设置时间 的频率向从站问询数据（默认100ms），当添加了多个从站后，主站向每个从站问询的时间间隔将叠加
-- 设置通讯超时时间和消息发送超时重发次数，当主站未在 设置的时间 内接收到从站数据，将向从站再次发送问询（问询次数按设置的 消息超时重发次数 发送，默认1）
-- 设置断线重连时间间隔，当从站与主站断连后，主站将在设置时间内重新连接从站(默认5000ms)
mb_ascii = modbus.create_master(modbus.MODBUS_ASCII, uartid,115200,3000,2000,1,5000)


-- 为主站添加从站，从站ID为1，可使用modbus.add_slave(master_handler, slave_id)接口添加多个从站，最多可以添加247个
mb_slave1 = modbus.add_slave(mb_ascii, 1)
-- -- 为主站添加从站，从站ID为2
-- mb_slave2 = modbus.add_slave(mb_ascii, 2)


-- 为从站1创建数据存储区，并创建通讯消息，默认为自动loop模式
slave1_msg1_buf = zbuff.create(1)
mb_slave1_msg1 = modbus.create_msg(mb_ascii, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf)
slave1_msg1_buf:clear()

-- -- 为从站1创建数据存储区，并创建通讯消息，如需要使用手动模式，须在这里设置为手动模式
-- slave1_msg1_buf = zbuff.create(1)
-- mb_slave1_msg1 = modbus.create_msg(mb_ascii, mb_slave1, modbus.REGISTERS, modbus.READ, 0, 10, slave1_msg1_buf,1,modbus.EXEC)
-- slave1_msg1_buf:clear()

-- -- 为从站2创建数据存储区，并创建通讯消息，如设置多个从站，需要给每个从站创建数据储存区
-- slave2_msg1_buf = zbuff.create(1)
-- mb_slave2_msg1 = modbus.create_msg(mb_ascii, mb_slave2, modbus.REGISTERS,  modbus.READ, 0, 10, slave2_msg1_buf)
-- slave2_msg1_buf:clear()


-- 启动Modubs设备
modbus.master_start(mb_ascii)


-- -- 设置通讯间隔时间，设置后主站将按每隔 设置时间 的频率向从站问询数据，当添加了多个从站后，主站向每个从站问询的时间间隔将叠加
-- modbus.set_comm_interval_time(mb_ascii, 3000)


-- -- 设置通讯超时时间，当主站未在 设置的时间 内接收到从站数据，将向从站再次发送问询（问询次数按设置的 消息超时重发次数 发送）
-- modbus.set_comm_timeout(mb_ascii, 2000)


-- -- 设置消息发送失败、超时重发次数，如果主站在设置超时时间内未接收到数据，将按设置次数问询数据
-- modbus.set_comm_resend_count(mb_ascii,2)


-- -- 设置消息通讯周期，搭配modbus.create_master/modbus.set_comm_interval_time(mb_rtu, 3000)设置通讯时间使用，若设置通讯周期为2次，将在2倍的通讯时间后向从站问询数据
-- modbus.set_msg_comm_period(mb_slave1_msg1, 2)


-- 获取所有从站状态,如果所有从站状态为正常，返回true，其他情况返回false,将在每隔5秒的时间获取所有从站状态，并在日志中打印状态（仅方便调试使用，量产时可删除）
sys.timerLoopStart(function()
    local status = modbus.get_all_slave_state(mb_ascii)
    log.info("modbus", status)
end, 5000)


-- 获取从站1的状态，每隔5秒获取从站状态并在日志打印出来（仅方便调试使用，量产时可删除）
sys.timerLoopStart(function()
    local status = modbus.get_slave_state(mb_slave1)
    log.info("modbus1", status)
end, 5000)

-- -- 获取从站2的状态，每隔5秒获取从站状态并在日志打印出来（仅方便调试使用，量产时可删除）
-- sys.timerLoopStart(function()
--     local status = modbus.get_slave_state(mb_slave2)
--     log.info("modbus2", status)
-- end, 5000)


-- -- 每隔5秒执行一次mb_slave1_msg1消息，使用modbus.exec(master_handler, msg_handler)接口须先在mmodbus.create_msg接口中设置为手动模式；成功返回true，其他情况返回false
-- sys.timerLoopStart(function()
--     local status=modbus.exec(mb_ascii, mb_slave1_msg1)
--     log.info("msg",status)
-- end,5000)


-- -- 测试删除一个从站对象，并删除与之相关的通讯消息句柄。需在主站停止时(modbus.master_stop)执行该操作，否则无效。
-- -- 将在3分钟后删除从站1（主站已关闭），删除与之相关的通讯消息句柄，并在5秒后重启主站，可以观察从站是否删除成功。
-- sys.timerStart(function()
--     local status = modbus.remove_slave(mb_ascii, mb_slave1)
--     log.info("modbus", "slave1 remove after 3 minutes")
--     log.info("remove", status)
    
-- -- 移除从站后，5秒后重新启动Modbus主站
--     sys.timerStart(function()
--         modbus.master_start(mb_ascii)
--         log.info("modbus", "Modbus master restarted after slave removal")
--     end, 5000)
-- end, 180000) 


-- 获取从站1的状态，每1秒获取一次数据并转换为JSON
sys.timerLoopStart(function()
    -- 检查从站状态
    local status = modbus.get_slave_state(mb_slave1)
    if status == 0 then  -- 0表示正常
        -- 读取缓冲区数据
        slave1_msg1_buf:seek(0)  -- 重置指针到起始位置
        
        -- 读取4个寄存器的值(每个寄存器2字节)
        local reg1 = slave1_msg1_buf:readU16()
        local reg2 = slave1_msg1_buf:readU16()
        local reg3 = slave1_msg1_buf:readU16()
        local reg4 = slave1_msg1_buf:readU16()
        
        -- 创建数据表
        local data = {
            addr = 1,  -- 从站地址
            fun = 3,   -- 功能码03
            reg1 = reg1 / 10,  -- 假设原始数据需要除以10得到实际值
            reg2 = reg2 / 10,
            reg3 = reg3 / 10,
            reg4 = reg4 / 10,
            timestamp = os.time()  -- 添加时间戳
        }
        
        -- 转换为JSON
        local json_str = json.encode(data)
        log.info("Modbus数据转JSON:", json_str)

    else
        log.warn("从站1状态异常:", status)
    end
end, 1000)


-- -- 将在主站开启2分钟后停止modbus主站
-- sys.timerStart(function()
--     modbus.master_stop(mb_ascii)
--     log.info("modbus", "Modbus stopped after 2 minutes")
-- end, 120000) 


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
