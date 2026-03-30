# AirUI 演示系统

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - AirUI 主程序，负责窗口管理和主循环调度

### 1.2 硬件驱动模块

1. **lcd_drv.lua** - LCD 显示驱动模块，基于 lcd 核心库，支持 ST7796 屏幕
2. **tp_drv.lua** - 触摸面板驱动模块，基于 tp 核心库，支持 GT911 触摸控制器

### 1.3 演示窗口模块

1. **home_win.lua** - 主窗口模块，提供所有演示入口
2. **all_component_win.lua** - 所有组件综合演示窗口
3. **label_win.lua** - 标签组件演示窗口
4. **button_win.lua** - 按钮组件演示窗口
5. **container_win.lua** - 容器组件演示窗口
6. **bar_win.lua** - 进度条组件演示窗口
7. **switch_win.lua** - 开关组件演示窗口
8. **dropdown_win.lua** - 下拉框组件演示窗口
9. **table_win.lua** - 表格组件演示窗口
10. **input_win.lua** - 输入框组件演示窗口
11. **msgbox_win.lua** - 消息框组件演示窗口
12. **image_win.lua** - 图片组件演示窗口
13. **tabview_win.lua** - 选项卡组件演示窗口
14. **win_win.lua** - 窗口组件演示窗口
15. **switch_demo_win.lua** - 窗口切换演示
16. **hzfont_win.lua** - 矢量字体（HZFont）演示窗口
17. **game_win.lua** - 俄罗斯方块游戏演示窗口

## 二、演示效果

| 主窗口 | 选项卡 | 容器 | 窗口 |
|------|--------------|------------|----------|
| ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_主窗口.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_选项卡.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_容器.png) | ![](https://docs.openluat.com/cdn/image/Air8000_AirUI_窗口.png) |

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
require("lcd_drv")
-- 加载触摸驱动
require("tp_drv")

exwin= require("exwin")

-- 引入演示模块
require("ui_main")
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

#### 5.5.1 主窗口操作

1. 设备启动后显示主窗口，包含所有演示入口卡片
2. 查看系统标题和版本信息
3. 点击各功能卡片进入对应演示窗口

#### 5.5.2 组件演示窗口

1. 所有组件演示：一次性查看12个AirUI组件
2. 标签组件：测试文本标签和图标标签
3. 按钮组件：体验不同大小和样式的按钮
4. 进度条组件：测试动画进度条和颜色自定义
5. 输入框组件：测试文本输入和键盘弹出
6. 消息框组件：体验多种消息框样式
7. 游戏演示：玩俄罗斯方块游戏，支持触摸控制

#### 5.5.3 字体演示窗口

1. 矢量字体窗口：查看高质量中文矢量字体显示
2. 支持不同字体大小和颜色对比
3. 中英文混合显示测试面


### 5.6 预期效果

- **系统启动**：正常初始化，显示主窗口
- **窗口切换**：流畅的窗口过渡效果
- **组件交互**：所有 UI 组件响应灵敏
- **字体显示**：各字体窗口正常显示，动态调整功能正常
- **触摸操作**：准确的触摸定位和事件响应

### 5.7 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **字体显示异常**：确认选择的字体驱动与固件匹配
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：调整 `ui_main.lua` 中的刷新率参数

## 六、窗口管理架构

### 6.1 exwin窗口管理扩展库

本演示已集成 `exwin` 窗口管理扩展库，提供基于栈的窗口生命周期管理。每个窗口作为一个独立窗口，通过消息机制打开和关闭。

**核心接口：**
- `exwin.open(config)` - 打开新窗口
- `exwin.close(win_id)` - 关闭指定窗口
- `exwin.is_active(win_id)` - 查询窗口是否活动
- `exwin.return_idle()` - 返回首窗口并销毁其他窗口

### 6.2 消息驱动窗口导航

窗口间导航采用消息发布/订阅模式，实现解耦：

1. **首窗口订阅**：`sys.subscribe("OPEN_HOME_win", ...)`
2. **其他窗口订阅**：`sys.subscribe("OPEN_XXX_win", ...)`（XXX为窗口名称大写）
3. **窗口跳转**：`sys.publish("OPEN_XXX_win")`

### 6.3 窗口改造示例

每个窗口文件需包含以下结构：

```lua

local win_id = nil

local function on_create()
    -- 创建UI
end

local function on_destroy()
    -- 清理UI
end

sys.subscribe("OPEN_XXX_win", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end)
```

## 七、扩展开发

本演示 demo 所有接口都在 [AirUI 核心库](https://docs.openluat.com/osapi/core/airui/)内有详细说明，如需实现更丰富的自定义功能可按接口说明实现。
