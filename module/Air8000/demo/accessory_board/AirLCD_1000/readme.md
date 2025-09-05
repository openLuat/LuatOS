# AirLCD_1000_Air8000 演示 demo

## 一、演示 demo 效果

1. 通过 demo 了解屏幕连接、配置、初始化过程，为显示做好准备
2. 通过 demo 将图片、12 号中文、英文、点、线、圆形、矩形、颜色填充、二维码显示在屏幕上
3. 通过 demo 了解如何使用接口对屏幕进行背光亮度调节、屏幕休眠、屏幕唤醒
4. 实现效果图

![](https://docs.openluat.com/air8000/luatos/app/AirLCD_1000%E6%BC%94%E7%A4%BAdemo/imges/RimHbQYQko7lifxk4S1ci8SQntc.jpg)

![](https://docs.openluat.com/air8000/luatos/app/AirLCD_1000%E6%BC%94%E7%A4%BAdemo/imges/BaH5b9WnKomL4SxNJxvc5rZKnIg.png)

## 二、代码结构和功能介绍

1. main.lua：主程序入口；
   1. ui_main.lua：UI 子模块的主程序入口。（功能：1、按 screen_data_table.lua 配置执行 UI 相关的初始化。2、显示的主循环程序，如显示图片、文字、二维码、色块等等）
      1. screen_data_table.lua：ui_main.lua 下面的子模块，负责存放显示屏和触摸屏相关配置
      2. AirLCD_1000.lua：ui_main.lua 下面的子模块，负责执行具体的屏幕初始化程序、屏幕 PWM 背光调节、屏幕通过背光 GPIO 执行休眠和唤醒

## 三、使用步骤

### 3.1 硬件准备

1. AirLCD_1000 显示屏*1
2. Air8000A 核心板*1
3. 母对母杜邦线*8
4. TYPE-C 数据线*1
5. 按照硬件接线图正确连接 LCD 显示屏
6. 确保背光控制引脚（如 demo 中 GPIO1）支持 PWM 功能
7. 将核心板正面开关打到供电位置，背面开关打到 USB ON 位置
### 3.2接线说明

<table>
<tr>
<td>引脚说明<br/></td><td>开发板<br/></td><td>屏幕<br/></td><td>引脚说明<br/></td></tr>
<tr>
<td>模组GPIO供电能力弱，所以使用VDD-EXT供电。如果使用GPIO需要外置LDO用GPIO取控制供电，注意：GPIO需要初始化，需要等待供电稳定后再进行初始屏幕。<br/></td><td>VDD-EXT<br/><br/></td><td>VCC<br/><br/></td><td>显示屏电源供电脚<br/><br/></td></tr>
<tr>
<td>电源地<br/></td><td>GND<br/></td><td>GND<br/></td><td>电源地<br/></td></tr>
<tr>
<td>LCD SPI 串口的时钟信号<br/></td><td>LCD_CLK<br/></td><td>CLK<br/></td><td>SPI 串口的时钟信号<br/></td></tr>
<tr>
<td>LCD SPI 串口的数据脚<br/></td><td>LCD_SDA<br/></td><td>MOS<br/></td><td>SPI 串口的数据输入脚<br/></td></tr>
<tr>
<td>LCD 复位脚<br/></td><td>LCD_RST<br/></td><td>RES<br/></td><td>显示屏复位脚<br/></td></tr>
<tr>
<td>LCD 数据/寄存器控制脚<br/></td><td>LCD_RS<br/><br/></td><td>DC<br/></td><td>4 线 SPI 串口的显示数据/寄存器指令<br/></td></tr>
<tr>
<td>LCD SPI片选，同一个SPI接口上有多个设备才使用<br/></td><td>LCD_CS<br/></td><td>CS<br/></td><td>LCD驱动芯片片选脚<br/></td></tr>
<tr>
<td>LCD 背光控制引脚<br/></td><td>GPIO_1/PWM0<br/></td><td>BKL<br/></td><td>背光使能引脚<br/></td></tr>
</table>

![](https://docs.openluat.com/air8000/luatos/app/AirLCD_1000%E6%BC%94%E7%A4%BAdemo/imges/KykbbPVHGojRMVxqT04cDzRSnUc.jpg)

### 3.3 底层固件准备

固件版本，推荐使用 V2014 及以后最新固件版本：[固件下载链接](https://docs.openluat.com/air8000/luatos/firmware/)

### 3.4软件准备

下载本 demo 中的代码文件以及图片文件

### 3.5 烧录程序

1. 下载 luatools 烧录工具：[luatools下载链接及使用说明](https://docs.openluat.com/air780epm/common/Luatools/)
2. 按照操作说明，将本 demo 内除 readme.md 外的全部文件通过 luatools 下载到模块内**（按住 BOOT 键开机，选择下载底层和脚本）**
3. 如需显示图片，如 demo 中显示的 logo，确保 `logo.jpg` 图片文件存在，下载时会放在模组 `/luadb/` 目录下
   ![](https://docs.openluat.com/air8000/luatos/app/AirLCD_1000%E6%BC%94%E7%A4%BAdemo/imges/UdWZbZ0tXoYPK5xG2Kbcx2y7nSc.png)

## 四、demo 文件

### **1、screen_data_table.lua**


### **2、main.lua**


### **3、ui_main.lua**


### **4、AirLCD_1000.lua**


## 五、程序对外接口

### 5.1 AirLCD_1000 模块接口

#### `AirLCD_1000.lcd_init()`

- 功能：初始化 AirLCD_1000LCD 显示屏
- 参数：

  - LCD_MODEL: LCD 型号字符串（如"AirLCD_1000"）
  - lcd_pin_dc: 数据/命令引脚号
  - lcd_pin_rst: 复位引脚号
  - lcd_pin_pwr: 背光控制引脚号
- 返回值：初始化成功状态(true/false), 屏幕宽度, 屏幕高度

#### `AirLCD_1000.setBacklight(level)`

- 功能：设置背光亮度
- 参数：level - 亮度级别(0-100)
- 返回值：设置成功状态(true/false)

#### `AirLCD_1000.setSleep(sleep)`

- 功能：设置屏幕休眠或唤醒
- 参数：sleep - true 进入休眠, false 唤醒
- 返回值：设置成功状态(true/false)
- **注意事项：目前在屏幕休眠模式下，仅 AIR780EPM 支持模组设置 pm.power(pm.WORK_MODE, 1)，其他型号暂时不支持，唤醒模组会导致模组死机**

### 5.2 screen_data_table 配置参数

- `lcd_models`: 支持的 LCD 型号及其参数
- `default`: 默认配置（滑动阈值、点击时间阈值等）预留后续扩展功能使用

### 5.3 更多显示接口

- 可以参考合宙 docs 上 LCD 库进行扩展使用：[https://docs.openluat.com/osapi/core/lcd/](https://docs.openluat.com/osapi/core/lcd/)

## 六、扩展说明

1. 目前支持 ST7796、ST7789、CO5300 显示芯片，其他 st7735 、st7735v、st7735s、gc9a01、gc9106l、gc9306x、ili9486 也同样支持，
2. 模组字体支持有限，需要使用其他字体可以搭配合宙 AirFONTS_1000 矢量字库使用
3. Air780EPM/EHM/EGH/EHV、Air8000 系列、Air8101，按正确的接口接线并修改 screen_data_table.lua 都可以使用此 demo
4. 其他屏幕可以参考 custom 的方式自定义屏幕初始化配置

```lua
-- 配置接口参数
local lcd_param = {
        port = lcd.HWID_0,      -- 使用的spi id 号
        pin_dc = 1,            -- QSPI模式不需要DC引脚
        pin_rst = 36,           -- 复位引脚
        pin_dc = 0xff,            -- 命令选择硬件，不设置
        pin_rst = 2,             -- 屏幕reset 管脚  
        direction = 0,            -- 屏幕方向
        w = width,                -- 屏幕宽度
        h = height,               -- 屏幕高度
        xoffset = 0,              -- X轴偏移像素
        yoffset = 0,              -- Y轴偏移像素
        sleepcmd = 0x10,          -- LCD睡眠命令
        wakecmd = 0x11,           -- LCD唤醒命令
    }
    
  -- 初始化SPI设备
        spi.deviceSetup(
            lcd.HWID_0,  -- LCD端口号
            nil,         -- CS片选脚，可选
            0,           -- CPHA=0
            0,           -- CPOL=0
            8,           -- 8位数据宽度
            20000000,    -- 20MHz波特率
            spi.MSB,     -- 高位先传
            1,           -- 主机模式
            1            -- 全双工模式
        )
        
    -- QSPI如有特殊配置，需要在lcd.init前配置好
    --lcd.qspi(0x02, 0x32, 0x12)
        
    -- 初始化屏幕 
    lcd.init("custom", lcd_param)
    
    -- 如有其他参数需要配置，可使用lcd.cmd命令
    --lcd.cmd(0x53, 0x20)
        
    -- 自定义初始化后必须运行该程序
    lcd.user_done()
```
