# 用法指南

## 交互模式

windows

```bash
luatos-pc.exe
```

linux

```bash
./luatos-pc
```

若需退出交互模式
```lua
os.exit()
```

## 指定文件或文件夹加载并启动

支持指定多个文件或文件夹,一起加载并启动

```
切换中文
chcp 65001
```

单文件启动
```bash
luatos-pc.exe  test/001.helloworld/main.lua
```

多文件启动,按第一个`main.lua`作为主文件
```bash
luatos-pc.exe  test/001.helloworld/main.lua test/abc.lua test/logo.jpg
```

按文件夹启动, 路径需要以`/`或者`\` 结尾
```bash
luatos-pc.exe ../LuatOS/demo/gmssl/
```

文件和文件夹混合启动
```bash
luatos-pc.exe test/001.helloworld/main.lua ../LuatOS/demo/gmssl/
```

## 加载luatools项目文件直接启动

```bash
luatos-pc.exe --llt=D:/luatools/project/air101_gpio.ini
```

## 加载luadb镜像文件启动

```bash
luatos-pc.exe --ldb=D:/luatools/SoC量产文件/script.bin
```
