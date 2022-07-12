# RC522 驱动

非接触式读写卡驱动 I2C 开发板模块

## 用法示例

```lua

local rc522 = require "rc522"
sys.taskInit(function()
    spi_rc522 = spi.setup(0,nil,0,0,8,10*1000*1000,spi.MSB,1,1)
    rc522.init(0,pin.PB04,pin.PB01)
    wdata = {0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
    while 1 do
        rc522.write_datablock(8,wdata)
        for i=0,63 do
            local a,b = rc522.read_datablock(i)
            if a then
                print("read",i,b:toHex())
            end
        end
        sys.wait(500)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=ADXL34
