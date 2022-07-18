# XMODEM 文件传输协议

XMODEM 文件传输协议

可用于air101/air103的刷机, 或者对其他设备传输文件/刷机

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

