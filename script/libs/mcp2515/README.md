# mcp2515 SP转CAN

CAN总线模块. 请务必确认硬件ok, 某宝上的CAN总线模块质量堪忧.

## 用法示例

```lua

local mcp2515 = require "mcp2515"

-- mcp2515    mcu
-- csk      spi_sck
-- si       spi_mosi
-- so       spi_miso
-- cs       spi_cs
-- int      gpio

sys.subscribe("mcp2515", function(len,buff,config)
    print("mcp2515", len,buff:byte(1,len))
    for k, v in pairs(config) do
        print(k,v)
    end
end)

sys.taskInit(function()
    local mcp2515_spi= 0
    local mcp2515_cs= pin.PB04
    local mcp2515_int= pin.PB01
    spi_mcp2515 = spi.setup(mcp2515_spi,nil,0,0,8,10*1000*1000,spi.MSB,1,0)
    mcp2515.init(mcp2515_spi,mcp2515_cs,mcp2515_int,mcp2515.CAN_500Kbps)

    mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,数据帧
    mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,数据帧
    mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,远程帧
    mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,远程帧

end)
```

## 购买链接

https://s.taobao.com/search?q=mcp2515
