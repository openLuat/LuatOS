# exEasyUI 演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - exeasyui 主程序，负责页面管理和按键事件分发和执行exeasyui的任务调度

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - UI 组件演示模块
3. **default_font_page.lua** - 默认字体演示模块
4. **gtfont_page.lua** - GTFont 矢量字体演示模块
5. **hzfont_page.lua** - HZFont 矢量字体演示模块

### 1.3 硬件驱动模块

1. **hw_default_font_drv.lua** - LCD显示驱动配置和默认字体驱动模块，使用内置 12 号点阵字体
2. **hw_gtfont_drv.lua** - LCD显示驱动配置和GTFont 矢量字库驱动模块
3. **hw_hzfont_drv.lua** - LCD显示驱动配置和HZFont 矢量字体驱动模块
4. **hw_customer_font_drv.lua** - LCD显示驱动配置和自定义外部字体驱动模块（开发中）
5. **key_drv.lua** - 按键硬件驱动模块，负责GPIO初始化和按键事件发布

当前演示的exeasyui V1.7.0版本还不支持同时启用多种字体，仅支持选择一种字体初始化，同时启用多种字体功能正在开发中

使用 HZfont 需要使用 V2020 版本以上的 14 号或者114号固件，且 14 号或114号固件仅支持 HZfont，不支持内置12号中文字体和GTfont核心库

### 1.4 按键处理模块

1. **key_handler.lua** - 按键逻辑处理模块，负责光标管理和界面导航
- BOOT键 在可点击区域间循环切换
- 开机键 模拟点击当前中心区域

## 二、演示效果

<table>
<tr>
<td>主页<br/></td><td>组件演示页<br/></td><td>默认字体页<br/></td><td>HZFont页<br/></td><td>GTFont页<br/></td></tr>
<tr>
<td><img src="https://docs.openluat.com/cdn/image/exeasyui_home_gage.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1000组件页面.jpg" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/exeasyui_default_font_page.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/exeasyui_hzfont_page.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/exeasyui_gtfont_page.png" width="80" /><br/></td></tr>
</table>


## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHM/Air780EHV/Air780EGH 核心板 × 1
- AirLCD_1000 配件板 × 1
- GTFont 矢量字库，使用的是 AirFONTS_1000 配件板 × 1
- 母对母杜邦线 × 14，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air780EHM/Air780EHV/Air780EGH 核心板和 AirLCD_1000配件板以及AirFONTS_1000 配件板的硬件接线方式为

  - Air780EHM/Air780EHV/Air780EGH 核心板通过 TYPE-C USB 口供电（核心板正面开关拨到 ON 一端），此种供电方式下，VDD_EXT 引脚为 3.3V，可以直接给 AirLCD_1000配件板和AirFONTS_1000 配件板供电；
  - 为了演示方便，所以 Air780EHM/Air780EHV/Air780EGH 核心板上电后直接通过 VBAT 引脚给 AirLCD_1000配件板，VDD-EXT引脚给AirFONTS_1000 配件板供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

### 3.2 接线配置

#### 3.2.1 LCD 显示屏接线

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH 核心板<br/></td><td>AirLCD_1000配件板<br/></td></tr>
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
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

#### 3.2.2 GTFont 字库接线

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH 核心板<br/></td><td>AirFONTS_1000配件板<br/></td></tr>
<tr>
<td>83/SPI0_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>84/SPI0_MISO<br/></td><td>MISO<br/></td></tr>
<tr>
<td>85/SPI0_MOSI<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>86/SPI0_CLK<br/></td><td>CLK<br/></td></tr>
<tr>
<td>24/VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

