# AirFONTS_1000

1、AirFONTS_1000是合宙推出的一款矢量字体的配件板，其中：

- 6线插针，SPI接口；
- 关键元器件：GT5SLCD2E-1A;
- 支持GBK中文和ASCII码字符集;
- 支持16到192号的黑体字体，支持灰度显示;
- 使用gtfont 高通字库
- 适用于Air780E系列/Air8000系列/Air8101系列；

2、gtfont 高通字库是 LuatOS 的外接字库芯片驱动库，支持2023年以后生产的GT5SLCD2E-1A高通系列字库芯片，提供了矢量的字体显示功能。

3、使用gtfont 高通字库开发的demo项目可以参考以下两个demo：

Air8000核心板+AirLCD_1000配件板：支持lcd各种组件、支持矢量字体、支持物理按键控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1000/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1000/lcd)
- 文档：[exlcd 扩展库在Air8000+AirLCD_1000上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1000/lcd/)

Air8000核心板+AirLCD_1010配件板：支持lcd各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1010/lcd](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1010/lcd)
- 文档：[exlcd 扩展库在Air8000+AirLCD_1010上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1010/lcd/)

在这2个demo中，gtfont 高通字库的应用，详见如下所示脚本文件：

驱动文件：**font_drv**文件夹内的gtfont_drv.lua脚本文件

显示文件：**ui**文件夹内的gtfont_page.lua 脚本文件

**注意事项：**

1、目前已经支持内置的hzfont矢量字库，相对于外置的gtfont矢量字库来说：

- hzfont性能更优；

- hzfont没有额外的硬件成本；

- 不过，hzfont需要占用大约1.7MB的Flash空间存储字库文件；

- 字库文件可以占用内置Flash空间，也可以使用外置的存储空间（例如TF卡）；

2、以下两种情况推荐使用hzfont矢量字库：

- 当您的项目没有外置存储空间（例如TF卡），hzfont字库文件存储到内置Flash中，评估一下这种LuatOS固件中的用户二次开发可用Flash空间，如果可以满足您的项目需求，推荐使用hzfont矢量字库；

- 当您的项目有外置存储空间（例如TF卡），并且第1种情况中的LuatOS固件可用Flash空间无法满足项目需求，也可以考虑将hzfont字库文件存储到外置存储空间中，这种情况，也推荐使用hzfont矢量字库；

3、使用 HZfont 需要使用 V2020 版本以上的 14 号或者114号固件，且 14 号或114号固件仅支持 HZfont，不支持内置12号中文字体和GTfont核心库。
