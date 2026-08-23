## Air8201G BLE 外围设备 demo 说明

本 demo 基于 Air780EHM_Air780EHV_Air780EGH 系列的 BLE peripheral demo，针对 Air8201G 做了以下适配：

1. **打开蓝牙供电**：`gpio.setup(27, 1)` — GPIO27 控制 Air5101S 供电的 LDO，需拉高打开蓝牙供电

## 与 Air780EHM 原始代码的差异

| 差异项 | Air780EHM (原始) | Air8201G (本demo) |
|--------|-----------------|-------------------|
| 蓝牙供电 GPIO | 无 | `gpio.setup(27, 1)` |


