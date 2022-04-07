# LuatOS@sysp

## 何为 sysp

sysp对sys.run的一种改造实现,以适应在非rtos环境下的LuatOS实现

当前, 本实现是为在浏览器上运行LuatOS而服务的

## 在浏览器上运行 LuatOS

可选的方案并不多, 而生产可用的, 只有 https://emscripten.org/

emscripten 的基本思路是 `C/C++` 转 `wasm` , 并配套相关加载器和函数构造

## 编译过程

整个过程可以在wsl2 或者 ubuntu 下执行, 不推荐windows下直接安装(反正我没成功)

### 安装emscripten

如果使用wsl2安装, 把目录放在D盘会比较方便, 如果放在wsl内部操作起来麻烦. 例如我的安装目录是 `D:\wsl\emsdk`

按链接里的教程来 https://emscripten.org/docs/getting_started/downloads.html

### 安装 emcc-port for SDL2

默认情况下, emcc会从github下载SDL2, 然后就是超级慢.

1. 修改 emsdk 目录下的 upstream/emscripten/tools/ports/sdl2.py
把 `ports.fetch_project`一行, 改成

```python
ports.fetch_project('sdl2', 'http://nutzam.com/wasm/SDL-' + TAG + '.zip', SUBDIR, sha512hash=HASH)
```

2. 然后触发安装

```bash
touch abc.c
emcc abc.c -sUSE_SDL=2 -sLEGACY_GL_EMULATION -o sdl2.html
```

### 开始编译sysp

1. 首先, cd到LuatOS主库的 `bsp/sysp` 目录, 也就是本README.md所在的目录
2. 按以下命令执行, 需要的时间较长,可能长达几分钟, 请耐心等待

```
mkdir build
cd build
emcmake cmake ..
emmake make -j16
```

说明:
* 建立build目录并进入其中进行编译, 避免编译对源码的干扰
* 基于`cmake`编译,但需要用`emcmake`包装一下, 同理 make 也需要用 `emmake` 进行包装

### 编译完成后的运行

若没有编译错误, 会生成3个主要文件

* luatos.html 演示用的页面
* luatos.js   加载wasm的js脚本
* luatos.wasm LuatOS的wasm表达文件,二进制文件

使用方法
* 启动一个http服务, 例如nginx/python的http.server, 能访问的页面的就行
* 使用Chrome访问该http服务, 例如 `http://127.0.0.1:8000/luatos.html`
* 按F12进入调试控制台, 输入一下命令

```js
// 第一步, 注入main.lua文件
Module.ccall("luat_fs_append_onefile", "int",["string","string","number"],["/main.lua", "_G.sys = require( \"sys\") sys.timerStart(function() lvgl.init() print(123) end, 2000)", 0])
// 第二步, 启动虚拟机
Module.ccall("luat_sysp_start", "int",[],[])
```

预期效果就是打印日志和显示一个绿色的图像区域

```log
I/sysp LuatOS@sysp V0007, Build: Apr  7 2022 12:00:11
D/main loadlibs luavm 1048568 8896 8896
D/main loadlibs sys   0 0 0
SDL_PIXELFORMAT_BGR565
123
```

## 关于执行脚本的一些限制

### 必须加载sys.lua, 且注册为全局变量

```lua
_G.sys = require("sys")
```

### 不可以执行sys.run

因为机制问题, 不能直接调用sys.run方法, 执行和测试时要在js脚本中对用户脚本进行一定的过滤和替换
