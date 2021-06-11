编译方式见官方sdk手册，这里只举例vscode

Windows下：

安装：

[ARM GCC compiler](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads)

[CMake](https://cmake.org/download/)

[Build Tools for Visual Studio 2019](https://visualstudio.microsoft.com/zh-hans/downloads/)

[Python 3.9](https://www.python.org/downloads/windows/)

[Visual Studio Code](https://code.visualstudio.com/)

vscode插件安装cmake，配置cmake扩展中cmake tools configuration，其中Cmake: Generator（要是用的cmake生成器）配置为NMake Makefiles

打开Visual Studio 2019在终端输入code打开vscode（这样cmake可以自动正确配置），打开文件夹选择我们的工程目录，选择gcc 10.21.1 arm-none-eabi工具链，点击build编译

