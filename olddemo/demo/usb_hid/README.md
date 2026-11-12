# USB HID 键鼠示例

适用于已启用 USB Host、USB HID Lua 订阅、AirUI 和 LCD 的 Air1601/Air1602 固件。
将本目录全部 Lua 脚本一起下载到设备，入口为 `main.lua`。

## 硬件

- 当前屏幕配置为 AirCAMERA_1032 的 RGB 1024×600，LCD 复位 GPIO15、背光 GPIO2。
- 开发板 USB 供电控制 GPIO12，USB Host 使用总线 0。
- 接入 USB 键盘、鼠标或无线键鼠共用接收器。不同板卡请调整驱动脚本中的接线配置。

## 文件

- `main.lua`：初始化屏幕、界面和 USB HID 订阅，再启动 USB Host。
- `lcd_drv.lua`：LCD 与 AirUI 初始化。
- `hid_lvgl.lua`：文本框、点击计数按钮和滚动列表。
- `hid_events.lua`：通过 `usb.hid_subscribe()` 记录 USB HID 接入、移除与队列统计。

## Lua 订阅

```lua
local sub = assert(usb.hid_subscribe({types = {usb.HID_EV_KEY, usb.HID_EV_REL}},
    function(kind, id, data)
        if kind == "frame" then
            for i = 1, data.count do
                log.info("usb_hid", id, data:get(i))
            end
        end
    end))
-- 保留 sub；停止接收时调用 sub:close()。
```

省略 `types` 接收所有默认类型；`device` 可选，按回调给出的设备 ID 筛选。
`data:get(i)` 返回事件类型、码值和值。回调也会收到 `attach`、`remove`、
`reset` 和 `overflow`，回调内不可等待。使用示例见 `hid_events.lua`。

## 验证

1. 启动后确认界面显示正常，日志出现 `HID_LUA_LVGL_READY`、`HID_LUA_API_READY` 和 `HID_C_HOST_READY`。
2. 移动鼠标并点击按钮；在右侧列表滚动，按钮点击次数不应增加。
3. 文本框中输入 abc、Shift+A、Backspace，最后应为 abc；Tab 切换焦点，Enter 点击按钮。
4. 拔插键鼠或共用接收器，确认重新接入后继续正常输入。
5. 观察 `HID_LUA_STABLE` 中的 overflow 为 0。

原 USB U 盘读写示例保留在相邻的 `../usb/` 目录。
