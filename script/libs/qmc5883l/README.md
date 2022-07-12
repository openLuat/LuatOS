# QMC5883L 驱动

地磁传感器 I2C 开发板模块

## 用法示例

```lua

local qmc5883l = require "qmc5883l"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    qmc5883l.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local qmc5883l_data = qmc5883l.get_data()
        log.info("qmc5883l_data", qmc5883l_data.x,qmc5883l_data.y,qmc5883l_data.z,qmc5883l_data.heading,qmc5883l_data.headingDegrees)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=QMC5883L
