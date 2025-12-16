# exEasyUI 演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - exeasyui 主程序，负责执行exeasyui的任务调度

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - UI 组件演示模块
3. **default_font_page.lua** - 默认字体演示模块

### 1.3 硬件驱动模块

1. **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和驱动模块，使用内置12号英文点阵字体



## 二、演示效果

<table>
<tr>
<td>主页<br/></td><td>组件演示页<br/></td><td>默认字体页<br/></td></tr>
<tr>
<td><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_homepage.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_componentpage.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1010__exeasyui_fontpage.png" width="80" /><br/></td></tr>
</table>


## 三、演示硬件环境

### 3.1 硬件清单

- Air780EPM 核心板 × 1
- AirLCD_1010 触摸配件板 × 1
- 母对母杜邦线 × 11，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air780EPM 核心板和 AirLCD_1010 配件板的硬件接线方式为

  - Air780EPM 核心板通过 TYPE-C USB 口供电（核心板正面开关拨到 ON 一端），此种供电方式下，VBAT 引脚为 3.3V，可以直接给 AirLCD_1010 配件板供电；
  - 为了演示方便，所以 Air780EPM 核心板上电后直接通过 VBAT 引脚给 AirLCD_1010 配件板供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

### 3.2 接线配置

#### 3.2.1 显示屏接线

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


### 3.3 实际接线图
![](https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1010接线图.jpg)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air780EHM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EPMM 1号固件


## 五、演示核心步骤

### 5.1 硬件准备

1. 按照硬件接线表连接所有设备
2. 通过 TYPE-C USB 口供电
3. 检查所有接线无误

### 5.2 软件配置

在 `main.lua` 中配置系统参数：

```lua
-- 必须加载才能启用exeasyui的功能
ui = require("exeasyui")


-- 加载lcd、tp驱动管理功能模块
-- 1、按lcd显示驱动配置和tp触摸驱动配置进行初始化，默认使用lcd内核固件中自带的12号英文点阵字体
require("hw_default_font_drv")


-- 加载exeassyui扩展库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、组件演示页、默认字体演示页
require("ui_main")
```

### 5.3 屏幕参数配置

在对应的驱动文件中根据实际硬件调整硬件参数：

- **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置驱动模块，使用内置 12 号英文点阵字体


### 5.4 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将图片文件随脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行
5. [点击查看Luatools 下载和详细使用](https://docs.openluat.com/air780epm/common/Luatools/)

### 5.5 功能测试

#### 5.5.1 主页面操作

1. 设备启动后显示主页面，包含两个功能按钮
2. 查看系统标题和版本信息
3. 点击各功能按钮进入对应演示页面

#### 5.5.2 组件演示页面

1. 测试进度条组件的动态更新
2. 体验消息框的弹出和按钮响应
3. 操作复选框查看状态变化
4. 在输入框中输入文本测试
5. 使用下拉框选择选项
6. 查看图片轮播效果（如有图片文件）

#### 5.5.3 字体演示页面

1. **默认字体页**：查看固定 12 号字体的颜色和英文显示
2. 在各页面使用返回按钮回到主页

### 5.6 预期效果

- **系统启动**：正常初始化，显示主页面
- **页面切换**：流畅的页面过渡效果
- **组件交互**：所有 UI 组件响应灵敏
- **字体显示**：各字体页面正常显示，动态调整功能正常
- **触摸操作**：准确的触摸定位和事件响应

### 5.7 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **图片无法显示**：确认图片文件已正确烧录到指定路径
4. **系统卡顿**：调整 `ui_main.lua` 中的刷新率参数

## 六、扩展开发

本演示 demo 所有接口都在 [exeasyUI UI 扩展库](https://docs.openluat.com/osapi/ext/exeasyui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。
