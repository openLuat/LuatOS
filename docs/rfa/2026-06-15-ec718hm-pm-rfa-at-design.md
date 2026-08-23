# EC718HM/EC718PM LuatOS AT 射频校准设计规格

> 日期：2026-06-15
> 关联计划：`docs/superpowers/plans/2026-06-15-ec718hm-pm-rfa-at-plan.md`

---

## 1. 背景与目标

在 LuatOS 固件中提供一套产线 AT 指令射频校准能力，使 EC718HM/EC718PM 系列模组能够直接通过 UART 接收产线工具下发的 AT 指令完成：
- 射频校准（RFCALI）
- 非信令综测（RFNST）
- 相关产线辅助操作（IMEI 读写、NPI 标志、Golden 数据、PMU 等）

设计沿用已有的 `rfa`（Radio Factory Agent）Thin C / Fat Lua 架构，C 端只做字节搬运和状态存储，所有 AT 协议逻辑由 `script/libs/rfa.lua` 完成。

---

## 2. 架构

```
产线工具 (UART)
      |
      v
+-----------------------------+
|  script/libs/rfa.lua        |  Fat Lua
|  - AT 解析 / 响应生成        |
|  - 7 阶段状态机              |
|  - ECRFNST 私有协议模板      |
|  - 扩展 register/registerRfnst|
+-----------------------------+
      | mobile.rfTestMode/Input/Param/Imei/ImeiSet/GmData/GmDataSet
      v
+-----------------------------+
|  components/mobile/         |  Lua-C 绑定
|  luat_lib_mobile.c          |
+-----------------------------+
      | luat_mobile_rf_test_*
      v
+-----------------------------+
|  luatos-soc-2024/interface/src/  | 真机 C 适配
|  luat_mobile_ec7xx.c        |
|  - mode/input -> soc_mobile_*   |
|  - param -> npi_config        |
|  - imei -> appGet/SetImeiNumSync |
|  - gmdata -> luat_fs_*        |
+-----------------------------+
      | soc_mobile_* / RfAtNstCmdPreHandle
      v
+-----------------------------+
|  PLAT 闭源库 / CP / PHY     |  RF 底层
+-----------------------------+
```

---

## 3. C 端接口

所有函数沿用 `luat_mobile_rf_test_*` 前缀，声明在 `components/mobile/luat_mobile.h`。

| 函数 | 签名 | 用途 |
|------|------|------|
| `luat_mobile_rf_test_mode` | `void(uint8_t uart_id, uint8_t on_off)` | 进入/退出 RF 测试模式，绑定 UART |
| `luat_mobile_rf_test_input` | `void(char *data, uint32_t data_len)` | 喂入字节；`data=NULL/0` 触发 flush |
| `luat_mobile_rf_test_param` | `int(const char *key, int *value, int is_set)` | 读写 NPI / state / 扩展参数 |
| `luat_mobile_rf_test_imei_get` | `int(char *out, uint32_t len)` | 读 15 位 IMEI |
| `luat_mobile_rf_test_imei_set` | `int(const char *imei)` | 写 15 位 IMEI |
| `luat_mobile_rf_test_gmdata_get` | `int(char *out, uint32_t len)` | 读 Golden Unit 数据 |
| `luat_mobile_rf_test_gmdata_set` | `int(const char *data, uint32_t len)` | 写 Golden Unit 数据 |
| `luat_mobile_rf_test_set_rx_cb` | `int(const luat_mobile_rf_test_rx_cb_t *cb)` | 注册 Rx 回调（PC 仿真用） |

### 3.1 `luat_mobile_rf_test_param` key 定义

| key | 读写 | PC 后端 | 真机后端 |
|-----|------|---------|----------|
| `rfCaliDone` | 读写 | s_rf_test 静态变量 | `NPI_PROCESS_STATUS_ITEM_RFCALI` |
| `rfNSTDone` | 读写 | s_rf_test 静态变量 | `NPI_PROCESS_STATUS_ITEM_RFNST` |
| `rfCTDone` | 读写 | s_rf_test 静态变量 | `NPI_PROCESS_STATUS_ITEM_RFCT` |
| `state` | 读写 | s_rf_test 静态变量 | 本地静态变量 |
| `erfMode` | 读写 | s_rf_test 静态变量 | 本地静态变量 |
| `pmuEnable` | 读写 | s_rf_test 静态变量 | 占位 0（待 PLAT API） |
| `pmuMode` | 读写 | s_rf_test 静态变量 | 占位 0（待 PLAT API） |
| `chipVer` | 读 | s_rf_test 静态变量 | 占位 0（待 PLAT API） |
| `bandList` | 读 | s_rf_test 静态变量 | 占位 0（待 PLAT API） |
| `facChk` | 读 | s_rf_test 静态变量 | 占位 0（待 PLAT API） |
| `save` | 写 | no-op | `npiSaveConfigToAPNV2()` |

