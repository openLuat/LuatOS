# USB HID Lua 订阅

`usb.hid_subscribe()` 提供 USB Host 键盘、鼠标等 HID 输入。AirUI/LVGL 和 Lua 是
独立消费者；实体 I²C 触摸继续走 C 层及 `tp` 回调，见 [TP 接入说明](README.tp.md)。

## USB HID 订阅

4211 默认固件从 `usb` 提供 USB Host HID 事件。它与 AirUI/触摸的 C 层输入独立：

```lua
local sub = assert(usb.hid_subscribe({types = {usb.HID_EV_KEY, usb.HID_EV_REL}},
    function(kind, id, data)
        if kind == "frame" then
            for i = 1, data.count do
                log.info("usb_hid", id, data:get(i))
            end
        end
    end))
-- 保留 sub；不再需要时调用 sub:close()。
```

`device` 是回调给出的 input 设备实例 ID。可用的类型常量包括
`usb.HID_EV_KEY`、`usb.HID_EV_REL`、`usb.HID_EV_ABS` 和 `usb.HID_EV_MSC`。
筛选在绑定设备时完成，非 USB 设备不进入该订阅的队列或恢复快照。`usb.on()`
仍用于原有 USB 事件。服务未就绪时返回 `nil, "not_ready"`。

回调在 Lua 消息线程运行，可以关闭订阅或创建新订阅，但不能 `sys.wait()` 或 yield。
回调出错会记录 `usb` 标签的错误日志并关闭该订阅，其他订阅和 LVGL 继续工作。

## 设备和状态快照

接入、重置及溢出恢复事件携带设备摘要（id、name、bus、vendor、product、version、
properties）、能力表 `caps` 和状态表 `state`。

`caps.keys/rel/msc` 是支持的事件码数组。`caps.abs[code]` 和 `caps.mt[code]`
包含 `min/max/initial`，`caps.mt_slots` 是多点触摸槽数。

状态字段：

- `id / sequence / timestamp_ms`：快照设备实例、序号和生产者单调时钟。
- `keys[code]`：当前按下的键为 true，松开的键无对应表项。
- `abs[code]`：普通绝对轴值。
- `slots[slot][code]`：每个触点槽的轴状态；槽号从 **0** 开始。
- `slot`：当前多点触摸槽；tracking ID 为 -1 表示该槽无接触。

REL 是增量，不保留累计位置。状态快照取自对应生命周期或恢复边界。
序号可能因其他消费者解绑出现间隔，
不能仅凭序号不连续判定丢帧；设备序号和时间戳均可能回绕。

## 订阅和事件

`usb.hid_subscribe(filter, callback)` 返回订阅 userdata。

| filter 字段 | 含义 |
| --- | --- |
| device | 可选，当前设备实例 ID；省略则自动匹配现在及以后接入的 USB HID 设备 |
| types | 可选，事件类型数组；默认 KEY、REL、ABS、MSC |
| queue_bytes | 每个订阅独立队列，默认 4096，范围 256..65536 |

按设备能力在订阅/接入时建立直接绑定；事件类型用数字位掩码筛选后直接入队。
每个订阅单独存整帧。键盘的 Shift、字母及鼠标按钮不会被拆成多次回调。
默认不发送 EV_SYN，帧边界已由回调表达。需要原始 SYN 时可以显式订阅。

| kind | data |
| --- | --- |
| attach | 接入/订阅时复制的设备信息和状态，见上文的设备和状态快照 |
| frame | 只读帧 userdata，有 device_id、sequence、timestamp_ms、count |
| reset | 重置后的完整设备信息和状态；取消交互，不完成点击 |
| remove | nil；设备已退出该订阅，取消其按键/拖动/触摸状态 |
| overflow | 此时 id 为 nil；data.reason 说明损失原因 |

`frame:get(i)` 返回 type、code、value，索引从 **1** 开始，`#frame` 等于 count。
帧拥有独立事件存储，允许保留引用；后续输入不会覆盖它。不要无限保存高频帧。
回调的 attach/reset 元数据随控制帧复制，所以即便设备在 Lua 处理前已经拔出，
也能读取原来的能力和状态；此时按该 ID 新建订阅会返回 not_found。

键码采用 [luat_input.h](../../luat/include/luat_input.h) 中的 input/Linux 编号。
按下、松开、重复的 value 分别为 1、0、2。字符布局、大小写转换、自动重复、光标
加速度、屏幕方向和手势由消费者处理。

`sub:close()` 幂等，立即停止后续回调并释放队列；GC 也会关闭无引用的订阅。
应用应保存订阅对象并主动 close。回调若通过闭包强引用自身订阅，需显式 close
打破 registry 回调引用所形成的环。订阅自身被 GC 不影响已保存的帧。

`sub:stats()` 返回 frames（成功入队的帧数，含生命周期帧）、overflows、
queue_bytes、queued_bytes、required_bytes、closed。
当前上限默认 16 个已公布设备、4 个同时订阅，可通过
`LUAT_INPUT_SERVICE_DEVICES/SUBSCRIPTIONS` 调整。

## 丢失与恢复

