# AirUI 组件演示

## 一、项目概述

本项目是基于 `AirUI` 图形用户界面库的完整组件演示程序，展示了多种 UI 组件和功能模块。每个演示模块独立运行，通过主程序 `main.lua` 统一调度管理。

## 二、项目结构

### 2.1 核心驱动模块
1.  **`main.lua`** - 主程序入口
    *   项目初始化和版本定义
    *   系统任务调度和看门狗配置
    *   演示模块的选择和加载
2.  **`lcd_drv.lua`** - LCD 显示驱动
    *   初始化 LCD 屏幕及背光
    *   配置显示参数和缓冲区
    *   初始化 AirUI 框架
3.  **`tp_drv.lua`** - 触摸面板驱动
    *   初始化 GT911 触摸控制器
    *   配置 I2C 通信和触摸回调
    *   绑定触摸设备到 AirUI 输入系统

### 2.2 基础组件演示
1.  **`airui_label.lua`** - 标签组件演示
2.  **`airui_button.lua`** - 按钮组件演示
3.  **`airui_image.lua`** - 图片组件演示
4.  **`airui_container.lua`** - 容器组件演示
5.  **`airui_bar.lua`** - （动态）进度条组件演示

### 2.3 交互组件演示
1.  **`airui_switch.lua`** - 开关组件演示
2.  **`airui_dropdown.lua`** - 下拉框组件演示
3.  **`airui_input.lua`** - 输入框和虚拟键盘演示
4.  **`airui_msgbox.lua`** - 消息框组件演示

### 2.4 布局与高级组件演示
1.  **`airui_table.lua`** - 表格组件演示
2.  **`airui_tabview.lua`** - 选项卡组件演示
3.  **`airui_win.lua`** - 窗口组件演示
4.  **`airui_switch_page.lua`** - 多页面切换功能演示
5.  **`airui_all_component.lua`** - 所有组件综合演示

### 2.5 字体渲染演示
1.  **`airui_hzfont.lua`** - HzFont 矢量字体特性演示

## 三、演示效果

<table>
<tr>
<td>组件<br/></td><td>输入法<br/></td></tr>
<tr>
<td><img src="https://docs.openLuat.com/cdn/image/AirUI_Air8000组件.png"><br/><br/></td><td><img src="https://docs.openLuat.com/cdn/image/AirUI_Air8000输入法.png"><br/></td></tr>
</table>


## 四 使用合宙 LuatOS-PC 模拟器仿真 exeasyui

### 4.1 PC 模拟器说明

- 合宙 LuatOS-PC 模拟器是一个能在 win10/win11 上模拟运行 lua 脚本的仿真软件，内置 LuatOS 内核固件，运行.lua 脚本效果与实际设备类似；
- 目前 PC 模拟器可以通过 LuaTools 工具的资源管理器进行下载，所以我们需要先下载安装 LuaTools 工具，然后再通过 LuaTools 工具来下载 LuatOS-PC 模拟器，最后通过 LuatOS-PC 模拟器运行 exeasyui 演示 demo；

### 4.2 LuatOS-PC 模拟器安装步骤

1. 点击下载：[Luatools v3 下载调试工具](https://docs.openluat.com/air780ehm/luatos/common/download/)
2. 通过 LuaTools 工具下载 LuatOS-PC 模拟器

   - LuaTools 工具安装完毕后，点击首页面左上角的--账户--打开资源下载
   - 选择-公共资源--LuatOS 的 PC 模拟器--选择最新版本 LuatOS-PC 模拟器--点击开始下载（非刷机）

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_1.png)

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_2.png)

### 4.3 下载底层固件和上层运行脚本

1. 下载运行所需固件，点击资源管理--选择 Air780EHM 的 LuatOS 固件--下载V2024版本及以上的 14/114 号固件
2. 下载本演示 demo 内所有.lua 脚本文件、images 文件夹内的图片

