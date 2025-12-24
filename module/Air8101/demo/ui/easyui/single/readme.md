# exEasyUI 组件演示

## 一、项目概述

本项目是基于 exEasyUI 图形用户界面库的完整组件演示程序，展示了 20 种不同的 UI 组件和功能模块。每个演示模块独立运行，通过主程序统一调度管理。

## 二、演示模块列表

### 2.1 系统核心模块

1. **main.lua** - 主程序入口模块
   - 项目初始化和版本定义
   - 系统任务调度和管理
   - 看门狗配置和系统监控
   - 演示模块的选择和加载
   - 提供统一的程序启动入口

2. **ui_main.lua** - 用户界面主控模块
   - 多页面管理和切换逻辑
   - 触摸事件分发和处理
   - 界面渲染调度
   - 主题管理和配置
   - 提供完整的用户交互体验

3. **hw_font_drv.lua** - 硬件字体驱动模块
   - 统一的硬件初始化接口
   - 支持多种字体后端配置
   - LCD显示参数管理
   - 触摸屏配置管理
   - 字体渲染引擎初始化

### 2.2 基础组件演示

1. **win_label.lua** - 动态更新标签演示（实时时间显示，使用默认字体）
2. **win_button.lua** - 基础按钮组件演示（使用默认字体）
3. **win_toggle_button.lua** - 切换按钮演示（图标切换，使用默认字体）
4. **win_progress_bar.lua** - 静态进度条演示（使用默认字体）
5. **win_dyn_progress_bar.lua** - 动态进度条演示（自动往复动画，使用默认字体）

### 2.3 交互组件演示

1. **win_message_box.lua** - 消息框组件演示（使用默认字体）
2. **win_check_box.lua** - 复选框组件演示（使用默认字体）
3. **win_combo_box.lua** - 下拉框组件演示（使用默认字体）
4. **win_input.lua** - 文本输入框演示（使用默认字体）
5. **win_password_input.lua** - 密码输入框演示（带显示/隐藏切换，使用默认字体）
6. **win_number_input.lua** - 数字输入框演示（带增减按钮，使用默认字体）

### 2.4 多媒体组件演示

1. **win_picture.lua** - 静态图片显示演示（使用默认字体）
2. **win_autoplay_picture.lua** - 自动轮播图片演示（使用默认字体）

### 2.5 高级功能演示

1. **win_all_component.lua** - 所有组件综合演示（带滚动功能，使用默认字体）
2. **win_horizontal_slide.lua** - 横向滑动页面演示（使用默认字体）
3. **win_vertical_slide.lua** - 纵向滑动页面演示（使用默认字体）
4. **win_switch_page.lua** - 页面切换演示（多页面导航，使用默认字体）

### 2.6 字体渲染演示

1. **win_hzfont.lua** - 内置HzFont矢量字体演示（目前Air8101支持HZFont的固件正在开发中）
2. **win_gtfont.lua** - 外置矢量字体演示（GTFont，需要 AirFONTS_1000 配件板）

## 三、演示效果

<table>
<tr>
<td>组件样式<br/></td><td>输入法<br/></td></tr>
<tr>
<td><img src="https://docs.openLuat.com/cdn/image/exeasyui_AirLCD_1020_component.png" width="150" /><br/></td><td><img src="https://docs.openLuat.com/cdn/image/exeasyui_input.png" width="150" /><br/></td></tr>
</table>

<table>
<tr>
<td>下拉框<br/></td><td>消息框<br/></td></tr>
<tr>
<td><img src="https://docs.openLuat.com/cdn/image/exeasyui_combo_box.png" width="150" /><br/></td><td><img src="https://docs.openLuat.com/cdn/image/exeasyui_message_box.png" width="150" /><br/></td></tr>
</table>

## 四 使用合宙 LuatOS-PC 模拟器仿真 exeasyui

### 4.1 PC 模拟器说明

- 合宙 LuatOS-PC 模拟器是一个能在 win10/win11 上模拟运行 lua 脚本的仿真软件，内置 LuatOS 内核固件，运行.lua 脚本效果与实际设备类似；
- 目前 PC 模拟器可以通过 LuaTools 工具的资源管理器进行下载，所以我们需要先下载安装 LuaTools 工具，然后再通过 LuaTools 工具来下载 LuatOS-PC 模拟器，最后通过 LuatOS-PC 模拟器运行 exeasyui 演示 demo；

