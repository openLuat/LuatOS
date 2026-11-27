--[[
@module  factory_hzadb
@summary 把 hzadb CUSTOM(0x40) 通道模拟成一根独立 UART，供产测调试命令串口使用
@version 1.0
@date    2026.11.05

背景：
- EC718( Air780EHM/EPM/EGG/EGP 等 ): hzadb 走 USB 虚拟出来的 SOC 日志输出端口；
- Air8101/Air160x: hzadb 走 uart0 日志口。
工厂上位机用 hzadb 协议连上这条调试口后，把 CUSTOM(0x40) 当作一根普通串口：
下行字节流 = 产测指令（如 "VERSION#"），可以任意分片；
上行字节流 = 产测回包（如 "Air8201_...#"），由设备经 custom_send 以 EVT 事件帧发出。
对 factory.lua 来说，它只是多了一根 UART 通道，原 USB 虚拟串口/UART 通道保持不变。

用法（factory.lua 内）：
    local hzadbUart
    hzadbUart = require("factory_hzadb").attach(function(data)
        -- data: 上位机经 CUSTOM 发来的原始字节
        hzadbRxCache = hzadbRxCache .. data
        while true do
            local result
            result, hzadbRxCache = proc(hzadbUart.id, hzadbRxCache)
            if not result then break end
        end
    end)
    if hzadbUart then
        hzadbUart.id       -- 虚拟通道 id，传给 send_response()
        hzadbUart.write(s) -- 回包，按 <=1024B 分片经 hzadb.custom_send() 发出
    end

约束：
- 回包走 flags.EVT 事件帧，不占用 CUSTOM 请求的应答体（应答体固定为空）。
  事件帧无重传，上位机按"超时重发指令"兜底。
- 固件未开 LUAT_USE_LOG_USER_CMD、或 hzadb 库版本过旧时，attach 返回 nil，
  原串口通道不受影响。
]]

local bridge = {}

bridge.VERSION = "20261105"

-- 单条事件帧载荷上限。hzadb.custom_send 本身允许 4096B；
-- 这里取 1024B，与 hzadb 的 MAX_CHUNK 一致，避免日志口单帧过大。
local MAX_EVENT = 1024

local function get_hzadb()
    -- 写成闭包里的 require("hzadb")：既不因缺库在加载期报错，又能被脚本打包器
    -- 静态扫描到，保证 hzadb.lua 会被收进固件
    local ok, hzadb = pcall(function() return require("hzadb") end)
    if not ok then
        log.warn("factory_hzadb", "hzadb 库不可用，调试串口通道关闭", hzadb)
        return nil
    end
    if type(hzadb) ~= "table" or type(hzadb.on_custom) ~= "function"
        or type(hzadb.custom_send) ~= "function" or type(hzadb.start) ~= "function" then
        log.warn("factory_hzadb", "hzadb 版本过旧(缺 CUSTOM 接口)，调试串口通道关闭")
        return nil
    end
    return hzadb
end

--- 把 hzadb CUSTOM(0x40) 挂成一根虚拟 UART
-- @function on_receive 收到上位机字节流时的回调
-- @return table|nil 成功返回 { id = "hzadb", write = function(data) end }
function bridge.attach(on_receive)
    if type(on_receive) ~= "function" then
        error("factory_hzadb.attach: on_receive must be a function")
    end

    local hzadb = get_hzadb()
    if not hzadb then
        return nil
    end

    local vuart = { id = "hzadb" }
    local write_warned = false

    --- 把产测回包按分片写入 CUSTOM 事件帧
    -- @string data 回包字节
    function vuart.write(data)
        if type(data) ~= "string" or #data == 0 then
            return
        end
        for i = 1, #data, MAX_EVENT do
            local chunk = data:sub(i, i + MAX_EVENT - 1)
            local ok, sent = pcall(hzadb.custom_send, chunk)
            if not ok then
                log.warn("factory_hzadb", "custom_send 异常，回包丢弃", sent)
                return
            end
            if sent == false then
                if not write_warned then
                    write_warned = true
                    log.warn("factory_hzadb", "日志口用户指令不可用，调试串口回包丢弃")
                end
                return
            end
        end
    end

    hzadb.on_custom(function(data)
        if type(data) ~= "string" then
            return hzadb.E_BADREQ, ""
        end
        local ok, err = pcall(on_receive, data)
        if not ok then
            log.error("factory_hzadb", "调试串口指令处理异常", err)
            return hzadb.E_IO, ""
        end
        -- 实际回包走 EVT 事件帧，CUSTOM 应答体留空
        return ""
    end)

    -- deferred: 在独立任务里执行 handler，避免在日志口 C 回调里跑耗时/可等待逻辑
    local ok_start, started = pcall(hzadb.start, { deferred = true })
    if not ok_start then
        -- 老固件可能没有 sys.taskInitEx，回退到日志回调内直接处理
        ok_start, started = pcall(hzadb.start)
    end
    if not ok_start or not started then
        log.warn("factory_hzadb", "hzadb.start 失败(固件未开 LUAT_USE_LOG_USER_CMD)",
            ok_start and "" or started)
        return nil
    end

    log.info("factory_hzadb", "hzadb 调试串口通道就绪", hzadb.VERSION)
    return vuart
end

return bridge
