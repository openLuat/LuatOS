# L3G4200D 驱动

3轴 加速度计 I2C 开发板模块

## 用法示例

```lua

local l3g4200d = require "l3g4200d"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    l3g4200d.init(i2cid)--初始化,传入i2c_id
    while 1 do
    local l3g4200d_data = l3g4200d.get_data()
    log.info("l3g4200d_data", l3g4200d_data.x,l3g4200d_data.y,l3g4200d_data.z)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=L3G4200D
