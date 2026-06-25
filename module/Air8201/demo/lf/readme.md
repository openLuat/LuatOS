## Air8201 lf demo 说明

Air8201 包含两款型号, 分别基于不同的模组:

* Air8201H 基于 Air780EHM 模组，未引出SPI, 所以无法挂载lf设备测试.
* Air8201G 基于 Air780EGH 模组，引出了SPI, 所以可以挂载lf设备测试.


## Air8201G lf 功能参考

Air8201G 使用 lf 核心库挂载外设，详细 demo 请查看：

1. **lf 核心库挂载 nor flash**：[AirSPINORFLASH_1000](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8201/demo/accessory_board/AirSPINORFLASH_1000)
   

2. **lf 核心库挂载 nand flash**：[AirSPINAND_1000](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8201/demo/accessory_board/AirSPINAND_1000)
   