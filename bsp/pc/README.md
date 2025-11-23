# LuatOS-PC

LuatOS-PC 是一个专为 PC 环境设计的 LuatOS 集成项目，支持 Windows、Linux 和 macOS 平台的编译和运行。该项目提供了一个完整的 Lua 开发环境，并集成了多种外设和网络功能，适用于模拟和开发嵌入式应用场景。

## 特性

- **跨平台支持**：支持 Windows、Linux 和 macOS 编译和运行。
- **交互模式 (REPL)**：支持实时交互式 Lua 编程。
- **单文件模式**：直接运行 `main.lua` 文件。
- **目录模式**：将指定目录挂载为 `/luadb`，模拟真实设备路径。
- **丰富的库支持**：包括 Lua 基础库、LuatOS 基础库、外设库、网络库、UI 库和各种工具库。
- **网络功能**：支持 TCP/IP、HTTP、MQTT、WebSocket、SNTP 等协议，并包含 TLS/SSL 支持。
- **图形界面支持**：集成 `LVGL` 和 `U8G2` 图形库，支持 GUI 开发。

## 编译说明

有关如何编译本项目，请参阅 [编译说明](doc/compile.md)。

## 使用说明

有关如何使用本项目，请参阅 [使用说明](doc/usage.md)。

## 设计文档

有关本项目的设计细节，请参阅 [设计文档](doc/design.md)。

## 已支持的库

- **Lua 基础库**：`io`, `os`, `table`, `math`, `bit` 等。
- **LuatOS 基础库**：`log`, `rtos`, `timer`。
- **外设库**：`uart`, `gpio`, `mcu`, `fskv`。
- **网络库**：`socket`, `http`, `mqtt`, `websocket`, `sntp`，含 TLS/SSL。
- **UI 库**：`lcd`, `lvgl`。
- **工具库**：`crypto`, `pack`, `json`, `gmssl`, `iotauth`, `bit64`, `zbuff`, `protobuf` 等。

## 授权协议

本项目采用 [MIT License](LICENSE)。