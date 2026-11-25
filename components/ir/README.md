# IR: NEC 红外遥控

本目录的 `luat_lib_ir.c` 提供 `luaopen_ir`。`LUAT_USE_IR` 启用 `ir.sendNEC`；`LUAT_USE_IR_RX` 独立控制接收，启用时 BSP 还需编译本目录的解码和捕获源码。任一开关启用时注册 `ir` 模块。

- `luat_ir_nec.c` 是纯 NEC 下降沿解码器，每个接收头使用独立状态。普通地址为 8 位，扩展地址为 16 位，只有命令反码正确的完整帧才更新键值。
- `luat_ir_capture_gpio.c` 是默认适配层，通过 LuatOS GPIO HAL 配置下降沿中断和上拉，使用 MCU 的 64 位时钟在中断中取时间戳。使用硬件捕获外设的 BSP 可定义 `LUAT_IR_CUSTOM_CAPTURE`，实现 `luat_ir_capture_start/stop`，在边沿到达时调用 `luat_ir_rx_edge(pin, timestamp_us)`。同一引脚的边沿必须串行；停止返回时必须保证中断不再访问该接收器。
- `luat_ir_rx.c` 管理回调和统计。ISR 仅投递完整帧或重复帧，不调用 Lua；消息携带初始化编号，关闭并重新打开引脚后不会收到上一次的回调。`rxStats` 统计解码结果；消息队列已满时回调可能丢失。

Lua 应用直接调用 `ir.rxInit(pin, callback)` 开始接收，`ir.rxStats(pin)` 读取统计，`ir.rxClose(pin)` 停止接收并释放引脚。可用的接收引脚由 BSP 决定。
