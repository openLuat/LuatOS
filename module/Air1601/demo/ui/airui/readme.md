# AirUI 组件演示

## 一、项目概述

本项目是基于 `AirUI` 图形用户界面库的完整组件演示程序，展示了多种 UI 组件和功能模块。每个演示模块独立运行，通过主程序 `main.lua` 统一调度管理。

## 二、项目结构

### 2.1 核心核心驱动模块

1. main.lua - 主程序入口，负责系统初始化和任务调度
- 项目初始化和版本定义
- 系统任务调度和看门狗配置
- 演示模块的选择和加载

2. lcd_drv -LCD 显示驱动模块，基于 lcd 核心库
- 初始化 LCD 屏幕及背光
- 配置显示参数和缓冲区
- 初始化 AirUI 框架

3. tp_drv - 触摸面板驱动模块，基于 tp 核心库
- 初始化 GT911 触摸控制器
- 配置 I2C 通信和触摸回调
- 绑定触摸设备到 AirUI 输入系统

### 2.2 基础组件演示
1. airui_home.lua AirUI 演示系统主页
2. airui_label.lua -标签组件演示页面
3. airui_button.lua - 按钮组件演示页面
4. airui_image.lua - 图片组件演示页面
5. airui_container.lua- 容器组件演示页面
6. airui_bar.lua - （动态）进度条组件演示页面

### 2.3 交互组件演示
1. airui_switch.lua -开关组件演示页面
2. airui_dropdown.lua - 下拉框组件演示页面
3. airui_input.lua - 输入框组件演示页面
4. airui_msgbox.lua - 消息框组件演示页面
5. airui_game.lua- 俄罗斯方块游戏演示页面

### 2.4 布局与高级组件演示
1. airui_table_page.lua - 表格组件演示页面
2. airui_tabview.lua - 选项卡组件演示页面
3. airui_win.lua - 窗口组件演示页面
4. airui_switch_page.lua -多页面切换功能演示
5. airui_all_component.lua - 所有组件演示页面

## 三、演示效果
![](https://docs.openluat.com/air1601/luatos/app/multimedia/ui/airui/image/GmJgbSOURoLL9jxRgiBcjV2gnfg.jpg)
![](https://docs.openluat.com/air1601/luatos/app/multimedia/ui/airui/image/AyPDbVeGyoXQaaxq2lFcZjernwf.jpg)
![](https://docs.openluat.com/air1601/luatos/app/multimedia/ui/airui/image/FAoNbQWLYovlSGxZYO9cbj4Nn2c.jpg)

## 四、准备硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

## 五、准备软件环境

### 5.1 软件环境

在开始实践本示例之前，先筹备一下软件环境：

1、烧录工具：[Luatools 下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、内核固件 [Air1601 最新版本的内核固件](https://gitee.com/openLuat/LuatOS/releases/tag/v1004.air1601.release)，demo 所使用的是 LuatOS-SoC_V1004_Air1601.soc 号固件

> **注意：使用 AirUI 需要使用 V1004 版本及以上的 固件**

3、脚本文件：[点此链接下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/ui/airui)

4、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件

准备好软件环境之后，接下来查看 [Air1601 开发板使用说明](https://docs.openluat.com/air1601/product/shouce/#air1601_2)，将本篇文章中演示使用的项目文件烧录到 Air1601 开发板中，烧录固件及脚本请参考[如何使用 Luatools 烧录软件](https://docs.openluat.com/air1601/luatos/common/download/)。

### 5.2  **API 介绍**

aiui 核心库：[https://docs.openluat.com/osapi/core/airui/](https://docs.openluat.com/osapi/core/airui/)

## 六、故障排除

1. 显示异常：请检查 LCD 接线是否正确，确认对应驱动文件中的硬件参数设置无误；同时检查 I2C/DISP/BL 开关是否已拨至正确位置。
2. 触摸无响应：请检查 TP 飞线连接是否虚焊，确认对应驱动文件中的硬件参数设置无误。
3. 图片无法显示：确认图片文件已正确烧录到指定路径。