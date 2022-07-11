# DS3231 驱动

实时时钟传感器 I2C 开发板模块

## 用法示例

```lua

local ds3231 = require "ds3231"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    ds3231.init(i2cid)--初始化,传入i2c_id
    while 1 do
        log.info("ds3231.get_temperature", ds3231.get_temperature())
        local time = ds3231.read_time()
        log.info("ds3231.read_time",time.tm_year,time.tm_mon,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec)
        sys.wait(5000)
        local set_time = {tm_year=2021,tm_mon=3,tm_mday=0,tm_wday=0,tm_hour=0,tm_min=0,tm_sec=0}
        ds3231.set_time(set_time)
        time = ds3231.read_time()
        log.info("ds3231_read_time",time.tm_year,time.tm_mon,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec)
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=DS3231
