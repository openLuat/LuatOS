# 文件系统

## 基本信息

* 起草日期: 2019-11-28
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要文件系统

* mcu内置一片flash区域或外部flash
* 使用该区域存放lua脚本及其他文件
* 将来可能还需要使用fatfs挂载sd卡

## 设计思路和边界

* 提供文件操作的lua api(增删改查), 用法与lua原生的io模块相同
* 提供lua虚拟机读取lua脚本的C API
* 额外提供获取文件系统信息的api, 包括C和lua

## C API

```c
Luat_FILE luat_fs_fopen(char const* _FileName, char const* _Mode);
uint8_t luat_fs_getc(Luat_FILE stream);
uint8_t luat_fs_fseek(Luat_FILE stream, long offset, int origin);
uint32_t luat_fs_ftell(Luat_FILE stream);
uint8_t luat_fs_fclose(Luat_FILE stream);
```

## Lua API

基础API, 与原生io模块相同

### 遍历文件夹

```lua
local names = io.lsdir("/ldata/")
```


## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)