#### 3.2.3 接线图
![](https://docs.openLuat.com/cdn/image/Air780EHV核心板_AirLCD_1000_AirFONTS_1000接线图.jpg)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air780EHM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EHM 1号固件
  
- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EHV 1号固件
  
- [点击下载Air780EGH系列最新版本内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EGH 1号固件


使用 HZfont 需要使用 V2020 版本以上的 14 号固件或114号固件，且 14 号固件或114号固件仅支持 HZfont
使用其他字体，demo 所使用的是 LuatOS-SoC_V2018 1 号固件

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照硬件接线表连接所有设备
2. 如使用 GTFont，需要连接 AirFONTS_1000 配件板
3. 通过 TYPE-C USB 口供电
4. 检查所有接线无误

### 5.2 软件配置

在 `main.lua` 中配置系统参数：

```lua
-- 必须加载才能启用exeasyui的功能
ui = require("exeasyui")


-- 加载lcd、tp和字库驱动管理功能模块，有以下四种：
-- 1、使用lcd内核固件中自带的12号中文字体的hw_default_font_drv，并按lcd显示驱动配置初始化
-- 2、使用hzfont核心库驱动内核固件中支持的软件矢量字库的hw_hzfont_drv.lua，并按lcd显示驱动配置初始化
-- 3、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板的hw_gtfont_drv.lua，并按lcd显示驱动配置初始化
-- 4、使用自定义字体的hw_customer_font_drv（目前开发中）
-- 最新情况可查看模组选型手册中对应型号的固件列表内，支持的核心库是否包含lcd、tp、12号中文、gtfont、hzfont，链接https://docs.openluat.com/air780epm/common/product/
-- 目前exeasyui V1.7.0版本支持使用已经实现的四种功能中的一种进行初始化，同时支持多种字体初始化功能正在开发中
require("hw_default_font_drv")
-- require("hw_hzfont_drv")
-- require("hw_gtfont_drv")
-- require("hw_customer_font_drv")开发中

-- 加载按键驱动模块
require("key_drv")

-- 加载exeassyui扩展库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、组件演示页、默认字体演示页、HZfont演示页、GTFont演示页和自定义字体演示页
require("ui_main")
```

### 5.3 驱动参数配置

在对应的驱动文件中根据实际硬件调整硬件参数：

1. **hw_default_font_drv.lua** - LCD显示驱动配置和默认字体驱动模块，使用内置 12 号点阵字体
2. **hw_gtfont_drv.lua** - LCD显示驱动配置和GTFont 矢量字库驱动模块
3. **hw_hzfont_drv.lua** - LCD显示驱动配置和HZFont 矢量字体驱动模块
4. **hw_customer_font_drv.lua** - LCD显示驱动配置和自定义外部字体驱动模块（开发中）
5. **key_drv.lua** - 按键硬件驱动模块，负责GPIO初始化和按键事件发布

### 5.4 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将图片文件随脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行
5. [点击查看Luatools 下载和详细使用](https://docs.openluat.com/air780epm/common/Luatools/)

### 5.5 功能测试

#### 5.5.1 主页面操作

1. 设备启动后显示主页面，光标自动定位在第一个按钮
2. 按BOOT键在不同按钮间切换焦点
3. 按PWR键进入对应演示页面
4. 使用返回按钮返回主页面

#### 5.5.2 组件演示页面

1. 测试进度条组件的动态更新
2. 体验复选框的状态变化
3. 查看图片轮播效果（如有图片文件）
4. 使用按键在不同组件间切换焦点

#### 5.5.3 字体演示页面

1. **默认字体页**：查看固定 12 号字体的颜色和中英文显示
2. **HZFont 页**：测试动态字体大小调整功能
3. **GTFont 页**：体验多尺寸矢量字体显示效果
4. 在各页面使用按键操作界面按钮

### 5.6 预期效果

- **系统启动**：正常初始化，显示主页面
- **字体显示**：各字体页面正常显示，动态调整功能正常
- **按键操作**：在各页面使用按键操作界面按钮

### 5.7 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **字体显示异常**：确认选择的字体驱动与硬件匹配
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：调整 `ui_main.lua` 中的刷新率参数

## 六、扩展开发

本演示 demo 所有接口都在 [exeasyUI UI 扩展库](https://docs.openluat.com/osapi/ext/exeasyui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。
