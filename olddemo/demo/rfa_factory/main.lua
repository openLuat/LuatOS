-- LuaTools 需要 PROJECT 和 VERSION。
PROJECT = "rfa_factory"
VERSION = "1.0.0"

sys = require("sys")
log.info("main", PROJECT, VERSION)
log.info("main", "atc type", type(atc))
-- 使用支持自定义 AT 指令的底层固件；检查通过后才加载 RFA、注册串口。
-- C 库可通过只读 rotable（userdata）导出，不限定为普通 table。
local atc_ready = atc ~= nil
if atc_ready then
    for _, name in ipairs({"create", "bind", "input", "on", "response"}) do
        if type(atc[name]) ~= "function" then
            atc_ready = false
            break
        end
    end
end

if atc_ready then
    local rfa = require("rfa")
    -- 常驻产测，不依据校准状态或 SETCFG 保存的 rfa_mode 切换业务。
    -- USB 和 UART1 顺序收发；UART2 由 GNSS 产测指令按需使用。
    log.info("main", "rfa ready")
    rfa.start(uart.VUART_0, 115200)
    rfa.start(1, 115200)
else
    log.error("rfa_factory", "固件缺少必要的 atc 接口，请烧录支持 ATC 的底层固件")
end

sys.timerLoopStart(function()
    print("hi, LuatOS")
    print("mem.lua", rtos.meminfo())
    print("mem.sys", rtos.meminfo("sys"))
end, 5000)

-- 用户代码结束；sys.run() 后不再添加语句。
sys.run()
