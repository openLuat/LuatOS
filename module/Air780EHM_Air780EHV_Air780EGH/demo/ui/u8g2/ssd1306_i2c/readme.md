# U8G2 SSD1306 I2C 显示屏与按键演示系统

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 用户界面主控模块，管理页面切换和事件分发

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **component_page.lua** - 组件演示模块，展示进度条和基本图形
3. **default_font_page.lua** - 内置字体演示模块，展示U8G2内置字体效果

### 1.3 驱动模块

1. **hw_default_font_drv.lua** - SSD1306 OLED 初始化和内置字体驱动模块（硬件 I2C）
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
<td>主页<br/></td><td>组件演示页<br/></td><td>内置中文字体页面<br/></td></tr>
<tr>
<td rowspan="2"><img src="https://docs.openluat.com/air780egh/luatos/app/multimedia/ui/u8g2/image/ssd1306_homepage.png" width="80" /><br/></td><td rowspan="2"><img src="https://docs.openluat.com/air780egh/luatos/app/multimedia/ui/u8g2/image/ssd_1306_component_page.png" width="80" /><br/></td><td><img src="https://docs.openluat.com/air780egh/luatos/app/multimedia/ui/u8g2/image/ssd1306_default_font_page.png" width="80" /><br/></td></tr>
</table>

## 四、功能详细说明

### 4.1 组件演示页面

1. **进度条显示** - 展示进度条，可通过"+10%"按钮增加进度（最大 100%）
2. **基本图形绘制** - 展示圆形、实心圆、矩形、实心矩形、三角形
3. **按钮交互** - 支持返回首页和调整进度两种功能

### 4.2 内置字体演示页面

1. **内置字体显示** - 展示 U8G2 内置中文字体效果
2. **时间显示** - 显示当前系统时间，支持实时更新
3. **简洁界面** - 单按钮设计，便于快速返回

### 4.3 按键交互功能

1. **页面导航** - 支持多页面之间的流畅切换
2. **防抖处理** - 按键驱动内置 50ms 防抖，防止误触发
3. **事件分发** - 统一的事件分发机制，便于扩展

## 五、演示硬件环境

### 5.1 硬件清单

- Air780EHM/Air780EHV/Air780EGH 核心板 × 1
- SSD1306 0.96 寸 OLED 显示屏（I2C 接口，4 PIN）× 1
- 母对母杜邦线 × 4
- TYPE-C 数据线 × 1

说明：

- Air780EHM/Air780EHV/Air780EGH 核心板通过 TYPE-C USB 口供电（核心板正面开关拨到 ON 一端），3V3引脚为 3.3V，可以直接给 SSD1306 OLED 屏供电；
- SSD1306 OLED 屏 I2C 默认从机地址（slave address）为 0x3C（部分模块为 0x3D，可通过模块板上的 0x78/0x7A 焊点切换），u8g2 库内部使用的是0x3C；
- 客户在设计实际项目时，建议通过 GPIO 控制 LDO 给屏幕供电，可以灵活控制屏幕的供电，降低整机功耗。

### 5.2 接线配置

#### 5.2.1 OLED 显示屏接线（硬件 I2C1）

| Air780EHM/Air780EHV/Air780EGH 核心板 | SSD1306 OLED |
|---|---|
| 67/I2C1SCL | SCK |
| 66/I2C1SDA | SDA |
| 3V3 | VDD |
| GND | GND |

注意：

- 上表中的 I2C1_SCL/I2C1_SDA 为 Air780EHM/Air780EHV/Air780EGH 核心板上 I2C1 通道对应的硬件引脚（请参照核心板原理图标识）；
- 当前 demo 默认使用 `i2c_id = 1`，如需使用 I2C1，请修改 `hw_drv/hw_default_font_drv.lua` 中 `i2c_id` 的取值；
- 如需使用软件 I2C（任意 GPIO），可参考 `hw_drv/hw_default_font_drv.lua` 中的注释说明，将 `mode` 改为 `"i2c_sw"`，并通过 `i2c_scl`、`i2c_sda` 配置具体 GPIO。