---

## 4. Lua 端 `rfa.lua`

### 4.1 公共 API

- `rfa.start(id, baud)` / `rfa.stop()`：UART 绑定
- `rfa.dispatch(line)`：纯函数 AT 派发，返回响应字符串
- `rfa.feed(chunk)`：流式切行
- `rfa.state()` / `rfa.setState(s)` / `rfa.reset()`：状态机
- `rfa.npiGet(k)` / `rfa.npiSet(k, v)`：NPI 标志
- `rfa.imei()` / `rfa.setImei(s)`：IMEI
- `rfa.register(prefix, fn)` / `rfa.registerRfnst(cmdId, fn)`：扩展点

### 4.2 内建 AT 命令覆盖

覆盖 `EC CAT1产线校准综测相关AT命令.xlsx` 中的 16 条核心命令：

| No. | AT Command | 处理说明 |
|-----|------------|----------|
| 1 | `AT` | 握手 |
| 2 | `ATE0`/`ATE1` | 回显开关 |
| 3 | `AT+CFUN=0/1/4` | 飞行模式 |
| 4 | `AT+CPIN?` | 固定 `+CME ERROR: 303` |
| 5 | `AT+CGSN=1` | 读 IMEI |
| 6 | `AT+ECPMUCFG` | 经 `mobile.rfTestParam` 读写 pmuEnable/pmuMode |
| 7 | `AT+ECRST` | 调用 `mobile.restart()` |
| 8 | `AT+ECCGSN=1,<imei>` | 写 IMEI |
| 9 | `AT+ECNPICFG` | NPI 标志读写 |
| 10 | `AT+ECGMDATA` | 经 `mobile.rfTestGmData/GmDataSet` 读写 |
| 11 | `AT+ECCHIPVER?` | 经 `mobile.rfTestParam("chipVer")` |
| 12 | `AT+ECRFNST=<hex>` | 私有协议模板响应 |
| 13 | `AT+ECBAND=?` | 经 `mobile.rfTestParam("bandList")` |
| 14 | `AT+ECICCID` | 经 `mobile.iccid()` |
| 15 | `AT+ECFACCHK=1` | 经 `mobile.rfTestParam("facChk")` |

### 4.3 状态机

| 阶段 | 值 | 触发 |
|------|---|------|
| IDLE | 0 | 初始 / reset |
| PREP | 1 | `AT+CGSN=1` |
| CALIB | 2 | 任意 `AT+ECRFNST=...` |
| SELF_CAL | 3 | cmdId `0x0D`/`0x0A` |
| WRITE_NV | 4 | `AT+ECNPICFG=rfCaliDone,1` |
| NST_TEST | 5 | cmdId `0x51~0x5A` |
| DONE | 6 | `AT+ECNPICFG=rfNSTDone,1` |

---

## 5. 真机实现细节

### 5.1 文件
- `luatos-soc-2024/interface/src/luat_mobile_ec7xx.c`
- `luatos-soc-2024/project/project.lua`（EC718HM 构建排除 audio/i2s）

### 5.2 依赖的 PLAT API
- `npi_config.h`: `npiGetProcessStatusItemValue`, `npiSetAndSaveProcessStatusItemValue`, `npiSaveConfigToAPNV2`
- `ps_lib_api.h`: `appGetImeiNumSync`, `appSetImeiNumSync`
- `luat_fs.h`: `luat_fs_fopen/fread/fwrite/fclose`

### 5.3 未实化部分
以下命令在真机目前返回占位值，需在 PLAT 侧公开对应 API 后替换：
- `AT+ECPMUCFG` 的 PMU 模式设置
- `AT+ECCHIPVER?` 的芯片版本读取
- `AT+ECBAND=?` 的支持 Band 查询
- `AT+ECFACCHK=1` 的 NV 头校验

---

## 6. 测试

- PC 端：`testcase/utest/drv/mobile_rfa_basic/` 4 套件 42+ case
- PC 端 com0com：`tools/rfa_com0com/test_rfa_com0com.py`
- 真机端：EC718HM/PM 开发板 + 产线工具或串口助手

---

## 7. 风险

1. `soc_mobile_rf_test_input` 对长 hex 字符串可能有长度限制，需与 `ATC_ECRFNST_0_STR_MAX_LEN` 对齐。
2. `AT+ECRFNST` 产线工具对响应时序敏感，需用逻辑分析仪/串口抓包对比 ec7xx-at。
3. PMU/ChipVer/Band/FACCHK 依赖未公开 PLAT API，当前为占位实现。
4. `mobile.rfTestParam` 的 `is_set` 语义在 Lua/C 边界易出错，业务代码应使用 `rfa.lua` 封装。
