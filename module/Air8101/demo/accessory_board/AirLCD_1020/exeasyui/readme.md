# exEasyUI 演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - exeasyui 主程序，负责执行exeasyui的任务调度

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - UI 组件演示模块
3. **default_font_page.lua** - 默认字体演示模块
4. **gtfont_page.lua** - GTFont 矢量字体演示模块
5. **hzfont_page.lua** - HZFont 矢量字体演示模块

### 1.3 硬件驱动模块

1. **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和默认字体驱动模块，使用内置 12 号点阵字体
2. **hw_gtfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和GTFont 矢量字库驱动模块
3. **hw_hzfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和HZFont 矢量字体驱动模块（开发中）
4. **hw_customer_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和自定义外部字体驱动模块（开发中）

当前演示的exeasyui V1.7.0版本还不支持同时启用多种字体，仅支持选择一种字体初始化，同时启用多种字体功能正在开发中

## 二、演示效果

<table>
<tr>
<td>主页<br/></td><td>组件演示页<br/></td><td>默认字体页<br/></td><td>GTFont页<br/></td></tr>
<tr>
<td><img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_home_gage.png.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_component_page.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_default_font_page.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_default_font_page.jpg" width="80" /><br/></td></tr>
</table>

## 三、演示硬件环境

### 3.1 硬件清单

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
  
### 3.2 接线配置

#### 3.2.1 LCD 显示屏接线

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

#### 3.2.2 GTFont 字库接线

<table> 
<tr> <td>Air8101 核心板</td><td>AirFONTS_1000配件板</td></tr>
 <tr> <td>66/GPIO3</td><td>CS</td></tr> 
 <tr> <td>67/GPIO4</td><td>MISO</td></tr> 
 <tr> <td>8/GPIO5</td><td>MOSI</td></tr> 
 <tr> <td>65/GPIO2</td><td>CLK</td></tr> 
 <tr> <td>vbat</td><td>VCC</td></tr> 
</table>

#### 3.2.3 接线图
![](https://docs.openLuat.com/cdn/image/Air8101_AirLCD_1020_AirFONTS_1000接线图.jpg)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air8101最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，demo所使用的是LuatOS-SoC_V1006_Air8101 1号固件

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
-- 1、使用lcd内核固件中自带的12号中文字体的hw_default_font_drv，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 2、使用hzfont核心库驱动内核固件中支持的软件矢量字库的hw_hzfont_drv.lua，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 3、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板的hw_gtfont_drv.lua，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 4、使用自定义字体的hw_customer_font_drv（目前开发中）
-- 最新情况可查看模组选型手册中对应型号的固件列表内，支持的核心库是否包含lcd、tp、12号中文、gtfont、hzfont，链接https://docs.openluat.com/air780epm/common/product/
-- 目前exeasyui V1.7.0版本支持使用已经实现的四种功能中的一种进行初始化，同时支持多种字体初始化功能正在开发中
require("hw_default_font_drv")
-- require("hw_hzfont_drv")开发中
-- require("hw_gtfont_drv")
-- require("hw_customer_font_drv")开发中

-- 加载exeassyui扩展库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、组件演示页、默认字体演示页、HZfont演示页、GTFont演示页和自定义字体演示页

require("ui_main")
```

### 5.3 屏幕参数配置

在对应的驱动文件中根据实际硬件调整硬件参数：

- **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和默认字体驱动模块，使用内置 12 号点阵字体
- **hw_gtfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和GTFont 矢量字库驱动模块
- **hw_hzfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和HZFont 矢量字体驱动模块（开发中）
- **hw_customer_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和自定义外部字体驱动模块（开发中）

### 5.4 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将图片文件随脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行
5. [点击查看Luatools 下载和详细使用](https://docs.openluat.com/air8101/common/Luatools/)

### 5.5 功能测试

#### 5.5.1 主页面操作

1. 设备启动后显示主页面，包含四个功能按钮
2. 查看系统标题和版本信息
3. 点击各功能按钮进入对应演示页面

#### 5.5.2 组件演示页面

1. 测试进度条组件的动态更新
2. 在输入框中输入文本测试
3. 点击按钮查看打印日志
4. 操作复选框查看状态变化
5. 体验消息框的弹出和按钮响应
6. 使用下拉框选择选项
7. 查看图片轮播效果（如有图片文件）

#### 5.5.3 字体演示页面

1. **默认字体页**：查看固定 12 号字体的颜色和中英文显示
2. **GTFont 页**：体验多尺寸矢量字体显示效果
3. 在各页面使用返回按钮回到主页

### 5.6 预期效果

- **系统启动**：正常初始化，显示主页面
- **页面切换**：流畅的页面过渡效果
- **组件交互**：所有 UI 组件响应灵敏
- **字体显示**：各字体页面正常显示，动态调整功能正常
- **触摸操作**：准确的触摸定位和事件响应

### 5.7 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **字体显示异常**：确认选择的字体驱动与硬件匹配
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：调整 `ui_main.lua` 中的sys.wait(time)刷新率参数

## 六、扩展开发

本演示 demo 所有接口都在 [exeasyUI UI 扩展库](https://docs.openluat.com/osapi/ext/exeasyui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。
