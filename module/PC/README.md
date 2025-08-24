# LuatOS 的PC模拟器

当前提供 windows 下的版本, 请使用LuaTools的"资源下载"功能获取最新版本

下载后, 会在 resource/LuatOS_PC 目录下

# 使用方法

## 直接当控制台形式输入指令来使用

1. 双击 luatos.bat 即可运行

## 在命令行(cmd)下指定文件路径来使用

```bash
# 蒋脚本放到user目录下, 使用以下命令, 会自动加载user目录下的所有文件到 /luadb/ 目录, 并执行其中的main.lua
luatos.bat .\user\
```

```bash
# 蒋脚本放到user目录下和LuatOS的脚本库, 支持多个路径和文件夹
luatos.bat .\user\ ..\LuatOS\script\lib\
```