- `queue_full`：只影响该订阅。清空旧状态后，服务自动提供当前绑定设备的
  attach 快照（resync=true），之后继续普通帧。这个边界在同一个服务锁内取得，
  不会把旧帧混到快照之后。相对移动无法补回。恢复内存不足时等待后续重试。
- `frame_too_large`：单个完整帧或接入元数据超过队列容量。
  data.required_bytes 给出该帧所需容量，通知后关闭此订阅；重新订阅并增大队列。
- `resource_error`：接入/重置元数据无法分配等资源错误，通知后关闭该订阅。
- 初次订阅找不到指定设备返回 `nil, "not_found"`；达到订阅上限或初始控制帧
  放不下返回 `nil, "subscription_limit_or_queue_too_small"`。

## 实现与平台接入

`LUAT_USE_INPUT` 启用核心、队列和服务。USB HID Lua 订阅还需启用 `LUAT_USE_USB`、
`LUAT_USE_INPUT_HID` 和 `LUAT_USE_USB_HID_LUA`，并编译 `luat_lib_usb.c`。
驱动使用 `luat_input_service_core()`。平台在启动阶段初始化服务，随后所有核心
register/feed/reset/unregister、目录 attach/detach 均持有服务锁。
注册后、允许产生报告前调用 service_attach；释放设备前调用 service_detach，
再 unregister。设备 ID 在这个平台统一 core 的生命周期中不复用。

锁顺序固定为 transport lock -> input service lock，Lua 订阅只取后者。
IRQ 仍先通过驱动已有机制转任务，不在 IRQ 调用 service。普通帧不申请 C 堆；
接入、重置和溢出恢复才复制元数据。Lua 对象创建、回调、GC 都在服务锁外。

消息总线只传无对象指针的唤醒；一个待处理唤醒可以覆盖多个订阅。普通帧每次
每订阅最多处理 8 帧，有积压会继续安排下一条有界消息；只在存在订阅时开启
20ms 重试定时器，处理消息投递失败或恢复内存不足，最后一个订阅关闭后销毁。
没有 Lua 订阅时，不分配队列、不创建重试定时器，也不创建输入任务。

## 验证

- `python components/input/tests/run_tests.py`：原有核心/队列并发、HID、触摸回归。
- `python components/input/tests/run_lua_tests.py`：编译真实 input 核心、服务、Lua
  USB Lua 绑定及仓库自带 Lua VM，RTOS/文件接口使用宿主适配。覆盖来源过滤、生命周期、元数据
  保存、帧只读和持有、类型筛选、按键/多点状态、溢出恢复、恢复分配失败、
  回调内关闭、GC、回调错误隔离、消息投递失败重试、批量处理与积压继续唤醒。
  Lua 分配器额外断言服务锁未被持有，退出时检查 C 堆资源全部释放。
- 国芯 `xmake build luatos` 已通过，新增文件通过宿主 `-Wall -Wextra -Werror`。
- 板端示例为 `olddemo/demo/usb_hid/hid_events.lua`。预期日志出现
  HID_LUA_API_READY、ATTACH、HID_LUA_STABLE，拔出时出现 remove。

## 2026-09-08 历史验证

以下日志来自移除全局 `input` 前的固件和示例，保留用于对照。

当时固件编译结果 FLASH 5257800 B、RAM 56808 B、PSRAM 3997448 B。
构建日志为 SDK 的 `csdk/project/luatos/build/input-lua-api-final-build.log`。
对比主线合并后的基线，模块约增加
10 KB Flash、272 B 静态 PSRAM；不包含按需分配的订阅及队列。
固件与脚本已通过 COM89 下载，启动测试通过：INPUT_LUA_API_READY、
INPUT_LUA_STABLE、HID_LUA_LVGL_READY 均出现，无 Lua 回溯或回调错误。
启动时键盘两个 HID 接口正常接入，队列为空且无溢出。
启动日志为 SDK 的 `csdk/project/luatos/build/input-lua-api-flash-retry2.log`；
2026-09-08 板端操作验证通过，日志为 SDK 的
`csdk/project/luatos/build/input-lua-api-live.log`：

- 键盘 1c4f:0002 的字母、Shift、Backspace、Tab、Enter 均收到按下/松开事件；
  屏幕日志显示 `abc → abcA → abc`，Enter 触发当前焦点的列表项。
- 键盘两个接口拔出后出现 REMOVE/STALE_ID_OK，重新接入分配新 ID 并继续上报。
- 鼠标 046d:c542 的移动、左键及双向滚轮均收到；拔插后继续移动/点击正常。
- 所有鼠标按钮点击和列表选择日志均对应前 200ms 内的真实左键释放；
  未发现滚轮误触发点击。
- KEY_FILTER_AND_STATE_OK 通过；持有帧在后续输入及热插拔后保持不变。
- 操作后累计 653 帧、1048 个事件；按键过滤订阅 87 帧；队列 0 字节、溢出 0，
  订阅仍有效，无 Lua 回溯或回调错误。此处记录 2026-09-08 的 HID 验证；后续实体 TP 结果见 [README.tp.md](README.tp.md)。
