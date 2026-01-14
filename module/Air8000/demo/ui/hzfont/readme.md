# hzfont 合宙字库

1、LuatOS支持hzfont 合宙字库，hzfont核心库能高效地把常见的TTF字体转成适合LCD屏幕显示的像素图。它具备智能缓存机制，加速文本渲染；使用UTF-8自动识别中英文，支持抗锯齿处理，让字体显示更加平滑细腻。只需加载一次字体，无需复杂操作，即可流畅显示各种中英文字符，适合UI界面动态文本的高品质显示需求。

2、使用hzfont 合宙字库开发的demo项目可以参考以下两个demo：

Air8000核心板+AirLCD_1000配件板：支持exeasyui各种组件、支持矢量字体、支持物理按键控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1000/exeasyui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1000/exeasyui)
- 文档：[hzfont 合宙字库在Air8000+AirLCD_1000上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1000/exeasyui/)

Air8000核心板+AirLCD_1010配件板：支持exeasyui各种组件、支持矢量字体、支持触摸控制

- 代码：[module/Air8000/demo/accessory_board/AirLCD_1010/exeasyui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/accessory_board/AirLCD_1010/exeasyui)
- 文档：[hzfont 合宙字库在Air8000+AirLCD_1010上的应用](https://docs.openluat.com/air8000/luatos/app/accessory/AirLCD_1010/exeasyui/)

在这2个demo中，hzfont 合宙字库的应用，详见如下所示脚本文件：

驱动文件： **hw_drv** 文件夹内的hw_hzfont_drv.lua脚本文件

显示文件：**ui**文件夹内的hzfont_page.lua 脚本文件

**注意事项：**

1、使用 HZfont 需要使用 V2020 版本以上的 14 号或者114号固件，且 14 号或114号固件仅支持 HZfont，不支持内置12号中文字体和GTfont核心库。

2、目前已经支持内置的hzfont矢量字库，相对于外置的gtfont矢量字库来说：

- hzfont性能更优；

- hzfont没有额外的硬件成本；

- 不过，hzfont需要占用大约1.7MB的Flash空间存储字库文件；

- 字库文件可以占用内置Flash空间，也可以使用外置的存储空间（例如TF卡）；

3、以下两种情况推荐使用hzfont矢量字库：

- 当您的项目没有外置存储空间（例如TF卡），hzfont字库文件存储到内置Flash中，评估一下这种LuatOS固件中的用户二次开发可用Flash空间，如果可以满足您的项目需求，推荐使用hzfont矢量字库；

- 当您的项目有外置存储空间（例如TF卡），并且第1种情况中的LuatOS固件可用Flash空间无法满足项目需求，也可以考虑将hzfont字库文件存储到外置存储空间中，这种情况，也推荐使用hzfont矢量字库；

