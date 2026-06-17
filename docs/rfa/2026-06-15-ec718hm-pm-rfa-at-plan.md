# EC718HM/EC718PM 系列模组 LuatOS AT 射频校准实施计划

> 基于 LuatOS rfa（Radio Factory Agent）框架，在 EC718HM/EC718PM 系列模组的 LuatOS 固件上实现产线 AT 指令射频校准功能。
> 计划日期：2026-06-15

---

## 1. 目标与范围

### 1.1 总体目标
在 LuatOS 固件中新增一个基于 rfa.lua 的 AT 服务器，通过指定 UART 接收产线校准/综测工具下发的 AT 指令，调用 mobile.rfTest* 系列 C API 与底层 RF 校准原语交互，最终使 EC718HM/EC718PM 系列模组能够用 LuatOS 固件完成产线射频校准与非信令综测。

### 1.2 覆盖命令（按 EC CAT1产线校准综测相关AT命令.xlsx）

| No. | AT Command | 属性 | 处理方式 | 备注 |
|-----|------------|------|----------|------|
| 1 | AT | 3GPP | rfa.lua 内置派发 | 握手 |
| 2 | ATE0/ATE1 | 3GPP | rfa.lua 内置派发 | 回显 |
| 3 | AT+CFUN=0 | 3GPP | rfa.lua 内置 + mobile.flymode | 进飞行模式 |
| 4 | AT+CPIN? | 3GPP | rfa.lua 内置 | 返回 CME ERROR: 303 |
| 5 | AT+CGSN | 3GPP | rfa.lua 内置 + mobile.rfTestImei | 读 IMEI |
| 6 | AT+ECPMUCFG | EigenComm | 新增 rfa.lua 处理或 C 层 mobile.rfTestParam 扩展 | PMU 模式 |
| 7 | AT+ECRST | EigenComm | 新增 rfa.lua 处理 | 软复位 |
| 8 | AT+ECCGSN | EigenComm | 新增 rfa.lua 处理 + mobile.rfTestImeiSet | 写 IMEI/SN |
| 9 | AT+ECNPICFG | EigenComm | rfa.lua 内置 + mobile.rfTestParam | 校准/综测标志位 |
| 10 | AT+ECGMDATA | EigenComm | 新增 rfa.lua 处理 + C 层扩展 | 金机数据读写 |
| 11 | AT+ECCHIPVER? | EigenComm | 新增 rfa.lua 处理或 C 层扩展 | 读芯片版本 |
| 12 | AT+ECRFNST | EigenComm | rfa.lua 私有协议派发 + mobile.rfTestInput | 校准/非信令指令 |
| 13 | AT+ECBAND=? | EigenComm | 新增 rfa.lua 处理或 C 层扩展 | 查支持 Band |
| 14 | AT+ECICCID | EigenComm | 新增 rfa.lua 处理 + mobile.* ICCID 接口 | 读 ICCID |
| 15 | AT+ECFACCHK=1 | EigenComm | 新增 rfa.lua 处理 + C 层扩展 | 查 NV 头 |

注：ECRFNST 的私有协议 cmdId 模板按产线工具需求通过 rfa.registerRfnst() 扩展；rfa.lua 默认输出占位响应。

### 1.3 不涉及范围（Non-goals）
- 不修改 ec7xx-at 现有 AT 固件实现。
- 不改动 PLAT 闭源预编译库中的 RfAtNstCmdPreHandle / RfAtTestCmd 内部逻辑。
- 不实现 ec7xx-at 中的扩展命令如 AT+ECRFTEST、AT+ECRFSTAT、AT+ECVERSION、AT+ECDIEXY 等（如需后续另开 PR）。
- 不替换现有产线工具，只保证 AT 协议层行为一致。

---

## 2. 现状分析

### 2.1 LuatOS 侧（框架已就绪）
- script/libs/rfa.lua：已有 7 阶段状态机、内置 AT 派发、扩展点 register / registerRfnst、UART 绑定。
- components/mobile/luat_mobile.h：已声明 6 个 luat_mobile_rf_test_* C API。
- components/mobile/luat_lib_mobile.c：已绑定 5 个 Lua API（mobile.rfTestMode/Input/Param/Imei/ImeiSet）。
- bsp/pc/port/luat_mobile_pc.c：PC 仿真后端完整实现，单元测试 testcase/utest/drv/mobile_rfa_basic/ 13 case 全过。

