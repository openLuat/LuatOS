
# exlcd 显示扩展库

1、LuatOS支持exlcd 扩展库，exlcd 扩展库是基于 lcd 核心库的二次封装，提供了更简化的屏幕管理功能，包括屏幕初始化、背光亮度等级控制、当前背光亮度等级查询、休眠/唤醒控制、休眠状态查询功能。该库旨在丰富 lcd 屏幕功能，简化合宙量产功能板、合宙 LCD 配件板的使用，减少用户代码。

2、使用exlcd 扩展库开发的demo项目可以参考以下两个demo：

Air8000核心板+AirLCD_1000配件板：支持lcd各种组件、支持矢量字体、支持物理按键控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1000/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1000/lcd)
- 文档：[exlcd 扩展库在Air8000+AirLCD_1000上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1000/lcd/)

Air8000核心板+AirLCD_1010配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[exlcd 扩展库在Air8000+AirLCD_1010上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1010/lcd/)

在这2个demo中，exlcd扩展库的应用，详见**lcd_drv**文件夹内的exlcd_drv.lua脚本文件
