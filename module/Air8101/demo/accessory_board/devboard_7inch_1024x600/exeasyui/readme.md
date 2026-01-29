# exEasyUI 演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - exeasyui 主程序，负责执行exeasyui的任务调度

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - UI 组件演示模块
3. **default_font_page.lua** - 默认字体演示模块
4. **hzfont_page.lua** - HZFont 矢量字体演示模块

### 1.3 硬件驱动模块

1. **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和默认字体驱动模块，使用内置 12 号点阵字体（Air8101 V2002版本101固件支持 102固件不支持）
2. **hw_hzfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和HZFont 矢量字体驱动模块（Air8101 V2002版本102固件支持 101固件不支持）
3. **hw_customer_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和自定义外部字体驱动模块（开发中）

当前演示的exeasyui V1.7.4版本还不支持同时启用多种字体，仅支持选择一种字体初始化，同时启用多种字体功能正在开发中

## 二、演示效果

<table>
<tr>
<td>主页<br/></td><td>组件演示页<br/></td><td>默认字体页<br/></td><td>HZFont页<br/></td></tr>
<tr>
<td><img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_home_gage.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/exeasyui_AirLCD_1020_component_page.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/
exeasyui_AirLCD_1020_component_page.png" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/exeasyui_hzfont.png" width="80" /><br/></td></tr>
</table>

## 三、演示硬件环境

### 3.1 硬件清单

- Air8101开发板底板 × 1
- USB 转串口供电下载扩展板 × 1
- LCD 扩展板 × 1
- 1024*600 分辨率横屏 7 寸 LCD+ 触摸面板配件 × 1
- 50PIN FPC 连接线 x 1
- TYPE-C 数据线 × 1
- Air8101开发板底板 和 LCD 扩展板LCD 扩展板 以及1024*600 分辨率横屏 7 寸 LCD+ 触摸面板配件的硬件接线方式为

  - Air8101开发板底板DL_UART0接口连接USB 转串口供电下载扩展板；
  - Air8101开发板底板J22接口通过50PIN FPC 连接线LCD 扩展板；
  - LCD 扩展板RGB888接口接1024*600 分辨率横屏 7 寸 LCD+ 触摸面板配件显示排线
  - LCD 扩展板 RGB-HMX接口接1024*600 分辨率横屏 7 寸 LCD+ 触摸面板配件触摸排线
  

#### 3.2 接线图
![](https://docs.openluat.com/air8101/luatos/common/hwenv/image/TyWTbBu9hoMypFxT1GLcp7UinVb.png)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)，demo所使用的luatools是V3.1.13

### 4.2 内核固件

- [点击下载Air8101最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，demo所使用的是LuatOS-SoC_V2002_Air8101 101和102号固件

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照硬件接线表连接所有设备
2. 通过 TYPE-C USB 口供电

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


-- 加载lcd、tp和字库驱动管理功能模块，有以下三种：
-- 1、使用lcd内核固件中自带的12号中文字体的hw_default_font_drv，并按lcd显示驱动配置和tp触摸驱动配置进行初始化
-- 2、使用hzfont核心库驱动内核固件中支持的软件矢量字库的hw_hzfont_drv.lua
-- 3、使用自定义字体的hw_customer_font_drv（目前开发中）
-- 最新情况可查看模组选型手册中对应型号的固件列表内，支持的核心库是否包含lcd、tp、12号中文、hzfont，链接https://docs.openluat.com/air780epm/common/product/
-- 目前exeasyui V1.7.0版本支持使用已经实现的四种功能中的一种进行初始化，同时支持多种字体初始化功能正在开发中
-- require("hw_default_font_drv") --（Air8101 V2002版本101固件支持 102固件不支持）
require("hw_hzfont_drv") --（Air8101 V2002版本102固件支持 101固件不支持）
-- require("hw_customer_font_drv")（目前开发中）


-- 加载exeassyui扩展库实现的用户界面功能模块
-- 实现多页面切换、触摸事件分发和界面渲染功能
-- 包含主页、组件演示页、默认字体演示页、HZfont演示页和自定义字体演示页
require("ui_main")

```

### 5.3 屏幕参数配置

在对应的驱动文件中根据实际硬件调整硬件参数：

- **hw_default_font_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和默认字体驱动模块，使用内置 12 号点阵字体
- **hw_hzfont_drv.lua** - lcd显示驱动配置、tp触摸驱动配置和HZFont 矢量字体驱动模块
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
2. **HZFont 页**：体验内置软件矢量字体，支持 12–100 号字体动态调整
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