### 2.2 luatos-soc-2024 侧（真机后端待补齐）
- interface/src/luat_mobile_ec7xx.c 已存在：
  - luat_mobile_rf_test_input()：转发到 soc_mobile_rf_test_input()，并做 toupper()。
  - luat_mobile_rf_test_mode()：转发到 soc_mobile_rf_test_mode()。
- 尚未实现：
  - luat_mobile_rf_test_param()：需映射到 npi_config.h 的 NPI 接口。
  - luat_mobile_rf_test_imei_get()：需调用 appGetImeiNumSync()。
  - luat_mobile_rf_test_imei_set()：需调用 appSetImeiNumSync()。
  - luat_mobile_rf_test_set_rx_cb()：按头文件注释，真机无需实现，返回 0 或 -1 即可。

### 2.3 ec7xx-at 侧（参考实现）
- PLAT/middleware/developed/at/atps/src/atec_rf.c：AT+ECRFNST 调用 RfAtNstCmdPreHandle()。
- PLAT/middleware/developed/at/atcust/src/atec_product.c：AT+ECNPICFG、AT+ECGMDATA、AT+ECRFSTAT 等。
- PLAT/middleware/developed/at/atcust/src/atec_plat_dev.c：AT+ECPMUCFG。
- PLAT/middleware/developed/open_am/driver/src/am_service.c：soc_mobile_rf_test_mode/input 的实现入口，在闭源 libcore_airm2m.a 中。
- 关键底层头文件：
  - PLAT/middleware/developed/common/inc/npi_config.h
  - PLAT/middleware/developed/ecapi/psapi/inc/ps_lib_api.h
  - PLAT/driver/hal/ec7xx/ap/inc/hal_rfCali.h

---

## 3. 架构设计

### 3.1 分层架构

```
产线工具 (UART)
      |
      v
+-----------------------------+
|  script/libs/rfa.lua        |  <- Fat Lua：AT 解析、状态机、响应生成、扩展钩子
|  - AT 命令派发               |
|  - ECRFNST 私有协议模板      |
|  - 状态机 / NPI / IMEI 管理  |
+-----------------------------+
      | mobile.rfTestMode/Input/Param/Imei/ImeiSet
      v
+-----------------------------+
|  components/mobile/         |  <- Lua<-C 绑定
|  luat_lib_mobile.c          |
+-----------------------------+
      | luat_mobile_rf_test_*
      v
+-----------------------------+
|  luatos-soc-2024/interface/src/  |  <- 真机 C 适配
|  luat_mobile_ec7xx.c        |
|  - mode/input -> soc_mobile_*   |
|  - param -> npi_config      |
|  - imei -> appGet/SetImeiNumSync |
+-----------------------------+
      | soc_mobile_* / RfAtNstCmdPreHandle
      v
+-----------------------------+
|  PLAT 闭源库 / CP / PHY     |  <- RF 底层
+-----------------------------+
```

### 3.2 关键设计决策

1. 沿用 Thin C / Fat Lua：已有 rfa.lua 承担全部 AT 协议逻辑，C 端只做字节透传与 NPI/IMEI 读写，避免在 C 端重复实现 AT 状态机。
2. 真机端补齐 4 个 C API：param、imei_get、imei_set、set_rx_cb，其中 set_rx_cb 为无操作桩。
3. AT+ECRFNST 透传路径：
   - rfa.lua 收到 AT+ECRFNST=<hex> 后，对已知 cmdId 模板生成同步响应；
   - 对未知/需要底层执行的 cmdId，通过 mobile.rfTestInput() 将 hex 字节流转发给 soc_mobile_rf_test_input()，由闭源库处理并异步返回。
   - 当前 rfa.lua 默认全部生成同步占位响应；若产线工具需要真响应，需按 cmdId 扩展 registerRfnst 回调。
