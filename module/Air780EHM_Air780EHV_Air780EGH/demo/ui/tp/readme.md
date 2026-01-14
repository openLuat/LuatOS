# tp 触摸库

1、LuatOS支持tp 触摸库，tp 触摸库是 LuatOS 提供的底层触摸驱动库，负责与触摸芯片进行直接通信，获取原始触摸数据。该库支持多种主流触摸芯片，提供基础的触摸事件检测功能，是构建高级触摸应用的基础。

2、使用tp 触摸库开发的demo项目可以参考以下demo：

Air780EHM/Air780EHV/Air780EGH核心板+AirLCD_1010配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[tp 触摸库在Air780EHV+AirLCD_1010上的应用](https://docs.openluat.com/air780ehv/luatos/app/accessory/AirLCD_1010/lcd/)
- 文档：[tp 触摸库在Air780EHM+AirLCD_1010上的应用](https://docs.openluat.com/air780epm/luatos/app/accessory/AirLCD_1010/lcd/)
- 文档：[tp 触摸库在Air780EGH+AirLCD_1010上的应用](https://docs.openluat.com/air780egh/luatos/app/accessory/AirLCD_1010/lcd/)

在这个demo中，tp 触摸库的应用，详见**tp_key_drv**文件夹内的tp_drv.lua脚本文件
