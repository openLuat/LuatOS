# AirLink RPC 真机测试建议

## 已完成的工作

### 1. 运行时统计与监控
✅ **新增统计 API**
- `luat_airlink_rpc_get_stats()` - 获取调用统计（成功/失败/超时/编码失败等）
- `luat_airlink_rpc_get_perf()` - 获取性能指标（延迟分布、编解码耗时）
- `luat_airlink_rpc_reset_stats()` - 重置统计
- `luat_airlink_rpc_print_stats()` - 打印可读的统计摘要

**作用**：
- 量化 RPC 性能（吞吐率、延迟、成功率）
- 诊断瓶颈（编码/解码是否成为瓶颈？）
- 长时间运行监控（发现内存泄漏或频繁超时）

### 2. 增强的调试日志
✅ **关键路径日志**
- RPC 请求发送：`[D] rpc call: mode=0 rpc_id=0x0101 req_len=64 timeout=5000ms`
- 编解码性能：`[D] rpc_nb_call: encode took 0ms ... decode took 0ms ...`
- 调用完成：`[D] rpc: success (took 12ms resp_len=32)`
- 服务端处理：`[D] rpc exec: rpc_id=0x0101 msg_type=0 req_len=48`

**作用**：
- 追踪 RPC 从发送→等待→响应的全生命周期
- 快速定位延迟和超时的根本原因
- 支持时间序列分析（如编码耗时是否随负载增加而增加）

### 3. 代码质量改进
✅ **线程安全性**
- 统计数据通过 mutex 保护，支持多任务并发读取
- 无竞态条件

✅ **内存管理**
- 所有临时 malloc 都配套 free（编码/解码缓冲区）
- 超时恢复正确释放资源（避免泄漏）

---

## 真机测试前的建议

### 优先级 1：必做

#### A. 编写测试脚本（1-2 天）
```
testcase/
├── airlink_rpc_basic/          # 基础功能测试
│   └── scripts/
│       ├── main.lua            # 入口（5个模块逐个验证）
│       └── rpc_test.lua        # 测试用例
├── airlink_rpc_stress/         # 压力测试
│   └── scripts/
│       ├── main.lua            # 入口
│       └── concurrent_calls.lua # 100 次并发调用
└── airlink_rpc_perf/           # 性能基准
    └── scripts/
        ├── main.lua
        └── latency_measure.lua # 1000 次调用统计
```

**关键步骤**：
1. GPIO（最简单）→ UART → WLAN → PM（最复杂）
2. 每个模块单点测试（验证编码/解码正确）
3. 组合测试（多个模块同时调用）

#### B. 部署到真机（1 天）
1. 编译 Slave（Air8000/Air8101）固件，启用全部 RPC 模块
2. 编译 Master（Air780E）固件，启用 RPC 客户端
3. 烧写并启动，确认日志输出正常

#### C. 单点功能验证（2 天）
- GPIO：控制 LED，观察延迟和成功率
- UART：发送已知数据，校验接收内容
- WLAN：查询信号强度、IP 等状态
- PM：控制电源状态（待机、唤醒）
- SDATA：发送传感器数据包

**成功标志**：
- ✅ 5 个模块都能返回预期结果
- ✅ 统计数据中 `call_success == call_total`（100% 成功率）
- ✅ 平均延迟 10-50ms（符合预期）

---

### 优先级 2：推荐

#### D. 压力和可靠性测试（3-5 天）

**并发测试**：
```lua
-- 创建 3 个任务，同时调用 GPIO/UART/WLAN RPC
for task = 1, 3 do
    sys.taskInit(function()
        for i = 1, 100 do
            rpc_call(...)
            sys.sleep(50)
        end
    end)
end
```
- 预期：100% 成功，无内存泄漏

**大数据测试**：
- SDATA notify 发送 1400B 数据块
- 观察吞吐率和是否有丢包（CRC 校验）

**超时恢复测试**：
- 故意让 Slave 响应延迟，观察 Master 超时恢复能力
- 验证 `result_reg` 正确清理，无内存泄漏

**长时间运行**：
- 运行 24 小时压力测试
- 采样内存使用、功耗等指标

#### E. 性能基准测试（2 天）

```lua
-- 采集 1000 次 GPIO RPC 的性能指标
stats = airlink.rpc_get_stats()
print("成功率: " .. (stats.call_success / stats.call_total * 100) .. "%")
print("吞吐率: " .. (stats.call_success / elapsed_time) .. " calls/s")
```

