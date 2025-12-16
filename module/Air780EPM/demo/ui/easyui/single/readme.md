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

3. **hw_font_drv.lua** - lcd显示、tp触摸初始化驱动模块
   - 统一的硬件初始化接口
   - LCD显示参数管理
   - 触摸屏配置管理

### 2.2 基础组件演示

1. **win_label.lua** - 动态更新标签演示（实时时间显示，使用默认12号英文点阵字体）
2. **win_button.lua** - 基础按钮组件演示（使用默认12号英文点阵字体）
3. **win_toggle_button.lua** - 切换按钮演示（图标切换，使用默认12号英文点阵字体）
4. **win_progress_bar.lua** - 静态进度条演示（使用默认12号英文点阵字体）
5. **win_dyn_progress_bar.lua** - 动态进度条演示（自动往复动画，使用默认12号英文点阵字体）

### 2.3 交互组件演示

1. **win_message_box.lua** - 消息框组件演示（使用默认12号英文点阵字体）
2. **win_check_box.lua** - 复选框组件演示（使用默认12号英文点阵字体）
3. **win_combo_box.lua** - 下拉框组件演示（使用默认12号英文点阵字体）
4. **win_input.lua** - 文本输入框演示（使用默认12号英文点阵字体）
5. **win_password_input.lua** - 密码输入框演示（带显示/隐藏切换，使用默认12号英文点阵字体）
6. **win_number_input.lua** - 数字输入框演示（带增减按钮，使用默认12号英文点阵字体）

### 2.4 多媒体组件演示

1. **win_picture.lua** - 静态图片显示演示（使用默认12号英文点阵字体）
2. **win_autoplay_picture.lua** - 自动轮播图片演示（使用默认12号英文点阵字体）

### 2.5 高级功能演示

1. **win_all_component.lua** - 所有组件综合演示（带滚动功能，使用默认12号英文点阵字体）
2. **win_horizontal_slide.lua** - 横向滑动页面演示（使用默认12号英文点阵字体）
3. **win_vertical_slide.lua** - 纵向滑动页面演示（使用默认12号英文点阵字体）
4. **win_switch_page.lua** - 页面切换演示（多页面导航，使用默认12号英文点阵字体）

## 三、演示效果

<table>
<tr>
<td>组件演示1<br/></td><td>组件演示2<br/></td></tr>
<tr>
<td><img src="https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_componen1.png" width="150" /><br/></td><td><img src="https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_componen2.png" width="150" /><br/></td></tr>
</table>

## 四 使用合宙 LuatOS-PC 模拟器仿真 exeasyui

### 4.1 PC 模拟器说明

- 合宙 LuatOS-PC 模拟器是一个能在 win10/win11 上模拟运行 lua 脚本的仿真软件，内置 LuatOS 内核固件，运行.lua 脚本效果与实际设备类似；
- 目前 PC 模拟器可以通过 LuaTools 工具的资源管理器进行下载，所以我们需要先下载安装 LuaTools 工具，然后再通过 LuaTools 工具来下载 LuatOS-PC 模拟器，最后通过 LuatOS-PC 模拟器运行 exeasyui 演示 demo；

### 4.2 LuatOS-PC 模拟器安装步骤

1. 点击下载：[Luatools v3 下载调试工具](https://gitee.com/link?target=https%3A%2F%2Fluatos.com%2Fluatools%2Fdownload%2Flast)
2. 通过 LuaTools 工具下载 LuatOS-PC 模拟器

   - LuaTools 工具安装完毕后，点击首页面左上角的--账户--打开资源下载
   - 选择-公共资源--LuatOS 的 PC 模拟器--选择最新版本 LuatOS-PC 模拟器--点击开始下载（非刷机）

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_1.png)

