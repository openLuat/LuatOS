# TCS3472 驱动

颜色传感器 I2C 开发板模块

## 用法示例

```lua

local tcs3472 = require "tcs3472"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    tcs3472.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local rgb_date = tcs3472.get_rgb()
        log.info("rgb_date.R:",rgb_date.R)
        log.info("rgb_date.G:",rgb_date.G)
        log.info("rgb_date.B:",rgb_date.B)
        log.info("rgb_date.C:",rgb_date.C)
        local lux_date = tcs3472.get_lux(rgb_date)
        log.info("lux_date:",lux_date)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=TCS3472
