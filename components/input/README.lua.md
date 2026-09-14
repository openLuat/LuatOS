# input Lua 接口

用于键盘、鼠标、触摸等统一输入。首个平台为国芯 Air1601/1602，USB HID
已接入。现有 AirUI/LVGL 与 Lua 是独立消费者；Lua 订阅不接管显示输入。
GT911 已通过 TP 公共层接入；见 [TP 接入说明](README.tp.md)。

## 使用示例

```lua
local sub = assert(input.subscribe({
    types = {input.EV_KEY, input.EV_REL},
    queue_bytes = 4096,
}, function(kind, id, data)
    if kind == "frame" then
        for i = 1, data.count do
            local event_type, code, value = data:get(i)
            log.info("input", id, event_type, code, value)
        end
    elseif kind == "attach" then
        log.info("input", "接入", id, data.name)
    elseif kind == "remove" then
        log.info("input", "拔出", id)
    elseif kind == "overflow" then
        -- 清除本订阅维护的全部按键、拖动和触点状态。
        -- queue_full 后会收到带 resync=true 的 attach 状态快照。
        log.warn("input", data.reason)
    end
end))
-- 保存 sub；不再需要时调用 sub:close()。
```

回调在 Lua 消息线程运行，可以查询 input、关闭订阅、创建新订阅，但不能
`sys.wait()` 或 yield。回调出错会记录 `input.lua callback error` 并关闭该订阅，
其他订阅与 LVGL 继续工作。

## 查询

- `input.list()`：返回当前设备摘要数组，每项有 id、name、bus、vendor、product、
  version、properties。无设备时为空数组。
- `input.info(id)`：返回摘要加 `caps` 和 `state`。
- `input.state(id)`：只返回当前状态快照。
- 不存在的 ID 返回 `nil, "not_found"`；分配失败返回 `nil, "no_memory"`。
  无效参数抛出参数错误。

`caps.keys/rel/msc` 是支持的事件码数组。`caps.abs[code]` 和 `caps.mt[code]`
包含 `min/max/initial`，`caps.mt_slots` 是多点触摸槽数。

状态字段：

- `id / sequence / timestamp_ms`：快照设备实例、序号和生产者单调时钟。
- `keys[code]`：当前按下的键为 true，松开的键无对应表项。
- `abs[code]`：普通绝对轴值。
- `slots[slot][code]`：每个触点槽的轴状态；槽号从 **0** 开始。
- `slot`：当前多点触摸槽；tracking ID 为 -1 表示该槽无接触。

REL 是增量，不保留累计位置。查询得到的是调用时的状态，可以新于正在处理
的事件帧。不要把它当作该帧发生时的状态。序号可能因其他消费者解绑出现间隔，
不能仅凭序号不连续判定丢帧；设备序号和时间戳均可能回绕。

## 订阅和事件

`input.subscribe(filter, callback)` 返回订阅 userdata。

| filter 字段 | 含义 |
| --- | --- |
| device | 可选，当前设备实例 ID；省略则自动匹配现在及以后接入的设备 |
| types | 可选，事件类型数组；默认 KEY、REL、ABS、MSC |
| queue_bytes | 每个订阅独立队列，默认 4096，范围 256..65536 |

按设备能力在订阅/接入时建立直接绑定；事件类型用数字位掩码筛选后直接入队。
每个订阅单独存整帧。键盘的 Shift、字母及鼠标按钮不会被拆成多次回调。
默认不发送 EV_SYN，帧边界已由回调表达。需要原始 SYN 时可以显式订阅。

| kind | data |
| --- | --- |
| attach | 接入/订阅时复制的设备信息和状态，结构与 info 一致 |
| frame | 只读帧 userdata，有 device_id、sequence、timestamp_ms、count |
| reset | 重置后的完整设备信息和状态；取消交互，不完成点击 |
| remove | nil；设备已退出该订阅，取消其按键/拖动/触摸状态 |
| overflow | 此时 id 为 nil；data.reason 说明损失原因 |

`frame:get(i)` 返回 type、code、value，索引从 **1** 开始，`#frame` 等于 count。
帧拥有独立事件存储，允许保留引用；后续输入不会覆盖它。不要无限保存高频帧。
回调的 attach/reset 元数据随控制帧复制，所以即便设备在 Lua 处理前已经拔出，
也能读取原来的能力和状态；此时主动调用 info(id) 会返回 not_found。

键码是 input/Linux 编号，不是 USB HID Usage 或 ASCII。按下/松开/重复分别为
`input.PRESS/RELEASE/REPEAT`（1/0/2）。模块导出常用 A-Z、导航键、修饰键、
鼠标按钮和轴常量，其他支持的事件码仍可使用数字。字符布局、大小写转换、
自动重复、光标加速度、屏幕方向和手势由消费者处理。

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

编译开关：`LUAT_USE_INPUT`、`LUAT_USE_INPUT_QUEUE`、`LUAT_USE_INPUT_LUA`。
其他平台需编译 service/queue/Lua 绑定、声明并注册 luaopen_input，再让驱动
使用 `luat_input_service_core()`。平台在启动阶段初始化服务，随后所有核心
register/feed/reset/unregister、目录 attach/detach 均持有服务锁。
注册后、允许产生报告前调用 service_attach；释放设备前调用 service_detach，
再 unregister。设备 ID 在这个平台统一 core 的生命周期中不复用。

锁顺序固定为 transport lock -> input service lock，Lua 查询/订阅只取后者。
IRQ 仍先通过驱动已有机制转任务，不在 IRQ 调用 service。普通帧不申请 C 堆；
接入/重置与状态查询才复制元数据。Lua 对象创建、回调、GC 都在服务锁外。

消息总线只传无对象指针的唤醒；一个待处理唤醒可以覆盖多个订阅。普通帧每次
每订阅最多处理 8 帧，有积压会继续安排下一条有界消息；只在存在订阅时开启
20ms 重试定时器，处理消息投递失败或恢复内存不足，最后一个订阅关闭后销毁。
没有 Lua 订阅时，不分配队列、不创建重试定时器，也不创建输入任务。

## 验证

- `python components/input/tests/run_tests.py`：原有核心/队列并发、HID、触摸回归。
- `python components/input/tests/run_lua_tests.py`：编译真实 input 核心、服务、Lua
  绑定及仓库自带 Lua VM，RTOS/文件接口使用宿主适配。覆盖生命周期、元数据
  保存、帧只读和持有、类型筛选、按键/多点状态、溢出恢复、恢复分配失败、
  回调查询/关闭、GC、回调错误隔离、消息投递失败重试、批量处理与积压继续唤醒。
  Lua 分配器额外断言服务锁未被持有，退出时检查 C 堆资源全部释放。
- 国芯 `xmake build luatos` 已通过，新增文件通过宿主 `-Wall -Wextra -Werror`。
- 板端脚本为 `olddemo/demo/usb_hid/input_demo.lua`，由 main.lua 加载，与实体屏幕
  AirUI 示例同时运行。预期看到 INPUT_LUA_API_READY、ATTACH、EVENT、
  KEY_FILTER_AND_STATE_OK 和 INPUT_LUA_STABLE；拔出时出现 REMOVE/STALE_ID_OK。

本次最终固件编译结果 FLASH 5257800 B、RAM 56808 B、PSRAM 3997448 B。
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
