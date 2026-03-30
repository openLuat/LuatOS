# LCD、按键与字体演示系统

## 一、功能模块介绍

### 1.1 核心主程序模块
1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 用户界面主控模块，管理页面切换和事件分发

### 1.2 显示页面模块
3. **home_page.lua** - 主页模块，提供应用入口和导航功能
4. **lcd_page.lua** - LCD图形绘制演示模块
5. **customer_font_page.lua** - 自定义字体演示模块

### 1.3 驱动模块
7. **lcd_drv.lua** - LCD显示驱动模块，基于lcd核心库，lcd_drv和exlcd_drv二选一使用
8. **exlcd_drv.lua** - LCD显示驱动模块，基于exlcd扩展库，lcd_drv和exlcd_drv二选一使用
9. **key_drv.lua** - 按键驱动模块，管理BOOT键和PWR键
10. **customer_font_drv.lua** - 自定义外部字体驱动功能模块

**注意**：当前设备仅支持自定义点阵字体显示中文，不支持内置12号中文字体和GTFont矢量字体。

## 二、按键消息介绍

1. **"KEY_EVENT"** - 按键事件消息，包含按键类型和状态
   - boot键事件：`boot_down`（按下）、`boot_up`（释放）
   - pwr键事件：`pwr_down`（按下）、`pwr_up`（释放）
   - 按键功能定义：
     - 主页：boot键（按下）选择/切换选项，pwr键（按下）确认
     - LCD页面：pwr键（按下）返回，boot键无功能
     - 自定义字体页面：pwr键（按下）返回，boot键无功能

## 三、显示效果

<table>
<tr><td>主页<br/></td><td>lcd核心库页面<br/></td><td>自定义字体页面<br/></td></tr><tr>
<td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1000_主页.png" width="80" /><br/></td>
<td rowspan="2"><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1000_lcd演示页.png" width="80" /><br/></td>
<td><img src="https://docs.openluat.com/cdn/image/Air780EPM_AirLCD_1000_自定义字体演示页.png" width="80" /><br/></td></tr>
</table>


### 4.1 LCD图形绘制演示
1. **基本图形绘制** - 展示点、线、矩形、圆形等基本图形绘制功能
2. **图片显示** - 支持外部图片文件显示
3. **二维码生成** - 动态生成并显示二维码
4. **xbm格式位图示例** - 显示16*16 xbm点阵
5. **自定义字体示例** - 使用自定义字体显示文字

### 4.2 自定义字体演示
1. **外部字体加载** - 支持加载外部自定义字体文件
2. **多颜色文字** - 支持不同颜色的文字显示

### 4.3 按键交互功能
1. **页面导航** - 支持多页面之间的切换
2. **按钮响应** - 按键的点击响应功能


## 五、演示硬件环境

本Demo支持三种硬件环境，请根据实际使用的硬件选择对应的配置：

| 硬件环境 | HARDWARE_ENV值 | LCD电源控制 | LCD背光控制 |
|---------|---------------|------------|------------|
| 核心板直连 | "CORE_BOARD" | 直接供电，无需GPIO控制 | GPIO1控制 |
| V1.2开发板 | "DEV_BOARD_V1.2" | GPIO28控制 | 未接背光，无需控制 |
| V1.3开发板 | "DEV_BOARD_V1.3" | GPIO29控制 | GPIO30控制（低电平亮） |

**配置方法：** 在`main.lua`中修改`HARDWARE_ENV`变量的值即可切换硬件环境。

### 5.1 核心板直连模式（CORE_BOARD）

#### 5.1.1 硬件清单

- Air780EPM核心板 × 1
- AirLCD_1000 配件板 × 1
- 母对母杜邦线 × 14
- TYPE-C 数据线 × 1

#### 5.1.2 硬件连接与控制

**核心板供电**：
   - Air780EPM核心板通过TYPE-C USB口供电（将核心板正面开关拨到 ON 一端）
   - 使用TYPE-C USB数据线连接核心板与电脑USB口

