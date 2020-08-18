---
module: luat_lib_fs
---

--------------------------------------------------
# fs.fsstat

```lua
fs.fsstat(path)
```

获取文件系统信息

## 参数表

Name | Type | Description
-----|------|--------------
`path`|`string`| 路径,默认"/",可选

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 获取成功返回true,否则返回false
2 |`int`| 总的block数量
3 |`int`| 已使用的block数量
4 |`int`| block的大小,单位字节
5 |`string`| 文件系统类型,例如lfs代表littlefs

## 调用示例

```lua
-- 打印根分区的信息
log.info("fsstat", fs.fsstat("/"))
```


--------------------------------------------------
# fs.fsize

```lua
fs.fsize(path)
```

获取文件大小

## 参数表

Name | Type | Description
-----|------|--------------
`path`|`string`| 文件路径

## 返回值

> `int`: 文件大小,若获取失败会返回0

## 调用示例

```lua
-- 打印main.luac的大小
log.info("fsize", fs.fsize("/main.luac"))
```


