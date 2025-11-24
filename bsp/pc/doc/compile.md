# 如何编译本BSP


## 编译说明

本代码依赖xmake最新版本, 请先安装xmake 3.0.0 或以上

### 下载依赖包(非常重要!!!)

临时下载目录: https://www.air32.cn/pc-xmake/

有多个文件,逐一下载,不要解压,放入pkgs目录即可


### windows平台

需要安装vs 2022版本, 安装"C++ 桌面开发"组件

一切就绪之后, 在cmd下, 在bsp/pc目录下,执行下面的批处理文件

```shell
build_windows_32bit_msvc.bat
```

若编译成功, 会生成 `build\out\luatos-lua.exe`

### linux平台

```shell
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt-get install -y lib32z1 binutils:i386 libc6:i386 libgcc1:i386 libstdc++5:i386 libstdc++6:i386 p7zip-full
./build_linux_32bit.sh
```
