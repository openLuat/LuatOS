# 内存分析工具

## 作用

1. 内存概述 - 统计各种数据类型的数量,所占内存大小
2. 内存分析 - 统计内存分布规律
3. 内存导出 - 以约定的形式输出整个内存区域
4. 内存查找 - 按指定条件查找内存占用

## 分析过程

1. 从当前线程的lua_State指针入手
2. 通过l_G字段访问全局唯一的global_State结构体
3. 遍历其allgc字段,可以得到lua vm内存的全貌

## 需要输出的指标

1. 每种数据类型的总数量和总内存大小
2. 每种数据类型中,最大和最小的内存占用值
3. 每种数据类型的分布规律(初定为10个区间)
4. 输出字符串池的状态

## 实现原型(C API)

```c
luat_memp_t* luat_memp_check(lua_State *L);
int luat_memp_dump(lua_State *L);
```

## 实现原型(Lua API)

```lua
rtos.memp("check")          -- 统计全部数据类型的数据
rtos.memp("dump", "uart1")  -- 把内存数据导出,通过uart1输出
rtos.memp("check", "co")    -- 仅统计协程的内存统计数据
```