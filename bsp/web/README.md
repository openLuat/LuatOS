# LuatOS Web BSP

`bsp/web` 是一个基于 `Emscripten` 的实验性浏览器目标，当前以 `bsp/pc` 为基础复用已有的 Lua VM / VFS / 定时器 / 日志等实现。

## 当前范围

- 复用 `bsp/pc` 的基础运行时与多数平台无关代码
- 单独提供 `LUAT_BSP_WEB` 配置头
- 提供最小化的 `luat_network_init` Web stub，避免把 `bsp/pc` 的 POSIX socket 初始化直接带入浏览器目标

## 构建方式

先进入 Emscripten 环境，再执行：

```bash
cd bsp/web
xmake f --cc=emcc --cxx=em++ --ld=emcc
xmake
```

## 说明

- 当前目标主要用于补齐 `bsp/web` 目录与构建入口，便于后续继续补充浏览器专用网络、GUI 和设备模拟能力。
- 浏览器不支持的能力（如原生 socket / 外设访问）暂未在该 BSP 中默认打开。
