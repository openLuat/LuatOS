# ulwip DHCP ARP 预热实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 ulwip DHCP 客户端成功获取 IP 后，追加发送 gratuitous ARP 与网关 ARP request，以刷新局域网 ARP 缓存并预热网关 MAC。

**架构：** 仅修改 `components/network/ulwip/src/ulwip_dhcp_client.c`，在 `DHCP_STATE_CHECK` 提交 IP 后、进入租约等待前插入两包 ARP；不改动共享 DHCP 状态机，不引入新状态或定时器。

**Tech Stack:** C, LwIP 2.2 (`etharp_gratuitous`, `etharp_request`), LuatOS ulwip, xmake (PC 模拟器验证)

---

## 文件变更

- **修改：** `components/network/ulwip/src/ulwip_dhcp_client.c`
  - 在 `DHCP_STATE_CHECK` 分支的 `netif_set_addr()` 之后插入 `etharp_gratuitous(netif)` 与 `etharp_request(netif, &gw)`。

---

### Task 1: 插入 gratuitous ARP 与网关 ARP 预热

**Files:**
- Modify: `components/network/ulwip/src/ulwip_dhcp_client.c:75-79`

**说明：**
目标代码块当前如下（`netif_set_addr` 紧接设置 state）：

```c
        // 设置到netif
        ip4_addr_t ipaddr = {.addr=dhcp->ip};
        ip4_addr_t netmask = {.addr=dhcp->submask};
        ip4_addr_t gw = {.addr=dhcp->gateway};
        netif_set_addr(netif, &ipaddr, &netmask, &gw);
        dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
```

- [ ] **Step 1: 在 `netif_set_addr` 与 `dhcp->state = DHCP_STATE_WAIT_LEASE_P1;` 之间插入 ARP 调用**

```c
        // 设置到netif
        ip4_addr_t ipaddr = {.addr=dhcp->ip};
        ip4_addr_t netmask = {.addr=dhcp->submask};
        ip4_addr_t gw = {.addr=dhcp->gateway};
        netif_set_addr(netif, &ipaddr, &netmask, &gw);
        // gratuitous ARP，通知局域网刷新本机 IP/MAC 映射
        etharp_gratuitous(netif);
        // 预热网关 MAC，避免上层首包出网卡顿
        if (ip4_addr_isany_val(gw) == 0) {
            etharp_request(netif, &gw);
        }
        dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
```

  注意：
  - `etharp_gratuitous` 与 `etharp_request` 已通过 `luat_ulwip.h` 间接引入 `lwip/etharp.h` 而可用。
  - 网关为空（`0.0.0.0`）时跳过网关 ARP，避免无意义发包。

- [ ] **Step 2: 检查 LwIP API 返回值并记录日志（可选但建议）**

```c
        err_t arp_err;
        arp_err = etharp_gratuitous(netif);
        if (arp_err != ERR_OK) {
            LLOGW("adapter %d gratuitous ARP failed %d", adapter_index, arp_err);
        }
        if (ip4_addr_isany_val(gw) == 0) {
            arp_err = etharp_request(netif, &gw);
            if (arp_err != ERR_OK) {
                LLOGW("adapter %d gateway ARP request failed %d", adapter_index, arp_err);
            }
        }
```

  说明：ARP 发送失败不应阻塞 DHCP 流程，仅记录 warning。

- [ ] **Step 3: 提交代码变更**

```bash
git add components/network/ulwip/src/ulwip_dhcp_client.c
git commit -m "feat(ulwip): send gratuitous ARP and gateway ARP after DHCP got IP"
```

---

### Task 2: 编译验证

**Files:**
- 无需修改文件，使用 `bsp/pc` 的 helper 脚本编译。

- [ ] **Step 1: 使用 PC 模拟器 helper 脚本执行增量编译**

```bash
cd bsp/pc
cmd /c build_windows_32bit_msvc.bat
```

  说明：
  - 根据项目 `AGENTS.md`，非 GUI 改动应使用该脚本，避免直接 `xmake -y` 全量重建。
  - 期望输出包含 `Build completed successfully`。

- [ ] **Step 2: 若出现编译错误，修复后重新编译**

  常见风险：
  - `etharp_gratuitous` 未定义：检查 `lwip/etharp.h` 是否被包含；ulwip 通过 `luat_ulwip.h` 已包含。
  - `ip4_addr_isany_val` 未定义：可改用 `ip4_addr_isany(&gw)` 或直接判断 `dhcp->gateway != 0`。

---

### Task 3: 运行/抓包验证（可选，视环境而定）

**Files:**
- 运行 `bsp/pc/build/out/luatos-lua.exe` 配合 ulwip DHCP 测试脚本。

- [ ] **Step 1: 运行 PC 模拟器下的 ulwip DHCP 示例**

  找到现有 ulwip DHCP 测试入口，例如：

```bash
cd bsp/pc
build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../bsp/pc/test/101.ulwip/scripts/
```

  或项目内对应的 ulwip 示例脚本路径。

- [ ] **Step 2: 通过 Wireshark/tcpdump 抓包确认**

  期望在 DHCP ACK 之后观察到：
  - 一帧 ARP Request，Sender IP 与 Target IP 均为本机分配到的 IP（gratuitous ARP）。
  - 一帧 ARP Request，Target IP 为 DHCP 分配的网关 IP。

- [ ] **Step 3: 若无法抓包，通过日志确认函数被调用**

  可在插入点临时增加 `LLOGI`：

```c
        LLOGI("adapter %d send gratuitous ARP and gateway ARP request", adapter_index);
```

  验证后保留或删除该日志（建议保留 `LLOGD` 级别日志以便后续排查）。

---

## Self-Review Checklist

- [ ] Spec 覆盖：设计文档中“改动范围、实现细节、错误处理、验证方案”均有对应任务。
- [ ] 无占位符：所有步骤均包含具体代码或命令。
- [ ] 类型/命名一致：`etharp_gratuitous`、`etharp_request`、`ip4_addr_isany_val` 与 LwIP 2.2 API 一致。
- [ ] 不引入新依赖：不启用 `LWIP_ACD`，不修改共享 DHCP 状态机。
