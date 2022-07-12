# BH1750 驱动

数字型光强度传感器 I2C 开发板模块

## 用法示例

```lua

local bh1750 = require "bh1750"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bh1750.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bh1750_data = bh1750.read_light()
        log.info("bh1750_read_light", bh1750_data)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=BH1750
