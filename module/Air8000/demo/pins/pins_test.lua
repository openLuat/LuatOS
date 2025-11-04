--[[
@module  pins_test
@summary pins_test测试功能模块
@version 1.0
@date    2025.10.15
@author  马亚丹
@usage
本demo演示的功能为：使用Air8000核心板，演示动态修改管脚复用功能
核心逻辑：
1.加载自定义的管脚配置文件
2.动态修改管脚复用功能，这里演示SPI管脚pin41脚即SPI1_CS复用为UART2_RX，pin40脚即SPI1_MOSI复用为UART2_TX
3.演示复用的串口管脚的功能，通过串口工具收发数据。

]]


--如果需要debug,在任何需要的地方添加这一行
--log.info ("打开debug",pins.debug(true))

--如果打开debug后需要关闭debug,在任何需要的地方添加这一行
--log.info ("打开debug",pins.debug(false))

--方式1 ：打开下面这行加载配置文件，如果烧录了pins_$model.json文件，就会自动加载，不需要pins.loadjson再设置加载
-- 其中 $model是模组型号, 例如 Air8000, 默认加载的是 luadb/pins_Air8000.json，其他格式的不会自动加载
--log.info ("加载luatIO生成的配置文件",pins.loadjson("/luadb/pins_Air8000.json"))
--在pins_Air8000.json文件中，pin40配置为UART2_TXD，pin41配置为UART2_RXD

--方式2 ：自定义配置文件要通过pins.loadjson加载
--如果烧录了pins_Air8000.json，在内核固件运行时，已经自动加载pins_Air8000.json，并且按照pins_Air8000.json的配置初始化所有io引脚功能，
--此处再加载my.json文件，会覆盖pins_Air8000.json中配置的所有io引脚功能，按照my.json的配置再次初始化所有io引脚功能,
--my.json文件中pin40配置为SPI1_MOSI，pin41配置为SPI1_CS，通过下面的配置管脚复用的两行代码将这两个脚配置为UART2使用，
--烧录多个.json文件时以最后一个文件的配置初始化所有io引脚功能
log.info ("加载自定义的配置文件",pins.loadjson("/luadb/my.json"))

--=======配置管脚复用=========--
local r1=pins.setup(41, "UART2_RX")
log.info ("配置pin41脚即SPI1_CS为UART2_RX",r1)
local r2=pins.setup(40, "UART2_TX")
log.info ("配置pin40脚即SPI1_MOSI为UART2_TX",r2)

--========验证复用的管脚的功能=========--
local uartid = 2 

--初始化 参数都可以根据实施情况修改
uart.setup(
    --串口id
    uartid,
    --波特率
    115200,
    8,--数据位
    1--停止位
)

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
    local n=0
    while n<10 do   
        sys.wait(2000)     
        log.info("这是第"..n.."次向串口发数据")
        -- 写入可见字符串
        --uart.write(uartid, "test data.")
        -- 写入十六进制字符串
        uart.write(uartid, string.char(0x55,0xAA,0x4B,0x03,0x86))
        n=n+1
        sys.wait(2000)
    end
end
sys.taskInit(uart_test)