![](https://docs.openLuat.com/cdn/image/Air8101使用PC模拟器下载固件.png)

### 4.4 使用 LuatOS-PC 模拟器仿真 运行 exeasyui 演示 demo

1. 返回 Luatloos 工具首页，点击--项目管理测试

![](https://docs.openLuat.com/cdn/image/进入luatools项目管理测试.png)

2. 创建一个项目并命名

![](https://docs.openLuat.com/cdn/image/创建项目.png)

3. 选择固件刚才下载的固件--点击打开，路径在 Luatools 目录下 resource\LuatOS_Air780EHM\LuatOS-SoC_VXXXX_Air780EHM

![](https://docs.openLuat.com/cdn/image/Air8101选择固件.png)

4. 将下载的 demo 图片资源和.lua文件拖入到项目管理内的脚本和资源列表区域--勾选添加默认 lib--点击模拟器运行--出来的界面就是 demo 在实际设备上运行界面的仿真，可以用鼠标进行交互

![](https://docs.openLuat.com/cdn/image/Air8101PC模拟器运行.png)


1. 如需切换 demo 内的演示内容，可打开下载脚本文件中的 mian.lua 文件，将需要演示 demo 的 require 前面的注释符"--"去掉，将不需要演示 demo 的 require 前面加上注释符“--”。修改后保存代码文件，再点击模拟器运行，就会出现所 require 的 demo 对应的界面仿真。
2. 比如：需要演示下拉框组件，将 main.lua 文件中的-- require("airui_dropdown") 改为 require("airui_dropdown") ，并把其他加载的组件改为注释状态。

![](https://docs.openluat.com/cdn/image/AirUI_选择加载程序.png)


## 五、真实设备演示硬件环境

### 5.1 实际设备演示说明

- 演示所使用的是 Air780EHM 核心板
- 其他组件演示，demo 所使用的固件是 LuatOS-SoC_V2024_Air780EHM_14.soc
- 使用其他型号模块可以参考 [docs 文档](https://docs.openluat.com/)中对应型号的固件支持功能进行固件选择，按管脚说明进行接线和配置 lcd_drv.lua 和 tp_drv.lua 中的参数，然后进行烧录使用

### 5.2 硬件清单

- Air780EHM 核心板 × 1
- AirLCD_1010 触摸配件板 × 1
- TYPE-C 数据线 × 1

### 5.2 接线配置

- AirLCD_1010 触摸配件板按以下线序通过杜邦线接到Air780EHM 开发板上
- Air780EHM 核心板 正面拨杆开关打到 ON 位置
- Air780EHM 开发板通过 TYPE-C USB 口供电

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH 核心板<br/></td><td>AirLCD_1010配件板<br/></td></tr>
<tr>
<td>53/LCD_CLK<br/></td><td>SCLK/CLK<br/></td></tr>
<tr>
<td>52/LCD_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>49/LCD_RST<br/></td><td>RES/RST<br/></td></tr>
<tr>
<td>50/LCD_SDA<br/></td><td>SDA/MOS<br/></td></tr>
<tr>
<td>51/LCD_RS<br/></td><td>DC/RS<br/></td></tr>
<tr>
<td>22/GPIO1<br/></td><td>BLK<br/></td></tr>
<tr>
<td>3.3V<br/></td><td>VCC<br/></td></tr>
<tr>
<td>67/I2C1_SCL<br/></td><td>SCL<br/></td></tr>
<tr>
<td>66/I2C1_SDA<br/></td><td>SDA<br/></td></tr>
<tr>
<td>101/WAKEUP0<br/></td><td>INT<br/></td></tr>
</table>

#### 5.3 接线图
![](https://docs.openLuat.com/cdn/image/Air780EHV+AirLCD_1010.jpg)

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780ehm/common/Luatools/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EHM最新版本内核固件](https://docs.openluat.com/air780ehm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2024_Air780EHM 14/114号固件


## 七、快速开始

### 7.1 硬件准备

1. 将屏幕对准定位点插入
2. Air780EHM 开发板侧面供电开关打到 USB供电一端
3. 通过 TYPE-C USB 口供电

### 7.2 软件配置

在 `main.lua` 中选择要运行的演示模块：

```lua
-- 加载显示驱动
lcd_drv = require("lcd_drv")
-- 加载触摸驱动
tp_drv = require("tp_drv")

-- 引入演示模块（每次只选择一个运行）
-- require("airui_label") --动态更新标签演示
-- require("airui_button")  --按钮演示
-- require("airui_image")  --图片显示演示
-- require("airui_container")  --容器演示
-- require("airui_bar")  --动态进度条演示
-- require("airui_dropdown")  --下拉框演示
-- require("airui_switch")  --开关组件演示
-- require("airui_msgbox")  --消息框组件演示
-- require("airui_input")  --输入框和键盘演示
-- require("airui_tabview")  --选项卡演示
-- require("airui_table") --表格演示
-- require("airui_win")  --标签窗口演示
require("airui_all_component") --所有组件综合演示
-- require("airui_switch_page")  --页面切换演示
-- require("airui_hzfont")  --内置软件矢量字体演示
```

### 7.3 软件烧录步骤

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载本项目所有脚本文件
3. 将演示图片文件（如 `logo.jpg` ）同.lua脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行选定的演示模块


## 八、故障排除

### 8.1 常见问题及解决方案

1. **显示异常**

   - 检查 LCD 接线是否存在异常
   - 确认 lcd_drv.lua 内屏幕型号及其参数配置是否正确
2. **触摸无响应**

   - 检查 I2C 接线是否存在异常
   - 确认确认 tp_drv.lua 内触摸芯片型号配置正确
3. **字体显示异常**

   - 确认选择的字体驱动与硬件匹配
   - 检查固件版本是否支持所选字体
4. **图片无法显示**

   - 确认图片文件已正确烧录
   - 检查文件路径和名称是否正确
5. **系统运行缓慢**

   - 检查是否有过多的组件同时渲染
   - 适当调整刷新间隔时间

### 8.2 调试技巧

- 使用 `log.info()` 输出调试信息
- 检查系统内存使用情况
- 逐步启用组件排查问题

## 九、扩展开发

本演示 demo 所有接口都在 [AirUI核心库](https://docs.openluat.com/osapi/core/airui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。