# BMX 驱动

气压传感器 I2C 开发板模块

## 用法示例

```lua

local bmx = require "bmx"
i2cid = 0
i2c_speed = i2c.SLOW
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bmx.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bmx_data = bmx.get_data()
        if bmx_data.temp then
            log.info("bmx_data_data.temp:"..(bmx_data.temp).."°C")
        end
        if bmx_data.press then
            log.info("bmx_data_data.press:"..(bmx_data.press).."hPa")
        end
        if bmx_data.high then
            log.info("bmx_data_data.high:"..(bmx_data.high).."m")
        end
        if bmx_data.hum then
            log.info("bmx_data_data.hum:"..(bmx_data.hum).."%")
        end
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=BMX
