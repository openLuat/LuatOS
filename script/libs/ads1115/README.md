# ADS1115 驱动

超小型 16位 精密 模数转换器 ADC 开发板模块

## 用法示例

```lua

local ads1115 = require "ads1115"
i2cid = 0 -- 根据实际设备选择
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    ads1115.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local ads1115_data = ads1115.get_val()
        log.info("ads1115_get_val", ads1115_data)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=ADS1115
