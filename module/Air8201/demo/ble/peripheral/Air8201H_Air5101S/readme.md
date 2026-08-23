## Air8201H BLE 外围设备 demo 说明

Air8201H 基于 Air780EHM 模组，未板载蓝牙，需通过 UART1 外挂 Air5101 蓝牙模块实现 BLE 功能。

## 代码使用说明

Air8201H 的 BLE 代码可直接复用 Air780EHM_Air780EHV_Air780EGH 系列的 demo，无需任何修改。

## 硬件连接

Air8201H 通过 FPC 线连接到 BTB 扩展板，再用扩展板的 UART1 引脚与 Air5101S 蓝牙开发板相连：

| Air8201H (通过BTB扩展板) | Air5101S 管脚 |
|--------------------------|--------------|
| UART1_TX                 | RX           |
| UART1_RX                 | TX           |
| GND                      | GND          |
| 4V                       | VBAT         |

## 完整代码与说明请参考

[Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S)
