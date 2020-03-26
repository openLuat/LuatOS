# Luat 平台层

为了跨平台, 需要一个"平台层"来隔离不同底层的实现


## 为什么需要"平台层"

* Lua的C语言实现, 代码基本上跨平台,但不是全部
* Luat作为对硬件平台的封装,需要抽象为HAL
* 还有一点, 就是对任务调度的抽象,包括定时器和消息队列

----------------------------------------------------------------------------------
## Lua 的跨平台

这里讨论的是`Lua 5.3.5`.

Lua 基本上是跨平台, 可以认为是95%以上, 以下为需要抽象的平台功能

----------------------------------------------------------------------------------
### 内存分配

lua没有一个全局变量, 所有内存都是通过 `lua_newstate(l_alloc, NULL)` 的`l_alloc`参数(一个方法指针) 来分配.

原形如下

```c
void *l_alloc (void *ud, void *ptr, size_t osize, size_t nsize)
```

所以, 我们需要定义一个抽象的C API

```c
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
```

详细的API设计, 在 [内存池](/markdown/core/luat_memory) 中定义, 其中还有`malloc`的抽象形式 `luat_heap_malloc`

----------------------------------------------------------------------------------
### io 操作

lua的io操作涉及4个方面
* `loadfile` 加载lua文件, 涉及 `fopen`/`fread`/`close` 等方法
* `lua_writestring` 原始实现是把数据传给标准输出(stdout)
* io库, 涉及`fopen`/`fread`/`fseek`/`close`/`feof`/`ferror` 等POSIX常用方法
* debug库, 涉及`getc`方法, 从标准输入(stdin)读取用户输入

```c
Lua_FILE * luat_fs_fopen(char const* _FileName, char const* _Mode);
```

详细的API设计, 在 [文件系统](/markdown/core/luat_fs) 中定义

这部分的修改, 是需要改动lua源码的, 替换原有的api调用

----------------------------------------------------------------------------------
### lua里面的系统API

lua里面与系统密切相关的API, 分别是

```c
time()    // os模块,获取系统时间, 需要支持
popen()   // io/os模块,启动一个新进程, 不需要支持,相关lua API删除
pclose()  // io/os模块, 关闭进程, 不需要支持,相关lua API删除
exit()    // 关闭lua所在的进程, 不需要支持,相关lua API删除
```

可见, 只有time方法是必须实现的, 而time的实现跟具体平台强相关, 所以必须抽象

```c
uint8_t luat_os_get_time(*time_t);
```

----------------------------------------------------------------------------------
## Luat 的跨平台

对设备接口和网络通信的封装, 本质上就是对厂商私有API的封装.

----------------------------------------------------------------------------------
### 外设

外设大多是同步API, 这C API 与 Lua API会非常相像

```c
uint8_t luat_gpio_setup(LuatGpioPin pin, Lua_Value value, LuatGpioPULL pullup);
```

```lua
local LED = 33
gpio.setup(LED, gpio.LOW, gpio.PULLUP)
```

----------------------------------------------------------------------------------
### 网络通信

这部分非常依赖于厂商的SDK, 如果假设均提供lwip之类的通信封装,则这部分没有太多的内容.

如果假设不存在lwip之类的封装, 则需要非常详尽的API设计(照抄lwip也未尝不可)

TODO 待完成网络通信的API设计

----------------------------------------------------------------------------------
## 任务调度


那Luat依赖任务调度相关的API, rtos层

* 定时器 timer   --  单次/循环触发中断
* 消息队列 queue --  消息排队处理
* 信号量 sem     --  预留

从原理上说, 即使没有rtos, 只要实现上述3组API, Luat跑着裸板上也是没有问题的.

能跑Luat的硬件, 其资源肯定能跑rtos. 是否使用rtos, 由厂商SDK决定.

所以, 上面3组API, 也有对应的抽象

* [定时器](/markdown/core/luat_timer)
* [消息总线](/markdown/core/luat_msgbus)
* [信号量]() 暂无场景支撑,未设计

## 相关知识点

* [编码规范](/markdown/proj/code_style)
* [文件系统](/markdown/core/luat_fs)
* [定时器](/markdown/core/luat_timer)
* [消息总线](/markdown/core/luat_msgbus)
* [内存池](/markdown/core/luat_memory)
