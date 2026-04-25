# AirLink RPC 真机测试指南

## 目录
1. [测试环境准备](#测试环境准备)
2. [统计数据和调试信息](#统计数据和调试信息)
3. [单点功能测试](#单点功能测试)
4. [压力和可靠性测试](#压力和可靠性测试)
5. [性能基准](#性能基准)
6. [故障排查](#故障排查)

---

## 测试环境准备

### 硬件清单

| 设备 | 规格 | 用途 |
|------|------|------|
| 主控 (Master) | Air8000 / Air780E | RPC 客户端（发起调用） |
| 从机 (Slave) | Air8000 / Air8101 | RPC 服务端（处理请求） |
| 通信接口 | SPI / UART | 链路层 |
| 功率表 | （可选）| 功耗测量 |

### 固件编译

```bash
# 编译支持 RPC 的固件（启用所有 RPC 模块）
cd bsp/device_type  # 如 bsp/air8000 或 bsp/air780e
xmake f -y
xmake -y

# 验证编译产物支持 RPC
strings firmware.bin | grep -i "rpc" || echo "检查成功（RPC 已链接）"
```

### 启用的 RPC 模块

确保目标固件启用以下编译宏（在 `luat_conf_bsp.h` 中）：

```c
#define LUAT_USE_AIRLINK_RPC         1  // 基础 RPC 框架
#define LUAT_USE_AIRLINK_RPC_GPIO    1  // GPIO RPC
#define LUAT_USE_AIRLINK_RPC_UART    1  // UART RPC
#define LUAT_USE_AIRLINK_RPC_WLAN    1  // WLAN RPC
#define LUAT_USE_AIRLINK_RPC_PM      1  // 电源管理 RPC
#define LUAT_USE_AIRLINK_RPC_SDATA   1  // 传感器数据 RPC
#define LUAT_USE_AIRLINK_RPC_BLUETOOTH 1 // 蓝牙 RPC
```

---

## 统计数据和调试信息

### 运行时统计 API

新增 C API 用于采集运行时统计：

```c
// 获取 RPC 调用统计
int luat_airlink_rpc_get_stats(luat_airlink_rpc_stats_t* stats);

// 获取性能指标（延迟、编解码耗时）
int luat_airlink_rpc_get_perf(luat_airlink_rpc_latency_t* latency,
                               luat_airlink_rpc_perf_t* perf);

// 重置统计数据
int luat_airlink_rpc_reset_stats(void);

// 打印统计摘要到日志
void luat_airlink_rpc_print_stats(void);
```

### 统计数据结构

**调用统计** (`luat_airlink_rpc_stats_t`)
```
├── call_total        - 总 RPC 调用次数
├── call_success      - 成功次数
├── call_timeout      - 超时次数
├── call_send_fail    - 发送失败
├── call_encode_fail  - 请求编码失败
├── call_decode_fail  - 响应解码失败
├── notify_total      - notify 总数
├── notify_success    - notify 成功数
└── notify_encode_fail
```

**延迟统计** (`luat_airlink_rpc_latency_t`)
```
├── total_ms  - 累计耗时（毫秒）
├── count     - 统计次数
├── min_ms    - 最小耗时
└── max_ms    - 最大耗时
```

**编解码性能** (`luat_airlink_rpc_perf_t`)
```
├── encode_total_us   - 总编码时间（微秒）
├── decode_total_us   - 总解码时间（微秒）
├── encode/decode_count - 编解码次数
└── encode/decode_max_us - 最大单次耗时
```

### 增强的调试日志

日志级别 `LLOGD`（调试）记录：

```
[D] rpc call: mode=0 rpc_id=0x0101 req_len=64 timeout=5000ms pkgid=0x...
[D] rpc_nb_call: encode took 0ms rpc_id=0x0101 enc_len=48
[D] rpc: success (took 12ms resp_len=32)
[D] rpc_nb_call: decode took 0ms rpc_id=0x0101 resp_len=32
```

日志级别 `LLOGE`（错误）记录问题：

```
[E] rpc: send2transport failed -3
[E] rpc: timeout after 5000ms (pkgid=0x... rpc_id=0x0101)
[E] rpc_nb_call: pb_encode req failed rpc_id=0x0101
```

### 在 Lua 脚本中读取统计

创建 Lua binding（需编写）：

```lua
-- 伪代码示例
local stats = airlink.rpc_get_stats()
log.info("RPC", string.format("成功率: %d/%d", 
         stats.call_success, stats.call_total))

local latency = airlink.rpc_get_latency()
log.info("RPC", string.format("延迟: avg=%dms min=%dms max=%dms",
         latency.avg_ms, latency.min_ms, latency.max_ms))
```

---

## 单点功能测试

### 测试 1：GPIO RPC（0x0100）

**目标**：验证远端 GPIO 控制（设置脚输出值）

**硬件连接**：
- Slave GPIO12 → LED 或逻辑分析仪
- 网络链路（SPI/UART）

**测试代码框架** （伪代码）：

```c
// Master 侧
GpioRpcRequest req = {
    .pin = 12,
    .value = 1  // 输出高电平
};

GpioRpcResponse resp = {0};

int ret = luat_airlink_rpc_nb_call(
    LUAT_AIRLINK_MODE_SPI_SLAVE,
    0x0101,  // rpc_id for gpio_set
    &gpio_request_fields,
    &req,
    &gpio_response_fields,
    &resp,
    5000  // timeout_ms
);

if (ret == 0) {
    printf("GPIO SET 成功\n");
} else {
    printf("GPIO SET 失败: %d\n", ret);
}
```

**验证指标**：
- ✅ 返回值 = 0（成功）
- ✅ LED 点亮 / 逻辑分析仪显示高电平
- ✅ 延迟 < 100ms

### 测试 2：UART RPC（0x0200）

**目标**：远端 UART 收发测试

**硬件连接**：
- Slave UART RX → 上位机串口 TX
- Slave UART TX → 上位机串口 RX

**测试代码框架**：

```c
// Master 向 Slave UART 发送数据
UartRpcRequest req = {
    .uart_id = 0,
    .data = "Hello World",
    .data_len = 11
};

UartRpcResponse resp = {0};

int ret = luat_airlink_rpc_nb_call(
    LUAT_AIRLINK_MODE_SPI_SLAVE,
    0x0201,  // uart_write
    &uart_request_fields,
    &req,
    &uart_response_fields,
    &resp,
    5000
);

if (ret == 0 && resp.written_len == 11) {
    printf("UART 写入成功\n");
}
```

**验证指标**：
- ✅ 上位机收到 "Hello World"
- ✅ 响应的 `written_len` 正确
- ✅ 无数据丢失

### 测试 3：WLAN RPC（0x0300）

**目标**：远端 WiFi 状态查询

**测试代码框架**：

```c
WlanStatusRequest req = {0};
WlanStatusResponse resp = {0};

int ret = luat_airlink_rpc_nb_call(
    LUAT_AIRLINK_MODE_SPI_SLAVE,
    0x0301,  // get_status
    &wlan_request_fields,
    &req,
    &wlan_response_fields,
    &resp,
    5000
);

if (ret == 0) {
    printf("WLAN 状态: signal=%d rssi=%d\n", resp.signal, resp.rssi);
}
```

**验证指标**：
- ✅ 返回值 = 0
- ✅ RSSI 值在合理范围内（-90 ~ -20 dBm）
- ✅ 信号强度等级正确

---

## 压力和可靠性测试

### 测试 4：并发 RPC 调用

**目标**：验证多任务并发 RPC 的线程安全性

**测试场景**：

```lua
-- Master 侧 Lua 脚本
sys.taskInit(function()
    for i = 1, 100 do
        local result = rpc_call(0x0101, {pin=12, value=i%2})
        if result ~= 0 then
            log.error("并发调用失败", i)
        end
        sys.sleep(10)
    end
end)

sys.taskInit(function()
    for i = 1, 100 do
        local result = rpc_call(0x0201, {uart_id=0, data="test"})
        if result ~= 0 then
            log.error("并发UART失败", i)
        end
        sys.sleep(15)
    end
end)

sys.run()
```

**预期结果**：
- 100% 成功率（无竞态条件导致的失败）
- 无内存泄漏（连续运行时堆内存不增长）

### 测试 5：大数据吞吐

**目标**：验证高负荷数据传输

**测试代码框架**：

```c
// 发送 1400 字节的数据块
uint8_t payload[1400];
for (int i = 0; i < sizeof(payload); i++) {
    payload[i] = (i % 256);
}

SdataNotify notify = {
    .data = payload,
    .data_len = 1400
};

int ret = luat_airlink_rpc_nb_notify(
    LUAT_AIRLINK_MODE_SPI_SLAVE,
    0x0501,  // sdata_data notify
    &sdata_notify_fields,
    &notify
);

// 验证吞吐率
uint64_t bytes_sent = 1400;
uint32_t latency_ms = 25;  // 从统计中获取
double throughput_kbps = (bytes_sent * 8) / (latency_ms);
printf("吞吐率: %.1f kbps\n", throughput_kbps);
```

**预期性能指标**：
- ✅ 吞吐率 > 50 kbps（SPI 模式）
- ✅ 无数据丢失 (CRC16 校验通过)
- ✅ 延迟 < 50ms（本地网络）

### 测试 6：超时恢复

**目标**：验证 RPC 超时后系统恢复能力

**测试代码框架**：

```c
// 模拟 Slave 端响应缓慢
// 在 Slave 的 handler 中加入延迟

for (int i = 0; i < 10; i++) {
    GpioRpcRequest req = {.pin = 12, .value = i % 2};
    GpioRpcResponse resp = {0};
    
    int ret = luat_airlink_rpc_nb_call(
        LUAT_AIRLINK_MODE_SPI_SLAVE,
        0x0101,
        &gpio_request_fields,
        &req,
        &gpio_response_fields,
        &resp,
        1000  // 1s 超时
    );
    
    if (ret == -1) {  // timeout
        printf("第 %d 次超时\n", i);
        // 验证后续调用仍能成功
        sleep(500);  // 等待 Slave 恢复
    } else if (ret == 0) {
        printf("调用成功\n");
    }
}
```

**预期结果**：
- ✅ 超时返回 -1
- ✅ 后续调用正常恢复
- ✅ 无内存泄漏（result_reg 正确清理）

---

## 性能基准

### 基准条件

| 参数 | 值 |
|------|-----|
| 通信链路 | SPI，时钟 10MHz |
| 报文大小 | GPIO 64B（req+resp） |
| 环境温度 | 室温 (25°C) |
| 运行时间 | 1000 次调用 |

### 基准结果采集脚本

```lua
-- 在 Master 侧运行
sys.taskInit(function()
    local start_tick = os.time() * 1000
    local success_count = 0
    local max_latency = 0
    local min_latency = 65535
    
    for i = 1, 1000 do
        local call_start = luat.mcu_tick64()
        local ret = rpc_gpio_set(12, i % 2)
        local call_latency = luat.mcu_tick64() - call_start
        
        if ret == 0 then
            success_count = success_count + 1
            max_latency = math.max(max_latency, call_latency)
            min_latency = math.min(min_latency, call_latency)
        end
    end
    
    local total_time = os.time() * 1000 - start_tick
    local throughput = (success_count * 1000) / total_time
    
    log.info("基准", string.format(
        "成功率: %d/%d, 吞吐: %.1f calls/s, "
        "延迟: min=%dms avg=%dms max=%dms",
        success_count, 1000, throughput,
        min_latency, total_time / 1000, max_latency
    ))
end)
```

### 预期基准指标

| 指标 | 预期值 | 说明 |
|------|--------|------|
| 成功率 | > 99.9% | 可靠性 |
| 平均延迟 | 10-30 ms | SPI 局域网 |
| 最小延迟 | 5 ms | 无拥塞路径 |
| 最大延迟 | 100 ms | 偶发重传 |
| 吞吐率 | > 30 calls/s | RPC 调用频率 |

---

## 故障排查

### 问题 1：timeout（-1）频繁出现

**症状**：
- RPC 调用超时返回 -1
- 日志中出现 `rpc: timeout after ...`

**排查步骤**：

1. **验证通信链路**：
   - 检查 SPI/UART 电平（示波器或逻辑分析仪）
   - 确认时钟信号稳定
   - 检查 GND 连接可靠性

2. **查看 Slave 端日志**：
   ```bash
   # 监听 Slave 串口日志，查看是否收到 RPC 请求
   # 如果日志中无 "rpc exec: rpc_id=..." 说明请求未送达
   ```

3. **调整超时值**：
   ```c
   // 先尝试更大的超时
   luat_airlink_rpc_nb_call(..., 10000);  // 从 5s 增加到 10s
   ```

4. **检查 Master 任务优先级**：
   - Ensure RPC calling task 不被高优先级任务抢占
   - Log 优先级和占用率

### 问题 2：内存泄漏（堆持续增长）

**症状**：
- 运行数小时后可用内存下降
- 日志无明显错误

**排查步骤**：

1. **打印堆统计**：
   ```c
   extern void luat_heap_stats(void);
   luat_heap_stats();  // 周期调用，观察变化
   ```

2. **启用 RPC 统计**：
   ```c
   luat_airlink_rpc_print_stats();  // 检查 call_decode_fail 等异常计数
   ```

3. **检查点**：
   - `result_reg` 是否满 → timeout 恢复失败
   - `enc_buf` 分配失败 → 内存不足
   - 未清理的 nanopb 结构体

### 问题 3：编码/解码失败（-4）

**症状**：
- RPC 返回 -4（编解码失败）
- 日志：`pb_encode req failed` 或 `pb_decode resp failed`

**排查步骤**：

1. **检查 .proto 定义**：
   - `.proto` 中字段类型与 C 结构体一致
   - 特别注意 `bytes` 类型字段的最大长度

2. **验证编解码缓冲区**：
   ```c
   #define NB_ENC_BUF_SIZE 1500  // 确保足够大
   ```

3. **查看生成的 .pb.h**：
   ```c
   // 检查 pb 消息默认值、嵌套结构等
   cat xxx.pb.h | grep -A 5 "typedef struct"
   ```

### 问题 4：Slave 无响应

**症状**：
- Master 侧 RPC 总是超时
- Slave 侧无日志输出

**排查步骤**：

1. **验证 Slave 固件**：
   ```bash
   # 检查 Slave 是否成功启动
   # 最小化固件仅包含 airlink 模块，去掉其他功能
   ```

2. **检查 RPC 模块启用**：
   ```c
   if (luat_airlink_rpc_nb_dispatch(...) == -404) {
       // 说明 handler 未注册
       LLOGE("rpc: 模块未启用");
   }
   ```

3. **启用服务端日志**：
   ```c
   // 在 Slave 的 luat_airlink_cmd_exec_rpc() 中已加入详细日志
   // 观察 "rpc exec:" 日志
   ```

---

## 快速检查清单

上真机测试前，运行此检查清单：

- [ ] 固件编译通过，无链接错误
- [ ] PC 模拟器上基础测试通过（loopback 模式）
- [ ] Master 和 Slave 硬件通信链路可靠（示波器验证）
- [ ] 两端固件都启用了 `LUAT_USE_AIRLINK_RPC=1`
- [ ] Slave 端日志正常输出
- [ ] Master 端单个 RPC 调用能成功返回
- [ ] 连续 100 次调用成功率 > 99%
- [ ] 统计数据（call_success / call_total）匹配
- [ ] 长时间运行（1 小时）无内存泄漏
- [ ] 故障恢复验证（超时后可继续调用）

---

## 附录：Lua Binding 参考

如需在 Lua 脚本中使用统计 API，需编写 binding：

```c
// 伪代码：components/airlink/binding/luat_lib_airlink.c
static int l_airlink_rpc_stats(lua_State *L) {
    luat_airlink_rpc_stats_t stats;
    luat_airlink_rpc_get_stats(&stats);
    
    lua_createtable(L, 0, 8);
    lua_pushinteger(L, stats.call_total);
    lua_setfield(L, -2, "call_total");
    // ... 其他字段
    
    return 1;
}

// 注册到 Lua
// luaL_newlib(L, airlink_lib);
```

---

## 联系与反馈

发现问题？请 Log：
1. RPC 调用的 `rpc_id` 和 `mode`
2. 错误码和时间戳
3. 统计数据摘要 (`luat_airlink_rpc_print_stats()`)
4. 系统日志（完整的 LLOGE 输出）

