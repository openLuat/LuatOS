# 如何编译本 BSP(PC 模拟器)

务必先把本文档完整看完, 再开始操作. 每一步都非常重要.

如果你不想手工操作, 把本文档的链接发给 AI 工具, 让它完成.

## 实测结论(Windows)

已在干净目录进行过完整编译验证, 以 VS2022 + xmake 环境执行 `build_windows_32bit_msvc_gui.bat` 可以成功构建.

编译成功时会出现以下任一或全部特征:

1. 日志包含 `build ok` 或 `Build completed successfully`
2. 产物存在: `bsp\pc\build\out\luatos-lua.exe`

说明: 编译过程中出现较多 warning(如 C4100/C4244/C4819)是常见现象, 只要最终 `build ok` 且 exe 产物存在, 即可判定编译成功.

## 依赖说明

1. 编译系统是 xmake, 要求版本号 3.0.5 以上
2. 编译器要求 VisualStudio 2022 或以上, Windows 平台必备; Linux 平台要求 gcc 10 以上
3. 操作系统要求 Windows 10 以上(不支持 Windows 7); Linux 要求 Ubuntu 20.04 以上

所需工具及相关压缩包可从下面地址下载:

地址: https://cdn18.air32.cn:19443/files/public/pc-xmake/

准备步骤:

1. 先克隆 LuatOS 仓库, 并新建 `bsp\pc\pkgs` 目录
2. 将上述链接中的文件逐个下载到 `pkgs` 目录
3. 不要解压, 文件名保持与页面一致

### xmake 安装说明

1. 如果没有安装 xmake, 或版本过低, 使用 `pkgs` 里的安装包安装
2. 安装时必须勾选加入 PATH, 这一步非常重要

### VS Code 安装说明

1. 如果已安装 VS Code, 可跳过
2. 可使用 `pkgs` 目录下的 `VSCodeUserSetup_xxx.exe` 按提示安装

### Windows 平台 Visual Studio 安装说明

使用 `pkgs` 目录中的 `VisualStudioSetup`, 安装 VS 2022 或以上版本, 并确保勾选 "C++ 桌面开发" 组件.

## Windows 下编译

1. 在 LuatOS 根目录右键, 选择 "使用 Code 打开"
2. 打开菜单: "终端" -> "新建终端"
3. 在终端执行:

```powershell
cd bsp\pc
.\build_windows_32bit_msvc_gui.bat
```

### 成功判定

满足下面两项即可认为编译成功:

1. 终端日志出现 `build ok` / `Build completed successfully`
2. 文件存在: `build\out\luatos-lua.exe`

### 失败判定

出现以下任一情况可认为编译失败:

1. 命令中断并返回非 0
2. 未出现 `build ok`
3. 未生成 `build\out\luatos-lua.exe`

若编译失败, 请附上完整报错日志再排查.

## Linux 平台

```shell
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt-get install -y lib32z1 binutils:i386 libc6:i386 libgcc1:i386 libstdc++5:i386 libstdc++6:i386 p7zip-full
./build_linux_32bit.sh
```
