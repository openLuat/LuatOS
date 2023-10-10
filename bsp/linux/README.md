
# LuatOS@Linux

* 编译工具xmake
* 文件系统,posix原生文件系统,以工作目录为基点
* 默认luavm和rtos内存分配均为 1MByte

## 简易编译说明

1. 先安装xmake

```shell
curl -fsSL https://xmake.io/shget.text | bash
```

2. 安装必要的库

```shell
apt install -y libssl1.1-dev llvm clang libreadline-dev libsdl2-dev
```

3. 执行编译,要进入本bsp的目录

```shell
xmake -y --root
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

## 常见问题

TODO
