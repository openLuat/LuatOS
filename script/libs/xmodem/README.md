# XMODEM 驱动

I2C 开发板模块

## 用法示例

```lua

local xmodem = require "xmodem"
sys.taskInit(function()
    xmodem.send(2,115200,"/luadb/test.bin")
    while 1 do
        sys.wait(1000)
    end
end)

sys.run()
```

## 购买链接

https://s.taobao.com/search?q=XMODEM
