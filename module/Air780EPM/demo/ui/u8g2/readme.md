# U8G2显示屏与按键演示系统

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 用户界面主控模块，管理页面切换和事件分发

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - 组件演示模块，展示进度条和基本图形
3. **default_font_page.lua** - 内置字体演示模块，展示U8G2内置字体效果

### 1.3 驱动模块

1. **hw_default_font_drv.lua** - LCD初始化和内置12号英文点阵字体驱动模块
2. **key_drv.lua** - 按键驱动模块，管理BOOT键和PWR键

## 二、按键消息介绍

1. **"KEY_EVENT"** - 按键事件消息，包含按键类型和状态
   - boot 键事件：`boot_down`（按下）、`boot_up`（释放）
   - pwr 键事件：`pwr_down`（按下）、`pwr_up`（释放）
   - 按键功能定义：
     - 主页：boot 键（释放）选择/切换选项，pwr 键（释放）确认
     - 组件演示页面：boot 键（释放）切换选项，pwr 键（释放）确认（返回或进度 +10%）
     - 内置字体页面：boot 键（释放）切换选项（只有一个返回按钮，无实际效果），pwr 键（释放）返回

注意：当前代码中只处理按键的释放事件（boot_up 和 pwr_up），按下事件被忽略。

## 三、显示效果

<table>
<tr>
<td>主页<br/></td><td>组件演示页<br/></td><td>GTFont页面<br/></td></tr>
<tr>
<td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EPM_st7567_homepage.jpg" width="80" /><br/></td><td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EPM_ST7567_component_page.jpg" width="80" /><br/></td><td><img src="https://docs.openluat.com/cdn/image/Air780EPM_st7567_default_font_page.jpg" width="80" /><br/></td></tr>
</table>

## 四、功能详细说明

1. **进度条显示** - 展示进度条，可通过"+10%"按钮增加进度（最大 100%）
2. **基本图形绘制** - 展示圆形、实心圆、矩形、实心矩形、三角形
3. **按钮交互** - 支持返回首页和调整进度两种功能

### 4.2 内置字体演示页面

1. **内置字体显示** - 展示 U8G2 内置12号英文点阵字体效果
2. **时间显示** - 显示当前系统时间，支持实时更新
3. **简洁界面** - 单按钮设计，便于快速返回

### 4.3 按键交互功能

1. **页面导航** - 支持多页面之间的流畅切换
2. **防抖处理** - 按键驱动内置 50ms 防抖，防止误触发
3. **事件分发** - 统一的事件分发机制，便于扩展


## 五、演示硬件环境

### 5.1 硬件清单

- Air780EPM核心板 × 1
- st7657 显示屏 × 1 [本demo演示使用的屏幕购买链接]( https://e.tb.cn/h.72oQitvwK2AJtDC?tk=ymJ3fuxC8L4)
- 母对母杜邦线 × 8，杜邦线太长的话，会出现 spi 通信不稳定的现象；
- TYPE-C 数据线 × 1
- Air780EPM核心板和 ST7567单色点阵屏的硬件接线方式为

  - Air780EPM核心板通过 TYPE-C USB 口供电（核心板正面开关拨到 ON 一端），此种供电方式下，VBAT 引脚为 3.3V，可以直接给 ST7567单色点阵屏供电；
  - 为了演示方便，所以 Air780EPM核心板上电后直接通过 VBAT 引脚给 ST7567单色点阵屏供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

### 5.2 接线配置

#### 5.2.1 LCD 显示屏接线

<table>
<tr>
<td>Air780EPM核心板<br/></td><td>st7567<br/></td></tr>
<tr>
<td>57/U3TXD<br/></td><td>SCL<br/></td></tr>
<tr>
<td>28/U2RXD<br/></td><td>CS<br/></td></tr>
<tr>
<td>20/GPIO24<br/></td><td>RST<br/></td></tr>
<tr>
<td>29/U2TXD<br/></td><td>SDA<br/></td></tr>
<tr>
<td>58/U3RXD<br/></td><td>DC<br/></td></tr>
<tr>
<td>GPIO24<br/></td><td>BL<br/></td></tr>
<tr>
<td>VBAT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

#### 5.2.2 接线图
![](https://docs.openLuat.com/cdn/image/Air780EPM_st7567接线图.jpg)

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EPM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2014_Air780EPM 1号固件

## 七、演示核心步骤

### 7.1 硬件准备
1. 按照硬件接线表连接所有设备
2. 确保电源连接正确，通过TYPE-C USB口供电
3. 检查所有接线无误，避免短路

### 7.2 软件配置
在`main.lua`中选择加载对应的驱动模块：

```lua
-- 加载显示和字体驱动模块
require("hw_default_font_drv")  -- 使用内置12号英文点阵字体

-- 加载按键驱动
require("key_drv")

-- 加载UI主模块
require("ui_main")
```

### 7.3 软件烧录
1. 使用Luatools烧录最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 烧录成功后设备自动重启后开始运行

### 7.4 功能测试

#### 7.4.1 主页面操作

1. 设备启动后显示主页面，包含两个功能选项
2. 使用 boot 键（释放）切换选择不同的菜单项
3. 使用 pwr 键（释放）进入选中的演示页面

#### 7.4.2 组件演示页面

1. 查看进度条显示（初始 30%）
2. 查看基本图形绘制效果
3. 使用 boot 键切换按钮（返回、+10%）
4. 使用 pwr 键执行当前选中按钮的功能

#### 7.4.3 内置字体演示页面

1. 查看内置字体显示效果
2. 查看当前时间显示（每 300ms 更新一次）
3. 使用 boot 键切换按钮（只有一个返回按钮）
4. 按 pwr 键返回主页

### 7.5 预期效果

- **系统启动**：显示开机信息（内置字体进入/GTFont 进入），然后进入主页面
- **主页面**：正常显示两个菜单项，boot 键切换选项，pwr 键确认
- **组件演示页面**：进度条和图形显示正常，按键功能正常
- **内置字体页面**：字体显示正常，时间更新正常，pwr 键返回
- **按键响应**：所有按键操作响应及时准确，页面切换流畅

### 7.6 故障排除

1. **显示屏不亮**

   - 检查电源接线是否正确
   - 确认 SPI 通信速率是否合适

2. **显示内容异常**

   - 检查初始化参数和命令是否正确
   - 确认显示屏分辨率设置是否与自己的屏幕相同

3. **按键无响应**

   - 检查按键 GPIO 引脚配置
   - 确认按键中断处理函数是否正确注册
   - 检查防抖参数是否合适

4. **系统卡顿或重启**

   - 确认内存使用情况
   - 适当调整屏幕刷新频率

### 7.7 扩展建议
  
  本demo所演示的接口都可以在[u8g2核心库](https://docs.openluat.com/osapi/core/u8g2)中找到，更丰富的使用方式可以参考u8g2核心库进行进一步开发。