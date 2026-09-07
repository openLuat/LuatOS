# luat_input：小型 C 输入核心

第一版实现统一事件、设备状态、直接订阅和可选整帧队列。适用于键盘、鼠标、单点/多点触摸；已提供独立 HID 报告解析器并接入国芯 USB Host；TP 接入、GUI、键盘布局/输入法属于后续适配工作。

设计依据：[Linux input event codes](https://docs.kernel.org/input/event-codes.html)、[Linux input driver model](https://docs.kernel.org/input/input-programming.html)、[Linux multi-touch protocol](https://docs.kernel.org/input/multi-touch-protocol.html)。沿用 type/code/value 和状态/增量的语义，采用适合 MCU 的帧头与传递接口，并非 Linux evdev 二进制 ABI。

## 配置可以分层，传输保持直接

```text
配置路径（低频，可扩展）：
项目默认值 → 设备类别 → 总线/设备 → 应用配置
               ↓ 配置层解析、合并，生成最终能力和订阅关系
      register(desc, state) / bind(device, consumer)

同步数据路径：
驱动任务 → luat_input_submit → 已绑定消费者回调

跨任务数据路径：
驱动任务 → luat_input_submit → 消费者的整帧队列 → 消费者任务
```

核心不创建任务、线程、定时器，不强制消息总线或队列。配置继承、按设备能力匹配消费者、优先级和设备分组可在上层配置阶段完成；第一版核心提供绑定原语，不内置配置树解析器。

提交直接使用实例句柄，热路径不遍历全设备表、不执行订阅条件匹配、不遍历配置树。每个设备只访问已绑定的直接链表，复杂度随该设备消费者数增长。多个配置规则最终指向同一回调/userdata 时只允许一个绑定，避免重复输入。

已有 USB/TP 任务可以直接提交；需要把原始 IRQ 数据转到任务解析时，优先复用驱动已有任务。HID 描述符解析、设备识别在接入阶段完成，不能在每次提交中重新执行。

## 数据与状态

- `luat_input_event_t` 固定 8 字节：`uint16_t type, code; int32_t value`。
- `luat_input_frame_t` 固定 16 字节：设备 ID、序号、毫秒时间戳、事件数、标志。
- 一次 `submit()` 是一帧，先校验全部事件，再更新全部状态，最后投递；非法尾事件不会留下半帧状态。可附带一个末尾 `SYN_REPORT`，也可省略。
- 同步回调借用原始事件数组，核心不复制事件。回调返回即结束借用，不能异步保留指针。
- 设备 ID 在同一 core 生命周期内单调分配，耗尽时拒绝注册。不同 core 的 ID 命名空间独立。
- sequence 为设备状态/绑定变更序号，允许 uint32 回绕，通过 `luat_input_sequence_after()` 比较，比较距离须小于 2^31。解绑也递增序号，因此其他订阅者可出现序号间隔，间隔本身不能直接等同丢帧。
- 普通帧携带生产者传入的单调时间戳。ATTACH/解绑 REMOVE 沿用设备最近一次时间戳；拓扑帧的排序以调用顺序和 sequence 为准。

| 类型 | 第一版语义 | 核心保存的状态 |
|---|---|---|
| KEY | 按下 1、释放 0、重复 2；Linux 键码/按钮码 | 紧凑位图，重复事件不改变状态 |
| REL | 有符号 X/Y、滚轮等增量 | 不保存累计位移 |
| ABS | 设备坐标，按声明范围校验 | 当前值 |
| ABS_MT_* | slot 选择，tracking ID、坐标、压力等 | 按槽保存；tracking ID=-1 表示离开 |
| MSC | 配置允许的扩展数据项，直接传递 | 不保存 |

KEY capability/state 使用按需长度位图，支持 0..0x2ff。ABS 能力是按 code 排序的稀疏数组，查询使用二分查找。MT 独立声明轴数组、槽数，默认最大槽数 16，可通过 `LUAT_INPUT_MT_SLOTS_MAX` 调整；声明 MT 时必须有初值为 -1 的 tracking ID。

状态内存由 `luat_input_state_words()` 计算，调用方提供 uint32_t 数组：

```text
key_words 个位图字
+ abs_count 个轴值
+ mt_slots × mt_count 个槽轴值
```

描述符与能力数组可放只读 Flash，注册后保持不变。驱动负责按键差分、去抖、重复策略和稳定的 contact ID；核心保留提交内容，不过滤重复值、不合并运动、不把按键转换成字符。设备能力不支持的事件返回 ENOTSUP；值或帧格式非法返回 EINVAL。

## 同步、所有权与生命周期

所有 core 操作由调用方串行化。单任务不需要额外锁；USB 和 TP 从不同任务提交时，用同一外部锁保护 core 操作，或投递到已有公共任务。回调也在该串行化范围内执行，所以应短小、非阻塞；日志/GUI通常绑定队列。核心没有隐含的 RTOS 依赖，序号原子更新不能代替其他状态的串行化。

回调允许查询状态、快照和枚举，禁止提交、绑定、解绑、reset、注销等重入修改，返回 EBUSY。`luat_input_init()` 只可在首次使用前调用，不能用来重置一个活动 core。

设备结构、描述符、能力数组、状态数组和绑定节点由调用方持有，首次注册/绑定前设备与节点须清零。句柄校验能识别复用设备槽后的旧实例 ID，但不能保护已经释放的设备结构指针。先停止生产并等待进行中的调用结束，再注销、释放存储。

- `bind` 向该消费者发送 ATTACH；它应获取当前 snapshot，避免订阅到已按下的设备时状态不完整。
- `unbind` 递增序号，发送 REMOVE 并清除节点；设备本身仍然注册。
- `reset` 清除按键、恢复 ABS 初值、取消所有 MT 接触，发送 RESET。消费者应取消操作，不能把 RESET 当正常点击完成。
- `unregister` 从活动目录移除设备、取消状态、发送 REMOVE|RESET，然后清除所有节点和设备结构。
- `enumerate` 获取当前设备实例；`lookup` 用 ID 取得带实例校验的 handle，`get_desc` 和 `get_capability` 查询只读描述与单项能力，`bind_id` 在配置路径完成查找和绑定。这些接口不会进入事件提交热路径。

不同物理设备的状态独立。多个键盘映射为一个逻辑键盘时，由消费者按 device_id 合并按键引用；鼠标加速度、光标边界、屏幕旋转、焦点、手势、键盘布局在适配/应用层处理。

## 可选队列及溢出恢复

`luat_input_queue.c` 用调用方提供的字节环形缓冲区存完整帧，不为每帧预留固定最大事件数组。入队复制一次，出队复制到消费者缓冲区；同步订阅不经过此模块。队列可被同一 core 的多个设备共享。

跨线程访问必须提供成对的 lock/unlock 回调，或由外部保证串行化；NULL hooks 明确表示外部已串行化，不代表无锁并发安全。涉及 ISR 时，锁和通知也必须适用于 ISR；不要让中断生产者等待被中断任务持有的互斥锁。

notify 只在空变为非空、正常变为丢失时调用，且在队列解锁之后执行，适合 RTOS 事件/信号量。信号应可保持待处理状态，消费者收到通知后读取到 EEMPTY；多余唤醒是允许的。销毁队列前必须解绑、停止生产，并处理完进行中的通知。

队列空间不足（包括单帧超过总容量）时，清空队列并设置独立的 sticky ELOST；后续提交继续返回 ELOST，直到消费者恢复。标记不占队列空间，避免连“丢失通知”也无法入队。其他消费者和设备核心状态继续正常提交，`submit()` 成功不表示所有队列都已接收。

恢复步骤：

1. 消费者遇到 ELOST，取消该队列来源的当前按键、拖动和触摸操作。
2. 进入 core 的串行化范围，先 `queue_reset()`，再用 `enumerate_bound(core, luat_input_queue_receive, queue, ...)` 获取该队列当前绑定的设备。
3. 对每个当前绑定设备取 snapshot，保存状态和 sequence；不再绑定的设备必须从消费者状态中移除。全局 `enumerate()` 无法识别“设备仍在线但已解绑”，不能代替此步骤。
4. 离开 core 串行化范围后继续读队列，过滤不晚于各 snapshot sequence 的旧帧。若再次 ELOST，重新执行恢复。

锁顺序始终是 core 外部串行化 → queue lock。消费者不得持有 queue lock 调用 core。若枚举/快照输出空间不足，应扩充配置或重试，不能将部分列表当成完整列表释放设备。

snapshot 能恢复当前 KEY/ABS/MT 状态，不能还原已经丢失的短按、REL 位移和滚轮增量；对此显式取消操作，不重放旧增量。第一版不做自动事件合并，以保留原始帧边界和按钮/运动顺序。

## 最小接入方式

使用 C11 编译。只使用同步核心时，将 `luat_input.c` 加入编译并定义 `LUAT_USE_INPUT`；需要队列时再加入 `luat_input_queue.c`、定义 `LUAT_USE_INPUT_QUEUE`。这些是编译器定义；本组件不隐式包含板级配置头。

```c
#include "luat_input.h"

static luat_input_core_t core;
static luat_input_device_t mouse;
static luat_input_link_t route;
static luat_input_handle_t handle;
static uint32_t mouse_state[9];
static const uint32_t buttons[9] = {[8] = 7U << 16}; /* BTN_LEFT/RIGHT/MIDDLE */
static const luat_input_device_desc_t mouse_desc = {
    .name = "mouse",
    .caps = {.keys = buttons, .key_words = 9, .rel_bits = 0x103},
    .properties = LUAT_INPUT_PROP_POINTER
};

/* 初始化：检查各接口返回值；消费函数应短小、非阻塞。 */
luat_input_init(&core);
luat_input_register(&core, &mouse, &mouse_desc, mouse_state, 9, &handle);
luat_input_bind(handle, &route, on_input_frame, userdata);

/* 驱动任务：一份解析后的鼠标报告只提交一次。 */
const luat_input_event_t frame[] = {
    {LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_LEFT, LUAT_INPUT_PRESS},
    {LUAT_INPUT_EV_REL, LUAT_INPUT_REL_X, 5},
    {LUAT_INPUT_EV_REL, LUAT_INPUT_REL_Y, -3}
};
luat_input_submit(handle, monotonic_ms, frame, 3);
```

完整可运行的最小程序见 `tests/core_only_test.c`。跨任务时，将接收函数改为 `luat_input_queue_receive`、userdata 改为初始化后的 queue；由消费者调用 `queue_read`。

## HID 驱动接入

增加 `luat_input_hid.c`、编译宏 `LUAT_USE_INPUT_HID`，接口位于 `luat_input_hid.h`。解析器不依赖 USB 栈、RTOS 或堆，调用方按 `luat_input_hid_size()` 分配一个接口的上下文。

接入顺序为 `hid_init`（解析描述符、注册并绑定）→ `hid_feed`（完整报告）→ 停止接收 → `hid_deinit` → 释放存储。init 后描述符可以释放；描述符中的字段位置、Report ID、范围和能力已经缓存。`hid_report_size` 返回描述符声明的最大 Input 报告字节数，含 Report ID，传输驱动应据此检查或提供完整报告组装。

支持标准键盘数组、位图、修饰键，鼠标按钮、相对 X/Y、垂直/水平滚轮，常用 Consumer/System 按键，以及单接触 ABS 坐标、触摸按下和压力。按键映射为 Linux 数值键码，不是 ASCII；输入报告重复保持某键时不生成软件重复事件。键盘 rollover 保留上次按键状态，等待有效报告；不同 Report ID 的按键状态分别保存并合并。

多接触 HID（Contact ID / Contact Count）当前明确拒绝，不能把多个触点误报成一个；input 核心本身已有 MT 能力，后续可增加专用 HID MT 适配。特殊编码、超出资源上限的描述符也返回错误，不猜测布局。键盘 LED/Feature/Output 传输尚未接入。

资源上限：描述符 1024 B、报告 512 B、8 个 Report ID、32 个 Input 字段组、128 个显式 Usage、8 个 ABS 轴、256 个事件/帧。未知应用集合不会产生事件，但其字段仍计入报告位偏移。标准布局外的键码映射可在 `key_code()` 扩展。

国芯当前数据路径：

```text
USB IRQ → 每接口原始报告环 → 已有 USB app 任务
       → hid_feed → input_submit → C 日志消费者
```

IRQ 仅复制本次完整包、记录时间和通知，不解析描述符、不打印。每接口 32 个槽，最多待处理 31 份报告，槽大小按端点最大包长分配；没有再启用 input 的可选消费者队列。接入阶段一次分配会话、解析器与环形缓冲区，运行时不申请内存。当前底层每回调只有一个 Interrupt 包，所以声明报告大于端点最大包长时拒绝 input 适配；USB HID 接口保持激活，但该接口不产生 input 帧。

2026-09-04 已回退电源控制改动：Host 电源恢复由 USB app 任务处理，枚举/物理断开仍由 control 任务处理。枚举期间主动断电的并发问题待处理，现有 host_app_lock 不覆盖完整枚举过程。input 注册、提交和注销共用现有 `host_app_lock`；IRQ 的环形缓冲区访问用短临界区协调，断开前停止接收、清除会话指针，再注销释放。任务事件携带实例 tag，拒绝拔插前遗留的通知。事件队列通知失败时由 app 任务重试，最长每 10 ms 检查一次，避免最后一次释放无人处理。

报告环溢出或传输错误时清除队列并发送 RESET，取消所有按键/接触；之后从新报告恢复，已丢失的运动不会补发。畸形报告也复位并限频记录错误。`luat_input_log.c` 提供可选 `luat_input_log_receive` 同步消费者，使用 LuatOS DEBUG 日志（tag 为 `input`），低于当前日志等级时直接返回。SDK 绑定该消费者，逐帧打印 `INPUT dev=... seq=... flags=... count=... events=type:code=value`，此日志适用于验证，性能测量时应关闭逐帧打印。国芯 ARM32 的 HID 上下文为 4712 B；8 B 端点另占 512 B 报告环与 32 B 会话信息，合计一次申请 5256 B（不含原始描述符及分配器开销）。ATTACH/REMOVE/RESET 使用帧标志，不伪造普通按键。

2026-09-04 移除 HID 专用日志消息、`SOC_USB_HOST_EVENT_HID_RX`、64 B 原始报告快照及其采样字段；输入日志统一由上述组件输出。USB 中断只投递 input 报告，不再额外投递日志消息。枚举、激活和错误诊断仍留在 USB 层。日志组件只需加入编译并绑定消费者，核心和解析器本身仍不依赖日志后端。

## 触摸适配

`luat_input_touch.c` 提供与触摸芯片无关的 C 适配器，使用 `LUAT_USE_INPUT_TOUCH` 单独裁剪。调用方按 `luat_input_touch_size(slots)` 提供存储，初始化时配置坐标、压力、触点宽度范围及最多槽位；运行时将一批 DOWN/MOVE/UP 槽位更新一次提交为完整 input 帧。适配器同时维护 Linux Type-B MT 的 slot/tracking ID/坐标状态和单指兼容的 BTN_TOUCH、ABS_X/Y；主触点抬起后自动切到仍按下的最低槽位。

适配器不依赖 `luat_tp`、USB、LVGL、RTOS 或堆，可由电容触摸驱动和后续 HID 多点触摸共同使用。触摸芯片层继续负责坐标方向、稳定 track ID 和硬件读取；同一批中重复槽位、越界值或非法事件会整帧拒绝。现有 `luat_tp` 回调尚未切换到该适配器，下一步在公共 TP 任务增加并行通知入口，保留现有 Lua/AirUI 行为。

## 验证与开销（2026-09-03）

在 LuatOS 根目录执行：

```powershell
python components/input/tests/run_tests.py
python components/input/tests/run_tests.py --arm-cc 'E:\tools\arm-gnu-toolchain-14.3.rel1-mingw-w64-x86_64-arm-none-eabi\bin\arm-none-eabi-gcc.exe'
```

测试覆盖整帧拒绝、按键/多触点状态、回调重入、快照、解绑/注销、旧实例、序号/ID 边界、环形缓冲区跨界、溢出与再次溢出恢复、消费者解绑目录，以及两个生产线程到一个消费线程的 20000 帧完整性。

GCC 使用 `-Wall -Wextra -Werror -Wpedantic`。独立同步核心、包含队列和关闭功能的构建均验证；测试产物写临时目录并自动清理。

ARM GCC 14.3，Cortex-M4 Thumb，`-Os`，链接裁剪前的目标文件测量：

| 项目 | 大小 |
|---|---:|
| 核心代码 | 2316 B（含设备查询与按 ID 绑定） |
| 可选队列代码 | 630 B |
| HID 解析器代码及只读映射 | 3756 B |
| 触摸适配器代码 | 1580 B |
| 上述模块全局 `.data` / `.bss` | 0 B |
| core 实例 | 12 B |
| 每设备运行结构 | 36 B |
| 每条绑定 | 16 B |
| 队列控制结构 | 36 B，另加调用方选择的缓冲区 |
| 示例鼠标按钮状态 | 36 B |
| 十触点、每点 X/Y/tracking ID 状态 | 120 B |

触摸适配器在 ARM32 上运行栈估算为 72 B；整帧事件暂存放在调用方提供的上下文中。两槽完整能力上下文约 456 B，16 槽上限约 1408 B，不占全局 `.bss`，也不在运行时申请内存。

核心与队列目标文件只引用 memcpy/memmove/memset；HID 解析器另外引用 input 核心 API，无堆、RTOS、Lua 依赖。上述代码大小不包含最终链接使用的 C 库函数，也不等同固件增量。submit 本身的编译器栈估算为 56 B，调用链和消费者另计。

本机 x64 GCC `-O2`，100 万帧、每帧 4 个事件、一个直接消费者，本次约 0.020 秒，未开启 LTO。这是本机微基准，不能据此推算国芯板上的处理时间；此数字仅针对独立核心的 Cortex-M4 编译；国芯固件使用 Cortex-M7，板上时延尚未测量。

国芯 Air1601 的 HID 接入、编译下载及真机复测已完成：鼠标 046D:C542 的按钮/滚轮/16 位 X/Y、键盘 1C4F:0002 的字母/修饰键/组合键，以及各自两次热插拔后继续输入。键盘调试中修正了 SDK 的 RX Flush 掩码和空中断遗留事件问题；修复版保存 433 个 input 帧，未出现接收/解析/环溢出错误。完整过程与日志位置见 SDK `csdk/project/test/host/README_hid.md`，这些结果不代替低速、HUB 和 HID 多点触摸验证。

## 后续扩展边界

- HID 解析器负责把 USB Usage 映射成输入键码、把报告转换成事件帧；原始 HID Usage 不能直接当 Linux keycode 使用。
- TP 适配在原始读取完成后提交，保留原有 API；屏幕方向变换统一放到显示适配层。
- 配置继承、输出 LED、按键布局、自动重复、事件合并均可作为独立能力增加。扩展时优先在接入/配置阶段预计算，保持 submit 路径短小。
- 国芯固件已接入 C HID 适配；不增加 Lua 接口，不更改 AirUI/LVGL，也不创建新的输入任务。