![](https://docs.openLuat.com/cdn/image/PC模拟器下载_2.png)

### 4.3 下载底层固件和上层运行脚本

1. 下载运行所需固件，点击资源管理--选择 Air780EPM 的 LuatOS 固件--下载最新版本的 1 号固件
2. 下载本演示 demo 内所有.lua 脚本文件、images 文件夹内的图片

![](https://docs.openLuat.com/cdn/image/Air780EPM使用PC模拟器下载固件.png)

### 4.4 使用 LuatOS-PC 模拟器仿真 运行 exeasyui 演示 demo

1. 返回 Luatloos 工具首页，点击--项目管理测试

![](https://docs.openLuat.com/cdn/image/进入luatools项目管理测试.png)

2. 创建一个项目并命名

![](https://docs.openLuat.com/cdn/image/创建项目.png)

3. 选择固件刚才下载的固件--点击打开，路径在 Luatools 目录下 resource\LuatOS_Air780EHM\LuatOS-SoC_VXXXX_Air780EHM

![](https://docs.openLuat.com/cdn/image/Air780EPM选择固件.png)

4. 将下载的 demo 图片资源和.lua文件拖入到项目管理内的脚本和资源列表区域--勾选添加默认 lib--点击模拟器运行--出来的界面就是 demo 在实际设备上运行界面的仿真，可以用鼠标进行交互

![](https://docs.openLuat.com/cdn/image/Air780EPMPC模拟器运行.png)

![](https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_componen1.png)

5. 如需切换 demo 内的演示内容，可打开下载脚本文件中的 mian.lua 文件，将需要演示 demo 的 require 前面--去掉，将不需要演示 demo 的 require 前面加上--。注释掉 require 的其他 demo 文件后，再点击模拟器运行，就会出现所 require 的 demo 对应的界面仿真。
   - 比如：需要演示下拉框组件，将-- require("win_combo_box") 改为 require("win_combo_box") ，并把其他加载的组件改为注释状态。
     ![](https://docs.openLuat.com/cdn/image/exeasyui加载组件演示模块.png)


## 五、真实设备演示硬件环境

### 5.1 实际设备演示说明

- 演示所使用的是 Air780EPM 核心板与 AirLCD_1010 配件板
- 使用组件演示，demo 所使用的是 LuatOS-SoC_V2018_1 号固件
- 使用其他型号模块可以参考 [docs 文档](https://docs.openluat.com/)中对应型号的固件支持功能进行固件选择，按管脚说明进行接线和配置 hw_font_drv.lua 中的参数，然后进行烧录使用

### 5.2 硬件清单

- Air780EPM 核心板 × 1
- AirLCD_1010 触摸配件板 × 1
- 母对母杜邦线 × 11，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air780EPM 核心板和 AirLCD_1010 配件板的硬件接线方式为

  - Air780EPM 核心板通过 TYPE-C USB 口供电（核心板正面开关拨到 ON 一端），此种供电方式下，VBAT 引脚为 3.3V，可以直接给 AirLCD_1010 配件板供电；
  - 为了演示方便，所以 Air780EPM 核心板上电后直接通过 VBAT 引脚给 AirLCD_1010 配件板供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；
  
### 5.2 接线配置

#### 5.2.1 显示屏接线

<table>
<tr>
<td>Air780EPM 核心板<br/></td><td>AirLCD_1010配件板<br/></td></tr>
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
<td>VBAT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>67/I2C1_SCL<br/></td><td>SCL<br/></td></tr>
<tr>
<td>66/I2C1_SDA<br/></td><td>SDA<br/></td></tr>
<tr>
<td>19/GPIO22<br/></td><td>INT<br/></td></tr>
</table>

### 5.3 接线图
![](https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1010接线图.jpg)

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EPM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EPMM 1号固件

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
```

### 7.3 软件烧录步骤

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载本项目所有脚本文件和图片文件
3. 将演示图片文件（如 `1.jpg`、`2.jpg` 等）同.lua脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行选定的演示模块
5. [点击查看Luatools 下载和详细使用](https://docs.openluat.com/air780epm/common/Luatools/)

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
3. **图片无法显示**

   - 确认图片文件已正确烧录
   - 检查文件路径和名称是否正确
4. **系统运行缓慢**

   - 检查是否有过多的组件同时渲染
   - 适当调整刷新间隔时间

### 9.2 调试技巧

- 使用 `log.info()` 输出调试信息
- 检查系统内存使用情况
- 逐步启用组件排查问题

## 十、扩展开发

本演示 demo 所有接口都在 [exeasyUI UI 扩展库](https://docs.openluat.com/osapi/ext/exeasyui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。