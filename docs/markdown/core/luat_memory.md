# 内存池

## 基本信息

* 起草日期: 2019-11-25
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要内存池

* 一段连续的区域分配给用户使用, 独立于系统的heap
* 这个内存区间的大小介于 64k ~ 100k
* Lua虚拟机及相关全局变量应该使用该区域

## 设计思路和边界

* 使用freertos的heap_4作为原型
* 额外提供一个用Lua虚拟机的alloc方法
* 提供API查询剩余内存
* API应该只涉及内存申请与释放,不做其他事情.

## C API

### 定义内存池总大小

```c
#define LUAT_MALLOC_HEAP_SIZE ((size_t) 85 * 1024)
```

###

```c
// 初始化内存
void  luat_heap_init(void);
// 申请内存
void* luat_heap_malloc(size_t len); // 如果失败,返回NULL
// 释放内存
void  luat_heap_free(void* ptr);
// 缩放内存块
void* luat_heap_realloc(void* ptr, size_t len);
// 申请内存并填充0
void* luat_heap_calloc(size_t len);
// 获取剩余内存
size_t luat_heap_getfree(void);
// Lua所需要的alloc方法
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
```

## Lua API

```lua
-- 获取总内存数量
mem.total_count()
-- 获取剩余内存数量
mem.free_count()
```

## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)

