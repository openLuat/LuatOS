## Air8201 SPI demo 说明

Air8201 包含两款型号, 分别基于不同的模组:

* Air8201H 基于 Air780EHM 模组，未引出SPI, 所以无法挂载SPI设备测试.
* Air8201G 基于 Air780EGH 模组，引出了SPI, 所以可以挂载SPI设备测试.


## Air8201G SPI 功能参考

Air8201G 的 SPI 接口可挂载三种外设，详细 demo 请查看：

1. **SPI 接口挂载 nor flash**：[AirSPINORFLASH_1000](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8201/demo/accessory_board/AirSPINORFLASH_1000)
   

2. **SPI 接口挂载 nand flash**：[AirSPINAND_1000](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8201/demo/accessory_board/AirSPINAND_1000)
   

3. **SPI 接口驱动 rc522**：[AirRC522_1000](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8201/demo/accessory_board/AirRC522_1000)
   