**配件板接线**：
   - 使用母对母杜邦线按照下表连接AirLCD_1000配件板

   **LCD 显示屏接线：**
   <table>
   <tr>
   <td>Air780EPM核心板<br/></td><td>AirLCD_1000配件板<br/></td></tr>
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
   <td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
   <tr>
   <td>GND<br/></td><td>GND<br/></td></tr>
   </table>

   **接线图：**
   ![](https://docs.openLuat.com/cdn/image/Air780EPM_AirLCD_1000_lcd演示接线图.png)

**LCD电源控制**：
   - 通过核心板上的VDD_EXT引脚直接供电，无需GPIO控制
   - 此种供电方式下，VDD_EXT引脚为3.3V

   > **注意**：为了演示方便，本模式直接通过VDD_EXT给配件板供电。客户在设计实际项目时，建议通过GPIO控制LDO给配件板供电，以灵活控制功耗。

**背光控制**：
   - 使用GPIO1控制LCD背光
   - 系统会自动设置`pin_pwr = 1`，通过lcd库自动管理背光开关

#### 5.1.3 配置说明

在`main.lua`中设置：
```lua
HARDWARE_ENV = "CORE_BOARD"
```

驱动会自动完成以下操作：
1. 无需控制GPIO供电（通过核心板上的VDD_EXT引脚供电）
2. `pin_pwr = 1` - 通过lcd库使用GPIO1控制背光

### 5.2 V1.2开发板（DEV_BOARD_V1.2）

#### 5.2.1 硬件清单

- Air780EPM v1.2开发板 × 1
- AirLCD_1000 配件板 × 1
- TYPE-C 数据线 × 1

#### 5.2.2 硬件连接与控制

**开发板供电**：
   - Air780EPM V1.2版本开发板通过TYPE-C USB口供电
   - 将开发板上的"外部供电/USB供电"拨动开关拨到"USB供电"一端
   - 使用TYPE-C USB数据线连接开发板与电脑USB口

**配件板连接**：
   - 将AirLCD_1000配件板按照下图所示方向插入开发板
   ![image](https://docs.openLuat.com/cdn/image/Air780EPM/Air780EPM_demo_accessory_board_lcd_v1.2.jpg)

**LCD电源控制**：
   - 使用GPIO28控制LCD电源供电
   - 系统会自动执行`gpio.setup(28, 1)`打开供电

**背光控制**：
   - 本版本开发板未接屏幕背光脚，无法控制背光
   - 系统会自动设置`pin_pwr = nil`，不通过lcd库控制背光

#### 5.2.3 配置说明

在`main.lua`中设置：
```lua
HARDWARE_ENV = "DEV_BOARD_V1.2"
```

驱动会自动完成以下操作：
1. `gpio.setup(28, 1)` - 打开GPIO28给LCD供电
2. `pin_pwr = nil` - 不通过lcd库控制背光

### 5.3 V1.3开发板（DEV_BOARD_V1.3）

#### 5.3.1 硬件清单

- Air780EPM v1.3开发板 × 1
- AirLCD_1000 配件板 × 1
- TYPE-C 数据线 × 1

#### 5.3.2 硬件连接与控制

**开发板供电**：
   - Air780EPM V1.3版本开发板通过TYPE-C USB口供电
   - 将开发板上的"外部供电/USB供电"拨动开关拨到"USB供电"一端
   - 使用TYPE-C USB数据线连接开发板与电脑USB口

**配件板连接**：
   - 将AirLCD_1000配件板按照下图所示方向插入开发板
   ![image](https://docs.openLuat.com/cdn/image/Air780EPM/Air780EPM_demo_accessory_board_lcd_v1.3.jpg)

**LCD电源控制**：
   - 使用GPIO29控制LCD电源供电
   - 系统会自动执行`gpio.setup(29, 1)`打开供电

**背光控制**：
   - 使用GPIO30控制LCD背光，通过NPN三极管控制
   - 系统会自动执行`gpio.setup(30, 0)`开启背光
   - 系统会自动设置`pin_pwr = nil`，不通过lcd库控制背光（避免lcd库逻辑与硬件电路冲突）

**背光控制原理：**
V1.3开发板的背光控制电路采用NPN三极管：
- **GPIO30 拉高** → 三极管导通 → BL脚接地 → **灭屏**
- **GPIO30 拉低** → 三极管截止 → BL脚悬空 → **亮屏**

**手动控制背光：**
如需在代码中动态控制背光：
```lua
-- 关闭背光（灭屏）
gpio.setup(30, 1)

-- 开启背光（亮屏）
gpio.setup(30, 0)
```

#### 5.3.3 配置说明

在`main.lua`中设置：
```lua
HARDWARE_ENV = "DEV_BOARD_V1.3"
```

驱动会自动完成以下操作：
1. `gpio.setup(29, 1)` - 打开GPIO29给LCD供电
2. `gpio.setup(30, 0)` - GPIO30拉低，开启背光
3. `pin_pwr = nil` - 不通过lcd库控制背光（避免lcd库逻辑与硬件电路冲突）


## 六、演示软件环境

### 6.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/) - 固件烧录和代码调试

### 6.2 内核固件

- [点击下载Air780EPM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，demo所使用的是LuatOS-SoC_V2018_Air780EPM 1号固件

### 6.3 字体文件
- 自定义字体文件：`customer_font_12.bin` 和 `customer_font_22.bin`（和lua脚本文件一起烧录，会自动放置在`/luadb/`目录下）
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


-- 加载按键驱动管理功能模块
key_drv = require "key_drv"


-- 加载字库驱动管理功能模块
-- 使用外部自定义字体不需要require "customer_font_drv"，可以参照customer_font_drv.lua内的使用说明进行创建和加载字体文件


-- 加载输入法驱动管理功能模块（正在开发中，后续补充）


-- 加载lcd核心库实现的用户界面功能模块
-- 实现多页面切换、按键事件分发和界面渲染功能
-- 包含主页、lcd核心库功能演示页、GTFont演示页和自定义字体演示页
require "ui_main"
```

### 7.3 软件烧录
1. 使用Luatools烧录最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 将字体文件和图片文件随脚本文件一起烧录到脚本分区
4. 烧录成功后设备自动重启后开始运行

### 7.4 功能测试

#### 7.4.1 主页面操作
1. 设备启动后显示主页面，包含两个个功能按钮，作为按键页面切换演示
2. 使用boot键切换选择，pwr键进入对应演示页面

#### 7.4.2 LCD演示页面
1. 查看基本图形绘制示例（点、线、矩形、圆形）
2. 查看图片显示区域（显示logo图片）
3. 查看二维码区域（合宙文档二维码）
4. 查看位图和字体示例
5. 按pwr键返回主页

#### 7.4.3 自定义字体页面
1. 查看外部字体文件显示效果
2. 查看多颜色文字显示（红色、绿色、蓝色）
3. 查看字体使用说明和接口信息
4. 按pwr键返回主页

### 7.5 预期效果

- **主页面**：正常显示，使用boot键切换选项，pwr键确认
- **LCD演示页面**：图形绘制清晰，图片和二维码显示正常，颜色示例完整，pwr键返回
- **自定义字体页面**：外部字体加载正确，多颜色文字显示正常，pwr键返回
- **按键交互**：所有按键操作响应及时准确，页面切换流畅

### 7.6 故障排除

1. **显示异常**：检查LCD接线是否正确，确认电源供电稳定
2. **按键无响应**：检查参数是否配置正确，确认按键驱动初始化成功
3. **字体显示异常**：检查所需显示内容是否包含在字体内，确认字体文件路径正确
4. **图片无法显示**：确认图片文件已正确烧录到指定路径
5. **系统卡顿**：检查内存使用情况，适当调整刷新频率