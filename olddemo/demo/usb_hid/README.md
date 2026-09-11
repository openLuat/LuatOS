# USB HID 键鼠与 input 示例

适用于已启用 USB Host、input、AirUI、LCD 和 TP 的 Air1601/Air1602 固件。
将本目录全部 Lua 脚本一起下载到设备，入口为 `main.lua`。

## 硬件

- 当前屏幕配置为 AirCAMERA_1032 的 RGB 1024×600，LCD 复位 GPIO15、背光 GPIO2。
- GT911 使用 I²C1、INT GPIO51、RST GPIO2；复位后恢复 GPIO2 背光输出。
- 开发板 USB 供电控制 GPIO12，USB Host 使用总线 0。
- 接入 USB 键盘、鼠标或无线键鼠共用接收器。不同板卡请调整驱动脚本中的接线配置。

## 文件

- `main.lua`：初始化屏幕、界面、input 订阅和触摸，再启动 USB Host。
- `lcd_drv.lua`：LCD 与 AirUI 初始化。
- `hid_lvgl.lua`：文本框、点击计数按钮和滚动列表。
- `input_demo.lua`：设备接入/移除、事件订阅、状态查询与队列统计。
- `tp_drv.lua`：GT911 初始化和触摸绑定。

## 验证

1. 启动后确认界面显示正常，日志出现 `HID_LUA_LVGL_READY`、`INPUT_LUA_API_READY` 和 `HID_C_HOST_READY`。
2. 移动鼠标并点击按钮；在右侧列表滚动，按钮点击次数不应增加。
3. 文本框中输入 abc、Shift+A、Backspace，最后应为 abc；Tab 切换焦点，Enter 点击按钮。
4. 拔插键鼠或共用接收器，确认重新接入后继续正常输入。
5. 用手指点击、拖动，确认与鼠标操作互不干扰；观察 `INPUT_LUA_STABLE` 中的 overflow 为 0。

原 USB U 盘读写示例保留在相邻的 `../usb/` 目录。
