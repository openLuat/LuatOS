PROJECT = "modbus_rtu_uart2"
VERSION = "001.000.000"

sys = require("sys")

-- mobile.simid(2)

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end
require"uart1_rtu"
require"uart2_rtu"
require"uart11_rtu"

-- 如果你用的是合宙DTU整机系列，才需要打开，否则按自己设计的PCB来
-- gpio.setup(1, 1) -- 485转TTL芯片供电打开
-- gpio.setup(24, 1) -- 外置供电电源打开


-- local modbus_tcp = require("modbus_tcp")

-- function modbus_tcp_test()
--     sys.waitUntil("IP_READY")
--     -- 连接到 Modbus TCP 服务器
--     local netc, err = modbus_tcp.connect("112.125.89.8", 42514)
--     if not netc then
--         log.error("Modbus TCP", "连接失败:", err)
--         return
--     end

--     -- 示例 1: 读取保持寄存器
--     local response, err = modbus_tcp.send_request(netc, 1, 0x03, 0, 10) -- 读取从站地址为 1 的保持寄存器，起始地址为 0，数量为 10
--     if not response then
--         log.error("Modbus TCP", "读取保持寄存器失败:", err)
--     else
--         log.info("Modbus TCP", "读取保持寄存器响应数据:", response.data)
--     end

--     -- 示例 2: 写入单个寄存器
--     local write_response, err = modbus_tcp.send_request(netc, 1, 0x06, 5, 1234) -- 向从站地址为 1 的寄存器地址 5 写入值 1234
--     if not write_response then
--         log.error("Modbus TCP", "写入单个寄存器失败:", err)
--     else
--         log.info("Modbus TCP", "写入单个寄存器响应数据:", write_response.data)
--     end

--     -- 关闭连接
--     -- modbus_tcp.close(netc)
-- end

-- sys.taskInit()

-- log.info("mem.lua", rtos.meminfo())
-- log.info("mem.sys", rtos.meminfo("sys"))

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
