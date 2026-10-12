# TP 接入 input

现有 `tp.init()` 配置硬件，并在启用 `LUAT_USE_INPUT_TOUCH` 时安装 TP→input 适配器。TP 公共驱动通过可选 sink 处理触点批次，不依赖 input 或 AirUI。
Lua 继续使用现有 `input.subscribe()`；`airui.device_bind_touch(tp_device)`
继续选择用于显示交互的 TP。无需 Lua 转发触摸数据，也没有新增采样任务。

## 编译与数据路径

启用 `LUAT_USE_INPUT`、`LUAT_USE_INPUT_TOUCH`，核心、队列和服务由总开关统一启用；
Lua API 额外启用 `LUAT_USE_INPUT_LUA`。
service 目录及 C 消费者不依赖 Lua，Lua 重试定时器仍只在存在 Lua 订阅时运行。
编译 input 核心/service/queue/touch，TP 公共层及 `luat_tp_input.c`；
AirUI 平台再编译 `luat_airui_input_touch_luatos.c`。

```
TP IRQ → 原有 TP 任务 → 芯片 read → luat_tp_input_feed → input_touch → input 核心
                                                                    ├─ Lua 队列
                                                                    └─ AirUI 采样环
```

每次读取只提交一个完整 input 帧。普通帧不申请 C 堆；TP 适配存储在初始化时
分配并在 C deinit 时释放。没有旧 TP Lua 回调时，跳过旧通道的复制和 msgbus
投递；注册了旧回调时仍提供转换后的触点数据，并处理投递失败的资源释放。

## C 应用装配

独立 C 应用先在公共启动阶段调用 `luat_input_service_init()` 并检查返回值，
再启动 TP；适配器不再隐式初始化 service。配置对象首次使用前清零。
需要 input 的 C 应用在 `luat_tp_init(cfg)` 前调用
`luat_tp_input_setup(cfg)` 并检查返回值；Lua `tp.init()` 已自动完成这一步。
不安装 sink 时，TP 保留原有坐标转换和 callback 路径，可独立编译、链接和运行。

也可设置自有 `luat_tp_sink_ops_t`，处理 open/process/reset/suspend/close。
sink 在 TP 互斥锁内执行，不得重入 TP 生命周期接口；process 输出完整的归一化
触点数组，正值表示交给旧 callback，零表示无变化，负值触发 reset。
open 失败时由 sink 清理自身的部分资源。context/id 由适配器持有，TP 不解释。
配置和 sink 对象须保持到停用及在途通知处理结束。

AirUI 的 `device_bind_touch`、原有触摸读取路径和 Lua API 均未调整。

## 坐标、触点与生命周期

- `w/h` 表示原始坐标范围，坐标必须满足 `0 <= x < w`、`0 <= y < h`。
- `direction` 的 90/270 度会交换输出宽高；镜像使用旋转后的宽高。
  边界使用 `w-1/h-1`，所有触点都转换。input 与旧 TP 回调使用同一变换。
- AirUI 从 input 读取时不再次应用 TP 方向；LVGL 显示旋转仍由显示层处理。
- 硬件 track_id 对应固定 slot，范围必须小于配置的 `tp_num`。
  `tp_num=0` 时公共适配器预留 `LUAT_TP_TOUCH_MAX` 个槽；板端 GT911 示例显式为 5。
- 每次新的接触分配新的正 tracking ID；抬起输出 tracking ID=-1。
  重复快照与坐标/宽度均未变化的持续触点不重复提交。
- TP 的 DOWN/UP/MOVE 显式转换为 input_touch 枚举，不能直接转换枚举数值。
- 按芯片驱动提供的触点增量处理；NONE 不代表抬起，不猜测缺失触点的状态。
- 输入批次越界/重复槽位或驱动返回负值时，取消整批并 reset input 状态。
  驱动隐藏的读数错误仍无法由公共层识别。
- 初始化、任务读数、休眠、唤醒、停用使用 TP 互斥锁；锁顺序为 TP → input service。
  服务锁只保护 input 数据，I²C 读取在服务锁之外；Lua/LVGL 回调不在服务锁内执行。
- `luat_tp_deinit()` 注销设备并释放 input 适配存储；配置对象必须继续存活到已排队
  的 IRQ 通知处理完毕，不能立即释放配置。没有新增 Lua close API。
