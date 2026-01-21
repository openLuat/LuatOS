
# LCD 驱动模块

1、LuatOS支持lcd核心库，lcd核心库是一个功能丰富的显示屏控制核心库，支持多种接口类型的 LCD 屏幕，包括 SPI、QSPI、RGB 等。该核心库提供了显示屏初始化、图形绘制、文本显示、图像处理、屏幕休眠、唤醒等功能；

2、使用lcd核心库开发的demo项目可以参考以下两个demo：

Air8000核心板+AirLCD_1000配件板：支持lcd各种组件、支持矢量字体、支持物理按键控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1000/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1000/lcd)
- 文档：[lcd核心库在Air8000+AirLCD_1000上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1000/lcd/)

Air8000核心板+AirLCD_1010配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[lcd核心库在Air8000+AirLCD_1010上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1010/lcd/)

在这2个demo中，lcd核心库的应用，详见如下所示脚本文件：

驱动文件： **lcd_drv**文件夹内的

- lcd_drv.lua - LCD显示驱动模块，基于lcd核心库，lcd_drv和exlcd_drv二选一使用

- exlcd_drv.lua - LCD显示驱动模块，基于exlcd扩展库，lcd_drv和exlcd_drv二选一使用

显示文件：**ui**文件夹内的

- ui_main.lua - 用户界面主控模块，管理页面切换和事件分发
- home_page.lua - 主页模块，提供应用入口和导航功能
- lcd_page.lua - LCD图形绘制演示模块
- gtfont_page.lua - GTFont矢量字体演示模块
- customer_font_page.lua - 自定义字体演示模块
