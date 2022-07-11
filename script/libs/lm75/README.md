# LM75 驱动

温度传感器 I2C 开发板模块

## 用法示例

```lua

local lm75 = require "lm75"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    lm75.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local lm75_data = lm75.get_data()
        if lm75_data then
            log.info("lm75_data", lm75_data.."℃")
        end
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=LM75
