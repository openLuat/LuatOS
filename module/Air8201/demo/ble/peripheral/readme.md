## Air8201 BLE 外围设备 demo 总览

Air8201 包含两款型号，蓝牙方案不同：

* **Air8201H**：基于 Air780EHM 模组，未板载蓝牙，需通过 UART1 外挂 Air5101 蓝牙模块实现 BLE 功能
* **Air8201G**：基于 Air780EGH 模组，已板载蓝牙（板载 Air5101，通过 UART1 连接），无需外挂蓝牙模块

## 代码使用说明

* **Air8201H**：BLE 代码可直接复用 Air780EHM_Air780EHV_Air780EGH 系列的 demo，无需任何修改
* **Air8201G**：在 780EHM demo 基础上，需要额外增加以下代码：
  - `gpio.setup(27, 1)` — 打开蓝牙供电

## 子目录说明

| 目录 | 说明 |
|------|------|
| `Air8201G_Air5101S/` | Air8201G 专用 demo 代码 |
| `Air8201H_Air5101S/` | Air8201H 使用说明（代码直接复用 780EHM 系列） |

## 完整代码与说明请参考

[Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S)
