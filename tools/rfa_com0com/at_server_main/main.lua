--[[
rfa AT server 入口(com0com 端到端测试用)
==========================================

替代 rfcal_at_server 入口,内部用 lua/luat/rfa.lua

启动方法:
  cd bsp/pc/build/out
  .\luatos-lua.exe ../../../../testcase/common/scripts/ ^
                  ../../../../tools/rfa_com0com/at_server_main/

环境要求:
  - com0com 已配对(setup_com0com_pair.ps1)
  - LuatOS PC 模拟器已绑定某个 VUART 到 com0com COM 端口
    (通过 LUAT_FORCE_WIN32 + luat_uart_i686.dll,见 bsp/pc/port/uart/uart_drv_win32.c)

默认监听 uart.VUART_1,可通过命令行环境变量 UART_ID 覆盖。

使用示例:
  -- 终端 1: 启动 AT server
  luatos-lua.exe ...\testcase\common\scripts\ ...\tools\rfa_com0com\at_server_main\

  -- 终端 2: 跑 Python 回归
  python tools\rfa_com0com\test_rfa_com0com.py --port COM5
]]

-- 解析环境变量(Windows:set UART_ID=2)
local uart_id = tonumber(os.getenv("UART_ID")) or uart.VUART_1
local baud = tonumber(os.getenv("UART_BAUD")) or 115200

-- require 路径:PC 模拟器 VFS 不支持 ../ 相对路径
-- 优先从当前目录或 common/scripts 同级目录加载
-- 实际生产代码在 lua/luat/rfa.lua
local rfa
local ok, mod = pcall(require, "rfa")
if ok and mod then
    rfa = mod
else
    -- 退化:尝试从 common/scripts 同级目录加载
    package.path = package.path .. ";../../../lua/luat/?.lua;../../../../lua/luat/?.lua"
    rfa = require "rfa"
end

if not rfa or type(rfa.start) ~= "function" then
    log.error("at_server_main", "无法加载 rfa 模块")
    if rtos.bsp() == "PC" then os.exit(1) end
    return
end

log.info("at_server_main", string.format(
    "启动 rfa AT server, uart_id=%d, baud=%d", uart_id, baud))

sys.taskInit(function()
    -- 等待 UART 硬件就绪
    sys.wait(500)
    rfa.start(uart_id, baud)
    log.info("at_server_main", "AT server 已就绪,等待 AT 命令...")

    -- 守护循环:每秒打印一次状态(便于监控)
    while true do
        sys.wait(1000)
        local state = rfa and rfa.state and rfa.state() or -1
        if state >= 0 then
            log.info("at_server_main", string.format("状态: %d", state))
        end
    end
end)

sys.run()
