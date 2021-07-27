# LVGL for LuatOS 手册

[toc]

# 简介

## 为何是LVGL

LVGL是一个开源的图形库，它提供了创建嵌入式GUI所需的一切，具有易于使用的图形元素、漂亮的视觉效果和低内存占用。

**LVGL特点：**

- 强大的[构建基块](https://docs.lvgl.io/master/widgets/index.html)：按钮、图表、列表、滑块、图像等
- 高级图形引擎：动画、抗锯齿、不透明、平滑滚动、混合模式等
- 支持[各种输入设备](https://docs.lvgl.io/master/overview/indev.html)：触摸屏、鼠标、键盘、编码器、按钮等
- 支持[多个显示器](https://docs.lvgl.io/master/overview/display.html)
- 硬件独立，可与任何微控制器和显示器一起使用
- 可扩展，可在小内存下操作（64 kB 闪存，16 kB RAM）
- 具有 UTF-8 处理、CJK、双向和阿拉伯语脚本支持的多语言支持
- 通过类似[CSS样式的](https://docs.lvgl.io/master/overview/style.html)完全可自定义的图形元素
- 支持操作系统、外部内存和 GPU，但不是必需的
- 即使单[帧缓冲区](https://docs.lvgl.io/master/porting/display.html)也具有平滑渲染
- 用 C 书写，与C++兼容
- 无需嵌入式硬件即可在 PC 上开发[模拟器](https://docs.lvgl.io/master/get-started/pc-simulator.html)
- 100+ 简单[示例](https://github.com/lvgl/lvgl/tree/master/examples)
- 在线和 PDF 中[的文件](http://docs.lvgl.io/)和 API 参考

LVGL官方支持C语言和MicroPython两种语言开发，LuatOS-Soc使用7.11版本的LVGL源码为基础制作了lua版本的LVGL，使您在使用LuatOS-Soc为您带来快速开发体验的同事，也能快速，高效的开发出漂亮的图形界面。

## 设备要求

基本上，大部分控制器（需要能够驱动显示屏）都适合运行 LVGL。最低要求是：

|  | 最小                         | 推荐     |
| :--: | :--------------------------: | :------: |
| 架构: | 16、32或64位微控制器或处理器           ||
| 时钟频率: | \> 16 MHz                    | > 48 MHz |
| Flash/ROM: | > 64 kB                      | \> 180 kB |
| RAM: | \> 16 kB | \> 48 kB |
| 显示缓冲区: | \> 1 ×水平分辨率像素 | \> 1/10屏幕辨率像素 |
| 编译器: | C99 或更新           ||

***注意：内存使用情况可能会因架构、编译器和构建选项有所差异。***

## 寻求帮助

在使用LVGL中如遇到问题可在[Issues](https://gitee.com/openLuat/LuatOS/issues)，[合宙社区](https://doc.openluat.com/home)以及[LVGL官方论坛](https://forum.lvgl.io/)上进行提问，也可进行bug反馈或向我们提建议，我们会及时做出回复。

# LVGL基础

## 写个HelloWorld

程序员学习语言的第一堂课就是HelloWorld，这里也使用显示HelloWorld的示例程序来让您直观的感受到它的方便：

```lua
lvgl.init(480,320)--lvgl初始化
local label = lvgl.label_create(nil, nil)--创建标签label
lvgl.label_set_text(label, "HelloWorld")--设置标签内容
lvgl.scr_load(label)--加载标签
```

运行效果：

![helloworld](images/helloworld.png)



是不是很简单？并且和c很像对吧？下面我们就说一下LuatOS版本的LVGL接口与C版本的区别

## LuatOS版本的LVGL接口

lua版本的lvgl已经做了大部分接口，并会不断地完善后续接口，总体来说，只要将原接口开头的LV_替换成lvgl.即可，但也有特例，比如不支持init方式创建组件，使用create来创建，还有字体设置以及lvgl符号等也有一些区别

## 常用概念



## 布局

lvgl布局要有图层概念，这就引入了父对象子对象以及前后台概念

## 事件模型

LVGL中可使用事件来进行进行交互。

## 样式

*样式*用于设置对象的外观。

# LVGL组件

## 速览

## 基础对象

lvgl首先要有对象(obj)的概念，也叫组件(WIDGETS)，即按钮，标签，图像，列表，图表或文本区域等等，他们有统一的基本属性:

- Position (位置)
- Size (尺寸)
- Parent (父母)
- Drag enable (拖动启用)
- Click enable (单击启用)
- position (位置)
- ...

我们可以通过`lvgl.obj_set_xxx`设置对象的xxx属性，通过`lvgl.obj_get_xxx`来获取xxx属性

下面我们通过代码直观的理解,以刚才的HelloWorld为例，我们在上面添加`lvgl.obj_set_pos`来设置位置，`lvgl.obj_set_size`来设置大小，`lvgl.obj_set_size`来设置大小，`lvgl.obj_set_click`来设置是否可以点击：

```lua
local label = lvgl.label_create(nil, nil)
lvgl.label_set_text(label, "HelloWorld")
lvgl.obj_set_pos(label, 200, 100);
lvgl.obj_set_size(label, 480, 172);
lvgl.obj_set_click(label, false);
lvgl.scr_load(label)
```

运行效果：

![helloworldobj](images/helloworldobj.png)

在面向对象的思想中，可以做到继承，这样可以减少代码重复。



## 圆弧

## 进度条

## 按钮

## 按钮矩阵

## 日历

## 画布

## 复选框

## 图表

## 容器

## 颜色选择器

## 下拉列表

## 仪表

## 图片

## 图片按钮

## 键盘

## 标签

## LED

## 线

## 列表

## 线表

## 消息框

## 对象掩盖

## 页面

## 滚轮

## 滑块

## 旋转器

## 微调器

## 开关

## 表格

## 标签视图

## 文本视图

## 平铺视图

## 窗口

# LVGL进阶

## 动画

## 主题

## 文件系统

## 输入设备

## 字体



## 显示设备

# 注意事项

