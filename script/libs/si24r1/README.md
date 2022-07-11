# SI24R1 驱动

无线收发驱动 I2C 开发板模块

## 用法示例

```lua

local si24r1 = require "si24r1"

sys.taskInit(function()
    spi_si24r1 = spi.setup(0,nil,0,0,8,10*1000*1000,spi.MSB,1,1)
    si24r1.init(0,pin.PB04,pin.PB01,pin.PB00)
    if si24r1.chip_check() then
        si24r1.set()
    end

    --发送示例
    -- si24r1.set_mode( si24r1.MODE_TX );		--发送模式	
    -- while 1 do
    --     sys.wait(1000)
    --     local a = si24r1.txpacket("si24r1test")
    --     print("a",a)
    -- end

    --接收示例 
    si24r1.set_mode( si24r1.MODE_RX );		--接收模式	
    while 1 do
        local i,data = si24r1.rxpacket( );		--接收字节
        print("rxbuf",i,data)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=SI24R1
