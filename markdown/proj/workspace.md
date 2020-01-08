# 搭建开发环境

本文以搭建rt-thread平台的LuatOS环境为主
分两种形式:
1. 子模块形式, bsp源码放着LuatOS源码目录下
2. package形式, rt-thread源码与LuatOS源码同级

无论哪种, 均使用SConscript关联起来.

## 安装必要的软件

* git 从git-scm官方下载
* rt-thread的env工具, 从rt-thread官方下载

## 下载源码(子模块形式)

请在D盘新建一个github目录, 在该目录下进行操作

### LuatOS源码

```bash
cd github
// 国内外地址选一个就行
// github地址
git clone git@github.com:openLuat/LuatOS.git
// 国内镜像地址
git clone git@gitee.com:wendal/LuatOS.git
```

### W60x源码

当前的bsp源码以git submodule的形式存在

```bash
cd LuatOS
git submodule init
git submodule update
```

## 编译

在`D:\github\LuatOS\bsp\w60x`目录下, 启动env工具

```
# 更新pkgs
pkgs --update
# 执行编译
scons
# 等待编译完成后, 可以在D:\github\LuatOS\bsp\w60x\Bin目录找到刷机文件, 刷机即可
```

## 下载源码(package形式)

本质上说, LuatOS可以作为rt-thread的一个package存在, 所以可以换一种方式编译

### LuatOS源码

与上一个方式一样,不再重复

### rt-thread源码

```bash
// github地址
git clone https://github.com/RT-Thread/rt-thread.git
```

### 配置w60x(其他mcu一样的操作)

进入 `rt-thread\bsp\w60x` 目录, 启动env工具, 并执行

```
pkgs --update
```

然后新建一个目录 `rt-thread\bsp\w60x\packages\luat`, 新建文件填入以下内容

```python
# for module compiling
import os
Import('RTT_ROOT')

cwd = "D:/github/LuatOS"
objs = SConscript(os.path.join(cwd, '/lua/SConscript'))
objs = objs + SConscript(os.path.join(cwd, '/luat/SConscript'))

Return('objs')
```

然后, 修改rtconfig.h, 增到main thread的堆栈大小到8192.

使用scons命令执行编译, 就可得到刷机文件
