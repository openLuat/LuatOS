--[[
@module  pins_dynamic
@summary pins_dynamic测试功能模块
@version 1.0
@date    2025.10.15
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EHM核心板，演示动态修改管脚复用功能
核心逻辑：
1.加载自定义的管脚配置文件my.json配置管脚功能
文件中配置
pin28功能是UART2_RXD

pin29功能是UART2_TXD

pin55功能是CAM_RX0

pin56功能是CAM_RX1

2.通过pins.setup接口动态修改管脚复用功能，

这里演示把pin28由原UART2_RXD功能配置为GPIO12，

pin29由原UART2_TXD功能配置为GPIO13，

pin55由原CAM_RX0功能配置为UART2_RXD，

pin56由原CAM_RX1功能配置为UART2_TXD，

3.演示重新配置的串口管脚的功能，通过串口工具收发数据。


]]


--如果需要debug,在任何需要的地方添加这一行
--log.info ("打开debug",pins.debug(true))

--如果打开debug后需要关闭debug,在任何需要的地方添加这一行
--log.info ("打开debug",pins.debug(false))


--自定义配置文件要通过pins.loadjson加载
--如果烧录了pins_Air780EHM.json，在内核固件运行时，已经自动加载pins_Air780EHM.json，并且按照pins_Air780EHM.json的配置初始化所有io引脚功能，
--此处再加载my.json文件，会覆盖pins_Air780EHM.json中配置的所有io引脚功能，按照my.json的配置再次初始化所有io引脚功能,
--my.json文件中：
--pin28默认为UART2_RXD，
--pin29默认为UART2_TXD，
--pin55默认为CAM_RX0，
--pin56默认为CAM_RX1，
--通过下面的配置管脚复用的代码将这四个脚重新配置：
--pin28由默认UART2_RXD修改配置为GPIO12，
--pin29由默认UART2_TXD修改配置为GPIO13,
--pin55由默认CAM_RX0配置为UART2_RXD，
--pin56由默认CAM_RX1配置为UART2_TXD

--烧录多个.json文件时以最后一个文件的配置初始化所有io引脚功能
log.info("加载自定义的配置文件", pins.loadjson("/luadb/my.json"))

--=======配置管脚复用=========--

log.info("uart", "重新配置uart2到新管脚")
uart.close(2)
local r1 = pins.setup(28, "GPIO12")
log.info("配置pin28脚即UART2_RXD为GPIO12", r1)
local r2 = pins.setup(29, "GPIO13")
log.info("配置pin29脚即UART2_TXD为GPIO13", r2)
gpio.close(12)
gpio.close(13)

local r3 = pins.setup(55, "UART2_RX")
log.info("配置pin55脚即CAM_RX0为UART2_RXD", r3)
local r4 = pins.setup(56, "UART2_TX")
log.info("配置pin56脚即CAM_RX1为UART2_TXD", r4)



--========验证复用的管脚的功能=========--
local uartid = 2

--初始化 参数都可以根据实施情况修改
uart.setup(
--串口id
    uartid,
    --波特率
    115200,
    8, --数据位
    1  --停止位
)

log.info("uart", "uart2重新配置完成")
local function ur_rec(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        -- #s 是取字符串的长度
        if #s > 0 then
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到，可以用以hex格式打印
            log.info("uart", "receive(hex)", id, #s, s:toHex())
        end
    until s == ""
end
-- 收取数据会触发回调, 这里的 "receive" 是固定值不要修改。
uart.on(uartid, "receive", ur_rec)


--向串口发送数据
local function uart_test()
    local n = 0
    while n < 10 do
        sys.wait(2000)
        log.info("这是第" .. n .. "次向串口发数据")
        -- 写入可见字符串
        --uart.write(uartid, "test data.")
        -- 写入十六进制字符串
        uart.write(uartid, string.char(0x55, 0xAA, 0x4B, 0x03, 0x86))
        n = n + 1
        sys.wait(2000)
    end
end



sys.taskInit(uart_test)
