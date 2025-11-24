# LCD、触摸与字体演示系统

## 一、功能模块介绍

### 1.1 核心主程序模块
1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 用户界面主控模块，管理页面切换和事件分发

### 1.2 显示页面模块
3. **home_page.lua** - 主页模块，提供应用入口和导航功能
4. **lcd_page.lua** - LCD图形绘制演示模块
5. **gtfont_page.lua** - GTFont矢量字体演示模块
6. **customer_font_page.lua** - 自定义字体演示模块

### 1.3 驱动模块
7. **lcd_drv.lua** - LCD显示驱动模块，基于lcd核心库，lcd_drv和exlcd_drv二选一使用
8. **exlcd_drv.lua** - LCD显示驱动模块，基于exlcd扩展库，lcd_drv和exlcd_drv二选一使用
9. **tp_drv.lua** - 触摸驱动模块，基于tp核心库，tp_drv和extp_drv二选一使用
10. **extp_drv.lua** - 触摸驱动模块，基于extp扩展库，tp_drv和extp_drv二选一使用
11. **gtfont_drv.lua** - GTFont矢量字库驱动模块
12. **customer_font_drv.lua** - 自定义外部字体驱动功能模块
13. **hzfont_drv.lua** - 合宙软件矢量字库（开发中）
    - gtfongt_drv、customer_font_drv、hzfont_drv
    - 可以都不启用
    - 可以仅启用一种
    - 可以启用任意两种
    - 可以全部启用

## 二、触摸消息介绍

1. **"BASE_TOUCH_EVENT"** - 基础触摸事件消息，包含触摸坐标和事件类型
   - tp触摸库事件类型：`tp.EVENT_DOWN`（按下）、`tp.EVENT_MOVE`（移动）、`tp.EVENT_UP`（抬起）
   - extp触摸库事件类型：`SINGLE_TAP`（单击）、`LONG_PRESS`（长按）可根据UI需求打开滑动事件
   - 坐标范围：X: 0-319，Y: 0-479

## 三、显示效果

<table>
<tr>
<td>主页<br/></td><td>lcd核心库页面<br/></td><td>gtfont页面<br/></td><td>自定义字体页面<br/></td></tr>
<tr>
<td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EHMLCD演示1.png" width="80" /><br/></td><td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EHMLCD演示2.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/Air780EHMLCD演3.png" width="80" /><br/></td><td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EHMLCD演示5.jpg" width="80" /><br/></td></tr>
<tr>
<td><img src="https://docs.openluat.com/cdn/image/Air780EHMLCD演示4.jpg" width="80" /><br/></td></tr>
</table>


## 四、演示功能概述

### 4.1 LCD图形绘制演示
1. **基本图形绘制** - 展示点、线、矩形、圆形等基本图形绘制功能
2. **图片显示** - 支持外部图片文件显示
3. **二维码生成** - 动态生成并显示二维码
4. **颜色示例** - 展示多种颜色显示效果

### 4.2 GTFont矢量字体演示
1. **矢量字体显示** - 使用AirFONTS_1000矢量字库小板显示平滑字体
2. **字体大小切换** - 支持10-192号字体大小动态变化
3. **灰度模式** - 支持灰度显示模式，字体边缘更平滑
4. **多颜色显示** - 支持多种颜色字体显示

### 4.3 自定义字体演示
1. **外部字体加载** - 支持加载外部自定义字体文件
2. **GB2312编码** - 支持GB2312编码的中文字体
3. **多颜色文字** - 支持不同颜色的文字显示

### 4.4 触摸交互功能
1. **页面导航** - 支持多页面之间的切换
2. **按钮响应** - 触摸按钮的点击响应功能
3. **模式切换** - 支持gtfont切换灰度/常规显示

## 五、演示硬件环境

### 5.1 硬件清单

- Air780EHM/Air780EHV/Air780EGH 核心板 × 1
- AirLCD_1010 触摸配件板 × 1
- GTFont 矢量字库，使用的是 AirFONT_1000 配件板 × 1
- 母对母杜邦线 × 17，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air780EHM/Air780EHV/Air780EGH 核心板和 AirLCD_1010配件板以及AirFONT_1000 配件板的硬件接线方式为

  - Air780EHM/Air780EHV/Air780EGH 核心板通过 TYPE-C USB 口供电（核心板背面的功耗测试开关拨到 OFF 一端），此种供电方式下，VDD_EXT 引脚为 3.3V，可以直接给 AirLCD_1010配件板和AirFONT_1000 配件板供电；
  - 为了演示方便，所以 Air780EHM/Air780EHV/Air780EGH 核心板上电后直接通过 vbat 引脚给 AirLCD_1010配件板和AirFONT_1000 配件板提供了 3.3V 的供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

### 5.2 接线配置

#### 5.2.1 LCD 显示屏接线

<table> 
<tr> <td>Air780EHM/Air780EHV/Air780EGH 核心板</td><td>AirLCD_1010配件板</td></tr> <tr> <td>53/LCD_CLK</td><td>SCLK/CLK</td></tr> <tr> <td>52/LCD_CS</td><td>CS</td></tr> <tr> <td>49/LCD_RST</td><td>RES/RST</td></tr> <tr> <td>50/LCD_SDA</td><td>SDA/MOS</td></tr> <tr> <td>51/LCD_RS</td><td>DC/RS</td></tr> <tr> <td>22/GPIO1</td><td>BLK</td></tr> <tr> <td>24/VDD_EXT</td><td>VCC</td></tr> <tr> <td>67/I2C1_SCL</td><td>SCL</td></tr> <tr> <td>66/I2C1_SDA</td><td>SDA</td></tr> <tr> <td>19/GPIO22</td><td>INT</td></tr> 
</table>

