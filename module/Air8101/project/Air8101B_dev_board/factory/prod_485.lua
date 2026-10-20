--[[
@module  prod_485
@summary 产测项 U485_TEST#：UART2 / RS485 一发一收
@usage
  U485_TEST#         RS485 差分回环：板 485 端子 A→对端A、B→对端B
                     （对端可为 USB-485 回显工装，或另一块板）
  U485_TEST,ttl#     UART2 TTL 自环：关串口拨码，短接 UART2 排针 TX-RX
@return  string —— "OK" / "ERROR"
前置条件（485 模式）
1. 板上 VBAT_485 拨码打开（485 收发器供电）；
2. 外部对端已接好 A-A、B-B（A/B 反了是常见坑，失败可对调试一次）；
3. 对端要"收到即原样回发"。实测最省事的做法：让对端**定时循环发送**测试字符串
   （SSCOM 勾"定时发送"、间隔 200ms），板子在这 3 秒窗口内必然收到。
   注意：USB-485 转换器本身不会自动回发，回发必须靠上位机软件。
4. 对端波特率需与本项一致，见 config 的 hw.rs485.baud（默认 115200）。

发送与接收是两个独立方向：
  串口板收到数据  = 板的发送方向通；
  板收到回发才 OK = 板的接收方向通。
本项为验证接收方向，采用**手动控制 RE/DE**（不使用 uart.setup 的自动换向，
该机制在 Air8101 上未经验证），并把每一步打进日志便于定位。
]]

local TIMEOUT_S = 3
local TEST_DATA = "U485_TEST_OK"
local DIR_TX    = 1   -- 发送方向电平（SP3485：DE 高有效）
local DIR_RX    = 0   -- 接收方向电平（RE 低有效）

return function(arg)
    local pins    = require "board_pins"
    local uart_id = pins.uart.rs485.id
    local c       = _G.project_config.hw.rs485
    local baud    = c.baud or 115200

    local ttl_mode = (type(arg) == "string" and arg:lower() == "ttl")

    if ttl_mode then
        -- TTL 模式：不经过 485 芯片，无方向脚
        uart.setup(uart_id, baud, 8, 1, uart.NONE, uart.LSB, 1024)
    else
        -- 保险：显式把方向脚声明成 GPIO（Air8101 上多次遇到 pad 默认功能不是 GPIO）
        if pins and pins.setup then
            local bp = require "board_pins"
            if bp.rs485 and bp.rs485.pad_dir then
                local ok = pcall(pins.setup, bp.rs485.pad_dir, "GPIO37")
                log.info("prod_485", "方向脚 pinmux:", ok and "OK" or "跳过")
            end
        end

        gpio.setup(c.en, 1)         -- 485_EN LDO 使能
        sys.wait(20)
        gpio.setup(c.dir, DIR_RX)   -- 先置于接收
        sys.wait(5)
        -- 注意：故意不传方向脚，改由本模块手动切换，便于确认是否真的切回了接收
        uart.setup(uart_id, baud, 8, 1, uart.NONE, uart.LSB, 1024)
    end

    local recv = ""
    uart.on(uart_id, "receive", function(id, len)
        local d = uart.read(id, len)
        if d and #d > 0 then
            recv = recv .. d
            log.info("prod_485", "收到", #d, "字节:", d)
            sys.publish("U485_DATA")
        end
    end)

    log.info("prod_485", "方向: 接收(RE/DE=" .. DIR_RX .. ")")

    if not ttl_mode then
        gpio.setup(c.dir, DIR_TX)   -- 切到发送
        sys.wait(5)
        log.info("prod_485", "方向: 发送(RE/DE=" .. DIR_TX .. ")")
    end

    uart.write(uart_id, TEST_DATA)
    log.info("prod_485", "已发送:", TEST_DATA, "波特率:", baud)

    if not ttl_mode then
        sys.wait(20)                -- 等数据发完（12 字节@115200≈1ms，留足余量）
        gpio.setup(c.dir, DIR_RX)   -- 切回接收
        log.info("prod_485", "方向: 已切回接收，等待回环")
    end

    local t0 = os.time()
    while os.time() - t0 < TIMEOUT_S do
        sys.waitUntil("U485_DATA", 500)
        if recv:find(TEST_DATA, 1, true) then break end
    end

    uart.on(uart_id, "receive", function() end)   -- 收尾：解绑回调

    if recv:find(TEST_DATA, 1, true) then
        log.info("prod_485", ttl_mode and "TTL 自环成功" or "485 回环成功")
        return "OK"
    end

    if #recv == 0 then
        log.error("prod_485", TIMEOUT_S .. " 秒内没收到任何数据 —— ",
            "说明发送方向通（对端已看到数据）、但接收方向没拿到回发。",
            ttl_mode and "查拨码是否关、TX-RX 是否短接"
                     or "查对端是否真的回发了数据（只看不收不等于回发）、A/B 是否接反")
    else
        log.error("prod_485", "收到的数据不匹配，实际:", recv,
            "（对端波特率需为 " .. baud .. "）")
    end
    return "ERROR"
end