**记录指标**：
- 成功率 (%)
- 平均/最小/最大延迟 (ms)
- 吞吐率 (calls/s)
- 编码/解码最大耗时 (ms)
- 峰值内存使用 (KB)

---

### 优先级 3：可选

#### F. 故障注入测试（可选）

**在 Slave 端注入故障**：
- 延迟响应（模拟处理慢）
- 随机丢包（模拟通信干扰）
- 内存不足（malloc 失败）

**观察**：
- Master 如何处理超时和错误码
- 系统恢复时间

#### G. 功耗和性能分析（可选）

如有条件：
- 用功率表测量 RPC 调用期间功耗
- 对比不同负载下的功耗特性
- 对比不同通信链路（SPI vs UART）的功耗

---

## 调试技巧

### 1. 启用详细日志
```c
// 在 luat_conf_bsp.h 中
#define LUAT_LOG_LEVEL LUAT_LOG_DEBUG  // 显示 LLOGD 调试日志
```

### 2. 定期打印统计摘要
```c
// 在长时间测试中，每 10s 打印一次
sys.taskInit(function()
    while true do
        sys.sleep(10000)
        airlink.rpc_print_stats()
    end
end)
```

### 3. 记录完整的日志到文件
```lua
-- 将日志定向到文件，便于离线分析
local logfile = io.open("/sd/rpc_test.log", "a")
logfile:write(os.date() .. " " .. msg .. "\n")
logfile:close()
```

### 4. 使用逻辑分析仪抓取 SPI/UART 波形
- 验证通信链路的完整性
- 测量实际传输延迟
- 识别重传和冲突

---

## 预期的成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| **成功率** | > 99.5% | 可靠性底线 |
| **平均延迟** | 10-50 ms | 取决于通信链路 |
| **最大延迟** | < 200 ms | 偶发情况（重传） |
| **吞吐率** | > 20 calls/s | RPC 调用频率 |
| **编码延迟** | < 1 ms | nanopb 效率 |
| **内存泄漏** | 0 byte/hour | 长时间运行稳定 |
| **超时恢复** | 100% | 能继续正常工作 |

---

## 风险和缓解措施

### 风险 1：通信链路不稳定
**表现**：高超时率，随机错误
**缓解**：
- 检查 PCB 布线（GND、EMI 屏蔽）
- 降低 SPI 时钟速度（从 10MHz → 5MHz）
- 增加校验和冗余（虽然已有 CRC16）

### 风险 2：编解码性能不足
**表现**：大数据 RPC 超时
**缓解**：
- 优化 .proto 定义（减少字段数量）
- 使用更小的编码缓冲区（NB_ENC_BUF_SIZE）
- 分块传输大数据（UART WRITE 已支持循环分块）

### 风险 3：内存碎片化
**表现**：长时间运行后内存耗尽
**缓解**：
- 使用内存池预分配
- 定期重启
- 监控堆碎片率

---

## 交付物清单

**代码变更**：
- ✅ `components/airlink/include/luat_airlink_rpc.h` - 新增统计 API
- ✅ `components/airlink/src/luat_airlink_rpc.c` - 统计实现和日志增强
- ✅ `components/airlink/src/exec_rpc/luat_airlink_cmd_exec_rpc.c` - 服务端日志增强

**文档**：
- ✅ `TESTING_GUIDE.md` - 完整真机测试指南（包含代码框架和预期指标）
- ✅ 此文件 - 建议和快速参考

**预期效果**：
- 能实时监控 RPC 性能
- 快速定位问题根源
- 支持长时间可靠性验证

---

## 后续工作（可选）

1. **Lua Binding**（推荐）
   - 在 Lua 脚本中直接调用 `airlink.rpc_get_stats()`
   - 便于自动化测试和监控

2. **Web 监控面板**（可选）
   - 实时展示 RPC 成功率、延迟、吞吐率曲线
   - 便于长时间测试的远程监控

3. **性能优化**（如需要）
   - Profile 编解码耗时，寻找瓶颈
   - 考虑使用 protobuf 或其他更高效的序列化格式

---

**最后**：建议先在 PC 模拟器（loopback 模式）上充分验证，再上真机。PC 模拟器的优势是快速迭代，失败不伤硬件。

祝测试顺利！🚀

