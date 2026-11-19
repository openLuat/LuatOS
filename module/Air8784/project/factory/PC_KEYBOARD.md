# Windows 模拟器键盘测试

需要包含 `pcconsole` 接口的新模拟器。聚焦黑色日志窗口操作；不是输入 Lua 命令。

| 状态 | Enter 回车 | Backspace 退格 |
| --- | --- | --- |
| 已注册且空闲 | 开始输入 SIP 账号 | 无操作 |
| 输入账号 | 提交非空账号并拨号 | 删除一位；空账号时取消输入 |
| 来电 | 接听 | 拒接 |
| 拨号或接听中 | 无操作 | 取消呼叫 |
| 已接通 | 无操作 | 挂断 |

账号支持字母、数字及 `+ * # _ . -`，最多 64 字符，使用项目配置的 SIP 域，不补尾号，不接受完整 URI。输入时发生来电或断网会丢弃未提交内容。手动测试前在云端关闭 `sip.auto_answer`。

PC 通话提示只打印日志，不调用 Air1103/ES8311 TTS。通话音频仍取决于模拟器固件及系统音频设备。

## 构建与更新

在 `bsp/pc` 执行 `cmd /c build_windows_32bit_msvc.bat`。只有出现 `Build completed successfully` 才算完成。程序输出位于 `bsp/pc/build/out/luatos-lua.exe`。

停止 LuaTools 启动的旧模拟器，备份实际使用的可执行文件，再用新构建替换；保留匹配的运行依赖。重新加载项目时应看到 `pc_sip_keys 键盘已启用`。提示“请更新模拟器”说明仍在运行旧程序；无交互控制台时按键不可用。

## PC Lua 接口

- `pcconsole.open()`：成功返回 true；无交互 Windows 控制台时返回 false、错误信息。
- `pcconsole.poll()`：非阻塞返回按键字符串数组；特殊键为 `enter`、`backspace`，普通键为可打印 ASCII 字符。每次最多读取 64 条系统输入记录并输出 64 个按键。
- `pcconsole.close()`：恢复原控制台模式，可重复调用。正常退出及控制台退出事件也恢复模式。未打开接口时 `poll()` 返回空表。

接口只读取当前控制台，不监听其他窗口。项目每 20ms 轮询，业务操作沿用 `SIP_APP_MAIN_ACCEPT_REQ`、`SIP_APP_MAIN_HANGUP_REQ` 和 `SIP_APP_MAIN_DIAL_REQ`。
