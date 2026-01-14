# AirFONTS_1000

1、AirFONTS_1000是合宙推出的一款矢量字体的配件板，其中：

- 6线插针，SPI接口；
- 关键元器件：GT5SLCD2E-1A;
- 支持GBK中文和ASCII码字符集;
- 支持16到192号的黑体字体，支持灰度显示;
- 使用gtfont 高通字库
- 适用于Air780E系列/Air8000系列/Air8101系列；

2、gtfont 高通字库是 LuatOS 的外接字库芯片驱动库，支持2023年以后生产的GT5SLCD2E-1A高通系列字库芯片，提供了矢量的字体显示功能。

3、使用gtfont 高通字库开发的demo项目可以参考以下demo：

Air8101核心板+AirLCD_1020配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8101/demo/accessory_board/AirLCD_1020/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/accessory_board/AirLCD_1020/lcd)
- 文档：[gtfont 高通字库在Air8101+AirLCD_1020上的应用](https://docs.openluat.com/air8101/luatos/app/accessory/AirLCD_1020/lcd/)

在这个demo中，gtfont 高通字库的应用，详见如下所示脚本文件：

驱动文件：**font_drv**文件夹内的gtfont_drv.lua脚本文件

显示文件：**ui**文件夹内的gtfont_page.lua 脚本文件
