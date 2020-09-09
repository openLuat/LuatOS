# 使用Air302 SDK编译固件

通常你不需要这份文档, 这是用于自行扩展固件的高级文档. 

我们提供的固件包就包含编译好的固件(ec后缀)

如果你是在找刷机/编译lua脚本之类的应用型文档, 这个文档不是你需要查看的内容.

## 提前告知

1. 该SDK不是C-SDK, 编译出的固件依然是LuatOS固件, 跑Lua脚本!!
2. SDK本身不开源(厂商要求),但欢迎报issue
3. 当前版本仅支持Keil编译,请确保有正版Keil

## 编译环境

1. Keil 5.0.5
2. windows 7 x64及以上
3. 起码预留2GB的磁盘空间
4. 安装能解压7zip格式的解压缩软件

## 编译说明

1. 请使用`git clone`下载LuatOS的源码, 不需要同步子模块`submodule`, 推荐目录为 `D:\github\LuatOS` . 不建议直接下载zip/tgz.
2. 下载air302_sdk的压缩包, 通常为7zip格式
3. 解压到 air302_sdk到 LuatOS源码目录下的 bsp/air302 , 得到的目录结构是这样的
```
LuatOS 
    - bsp
        - air302
            - air302_sdk
                - luat
                - PLAT
                    - build.bat
                    - KeilBuild.bat
                    - project
                        - ec616_0h00
                            - apps
                                - air302
                                    - ARMCC
                                        - Makefile
```
4. 如果Keil安装目录不是`D:\keil_v5`, 修改 `KeilBuild.bat` 中Keil的路径
5. 如果LuatOS不在`D:\github\LuatOS`, 修改 上述目录结构中的Makefile文件
6. 修改或创建local.ini中的PLAT_ROOT路径, 指向 `PLAT` 目录
7. 在`bsp\air302`目录执行 `python air302.py build pkg` 
8. 编译成功会显示 大大的 `PASS`, 并自动打包生成固件压缩包.
9. 如果编译失败, 可单独执行`build.bat`,看看具体的报错原因.

