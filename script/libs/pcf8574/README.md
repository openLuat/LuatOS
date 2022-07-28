# LM75 驱动

IO扩展 I2C 开发板模块

## 用法示例

```lua

local pcf8574 = require "pcf8574"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    pcf8574.init(i2cid)--初始化,传入i2c_id
    for i=0,7 do
        print(pcf8574.pin(i))
    end
    pcf8574.pin(0,1)
    for i=0,7 do
        print(pcf8574.pin(i))
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=PCF8574
