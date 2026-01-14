# tp 触摸库

1、LuatOS支持tp 触摸库，tp 触摸库是 LuatOS 提供的底层触摸驱动库，负责与触摸芯片进行直接通信，获取原始触摸数据。该库支持多种主流触摸芯片，提供基础的触摸事件检测功能，是构建高级触摸应用的基础。

2、使用tp 触摸库开发的demo项目可以参考以下demo：

Air780EPM核心板+AirLCD_1010配件板：支持lcd各种组件、支持英文字体以及少量自定义的点阵中文字体、支持触摸控制

- 代码：[module/Air780EPM/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/air780epm/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[tp 触摸库在Air780EPM+AirLCD_1010上的应用](https://docs.openluat.com/air780epm/luatos/app/accessory/AirLCD_1010/lcd/)

在这个demo中，tp 触摸库的应用，详见**tp_key_drv**文件夹内的tp_drv.lua脚本文件
