--[[
@module  factory
@summary 产测主控：串口指令解析 + 指令分发 + 回包
@version 1.2
@date    2026.10.15
@usage
产测串口由 config 的 factory.uart_id 指定（默认 1 = UART1，外接串口板），115200 8N1。

回包格式（与 Air8300/Air8301 工业模组产测一致）：
    成功          OK#
    失败          ERROR#
    带数据的项    <值>#（如 IP、热点数量、版本号）
中文说明只写日志，不进串口回包。

指令表：
    VERSION#                    固件版本（PROJECT_VERSION）
    MODEL,型号# / MODEL?#       写 / 读工业型号
    HVERSION,版本# / HVERSION?# 写 / 读硬件版本
    LCD_TEST#  TP_TEST#  I2C_SCAN#  U485_TEST#  WIFI_TEST#  SD_TEST#
    NAND_TEST# ETH_TEST# CAM_TEST# AUDIO_TEST# 4G_TEST#
    RST#                         重启（不写产测完成标记）
    TEST_DONE#                   标记完成并重启进用户模式
]]

local prodmeta = require "prod_meta"

-- 产测串口：取板级配置（config_*.lua 的 factory 段），换板型/换接线不用改产测代码
local ft_cfg   = (_G.project_config and _G.project_config.factory) or {}
local UART_ID  = ft_cfg.uart_id or 1
local BAUD     = ft_cfg.baud or 115200
local RECV_MAX = 256

local recv_buf = ""
local rx_enabled = false  -- 轮询兜底是否生效（4G_TEST 让出串口时置 false）
local busy     = false   -- 同一时刻只跑一项测试

local function send(s)
    s = tostring(s)
    uart.write(UART_ID, s .. "#")
    log.info("factory", "TX ->", s .. "#")
end

-- ===== 基础指令 =====
local CMD = {}

CMD["VERSION"] = function()
    send(PROJECT .. "_" .. VERSION)
end

CMD["INFO"] = function()
    local cfg = _G.project_config or {}
    send(cfg.chip or "ERROR")
end

CMD["MODEL"] = function(arg)
    if not arg or arg == "" or arg == "?" then
        send(prodmeta.get("PROD") or "ERROR")
        return
    end
    send(prodmeta.set("PROD", arg) and "OK" or "ERROR")
end

CMD["HVERSION"] = function(arg)
    if not arg or arg == "" or arg == "?" then
        send(prodmeta.get("PCB") or "ERROR")
        return
    end
    send(prodmeta.set("PCB", arg) and "OK" or "ERROR")
end

CMD["RST"] = function()
    -- 单独重启：不写 test_done，延时确保 OK# 已发出
    send("OK")
    sys.timerStart(rtos.reboot, 500)
end

CMD["TEST_DONE"] = function()
    fskv.set("test_done", 1)
    send("OK")
    sys.timerStart(rtos.reboot, 3000)
end

-- ===== 产测项实现模块 =====
-- 约定：模块返回字符串 —— "OK" / "ERROR" / 具体值（IP、热点数量等）
-- 用函数包住 require：既保证是静态引用（烧录合并器才会打包这些文件），
-- 又让各产测项在首次调用时才加载、不占启动内存。
local TEST_MODULES = {
    LCD_TEST   = function() return require "prod_lcd"   end,
    TP_TEST    = function() return require "prod_tp"    end,
    I2C_SCAN   = function() return require "prod_i2c"   end,
    U485_TEST  = function() return require "prod_485"   end,
    WIFI_TEST  = function() return require "prod_wifi"  end,
    SD_TEST    = function() return require "prod_sd"    end,
    CAM_TEST   = function() return require "prod_cam"   end,
    AUDIO_TEST = function() return require "prod_audio" end,
    NAND_TEST  = function() return require "prod_nand"  end,
    ETH_TEST   = function() return require "prod_eth"   end,
    ["4G_TEST"] = function() return require "prod_4g"   end,
}

