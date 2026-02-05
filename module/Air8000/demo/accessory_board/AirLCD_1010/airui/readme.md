# AirUI 演示系统

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - AirUI 主程序，负责页面管理和主循环调度

### 1.2 硬件驱动模块

1. **lcd_drv.lua** - LCD 显示驱动模块，基于 lcd 核心库，支持 ST7796 屏幕
2. **tp_drv.lua** - 触摸面板驱动模块，基于 tp 核心库，支持 GT911 触摸控制器

### 1.3 演示页面模块

1. **home_page.lua** - 主页模块，提供所有演示入口
2. **all_component_page.lua** - 所有组件综合演示页面
3. **label_page.lua** - 标签组件演示页面
4. **button_page.lua** - 按钮组件演示页面
5. **container_page.lua** - 容器组件演示页面
6. **bar_page.lua** - 进度条组件演示页面
7. **switch_page.lua** - 开关组件演示页面
8. **dropdown_page.lua** - 下拉框组件演示页面
9. **table_page.lua** - 表格组件演示页面
10. **input_page.lua** - 输入框组件演示页面
11. **msgbox_page.lua** - 消息框组件演示页面
12. **image_page.lua** - 图片组件演示页面
13. **tabview_page.lua** - 选项卡组件演示页面
14. **win_page.lua** - 窗口组件演示页面
15. **switch_page_demo.lua** - 页面切换演示
16. **hzfont_page.lua** - 矢量字体（HZFont）演示页面
17. **game_page.lua** - 俄罗斯方块游戏演示页面

## 二、演示效果

| 主页 | 选项卡 | 容器 | 窗口 |
|------|--------------|------------|----------|
| ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_主页.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_选项卡.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_容器.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_窗口.png) |

| 下拉框 | 表格 | 进度条 | 输入框 |
|----------|------------|------------|----------|
| ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_下拉框.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_表格.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_进度条.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_输入框.png) |


## 三、演示硬件环境

### 3.1 实际设备演示说明

- 演示所使用的是 Air8000 开发板
- 其他组件演示，demo 所使用的固件是 LuatOS-SoC_V2024_Air8000_14.soc
- 使用其他型号模块可以参考 [docs 文档](https://docs.openluat.com/)中对应型号的固件支持功能进行固件选择，按管脚说明进行接线和配置 lcd_drv.lua 和 tp_drv.lua 中的参数，然后进行烧录使用

### 3.2 硬件清单

- Air8000 开发板 × 1
- AirLCD_1010 触摸配件板 × 1
- TYPE-C 数据线 × 1

### 3.3 接线配置

- AirLCD_1010 触摸配件板插入到Air8000 开发板 四线SPI屏接口
- Air8000 开发板 4G天线旁拨码开关打到 ON 位置，此时背光正常供电
- Air8000 开发板 侧面供电开关打到 USB供电一端，开发板通过 TYPE-C USB 口供电


#### 3.4 接线图
![](https://docs.openLuat.com/cdn/image/Air8000开发板+屏幕.jpg)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air8000最新版本内核固件](https://docs.openluat.com/air8000/luatos/firmware/)，demo所使用的是LuatOS-SoC_V2024_Air8000 14/114号固件



## 五、演示核心步骤

### 5.1 硬件准备

1. 将屏幕对准定位点插入
2. Air8000 开发板侧面供电开关打到 USB供电一端
3. 通过 TYPE-C USB 口供电

### 5.2 软件配置

在 `main.lua` 中选择要运行的演示模块：

```lua
-- 加载显示驱动
lcd_drv = require("lcd_drv")
-- 加载触摸驱动
tp_drv = require("tp_drv")

-- 引入演示模块（每次只选择一个运行）
require("ui_main") --动态更新标签演示
```

### 5.3 初始化参数配置

在对应的驱动文件中根据实际硬件调整硬件参数：

- **lcd_drv.lua** - lcd显示驱动配置、AirUI初始化、hzfont初始化配置
- **tp_key_drv.lua** - tp触摸驱动配置和初始化，触摸设备绑定AirUI

### 5.4 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将图片文件随脚本文件一起烧录到脚本分区
4. 设备自动重启后开始运行
5. [点击查看Luatools 下载和详细使用](https://docs.openluat.com/air8000/common/Luatools/)


### 5.5 功能测试

#### 5.5.1 主页面操作

1. 设备启动后显示主页面，包含所有演示入口卡片
2. 查看系统标题和版本信息
3. 点击各功能卡片进入对应演示页面

#### 5.5.2 组件演示页面

1. 所有组件演示：一次性查看12个AirUI组件
2. 标签组件：测试文本标签和图标标签
3. 按钮组件：体验不同大小和样式的按钮
4. 进度条组件：测试动画进度条和颜色自定义
5. 输入框组件：测试文本输入和键盘弹出
6. 消息框组件：体验多种消息框样式
7. 游戏演示：玩俄罗斯方块游戏，支持触摸控制

#### 5.5.3 字体演示页面

1. 矢量字体页：查看高质量中文矢量字体显示
2. 支持不同字体大小和颜色对比
3. 中英文混合显示测试面


### 5.6 预期效果

- **系统启动**：正常初始化，显示主页面
- **页面切换**：流畅的页面过渡效果
- **组件交互**：所有 UI 组件响应灵敏
- **字体显示**：各字体页面正常显示，动态调整功能正常
- **触摸操作**：准确的触摸定位和事件响应

### 5.7 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **字体显示异常**：确认选择的字体驱动与固件匹配
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：调整 `ui_main.lua` 中的刷新率参数

## 六、扩展开发

本演示 demo 所有接口都在 [AirUI 核心库](https://docs.openluat.com/osapi/core/airui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。
