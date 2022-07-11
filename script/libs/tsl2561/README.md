# TSL2561 驱动

光强传感器驱动 I2C 开发板模块

## 用法示例

```lua

local tsl2561 = require "tsl2561"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    tsl2561.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local tsl2561_data = tsl2561.get_data()
        log.info("tsl2561_data", tsl2561_data.."Lux")
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=TSL2561
