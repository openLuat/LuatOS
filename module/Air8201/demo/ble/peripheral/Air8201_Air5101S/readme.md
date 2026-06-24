## Air8201 BLE 外围设备 demo 说明

Air8201 包含两款型号, 蓝牙方案不同:

* **Air8201H**：基于 Air780EHM 模组, 未板载蓝牙, 需通过 UART 外挂 Air5101 蓝牙模块实现 BLE 功能;
* **Air8201G**：基于 Air780EGH 模组, 已板载蓝牙(板载 Air5101, 通过 UART2 连接), 无需外挂蓝牙模块。

## 代码使用说明

* **Air8201H**：BLE 代码可直接复用 Air780EHM_Air780EHV_Air780EGH 系列的 demo;
* **Air8201G**：在上述 demo 基础上, 调用 `exril_5101.config_uart(2)` 将 uart_id 改为 2(因板载 Air5101 通过 UART2 连接)。

## 硬件连接

* **Air8201H**：通过 FPC 线连接到 BTB 扩展板, 再用扩展板的 UART1 引脚与 Air5101S 蓝牙开发板相连;
* **Air8201G**：无需外挂 Air5101S, 直接用裸板测试即可。

## 完整代码与说明请参考

[Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/ble/peripheral/Air780EHM_Air5101S)