- 休眠及唤醒重置接触状态，休眠期间丢弃已排队的读数通知；停用后设备 ID 失效。

## AirUI

使用一个 16 帧采样环，两个触摸指针使用独立读游标；鼠标继续使用第 3 个指针。
这样快速 DOWN/UP 不会因为 GUI 只读取最新状态而丢失。所有触点仍可经原有
AirUI 触摸订阅通知，原有通知的 track_id 继续表示槽位；完整 tracking ID 通过
input API 获取。

采样环溢出时取消当前交互，并丢弃该触点到抬起为止的数据；不补出点击。
reset/remove 取消 LVGL 当前交互并清理缓存。启用 input touch 后该设备不会再
被旧的 `tp_config->tp_data` 读取路径重复消费。

## 板端示例

`olddemo/demo/usb_hid/tp_drv.lua` 使用 AirCAMERA_1032 参考接线：GT911、I²C1、
INT51、RST2、1024×600、5 点。GPIO2 同时被当前 LCD 示例作为背光控制，
TP 初始化后恢复高电平。脚本不注册旧 TP 回调。

`input_demo.lua` 记录 TP_TRACKING、BTN_TOUCH 及每两秒的 TP_STATE，
INPUT_LUA_STABLE 同时报告队列长度和溢出数。
当前示例不触发 TP 休眠或唤醒，Esc 仅作为普通键盘输入处理。

## 验证

- `python components/input/tests/run_tp_tests.py`：真实 TP 公共层、input 服务、
  多点适配器、真实 LVGL 9，关闭 input Lua 模块；RTOS/I²C 使用宿主适配。
  覆盖初始化失败/停用、旧 ID、批次原子性、触点复用、16 种方向镜像、
  旧回调坐标、双指针、快速点按、休眠取消、读数错误和队列溢出。
  另有完全不链接 input/AirUI 的 TP 独立模式及自定义 sink 回归。
  新增生产代码按 `-Wall -Wextra -Werror` 编译。
- 2026-09-09 提交前重跑 input 核心/队列、HID/touch、Lua 接口、TP 和真实
  LVGL HID 回归，全部通过；包括 20000 帧并发和 10000 次 HID 报告变异。
- 唤醒修改回退、清理 GUI 重复日志后的国芯固件编译通过：FLASH 5261088 B、
  RAM 56808 B、PSRAM 3999448 B。日志为 SDK 的
  `csdk/project/luatos/build/input-hid-precommit-build.log`。
  相比 TP 接入前，Flash 增加 3288 B，静态 PSRAM 增加 2000 B；另有按需分配的
  TP 适配存储及 RTOS 互斥锁。
- PC GUI 编译已执行，仍在已有 GmSSL 符号链接错误处失败。
- 板端启动通过，GT911 注册为 input 设备；单指点击、快速点按、拖动及四角
  操作已通过。双指交替抬起记录了两组 `2→1→0` 触点，剩余手指 tracking ID
  保持不变。鼠标接入及操作、触摸选框后的键盘输入也已记录；1303 帧、4967
  个事件时队列溢出为 0。
- 实机发现测试脚本不能使用 `package.loaded`，Esc 导致回调异常并关闭订阅；
  1.3.1 改为由主脚本保存 TP 模块引用，同时将能力表的稀疏轴编号转换为 JSON
  字符串键。
- 历史唤醒时序修正版实机多次 Esc 休眠/唤醒及触摸恢复通过。日志记录
  103.080 s、112.920 s 唤醒，随后均有新的 tracking ID 和按钮点击；
  215 帧、986 个事件时队列无溢出，订阅保持开启。证据见 SDK 的
  `csdk/project/luatos/build/input-tp-wake-sync-live.log`。
  1.3.2 清除临时寄存器诊断和开机自动休眠，保留 Esc 手动测试。

当前示例版本为 1.3.3，已回退 GT9xx 唤醒时序修改，移除 Esc 休眠测试和
相关脚本引用，并关闭 USB 底层调试输出。提交前完成编译，未重新下载实机。
以上唤醒验证仅记录历史修正版结果，不代表当前驱动支持可靠的硬件唤醒。
TP 接入 input、LVGL 以及公共层的状态 reset/取消机制继续保留。

此前暂缓的芯片驱动边界检查和读数语义修改仍未纳入；公共适配器的校验
发生在驱动返回之后。
