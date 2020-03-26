# 如何开发

总的开发分成若干部分:

1. lua虚拟机的开发/优化
2. lua模块的开发
3. 配套工具/功能的开发

本章主要描述如何开发一个lua模块

## Lua 模块开发的组成部分

分成几个必要的部分

1. 模块的设计文档
2. 模块的Lua API实现
3. 模块的C API实现(平台抽象层)

产出物

1. 文档若干
2. luat_lib_xxx.c 一份/多份
3. luat_xxx.h 一份/多份
4. luat_xxx_rtt.c/luat_xxx_freertos.c 一份
5. luat_demo_xxx.lua 可选

### 模块的设计文档

文档的基本模板

```markdown
# 标题

## 基本信息

## 为什么写这个功能 -- 实现什么功能

## 设计边界有哪些 -- 做什么, 不做什么

## Lua API -- 暴露给lua代码的api设计成怎样, 最好提供设想的代码

## C API -- 抽象平台层, 封装一下
```

### Lua API 设计与实现

Lua API, 是暴露给用户lua代码调用的API, 负责读取用户参数, 校验参数, 整理返回值.

通常分3种: 纯lua, 部分lua部分c, 纯c

当前我们设计和实现, 一般是纯C的实现, 它类似这样

```c
int luat_lib_sys_run(Lua_State *L) {
    luaL_checkXXX ; // 取参数

    lua_sys_xxx   ; // 调用C API

    luaL_pushXXXX ; // 把返回值压入堆栈

    return 2; // 返回值的个数
}
```

然后配套一个注册函数, 这个可以参考lua内置库, 例如 `lmathlib.c`

要求:
1. 一般情况下只能调用luat_xxx 开头及系统函数
2. 不要直接调用freertos/rt-thread/私有库的函数, 特殊情况特殊分析.
3. 使用luat_heap_mallac分配内存为主,注意防范内存泄漏
4. 可以不提供头文件

### C API 设计与实现

要求:
1. 必须提供头文件,供Lua API/其他C API调用.
2. 使用luat_heap_mallac分配内存为主,注意防范内存泄漏
3. 设计的API应尽量屏蔽平台差异, 提供对外一致的观感
4. 通过不需要传递`Lua_State *L`, 而是传递一个参数列表或数据结构

```c
int luat_gpio_setup(luat_gpio_t conf) {
    //平台相关的实现...

    return 0; // ok or not
}
```
