# tp 触摸库

1、LuatOS支持tp 触摸库，tp 触摸库是 LuatOS 提供的底层触摸驱动库，负责与触摸芯片进行直接通信，获取原始触摸数据。该库支持多种主流触摸芯片，提供基础的触摸事件检测功能，是构建高级触摸应用的基础。

2、使用tp 触摸库开发的demo项目可以参考以下demo：

Air1601开发板+1024*600 分辨率横屏 5 寸 LCD+ 触摸面板：支持airui各种组件、支持矢量字体、支持触摸控制

- 代码：[Air1601/demo/ui/airui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/ui/airui)
- 文档：[lcd核心库在Air1601+5 寸 LCD上的应用](https://docs.openluat.com/air1601/luatos/app/multimedia/ui/airui/)

在这个demo中，tp 触摸库的应用，详见tp_drv.lua脚本文件

airui 是基于 LVGL 9.4 版本进行图形层封装的 LuatOS 核心库，把常用组件、事件管理、输入和基础视觉主题封装为更易上手的 Lua 接口，便于在支持 LuatOS 的设备和 PC 上统一开发。

建议使用airui来开发显示界面，airui demo参考：[Air1601/demo/ui/airui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/ui/airui)
