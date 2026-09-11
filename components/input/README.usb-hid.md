# USB HID 应用接入

USB BSP 只负责传输，主库默认处理为 input 事件。对接新平台只需要 `luat_usb_hid.h`，无需依赖 input 结构或国芯 USB 类型。

## 默认处理

编译 `luat/weak/luat_usb_hid.c`、`components/input/luat_input_usb_hid.c` 及现有 HID 解析器/核心/日志，启用 `LUAT_USE_INPUT`、`LUAT_USE_INPUT_HID`。可选的 service、Lua 和 AirUI 使用原有配置。

默认路径为 BSP 原始回调 → 主库报告环 → 共享 HID 任务 → input 消费者。核心和 HID 解析器仍无 RTOS/堆依赖；RTOS、内存和应用策略仅在 USB HID 接入模块中。

AirUI 接入由 `components/airui/src/platform/luatos/luat_airui_input_service_luatos.c` 管理：在 AirUI 初始化时订阅 service 的设备生命周期，绑定已有及后续接入的键鼠设备。HID 适配器不包含 AirUI 头文件，不负责 GUI 初始化和绑定；未初始化 AirUI 时，input 及 Lua 订阅仍独立运行。原有 AirUI 触摸路径保持不变。

service 由各 BSP 按需初始化，LuatOS 公共启动入口不调用。国芯在 `luat_main_ccm42xx.c` 中受 `LUAT_USE_INPUT_SERVICE` 控制，在 `luat_init()` 开头、创建 Lua 任务前调用；使用 RTOS 系统堆，无需等待 Lua VM 堆初始化。其他 BSP 或 `sysp` 宿主启用该服务时，需要在自己的启动入口完成初始化。HID、TP、AirUI 和 Lua input 只检查服务就绪，不再代为初始化。独立 C 应用须在启动 USB、TP 等生产者和消费者前调用 `luat_input_service_init()` 并检查返回值。未就绪时接入失败，初始化后需重新接入设备。

## 自定义处理

在 USB Host 启用前注册 C 回调，不需要 Lua：

```c
#include "luat_usb_hid.h"

static void app_hid(luat_usb_hid_host_t *device, luat_usb_hid_event_t event,
                    const uint8_t *data, uint32_t length)
{
    switch (event) {
    case LUAT_USB_HID_OPEN:
        /* 任务上下文：读取描述符，分配应用状态，保存在 device->userdata。 */
        break;
    case LUAT_USB_HID_REPORT:
        /* 可为中断上下文：复制 data[0..length)，投递到应用自己的任务。 */
        break;
    case LUAT_USB_HID_RX_ERROR:
        /* 可为中断上下文：记录丢失标记，通知应用任务取消状态。 */
        break;
    case LUAT_USB_HID_CLOSE:
        /* 任务上下文：结束应用内在途处理，再释放 userdata 并置 NULL。 */
        break;
    }
}

/* 初始化阶段；之后再打开 USB Host。 */
luat_usb_hid_set_callback(app_hid);
```

回调直接接收原始 HID，不会再经过默认 input 解码或 AirUI 绑定。启用 input 的固件也可以使用此方式；关闭 input 的固件无需链接解析器即可使用原始回调。

若仅部分设备使用默认 input，可在应用回调内按 VID/PID/接口号判断后，把该设备的所有事件交给 `luat_input_usb_hid_callback(device, event, data, length)`；其 userdata 由该适配器独占。不要仅转交 REPORT，或把已交给适配器的设备再按另一种格式处理 userdata。

## 生命周期和上下文

1. BSP 为每个接口提供独立且清零的 `luat_usb_hid_host_t`，填写描述符、VID/PID、接口、包长等信息。
2. BSP 在任务里调用 OPEN，返回后才能启动 RX。应用拒绝解析某种 HID 时，底层仍可继续接收。
3. REPORT 每次只借用一份完整 Interrupt 包，数据指针在回调返回后失效。它与 RX_ERROR 可能在 IRQ 内调用，不能直接解析、打印、分配、阻塞或调用 Lua/LVGL。
4. BSP 停止接收并等待在途回调结束后，在任务里调用 CLOSE，然后释放描述符和设备存储。CLOSE 可能来自部分初始化失败，应用必须容忍没有成功 OPEN 的 CLOSE。

OPEN/CLOSE 必须由传输层串行化。描述符和设备信息至少保持到 CLOSE 返回；应用异步处理必须复制所需数据。BSP 不读取或解释 userdata，也不以 userdata 是否为空决定要不要回调数据。

`luat_usb_hid_set_callback(NULL)` 恢复默认处理。仅能在尚未启用 Host，或所有接口关闭且回调全部停止后切换；这不是活动设备的热切换接口。

## 验证

```text
python components/input/tests/run_usb_hid_tests.py
```

不依赖 CCM 头文件。测试覆盖高优先级任务在创建函数返回前抢占运行、初始化失败清理、原始包复制、失败通知重试、环溢出/错误取消、精确预算边界、多接口、断开旧通知，以及 service 观察者移除/重新注册、AirUI 延迟启动及热插拔绑定、关闭 input、自定义应用回调。

2026-09-10 修复任务启动时序：CCM 创建事件任务时先恢复调度，再返回句柄。HID 工作任务可抢占创建者，此时全局 `worker` 尚未写入。任务入口应通过 `luat_rtos_get_current_handle()` 获取自身句柄来等待事件；不能依赖创建函数尚未写入的输出值，否则空句柄等待立即失败，高优先级任务忙循环会阻止枚举继续。回归用例在发布句柄之前先执行任务，防止再次遗漏这种时序。