### 4.2 LuatOS-PC 模拟器安装步骤

1. 点击下载：[Luatools v3 下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)
2. 通过 LuaTools 工具下载 LuatOS-PC 模拟器

   - LuaTools 工具安装完毕后，点击首页面左上角的--账户--打开资源下载
   - 选择-公共资源--LuatOS 的 PC 模拟器--选择最新版本 LuatOS-PC 模拟器--点击开始下载（非刷机）

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_1.png)

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_2.png)

### 4.3 下载底层固件和上层运行脚本

1. 下载运行所需固件，点击资源管理--选择 Air8101 的 LuatOS 固件--下载最新版本的 1 号固件
2. 下载本演示 demo 内所有.lua 脚本文件、images 文件夹内的图片

![](https://docs.openLuat.com/cdn/image/Air8101使用PC模拟器下载固件.png)

### 4.4 使用 LuatOS-PC 模拟器仿真 运行 exeasyui 演示 demo

1. 返回 Luatloos 工具首页，点击--项目管理测试

![](https://docs.openLuat.com/cdn/image/进入luatools项目管理测试.png)

2. 创建一个项目并命名

![](https://docs.openLuat.com/cdn/image/创建项目.png)

3. 选择固件刚才下载的固件--点击打开，路径在 Luatools 目录下 resource\LuatOS_Air8101\LuatOS-SoC_VXXXX_Air8101

![](https://docs.openLuat.com/cdn/image/Air8101选择固件.png)

4. 将下载的 demo 图片资源和.lua文件拖入到项目管理内的脚本和资源列表区域--勾选添加默认 lib--点击模拟器运行--出来的界面就是 demo 在实际设备上运行界面的仿真，可以用鼠标进行交互

![](https://docs.openLuat.com/cdn/image/Air8101PC模拟器运行.png)

![](https://docs.openLuat.com/cdn/image/模拟器仿真界面.png)

5. 如需切换 demo 内的演示内容，可打开下载脚本文件中的 mian.lua 文件，将需要演示 demo 的 require 前面--去掉，将不需要演示 demo 的 require 前面加上--。注释掉 require 的其他 demo 文件后，再点击模拟器运行，就会出现所 require 的 demo 对应的界面仿真。
   - 比如：需要演示下拉框组件，将-- require("win_combo_box") 改为 require("win_combo_box") ，并把其他加载的组件改为注释状态。
     ![](https://docs.openLuat.com/cdn/image/PC模拟器使用_2.png)


## 五、真实设备演示硬件环境

### 5.1 实际设备演示说明

- 演示所使用的是 Air8101 核心板与 AirFONTS_1000 配件板
- 使用 HZfont目前还没有支持的固件
- 其他组件演示，demo 所使用的固件是 LuatOS-SoC_V1006_Air8101_1.soc
- 使用其他型号模块可以参考 [docs 文档](https://docs.openluat.com/)中对应型号的固件支持功能进行固件选择，按管脚说明进行接线和配置 hw_font_drv.lua 中的参数，然后进行烧录使用

### 5.2 硬件清单

- Air8101 核心板 × 1
- AirLCD_1020 触摸配件板 × 1
- GTFont 矢量字库，使用的是 AirFONTS_1000 配件板 × 1
- 双排40PIN的双头线 x 1
- 母对母杜邦线 × 6，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air8101 核心板和 AirLCD_1020配件板以及AirFONTS_1000 配件板的硬件接线方式为

  - Air8101 核心板通过 TYPE-C USB 口供电（核心板背面的功耗测试开关拨到 OFF 一端,正面开关打到 3.3V 一端），此种供电方式下，vbat 引脚为 3.3V，可以直接给 AirLCD_1020配件板和AirFONTS_1000 配件板供电；
  - 为了演示方便，所以 Air8101 核心板上电后直接通过 vbat 引脚给 AirLCD_1020配件板和AirFONTS_1000 配件板提供了 3.3V 的供电；
  - 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给LCD和TP供电，这样可以灵活地控制供电，可以使项目的整体功耗降到最低；
  - 核心板和配件板之间配备了双排40PIN的双头线，可以参考下表很方便地连接双方各自的40个管脚，插入或者拔出双头线时，要慢慢的操作，防止将排针折弯；

### 5.2 接线配置

#### 5.2.1 显示屏接线

<table>
<tr>
<td>Air8101核心板<br/></td><td>AirLCD_1020配件板<br/></td></tr>
<tr>
<td>gnd<br/></td><td>GND<br/></td></tr>
<tr>
<td>vbat<br/></td><td>VCC<br/></td></tr>
<tr>
<td>42/R0<br/></td><td>RGB_R0<br/></td></tr>
<tr>
<td>40/R1<br/></td><td>RGB_R1<br/></td></tr>
<tr>
<td>43/R2<br/></td><td>RGB_R2<br/></td></tr>
<tr>
<td>39/R3<br/></td><td>RGB_R3<br/></td></tr>
<tr>
<td>44/R4<br/></td><td>RGB_R4<br/></td></tr>
<tr>
<td>38/R5<br/></td><td>RGB_R5<br/></td></tr>
<tr>
<td>45/R6<br/></td><td>RGB_R6<br/></td></tr>
<tr>
<td>37/R7<br/></td><td>RGB_R7<br/></td></tr>
<tr>
<td>46/G0<br/></td><td>RGB_G0<br/></td></tr>
<tr>
<td>36/G1<br/></td><td>RGB_G1<br/></td></tr>
<tr>
<td>47/G2<br/></td><td>RGB_G2<br/></td></tr>
<tr>
<td>35/G3<br/></td><td>RGB_G3<br/></td></tr>
<tr>
<td>48/G4<br/></td><td>RGB_G4<br/></td></tr>
<tr>
<td>34/G5<br/></td><td>RGB_G5<br/></td></tr>
<tr>
<td>49/G6<br/></td><td>RGB_G6<br/></td></tr>
<tr>
<td>33/G7<br/></td><td>RGB_G7<br/></td></tr>
<tr>
<td>50/B0<br/></td><td>RGB_B0<br/></td></tr>
<tr>
<td>32/B1<br/></td><td>RGB_B1<br/></td></tr>
<tr>
<td>51/B2<br/></td><td>RGB_B2<br/></td></tr>
<tr>
<td>31/B3<br/></td><td>RGB_B3<br/></td></tr>
<tr>
<td>52/B4<br/></td><td>RGB_B4<br/></td></tr>
<tr>
<td>30/B5<br/></td><td>RGB_B5<br/></td></tr>
<tr>
<td>53/B6<br/></td><td>RGB_B6<br/></td></tr>
<tr>
<td>29/B7<br/></td><td>RGB_B7<br/></td></tr>
<tr>
<td>28/DCLK<br/></td><td>RGB_DCLK<br/></td></tr>
<tr>
<td>54/DISP<br/></td><td>RGB_DISP<br/></td></tr>
<tr>
<td>55/HSYN<br/></td><td>RGB_HSYNC<br/></td></tr>
<tr>
<td>56/VSYN<br/></td><td>RGB_VSYNC<br/></td></tr>
<tr>
<td>57/DE<br/></td><td>RGB_DE<br/></td></tr>
<tr>
<td>14/GPIO8<br/></td><td>LCD_BL<br/></td></tr>
<tr>
<td>13/GPIO9<br/></td><td>LCD_RST<br/></td></tr>
<tr>
<td>8/GPIO5<br/></td><td>LCD_SDI<br/></td></tr>
<tr>
<td>9/GPIO6<br/></td><td>LCD_SCL<br/></td></tr>
<tr>
<td>68/GPIO12<br/></td><td>LCD_CS<br/></td></tr>
<tr>
<td>75/GPIO28<br/></td><td>TP_RST<br/></td></tr>
<tr>
<td>10/GPIO7<br/></td><td>TP_INT<br/></td></tr>
<tr>
<td>12/U1TX<br/></td><td>TP_SCL<br/></td></tr>
<tr>
<td>11/U1RX<br/></td><td>TP_SDA<br/></td></tr>
</table>

#### 5.2.2 GTFont 字库接线

<table> 
<tr> <td>Air8101 核心板</td><td>AirFONTS_1000配件板</td></tr>
 <tr> <td>66/GPIO3</td><td>CS</td></tr> 
 <tr> <td>67/GPIO4</td><td>MOSI</td></tr> 
 <tr> <td>8/GPIO5</td><td>MISO</td></tr> 
 <tr> <td>65/GPIO2</td><td>CLK</td></tr> 
 <tr> <td>vbat</td><td>VCC</td></tr> 
</table>

#### 5.2.3 接线图
![](https://docs.openLuat.com/cdn/image/Air8101_AirLCD_1020_AirFONTS_1000接线图.jpg)

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air8101最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，demo所使用的是LuatOS-SoC_V1006_Air8101 1号固件


## 七、快速开始

### 7.1 硬件准备

1. 按照硬件接线表连接所有设备
2. 如使用 GTFont 演示，需要连接 AirFONTS_1000  配件板
3. 通过 TYPE-C USB 口供电
4. 检查所有接线无误

### 7.2 软件配置

在 `main.lua` 中选择要运行的演示模块：

```lua
-- 必须加载才能启用exeasyui的功能
ui = require("exeasyui")

-- 加载显示、触摸和字体驱动模块
hw_font_drv = require("hw_font_drv")

-- 引入演示模块
-- 使用哪个加载哪个，每次选择加载一个；
-- require("win_label") --动态更新标签演示
-- require("win_button")  --基础按钮组件演示
-- require("win_toggle_button")  --切换按钮演示
-- require("win_progress_bar")  --静态进度条演示
-- require("win_dyn_progress_bar")  --动态进度条演示
-- require("win_message_box")  --消息框组件演示
-- require("win_check_box")  --复选框组件演示
-- require("win_picture")  --静态图片显示演示
-- require("win_autoplay_picture")  --自动轮播图片演示
-- require("win_combo_box")  --下拉框组件演示
-- require("win_input")  --文本输入框演示
-- require("win_password_input")  --密码输入框演示
-- require("win_number_input")  --数字输入框演示
require("win_all_component")  --所有组件综合演示
-- require("win_horizontal_slide")  --横向滑动页面演示
-- require("win_vertical_slide")  --纵向滑动页面演示
-- require("win_switch_page")  --页面切换演示
-- require("win_hzfont")  --内置软件矢量字体演示
-- require("win_gtfont")  --外置硬件矢量字体演示
```

### 7.3 软件烧录步骤

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载本项目所有脚本文件
3. 将演示图片文件（如 `1.jpg`、`2.jpg` 等）同.lua脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行选定的演示模块

## 八、演示效果说明

### 8.1 组件功能特点

- **响应式设计**：所有组件支持触摸交互
- **主题支持**：支持浅色/深色主题切换
- **滚动功能**：支持横向和纵向滚动页面
- **动态更新**：支持实时数据更新显示
- **事件处理**：完整的触摸和点击事件处理

## 九、故障排除

### 9.1 常见问题及解决方案

1. **显示异常**

   - 检查 LCD 接线是否存在异常
   - 确认 hw_font_drv.lua 内屏幕型号及其参数配置是否正确
2. **触摸无响应**

   - 检查 I2C 接线是否存在异常
   - 确认确认 hw_font_drv.lua 内触摸芯片型号配置正确
3. **字体显示异常**

   - 确认选择的字体驱动与硬件匹配
   - 检查固件版本是否支持所选字体
4. **图片无法显示**

   - 确认图片文件已正确烧录
   - 检查文件路径和名称是否正确
5. **系统运行缓慢**

   - 检查是否有过多的组件同时渲染
   - 适当调整刷新间隔时间

### 9.2 调试技巧

- 使用 `log.info()` 输出调试信息
- 检查系统内存使用情况
- 逐步启用组件排查问题

## 十、扩展开发

本演示 demo 所有接口都在 [exeasyUI UI 扩展库](https://docs.openluat.com/osapi/ext/exeasyui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。