4. PMU/Golden/ChipVer/Band/ICCID/FACCHK：
   - 先尝试在 rfa.lua 中通过现有 mobile.* API（如 mobile.imei()、mobile.flymode()）实现；
   - 缺少的接口优先扩展 mobile.rfTestParam 的 key 集合，由 C 层调用对应 PLAT API；
   - 若 PLAT 无公开 API，则通过 mobile.rfTestInput() 走 soc_mobile_rf_test_input() 的私有通道。
5. EC718HM/EC718PM 共用同一接口文件：luat_mobile_ec7xx.c 不拆分；构建系统按 --chip_target 自动选择 PLAT/libs/ec718pm* 或 ec718hm* 预编译库。

---

## 4. 任务分解

### Phase 1：luatos-soc-2024 真机 C 实现

目标：补齐 luat_mobile_rf_test_param / imei_get / imei_set / set_rx_cb，使 mobile.rfTest* 在 EC718HM/PM 真机上可用。

文件：luatos-soc-2024/interface/src/luat_mobile_ec7xx.c

1. 包含必要头文件：
   - PLAT/middleware/developed/common/inc/npi_config.h
   - PLAT/middleware/developed/ecapi/psapi/inc/ps_lib_api.h
2. 实现 luat_mobile_rf_test_param(const char *key, int *value, int is_set)：
   - key "rfCaliDone" -> NPI_PROCESS_STATUS_ITEM_RFCALI
   - key "rfNSTDone" -> NPI_PROCESS_STATUS_ITEM_RFNST
   - key "rfCTDone" -> NPI_PROCESS_STATUS_ITEM_RFCT
   - key "state" / "erfMode" -> 本地静态变量（非持久化）
   - key "save" -> 调用 npiSaveConfigToAPNV2()（确认接口名）
   - 不支持的 key 返回 -1
3. 实现 luat_mobile_rf_test_imei_get(char *out, uint32_t len)：
   - 调用 appGetImeiNumSync(out)，确保字符串结束。
4. 实现 luat_mobile_rf_test_imei_set(const char *imei)：
   - 校验长度 15，调用 appSetImeiNumSync((char*)imei)。
5. 实现 luat_mobile_rf_test_set_rx_cb(...)：
   - 真机无需，直接返回 0。
6. 编译验证：
   cd luatos-soc-2024/project/example_mobile
   xmake f --chip_target=ec718pm
   xmake
   同样对 ec718hm 做一次编译验证。

### Phase 2：LuatOS rfa.lua 扩展

目标：支持 Excel 中的 16 条核心产线命令，并保留扩展点。

文件：LuatOS/script/libs/rfa.lua

1. 在 _builtin_dispatch 中新增：
   - AT+ECRST -> 调用 mobile.restart() 或 mobile.rfTestInput 私有通道；返回 OK 后触发复位。
   - AT+ECCGSN=<type>,<sn/imei> -> 校验类型与长度，调用 mobile.rfTestImeiSet()。
   - AT+ECGMDATA? -> 返回 Golden Unit 数据（先返回 OK 占位，后续接 Phase 4）。
   - AT+ECGMDATA=<data> -> 写入 Golden Unit 数据。
   - AT+ECCHIPVER? -> 返回芯片版本字符串。
   - AT+ECBAND=? -> 返回支持的 Band 列表。
   - AT+ECICCID -> 调用 mobile.iccid() 或等效 API。
   - AT+ECPMUCFG=<enable>[,<mode>] -> 设置 PMU 模式。
   - AT+ECPMUCFG? -> 查询 PMU 模式。
   - AT+ECFACCHK=1 -> 返回 NV 头校验结果。
2. 对 AT+ECRFNST 处理增强：
   - 保留默认占位响应；
   - 增加常见 cmdId（如 0x0D、0x0A、0x51-0x5A）的模板响应；
   - 提供 rfa.registerRfnst() 让项目级 Lua 代码注入更多模板。
3. 添加 rfa.atServerStart(id, baud) 别名（与 rfa.start 等价），便于产线工具文档对齐。

### Phase 3：LuatOS C 绑定修正（如需要）

