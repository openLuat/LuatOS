# GT911 驱动

电容触摸驱动 I2C 开发板模块

## 用法示例

```lua

local gt911 = require "gt911"

local i2cid = 0
local gt911_res = pin.PA07
local gt911_int = pin.PA00
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    gt911.init(i2cid,gt911_res,gt911_int)
    while 1 do
        sys.wait(1000)
    end
end)

local function gt911CallBack(press_sta,i,x,y)
    print(press_sta,i,x,y)
end

sys.subscribe("GT911",gt911CallBack)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=GT911
