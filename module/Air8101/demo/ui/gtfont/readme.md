# gtfont 高通字库

1、LuatOS支持gtfont 高通字库，gtfont 高通字库是 LuatOS 的外接字库芯片驱动库，支持2023年以后生产的GT5SLCD2E-1A高通系列字库芯片，提供了矢量的字体显示功能。

2、使用gtfont 高通字库开发的demo项目可以参考以下demo：

Air8101核心板+AirLCD_1020配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8101/demo/accessory_board/AirLCD_1020/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/accessory_board/AirLCD_1020/lcd)
- 文档：[gtfont 高通字库在Air8101+AirLCD_1020上的应用](https://docs.openluat.com/air8101/luatos/app/accessory/AirLCD_1020/lcd/)

在这个demo中，gtfont 高通字库的应用，详见如下所示脚本文件：

驱动文件：**font_drv**文件夹内的gtfont_drv.lua脚本文件

显示文件：**ui**文件夹内的gtfont_page.lua 脚本文件
