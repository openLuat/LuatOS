# LIS2DH12 驱动

3轴 加速度计 I2C 开发板模块

## 用法示例

```lua

local lis2dh12 = require "lis2dh12"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    lis2dh12.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local lis2dh12_data = lis2dh12.get_data()
        log.info("lis2dh12_data", "lis2dh12_data.x"..(lis2dh12_data.x),"lis2dh12_data.y"..(lis2dh12_data.y),"lis2dh12_data.z"..(lis2dh12_data.z),"lis2dh12_data.temp"..(lis2dh12_data.temp))
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=LIS2DH12
