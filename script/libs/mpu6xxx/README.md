# MPU6XXX 驱动

加速度计 I2C 开发板模块

## 用法示例

```lua

local mpu6xxx = require "mpu6xxx"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    mpu6xxx.init(i2cid)--初始化,传入i2c_id
    while 1 do
        sys.wait(100)
        local temp = mpu6xxx.get_temp()--获取温度
        log.info("6050temp", temp)
        local accel = mpu6xxx.get_accel()--获取加速度
        log.info("6050accel", "accel.x",accel.x,"accel.y",accel.y,"accel.z",accel.z)
        local gyro = mpu6xxx.get_gyro()--获取陀螺仪
        log.info("6050gyro", "gyro.x",gyro.x,"gyro.y",gyro.y,"gyro.z",gyro.z)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=MPU6XXX
