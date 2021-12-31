
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

## 常见问题

**1：执行`cmake ..`时报错：**

```
-- The C compiler identification is GNU 8.3.0
-- The CXX compiler identification is unknown
-- Check for working C compiler: /usr/bin/cc
-- Check for working C compiler: /usr/bin/cc -- works
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Detecting C compile features
-- Detecting C compile features - done
CMake Error at CMakeLists.txt:14 (project):
  No CMAKE_CXX_COMPILER could be found.

  Tell CMake where to find the compiler by setting either the environment
  variable "CXX" or the CMake cache entry CMAKE_CXX_COMPILER to the full path
  to the compiler, or to the compiler name if it is in the PATH.


-- Configuring incomplete, errors occurred!
See also "/data/home/lqy/code/LuatOS/bsp/linux/build/CMakeFiles/CMakeOutput.log".
See also "/data/home/lqy/code/LuatOS/bsp/linux/build/CMakeFiles/CMakeError.log".
```

**答：未安装g++，执行`sudo apt-get install g++`**

**2：执行`make`时报错：**

```
[ 99%] Building C object CMakeFiles/luatos.dir/src/lua.c.o
/data/home/lqy/code/LuatOS/bsp/linux/src/lua.c:82:10: fatal error: readline/readline.h: 没有那个文件或目录
 #include <readline/readline.h>
          ^~~~~~~~~~~~~~~~~~~~~
compilation terminated.
make[2]: *** [CMakeFiles/luatos.dir/build.make:76：CMakeFiles/luatos.dir/src/lua.c.o] 错误 1
make[1]: *** [CMakeFiles/Makefile2:265：CMakeFiles/luatos.dir/all] 错误 2
make: *** [Makefile:130：all] 错误 2

```

**答：缺少libreadline-dev依赖包,造成找不到readline.h，执行`sudo aptitude install libreadline-dev`**

