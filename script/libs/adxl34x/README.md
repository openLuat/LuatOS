# ADXL34X 驱动

3轴 加速度计 I2C 开发板模块

## 用法示例

```lua

local adxl34x = require "adxl34x"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    adxl34x.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local adxl34x_data = adxl34x.get_data()
        log.info("adxl34x_data", "adxl34x_data.x"..(adxl34x_data.x),"adxl34x_data.y"..(adxl34x_data.y),"adxl34x_data.z"..(adxl34x_data.z))
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=ADXL34
