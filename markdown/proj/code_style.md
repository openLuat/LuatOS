# 编码规范


## C API规范

* C API均以 `luat_` 开头, 后接模块名, 然后是方法名
* 使用抽象的类型定义, 例如不使用`int`, 使用`uint32_t`
* 使用下划线命名方式

举例

```c
LUA_API void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
```

## Lua API 规范

* 使用驼峰命名

TODO lua api规范

