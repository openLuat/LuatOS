
# 适配LuatOS的步骤和方法

## 基本步骤

1. 编译环境的集成
2. 核心功能的适配
3. 外设的适配
4. 网络接口的适配

## 编译环境的集成

在这一步里, 需要将LuatOS指定目录下的文件, 一起加入厂商SDK的编译环境中

目录有:

```
$LUATOS
    - lua                       # Lua虚拟机
    - luat/module               # lua库实现
    - luat/packages/vsprintf    # 平台无关的printf实现
    - luat/packages/lua-cjson   # 平台无关的json库
    - luat/packages/heap        # 平台无关的lua heap实现
```

以上目录内的.h文件需要加入include配置, .c文件加入到编译路径.

请务必确保编译能通过,然后再做下一步

## 核心功能的适配

核心功能是  msgbus, timer, uart, fs,及几个基础方法.

* `msgbus`和`timer`, 如果是`freertos`, 使用现成的 luat/freertos 目录下的代码, 否则需要实现 `luat_msgbus.h` 和 `luat_timer.h`
* `uart` , 对应 `luat_uart.h` 需要逐一实现
* `fs`, 文件系统, 如果支持posix风格的,则自带实现,否则需要实现 `luat_fs.h`
* 几个基础方法, 可以根据编译时根据link的报错逐个实现, 主要在 `luat_base.h`

完成编译环境的集成后, 在用户程序的入口处, 添加如下代码

```c
#include "bget.h"

bpool(ptr, size); // lua vm需要一块内存用于内部分配, 给出首地址及大小.
luat_main();      // luat_main是LuatOS的主入口, 该方法通常不会返回.
```

即可验证LuatOS的启动过程.

建议的实现步骤
1. 先把uart功能实现完成, 这是必不可少的
2. 仿造rtt版的`luat_openlibs`, 实现lua库的加载. 初始阶段可以只加载lua本身自带的库.
3. 然后把文件系统的实现处理好, 即使只做空实现, 也要保证编译通过
4. 加入luat_main, 开始查漏补缺, 补充完整后, 启动会提示找不到`main.luac`, 这时候又下一城了.

## 外设的适配

外设通常指 `gpio`/`i2c`/`spi`, 实现对应的.h文件就可以了, 然后在`luat_openlibs`加载

## 网络接口的适配

这个需要实现`netclient.h`, 会比较复杂, 请参考rtt的实现, 如有疑问请报issue或加QQ群沟通.
