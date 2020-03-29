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


## Git 提交规范

1. 主分支 master
2. 开发分支, 由开发者自行开立, 命名遵循: issue_xxx, feature_xxx 前缀
3. 提交时的commit
4. 严禁使用 `git push -f` 执行 强制推送

```
add:  xxxx   添加功能,特性
update: xxx  修改功能,特性, 改变行为
remove: xxxx 删除功能,特性
fix:  xxxx   明确修复指定的issue, 贴上issue完整链接
revert: xxx  回滚某个操作
```

常用git命令

```bash
# 添加文件/文件夹
git add xxx
# 执行提交
git commit -m "fix: xxxx"
# 拉取最新代码
git pull
# 推送提交
git push
```

## Lua接口注释规范

### 在C文件内的接口

在文件的最上方，格式如下：

```c
/*
@module  模块的调用名
@summary 模块的简短描述信息
@version 版本号，可选
@data    日期，可选
*/
```

在Lua内可调用的函数，格式类似ldoc，如下：

```c
/*
@function module.function(调用时用到的完整函数名)
@string 第一个参数，@后跟参数类型，空格后跟参数解释
@number[opt=nil] 第二个参数，默认值为nil
@table[opt={}] 第三个参数，默认值为{}
...根据实际，列出所有参数
@return 类型 返回的第一个值，这里是解释
@return string 返回的第二个值，类型为string
...根据实际，列处所有返回值
@usage
--使用的例子，可多行
lcoal a,b,c = module.function("test",nil,{1,2,3})
*/
static int l_module_function(lua_State *L) {
    //一堆代码
}
```

### 在Lua文件内的接口

在文件的最上方，格式如下：

```lua
-- @module  模块的调用名
-- @summary 模块的简短描述信息
-- @version 版本号，可选
-- @data    日期，可选
```

可调用的函数，格式类似ldoc，如下：

```lua
-- @function module.function(调用时用到的完整函数名)
-- @string 第一个参数，@后跟参数类型，空格后跟参数解释
-- @number[opt=nil] 第二个参数，默认值为nil
-- @table[opt={}] 第三个参数，默认值为{}
-- ...根据实际，列出所有参数
-- @return 类型 返回的第一个值，这里是解释
-- @return string 返回的第二个值，类型为string
-- ...根据实际，列处所有返回值
-- @usage
-- --使用的例子，可多行
-- lcoal a,b,c = module.function("test",nil,{1,2,3})
```