for cmd, loader in pairs(TEST_MODULES) do
    CMD[cmd] = function(arg)
        local ok_load, fn = pcall(loader)
        if not ok_load then
            log.error("factory", cmd, "模块加载失败:", tostring(fn))
            return send("ERROR")
        end
        local success, res = pcall(fn, arg)
        if not success then
            log.error("factory", cmd, "执行异常:", tostring(res))
            return send("ERROR")
        end
        send(res or "ERROR")
    end
end

-- ===== 解析与分发 =====
local function handle(line)
    line = line:match("^%s*(.-)%s*$")
    if line == "" then return end

    -- 兼容 "MODEL?#" / "MODEL?Air8101B#" 这种写法（Air8300/Air8301 产测习惯）：
    -- 把指令名后紧跟的 '?' 规范成 ','，再统一切分
    local qname, qrest = line:match("^([%w_]+)%?(.*)$")
    if qname then
        line = qname .. "," .. qrest
    end

    -- 只按第一个分隔符切分：分隔符支持 , 和空格
    local name, arg = line:match("^([%w_]+)[%s,]+(.*)$")
    if not name then
        name, arg = line, nil
    end
    name = name:upper()

    log.info("factory", "CMD:", name, arg or "")
    local fn = CMD[name]
    if not fn then
        log.warn("factory", "未知指令:", name)
        return send("ERROR")
    end

    -- 测试项内部会 sys.wait（等扫描/触摸/回环），必须放到任务里跑，
    -- 否则会阻塞串口接收回调
    if busy then
        log.warn("factory", "上一项测试未结束，忽略:", name)
        return send("ERROR")
    end
    busy = true
    sys.taskInit(function()
        local success, err = pcall(fn, arg)
        if not success then
            log.error("factory", name, "执行异常:", tostring(err))
            send("ERROR")
        end
        busy = false
    end)
end

-- ===== 串口接收（按 # 分包）=====
-- 就绪提示：必须在静默日志之前打印
log.info("factory", "产测模式就绪", PROJECT, VERSION,
    "指令口 UART" .. UART_ID, BAUD .. " 8N1，指令以 # 结尾")

-- UART0 同时是日志口：静默日志后由 uart 库完全接管该串口，
-- 否则 log 驱动会与产测收发抢同一个串口（表现为日志能看、指令进不来）。
-- 调试时可把 config 里的 factory.log_silent 改为 false。
if ft_cfg.log_silent then
    log.setLevel("SILENT")
end

-- 接收处理：把数据累进缓冲，按 # 切分后逐条分发
-- 抽成 feed()，中断回调和下面的轮询兜底都走这一条路（数据只会被读走一次，不会重复分发）
local function feed(data)
    if not data or data == "" then return end

    -- 诊断用：把收到的原始字节打出来（hex）。
    -- 到过现场的现象是"发指令没反应"：其实串口板/线电平不对时收到的是乱码，
    -- 里面没有 '#' → 不触发任何指令；这行日志能一眼看出收到的到底是什么。
    log.info("factory", "收到", #data, "字节:", data:toHex())

    recv_buf = recv_buf .. data
    if #recv_buf > RECV_MAX then
        recv_buf = recv_buf:sub(-RECV_MAX)
    end

    while true do
        local idx = recv_buf:find("#", 1, true)
        if not idx then break end
        local line = recv_buf:sub(1, idx - 1)
        recv_buf = recv_buf:sub(idx + 1)
        handle((line:gsub("[\r\n]", "")))
    end
end

local function on_receive(id, len)
    feed(uart.read(id, len))
end

local function uart_bind()
    uart.setup(UART_ID, BAUD, 8, 1, uart.NONE, uart.LSB, 1024)
    uart.on(UART_ID, "receive", on_receive)
    rx_enabled = true
end

local function uart_unbind()
    rx_enabled = false
    uart.on(UART_ID, "receive", function() end)
end

_G.factory_uart = { id = UART_ID, bind = uart_bind, unbind = uart_unbind }

uart_bind()

sys.timerLoopStart(function()
    if not rx_enabled then return end
    feed(uart.read(UART_ID, 512))
end, 50)

-- 注：调试用的 RDY# / PING# 握手与心跳已移除（2026-10-16）。
-- 产测口只做"收指令 → 回包"，不主动往外发任何东西，避免干扰现场判断。
