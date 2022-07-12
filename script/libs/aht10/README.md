# AHT10 驱动

温湿度传感器 I2C 开发板模块

## 用法示例

```lua

local aht10 = require "aht10"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    aht10.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local aht10_data = aht10.get_data()
        log.info("aht10_data", "aht10_data.RH:"..(aht10_data.RH*100).."%","aht10_data.T"..(aht10_data.T).."℃")
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=AHT10
