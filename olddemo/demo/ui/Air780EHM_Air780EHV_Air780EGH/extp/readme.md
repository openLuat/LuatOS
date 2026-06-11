# extp 触摸扩展库

1、LuatOS支持触摸扩展库，extp 触摸扩展库是 tp 核心库功能的扩展，提供手势识别和触摸事件处理的高级功能。该库在 tp 库获取原始触摸数据的基础上，自动解析为各种手势事件，并通过统一的消息接口发布，简化了触摸应用开发和合宙量产功能板、合宙 LCD 配件板的使用。

2、使用extp  触摸扩展库开发的demo项目可以参考以下demo：

Air780EHM/Air780EHV/Air780EGH核心板+AirLCD_1010配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[extp 触摸扩展库在Air780EHV+AirLCD_1010上的应用](https://docs.openluat.com/air780ehv/luatos/app/accessory/AirLCD_1010/lcd/)
- 文档：[extp 触摸扩展库在Air780EHM+AirLCD_1010上的应用](https://docs.openluat.com/air780epm/luatos/app/accessory/AirLCD_1010/lcd/)
- 文档：[extp 触摸扩展库在Air780EGH+AirLCD_1010上的应用](https://docs.openluat.com/air780egh/luatos/app/accessory/AirLCD_1010/lcd/)

在这个demo中，extp 触摸扩展库的应用，详见**tp_key_drv**文件夹内的extp_drv.lua脚本文件

