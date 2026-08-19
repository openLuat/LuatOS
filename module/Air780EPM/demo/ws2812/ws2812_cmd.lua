--[[
@module  ws2812_cmd
@summary Air1780P/H/HV 串口命令接口，运行时调节亮度和速度
@version 1.0
@date    2026.08.18
@usage
适用产品：合宙 Air1780P / Air1780H / Air1780HV。

本模块负责通过 UART1（USB 虚拟串口）接收文本命令，动态修改
WS2812_CFG.brightness 和 WS2812_CFG.speed_ms，无需重新烧录。

支持命令（以回车或换行结尾）：
  b=NNN   设置亮度 0~255
  s=NNN   设置帧间隔 20~2000ms
  b?      查询当前亮度
  s?      查询当前帧间隔

通信参数：115200 8N1。
]]

-- UART_ID = 1：在 Air 系列模组上，UART1 默认映射为 USB 虚拟串口，
-- 插 USB 后电脑会枚举出一个 COM 口，直接发命令即可，不需要额外接 USB-TTL。
local UART_ID = 1

-- rx_buf：接收累积缓冲区（字符串）。
-- 串口数据是流式到达的，一条 "b=128\r\n" 可能被底层拆成多次 recv 回调
-- （比如先收到 "b=1"，再收到 "28\r"，再收到 "\n"），不能假设一次回调就是一条完整命令。
-- 每次收到数据就拼到 rx_buf 末尾，再用 string.find 查找换行符，切出完整的一行，
-- 剩余未换行的残片继续留在 rx_buf 里等下一次拼接。
local rx_buf = ""

-- cmd_queue：命令队列（FIFO）。
-- uart.on 的 "recv" 回调运行在中断/事件上下文中，里面绝对不能做耗时操作
-- （比如 sys.wait、大量 log、写 WS2812 灯带），否则会阻塞串口接收，造成丢字节。
-- 正确做法：回调里只做"读字节 + 拼包 + 切行"，把切好的完整命令塞进 cmd_queue，
-- 然后立刻返回；由独立协程 task 每 20ms 轮询队列，取出命令慢慢处理。
local cmd_queue = {}

-- clamp：数值范围保护，把输入值钳制在 [lo, hi] 闭区间内。
-- tonumber 失败时用 lo 作为默认值；math.floor 保证是整数。
local function clamp(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end

-- 独立 task：从命令队列取命令并处理
sys.taskInit(function()
    while true do
        if #cmd_queue > 0 then
            local line = table.remove(cmd_queue, 1)
            if line == "b?" then
                log.info("cmd", "brightness =", WS2812_CFG.brightness)
            elseif line == "s?" then
                log.info("cmd", "speed_ms =", WS2812_CFG.speed_ms)
            else
                -- 匹配 b=数字 或 s=数字 形式
                local k, v = string.match(line, "^([bs])=(%-?%d+)$")
                if k == "b" then
                    WS2812_CFG.brightness = clamp(v, 0, 255)
                    log.info("cmd", "brightness =", WS2812_CFG.brightness)
                elseif k == "s" then
                    WS2812_CFG.speed_ms = clamp(v, 20, 2000)
                    log.info("cmd", "speed_ms =", WS2812_CFG.speed_ms)
                else
                    log.info("cmd", "unknown:", line, "(use b=NNN s=NNN b? s?)")
                end
            end
        end
        sys.wait(20)
    end
end)

-- 初始化串口；if uart then 是防御性判断，防止精简固件无 uart 模块时崩溃
if uart then
    uart.setup(UART_ID, 115200)
    uart.on(UART_ID, "recv", function(id, len)
        local data = uart.read(id, len)
        if not data then return end
        rx_buf = rx_buf .. data
        while true do
            -- 兼容 \n / \r / \r\n 三种换行风格
            local s, e = string.find(rx_buf, "[\r\n]+")
            if not s then break end
            local line = string.sub(rx_buf, 1, s - 1)
            rx_buf = string.sub(rx_buf, e + 1)
            if line ~= "" then
                cmd_queue[#cmd_queue + 1] = line
            end
        end
    end)
    log.info("cmd", "串口命令已就绪 (115200): b=NNN s=NNN b? s?")
else
    log.warn("cmd", "固件未启用 uart，无法使用串口命令")
end