#### 5.2.2 接线图
![](https://docs.openluat.com/air780egh/luatos/app/multimedia/ui/u8g2/image/ssd1306_hwenv.png)

## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EHM系列最新版本内核固件](https://docs.openluat.com/air780ehm/luatos/firmware/version/)
- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)
- [点击下载Air780EGH系列最新版本内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 七、演示核心步骤

### 7.1 硬件准备

1. 按照硬件接线表连接 OLED 显示屏的 SCK、SDA、VDD、GND 共 4 根线
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 7.2 软件配置

在 `main.lua` 中加载对应的驱动模块：

```lua
-- 加载显示和字体驱动模块
require("hw_default_font_drv")  -- 使用内置12号中文点阵字体

-- 加载按键驱动
require("key_drv")

-- 加载UI主模块
require("ui_main")
```

如需修改 I2C 通道编号或切换为软件 I2C，请编辑 `hw_drv/hw_default_font_drv.lua`：

```lua
-- 硬件 I2C 模式（默认）
local result = u8g2.begin({
    ic = "ssd1306",
    direction = 0,
    mode = "i2c_hw",
    i2c_id = 1           -- 修改此处切换 I2C 通道
})

-- 软件 I2C 模式（任意 GPIO）
-- local result = u8g2.begin({
--     ic = "ssd1306",
--     direction = 0,
--     mode = "i2c_sw",
--     i2c_scl = <SCL_GPIO>,
--     i2c_sda = <SDA_GPIO>
-- })
```

### 7.3 软件烧录

1. 使用 Luatools 烧录最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 烧录成功后设备自动重启后开始运行

### 7.4 功能测试

#### 7.4.1 主页面操作

1. 设备启动后显示开机信息（"内置字体进入"），随后进入主页面
2. 使用 boot 键（释放）切换选择不同的菜单项
3. 使用 pwr 键（释放）进入选中的演示页面

#### 7.4.2 组件演示页面

1. 查看进度条显示（初始 30%）
2. 查看基本图形绘制效果
3. 使用 boot 键切换按钮（返回、+10%）
4. 使用 pwr 键执行当前选中按钮的功能
5. 按 pwr 键（当返回按钮选中时）返回主页

#### 7.4.3 内置字体演示页面

1. 查看内置字体显示效果
2. 查看当前时间显示（每 300ms 更新一次）
3. 使用 boot 键切换按钮（只有一个返回按钮）
4. 按 pwr 键返回主页

### 7.5 预期效果

- **系统启动**：显示开机信息（内置字体进入），然后进入主页面
- **主页面**：正常显示两个菜单项，boot 键切换选项，pwr 键确认
- **组件演示页面**：进度条和图形显示正常，按键功能正常
- **内置字体页面**：字体显示正常，时间更新正常，pwr 键返回
- **按键响应**：所有按键操作响应及时准确，页面切换流畅

### 7.6 故障排除

1. **显示屏不亮 / 全黑**

   - 检查 VDD、GND 接线是否正确
   - 部分 OLED 模块的 I2C 从机地址为 0x3D，需要确认与默认从机地址 0x3C 是否匹配
   - 确认 i2c_id 与实际接线的硬件 I2C 通道是否一致

2. **显示内容异常或花屏**

   - 检查 SCK/SDA 接线是否正确，是否接反
   - 确认 SSD1306 模块是否为 128x64 分辨率
   - I2C 上拉电阻是否正常（绝大多数 SSD1306 模块板上已自带）

3. **按键无响应**

   - 检查按键 GPIO 引脚配置
   - 确认按键中断处理函数是否正确注册
   - 检查防抖参数是否合适

4. **系统卡顿或重启**

   - 确认内存使用情况
   - 适当调整屏幕刷新频率

### 7.7 扩展建议

本 demo 所演示的接口都可以在 [u8g2 核心库](https://docs.openluat.com/osapi/core/u8g2) 中找到，更丰富的使用方式可以参考 u8g2 核心库进行进一步开发。
