# hzfont 合宙字库

1、LuatOS支持hzfont 合宙字库，hzfont核心库能高效地把常见的TTF字体转成适合LCD屏幕显示的像素图。它具备智能缓存机制，加速文本渲染；使用UTF-8自动识别中英文，支持抗锯齿处理，让字体显示更加平滑细腻。只需加载一次字体，无需复杂操作，即可流畅显示各种中英文字符，适合UI界面动态文本的高品质显示需求。

2、使用hzfont 合宙字库开发的demo项目可以参考以下demo：

Air1601开发板+1024*600 分辨率横屏 5 寸 LCD+ 触摸面板：支持airui各种组件、支持矢量字体、支持触摸控制

- 代码：[Air1601/demo/ui/airui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/ui/airui)
- 文档：[hzfont 合宙字库在Air1601+5 寸 LCD上的应用](https://docs.openluat.com/air1601/luatos/app/multimedia/ui/airui/)

在这个demo中，hzfont 合宙字库的应用，详见如下所示脚本文件：

加载字体文件： ui_main.lua脚本文件中，通过airui.font_load函数加载hzfont 字库

显示文件：airui_hzfont.lua 脚本文件，矢量字体演示页面

**注意事项：**

1、目前已经支持内置的hzfont矢量字库，相对于外置的矢量字库来说：

- hzfont性能更优；

- hzfont没有额外的硬件成本；

- 不过，hzfont需要占用大约1.7MB的Flash空间存储字库文件；

- 字库文件可以占用内置Flash空间，也可以使用外置的存储空间（例如TF卡）；

3、以下两种情况推荐使用hzfont矢量字库：

- 当您的项目没有外置存储空间（例如TF卡），hzfont字库文件存储到内置Flash中，评估一下这种LuatOS固件中的用户二次开发可用Flash空间，如果可以满足您的项目需求，推荐使用hzfont矢量字库；

- 当您的项目有外置存储空间（例如TF卡），并且第1种情况中的LuatOS固件可用Flash空间无法满足项目需求，也可以考虑将hzfont字库文件存储到外置存储空间中，这种情况，也推荐使用hzfont矢量字库；

airui 是基于 LVGL 9.4 版本进行图形层封装的 LuatOS 核心库，把常用组件、事件管理、输入和基础视觉主题封装为更易上手的 Lua 接口，便于在支持 LuatOS 的设备和 PC 上统一开发。

建议使用airui来开发显示界面，airui demo参考：[Air1601/demo/ui/airui](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/ui/airui)