#### 5.2.2 GTFont 字库接线

<table> 
<tr> <td>Air780EHM/Air780EHV/Air780EGH 核心板</td><td>AirFONT_1000配件板</td></tr> <tr> <td>83/SPI0_CS</td><td>CS</td></tr> <tr> <td>84/SPI0_MISO</td><td>MISO</td></tr> <tr> <td>85/SPI0_MOSI</td><td>MOSI</td></tr> <tr> <td>86/SPI0_CLK</td><td>CLK</td></tr> <tr> <td>24/VDD_EXT</td><td>VCC</td></tr> 
</table>

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EHM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EHM 1号固件
  
- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EHV 1号固件
  
- [点击下载Air780EGH系列最新版本内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EGH 1号固件

### 6.3 字体文件
- 自定义字体文件：`customer_font_24.bin`（和lua脚本文件一起烧录，会自动放置在`/luadb/`目录下）
- 演示图片文件：`logo.jpg`（和lua脚本文件一起烧录，会自动放置在`/luadb/`目录下）
- [点击查看自定义字体生成和使用说明](https://docs.openluat.com/osapi/core/lcd/?h=lcd#_6)


## 七、演示核心步骤

### 7.1 硬件准备
1. 按照硬件接线表连接所有设备
2. 确保电源连接正确，通过TYPE-C USB口供电
3. 检查所有接线无误，避免短路

### 7.2 软件配置
在`main.lua`中选择加载对应的驱动模块：

```lua
-- 加载显示屏驱动管理功能模块，有以下两种：
-- 1、使用lcd核心库驱动的lcd_drv.lua
-- 2、使用exlcd扩展库驱动的exlcd_drv.lua
-- 根据自己的需求，启用两者中的任何一种都可以
-- 也可以不启用任何一种，不使用显示屏功能
lcd_drv = require "lcd_drv"
-- lcd_drv = require "exlcd_drv"


-- 加载触摸面板驱动管理功能模块，有以下两种：
-- 1、使用tp核心库驱动的tp_drv.lua
-- 2、使用extp扩展库驱动的extp_drv.lua
-- 根据自己的需求，启用两者中的任何一种都可以
-- 也可以不启用任何一种，不使用触摸面板功能
tp_drv = require "tp_drv"
-- tp_drv = require "extp_drv"


-- 加载字库驱动管理功能模块，有以下三种：
-- 1、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板的gtfont_drv.lua
-- 2、使用hzfont核心库驱动内核固件中支持的软件矢量字库的hzfont_drv.lua（正在开发中，后续补充）
-- 3、使用自定义字体
-- 根据自己的需求，启用三者中的任何几种都可以
-- 也可以不启用任何一种，只使用内核固件中自带的点阵字库
require "gtfont_drv"
-- require "hzfont_drv"
-- 使用外部自定义字体不需要require "customer_font_drv"，可以参照customer_font_drv.lua内的使用说明进行创建和加载字体文件



-- 加载输入法驱动管理功能模块（正在开发中，后续补充）


-- 加载lcd核心库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、lcd核心库功能演示页、GTFont演示页和自定义字体演示页
require "ui_main"
```

### 7.3 软件烧录
1. 使用Luatools烧录最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将字体文件和图片文件随脚本文件一起烧录到脚本分区或者单独烧录到文件系统
4. 设备自动重启后开始运行

### 7.4 功能测试

#### 7.4.1 主页面操作
1. 设备启动后显示主页面，包含三个功能按钮
2. 查看系统功能概览信息
3. 点击各功能按钮进入对应演示页面

#### 7.4.2 LCD演示页面
1. 查看基本图形绘制示例（点、线、矩形、圆形）
2. 查看图片显示区域（显示logo图片）
3. 查看二维码区域（合宙文档二维码）
4. 查看颜色填充示例展示
5. 点击"返回"按钮回到主页

#### 7.4.3 GTFont演示页面
1. 计时阶段，gtfont说明显示
2. 字体大小变化阶段，查看10-192号字体动态变化
3. 点击"灰度/常规"切换按钮，体验不同显示模式
4. 查看多颜色字体显示效果
5. 点击"返回"按钮回到主页

#### 7.4.4 自定义字体页面
1. 查看外部字体文件显示效果
2. 查看多颜色文字显示（红色、绿色、蓝色）
3. 查看字体使用说明和接口信息
4. 点击"返回"按钮回到主页

### 7.5 预期效果

- **主页面**：正常显示，三个功能按钮响应灵敏
- **LCD演示页面**：图形绘制清晰，图片和二维码显示正常，颜色示例完整
- **GTFont演示页面**：字体显示平滑，字号切换流畅，灰度模式切换正常
- **自定义字体页面**：外部字体加载正确，多颜色文字显示正常
- **触摸交互**：所有触摸操作响应及时准确，页面切换流畅

### 7.6 故障排除

1. **显示异常**：检查LCD接线是否正确，确认电源供电稳定
2. **触摸无响应**：检查I2C接线，确认触摸芯片初始化成功
3. **字体显示异常**：检查SPI接线（如使用GTFont），确认字体文件路径正确
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：检查内存使用情况，适当调整刷新频率