文件：LuatOS/components/mobile/luat_lib_mobile.c

1. 检查 l_mobile_rf_test_param 的 is_set 参数处理：当前 lua_toboolean(L, 4) 对整数 0 判断为 true，需确认 rfa.lua 已用 nil/false 表示读；如需更健壮，可改为显式判断 lua_isnil/lua_isboolean。
2. 检查 LUAT_USE_MOBILE_RFA 宏在目标 BSP（如 bsp/ec7xx）中是否已打开；未打开则添加。

### Phase 4：Golden / PMU / ChipVer / Band / ICCID / FACCHK 的 C 后端（按需）

目标：若 rfa.lua 缺少对应 mobile.* API，则通过扩展 mobile.rfTestParam 或新增 C API 实现。

文件：
- LuatOS/components/mobile/luat_mobile.h（仅当新增 API 时）
- LuatOS/components/mobile/luat_lib_mobile.c
- luatos-soc-2024/interface/src/luat_mobile_ec7xx.c

1. AT+ECGMDATA：
   - 方案 A：通过 mobile.rfTestParam 新增 key "gmData"（读写 int 数组或字符串长度受限）。
   - 方案 B：新增 mobile.rfTestGmData(buf) / mobile.rfTestGmDataSet(buf) 字符串 API。
   - 推荐方案 B，因为 Golden 数据可能较长。
2. AT+ECPMUCFG：
   - 新增 mobile.rfTestParam key "pmuMode" / "pmuEnable"，C 层调用 apmuSetDeepestSleepMode() 或 PMU_SetSleepMode()。
3. AT+ECCHIPVER?：
   - 新增 mobile.rfTestParam key "chipVer"，C 层调用现有 chipver API。
4. AT+ECBAND=?：
   - 新增 mobile.rfTestParam key "bandList"，C 层返回支持的 Band 位图。
5. AT+ECICCID：
   - 优先复用 mobile.iccid()；若不可用，新增 mobile.rfTestIccid()。
6. AT+ECFACCHK=1：
   - 新增 mobile.rfTestParam key "facChk"，C 层调用 NV 头校验接口。

Phase 4 的具体命令可在进入开发后根据产线工具实际交互日志裁剪；本计划按“全部实现”排期。

### Phase 5：单元测试与集成测试

文件：
- LuatOS/testcase/utest/drv/mobile_rfa_basic/scripts/mobile_rfa_test.lua
- LuatOS/tools/rfa_com0com/test_rfa_com0com.py
- 新增：testcase/utest/drv/mobile_rfa_basic/scripts/ec718_rfa_test.lua（真机行为 mock）

1. PC 端单元测试：
   - 扩展 mobile_rfa_test.lua，覆盖新增命令（ECRST、ECCGSN、ECGMDATA、ECPMUCFG、ECBAND、ECICCID、ECFACCHK、ECCHIPVER）。
   - 验证状态机推进、IMEI 读写、NPI 保存。
2. PC 端 com0com 回归：
   - 扩展 test_rfa_com0com.py，覆盖 Excel 中的核心命令。
3. 真机测试：
   - 在 EC718HM/PM 开发板上烧录 LuatOS 固件。
   - 使用 USB/UART 连接产线工具或串口助手，验证：
     - 握手与回显
     - CFUN=0 进入飞行模式
     - CGSN 读 IMEI
     - ECCGSN 写 IMEI
     - ECGMDATA 读写
     - ECRFNST 私有协议响应
     - ECNPICFG 标志位读写与掉电保持
     - ECRST 复位
4. 产线工具对齐：
   - 用实际产线工具跑一遍校准/综测流程，对比 ec7xx-at 输出行为差异并修复。

### Phase 6：文档与落档

文件：
- LuatOS/components/mobile/README_rfa.md（更新，补充 EC718HM/PM 真机适配说明）
- LuatOS/docs/superpowers/specs/2026-06-15-ec718hm-pm-rfa-at-design.md（新增设计规格）
- LuatOS/docs/superpowers/plans/2026-06-15-ec718hm-pm-rfa-at-plan.md（本计划落档）
- LuatOS/docs/rfa/ 下同步 mirror

