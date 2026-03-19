# 如何编译本BSP(PC模拟器)

务必先把本文档完整看完, 再开始操作. 每一步都非常重要.

如果你不想手工操作, 把本文档的链接发给AI工具, 让它完成.

## 依赖说明

1. 编译系统是 xmake , 要求版本号 3.0.5 以上!!
2. 编译器要求 VisualStudio 2022 或以上, windows平台必备. linux平台要求gcc 10以上.
3. 操作系统要求 win10 以上, 不支持win7, linux 要求 ubuntu 20.04 以上
4. 

所需要的所有工具及相关压缩包, 都可以从下面的地址下载

地址: https://cdn18.air32.cn:19443/files/public/pc-xmake/

1. 先克隆LuatOS库, 并新建 bsp\pc\pkgs 目录
2. 将 上述链接 中的文件, 逐个下载到pkgs目录, 不要解压, 文件名保持与页面一致!!!

### xmake安装说明

1. 如果没有安装过xmake, 或者xmake版本低, 使用 pkgs 里面的xmake安装文件进行安装
2. 安装时必须选加入PATH中, 非常重要

### vscode 安装说明

1. vscode 如果已经安装过, 那么可以忽略安装步骤
2. 使用 pkgs 目录下的 `VSCodeUserSetup_xxx.exe` 双击按提示完成安装即可.

### windows平台VisualStudio的安装

使用 pkgs目录里面的`VisualStudioSetup`, 需要安装vs 2022版本, 必须选上安装"C++ 桌面开发"组件

## windows下的编译

1. 在 LuatOS 目录下, 右键, 选择 "使用 Code 打开"
2. 点击上方菜单 "终端", "新建终端"
3. 在终端内, 输入如下命令切换目录 `cd bsp\pc`
4. 执行编译命令 `.\build_windows_32bit_msvc_gui.bat`

若编译成功, 会生成 `build\out\luatos-lua.exe`

若编译失败, 把报错信息发给DeepSeek或者豆包解决.

### linux平台

```shell
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt-get install -y lib32z1 binutils:i386 libc6:i386 libgcc1:i386 libstdc++5:i386 libstdc++6:i386 p7zip-full
./build_linux_32bit.sh
```
