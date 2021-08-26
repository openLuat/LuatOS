
# LuatOS@Linux

* 底层rtos FreeRTOSv202012.00
* 编译工具cmake/make/gcc
* 文件系统,posix原生文件系统,以工作目录为基点
* 默认luavm和rtos内存分配均为 1MByte

## 简易编译说明

```sh
cd bsp/linux
mkdir build
cd build
cmake ..
make
```

编译完成后, 会在build目录生成 `luatos`

## 简单用法

```sh
./luatos
```

```lua
local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    while true do
        log.info("hi", os.date())
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
end)

sys.run()
```