---

## 5. 时间线与里程碑

| 阶段 | 内容 | 预期输出 | 验收标准 |
|------|------|----------|----------|
| W1 | Phase 1：C 后端补齐 | PR 到 luatos-soc-2024 | ec718pm / ec718hm 编译通过；mobile.rfTestParam/Imei 真机可用 |
| W1-W2 | Phase 2：rfa.lua 扩展 | PR 到 LuatOS | PC 端 13+ 新增 case 全过 |
| W2 | Phase 3：C 绑定修正 | PR 到 LuatOS | 绑定参数行为与 rfa.lua 一致 |
| W2-W3 | Phase 4：扩展命令 C 后端 | PR 到 luatos-soc-2024 + LuatOS | 所有 Excel 命令在 PC/真机有响应 |
| W3 | Phase 5：测试与真机验证 | 测试报告 | com0com 回归通过；真机校准流程跑通 |
| W3-W4 | Phase 6：文档与落档 | 文档 PR | README + spec + plan 合并 |

---

## 6. 风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| npi_config.h / appGetImeiNumSync 在 ec718hm 与 ec718pm 上行为不一致 | 中 | 在两个目标上分别编译并真机验证；若 API 有差异，用宏隔离 |
| soc_mobile_rf_test_input 对长 hex 字符串（>8000 字符）有长度限制 | 中 | 与 ec7xx-at 中 ATC_ECRFNST_0_STR_MAX_LEN 对齐；超长时分片或报错 |
| AT+ECGMDATA 需要文件系统（LittleFS）支持，LuatOS 真机文件路径不同 | 中 | 复用 LuatOS io/fs API 而非直接写 /rfTestFile；PC 端用内存缓冲 |
| 产线工具对 AT+ECRFNST 响应时序敏感 | 高 | 使用逻辑分析仪/串口抓包对比 ec7xx-at 与 LuatOS 输出；必要时调整 rfa.lua 响应延迟 |
| mobile.rfTestParam 的 is_set 参数语义在 Lua/C 边界易出错 | 中 | 在 luat_lib_mobile.c 中显式判断 lua_isboolean 或 lua_isnil，拒绝整数 0/1 |
| 部分命令（ECCHIPVER、ECFACCHK、ECPMUCFG）可能依赖未公开的 PLAT API | 高 | 先在 ec7xx-at 中确认这些命令的底层调用；若无法直接调用，通过 soc_mobile_rf_test_input 私有通道透传 |

---

## 7. 验证清单

- [ ] ec718pm 目标 xmake 0 错误 0 警告。
- [ ] ec718hm 目标 xmake 0 错误 0 警告。
- [ ] PC 端 mobile_rfa_basic utest OVERALL_PASS。
- [ ] PC 端 com0com 回归覆盖 Excel 16 条命令。
- [ ] 真机 AT+CGSN=1 返回正确 IMEI。
- [ ] 真机 AT+ECCGSN=1,<imei> 写入并持久化 IMEI。
- [ ] 真机 AT+ECNPICFG? 与 AT+ECNPICFG=rfCaliDone,1 读写正常，掉电保持。
- [ ] 真机 AT+ECRFNST=<hex> 与产线工具交互无 ERROR/CRCERROR。
- [ ] 真机校准/综测流程与 ec7xx-at 行为一致。

---

## 8. 仓库与分支建议

| 仓库 | 分支 | 说明 |
|------|------|------|
| LuatOS | feature/ec718-rfa-at | rfa.lua 扩展、C 绑定修正、测试与文档 |
| luatos-soc-2024 | feature/ec718-rfa-cbackend | 真机 C 后端实现 |
| ec7xx-at | 不修改 | 仅作为参考实现和对比基准 |

---

## 9. 后续可扩展

1. 支持 AT+ECRFTEST 等 ec7xx-at 扩展命令。
2. 将 rfa.lua 状态机与 LuatOS fdb/kv 持久化对接，替代本地静态变量。
3. 多 UART 同时校准（多 DUT 并行）支持。
4. 与产线 MES 系统对接，上传校准结果。
