--[[
@module  config.template
@summary 项目配置文件参数完整说明（参考模板，不可直接使用）
@version 1.0
@date    2026.05.22
@author  江访

=== 所有参数取值范围与说明 ===
]]

--[[
============================= 顶层字段 =============================
name       : string  项目命名（与设计文档一致），如 "Engine_Air8000W_4inch_320x480_000_V000"
chip       : string  主控型号，取值见下方「chip 枚举」
baseboard  : string  底板型号，自由文本，如 "合宙引擎主机8000W_V000"
pins       : table   引脚配置数组，元素格式 { pin = number, func = string }
hw         : table   硬件配置，含 lcd / tp 子表
features   : table   功能开关，所有字段为 boolean
ui         : table   UI 条件显示开关，所有字段为 boolean
]]

--[[
============================= chip 枚举 =============================
Air1601     :  RGB LCD, WiFi(airlink SPI), I2C, SPI, PSRAM, USB — 无4G/无GPS
Air1602     :  同 Air1601
Air8000W    :  4G + WiFi(exnetif), SPI LCD, I2C, PWM — 无蓝牙/无以太网/无CAN
Air8000A    :  4G + WiFi + GPS/BDS, SPI LCD, I2C, PWM — 无蓝牙/无以太网
Air8000D    :  同 Air8000A + GPS/BDS
Air8101     :  WiFi(exnetif), RGB LCD, USB Host, I2C, SPI, PWM — 无4G/无GPS
Air8101B    :  同 Air8101（更小封装）
Air780EGG   :  4G + GPS/BDS + 以太网 + CAN + RS485, SPI LCD — 无WiFi
Air780EHV   :  4G + 以太网 + CAN + RS485, SPI LCD — 无WiFi/无GPS
Air780EHU   :  同 Air780EHV
Air780EHM   :  同 Air780EHV
Air780EHN   :  同 Air780EHV
PC          :  PC模拟器
]]

--[[
============================= hw.lcd =============================
model        : string  屏幕IC驱动模块名，取值:
                         "lcd_st7796"       — SPI ST7796 (3.5/4寸, 320×480 或 480×320)
                         "lcd_nv3052c_5in"  — RGB NV3052C (5寸, 720×1280, 含init cmds)
                         "lcd_st7701s_5in"  — RGB ST7701S (5寸, 480×854, 含init cmds)
                         "lcd_hx8282_10in"  — RGB HX8282 (10.1寸, 1024×600)
                         "lcd_custom_7in"   — RGB 通用 (7寸, 1024×600)
                         "lcd_custom_10in"  — RGB 通用 (10.1寸, Air1601底板时序)
                         "lcd_custom_evb_10in" — RGB 通用 (10.1寸, EVB底板时序)

params       : table   传给 model 驱动 init() 的参数，字段因 model 而异：

  [通用参数 — 所有 model ]
  port        : lcd.HWID_0 或 lcd.RGB   接口类型
  pin_rst     : number  (0~255)         LCD 复位引脚 GPIO 编号
  direction   : number  (0|1|2|3)       屏幕方向: 0=0° 1=90° 2=180° 3=270°
  w           : number  (1~2048)        水平分辨率
  h           : number  (1~2048)        竖直分辨率
  xoffset     : number  (可选, 默认0)    X 偏移
  yoffset     : number  (可选, 默认0)    Y 偏移

  [SPI 屏专属 — lcd_st7796]
  pin_pwr     : number  (可选, 0~255)    屏幕供电 GPIO，设为输出高
  pwr_pins    : table   (可选)           多引脚供电: {{pin, val}, ...}

  [RGB 屏专属 — 含 SPI 初始化引脚的 model]
  pin_clk     : number  (0~255)         SPI 时钟引脚 (用于 RGB 屏 SPI 初始化)
  pin_sda     : number  (0~255)         SPI 数据引脚
  pin_cs      : number  (0~255)         SPI 片选引脚
  hbp         : number  (可选)          水平后沿 (Horizontal Back Porch)
  hspw        : number  (可选)          水平同步脉宽
  hfp         : number  (可选)          水平前沿
  vbp         : number  (可选)          垂直后沿
  vspw        : number  (可选)          垂直同步脉宽
  vfp         : number  (可选)          垂直前沿
  bus_speed   : number  (可选, Hz)      RGB 总线速度，默认 51_000_000
  pclk        : lcd.PCLK_RISING or lcd.PCLK_FALLING  (可选) 像素时钟边沿

  [st7796 SPI 例]
  params = { port = lcd.HWID_0, pin_rst = 36, pin_pwr = 28, direction = 0, w = 320, h = 480 }

  [nv3052c_5in RGB 例]
  params = { port = lcd.RGB, pin_clk = 23, pin_sda = 22, pin_cs = 2, pin_rst = 15, direction = 0, w = 720, h = 1280 }

need_buffer  : boolean  RGB 屏需设为 true（启用帧缓冲），SPI 屏设为 false
screen_size  : number  屏幕物理尺寸(英寸)，用于 PPI 密度计算:
                        4.0  (4寸 SPI 屏)、5.0  (5寸屏)、7.0  (7寸屏)、10.0 (10.1寸屏)
font         : table   字体配置:
  size       : number  (12~255)         默认字体大小: 14(低分辨率) / 20(高分辨率)
  path       : string  (可选)           字体文件路径，如 "/MiSans_gb2312.ttf"
                         有 path → 从文件系统加载 ttf（Air8101 用）
                         无 path → 使用固件内置字库（其他平台）
  type       : string  (可选, "hzfont") 字体类型
  cache_size : number  (可选, 默认1024) 缓存字数
  antialias  : number  (可选, 1~4)      抗锯齿等级
  global     : boolean (可选)           是否全局注册

backlight    : table   背光 PWM 配置:
  pwm_ch     : number  (0~N)           PWM 通道号
  pwm_freq   : number  (Hz)            PWM 频率: 1000 / 10000

rotation     : number  (可选, 0|90|180|270)  屏幕旋转角度，默认 0
                         仅 st7701s_5in 的 Air8101 5寸屏需设为 180
]]

--[[
============================= hw.tp =============================
model        : string  触摸驱动模块名，目前唯一值: "tp_gt911"

params       : table   传给 tp_gt911.init() 的参数:
  port       : number  (0~2)           I2C 端口号
  pin_rst    : number  (0~255)         TP 复位引脚 GPIO
  pin_int    : number  (0~255) 或 gpio.WAKEUP0  TP 中断引脚 GPIO
  int_type   : tp.FALLING or tp.RISING (可选) 中断触发类型
  i2c_speed  : i2c.SLOW or i2c.FAST or i2c.HIGH (可选) I2C 速度，默认标准
  w          : number  (可选)          触摸面板宽度（大屏需设）
  h          : number  (可选)          触摸面板高度（大屏需设）
  gpio_reset : number  (可选)          GPIO 复位引脚，初始化前置低再释放

  例: params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0, i2c_speed = i2c.SLOW }
]]

--[[
============================= features 功能开关 =============================
全部 boolean 类型。

net_4g       : 是否启用 4G 网络
               需要额外配置 net_4g_config 来区分原生4G/airlink 4G（见下方）
wifi         : 是否启用 WiFi
ethernet     : 是否启用以太网
buzzer       : 是否有蜂鸣器
speaker      : 是否有喇叭
mic          : 是否有麦克风
sd_card      : 是否有 SD/tf 卡槽
nand_flash   : 是否有 NAND Flash
gnss         : 是否有 GPS/北斗定位
bluetooth    : 是否有蓝牙
can          : 是否有 CAN 总线
rs485        : 是否有 RS485 接口
usb_camera   : 是否有 USB 摄像头
spi_camera   : 是否有 SPI 摄像头
i2c_sensor   : 是否有 I2C 传感器 (SHT30/VOC等)

net_4g_config : table  (可选, 仅 net_4g=true 时有效)  4G 连接方式:
  不填或 type ~= "airlink"  → 原生 4G (Air8000/Air780E 系列)
  type = "airlink"           → airlink 外挂 4G (Air8101/Air1601 + Air780EPM)

  [airlink 4G 专属参数]
  type              : "airlink"
  airlink_type      : airlink.MODE_SPI_MASTER / airlink.MODE_SPI_SLAVE / airlink.MODE_UART
  airlink_spi_id    : number  (SPI模式)  SPI 接口 ID
  airlink_cs_pin    : number  (SPI模式)  片选 GPIO
  airlink_rdy_pin   : number  (SPI模式)  RDY GPIO
  airlink_uart_id   : number  (UART模式) UART 接口 ID
  airlink_uart_baud : number  (UART模式, 默认2000000) 波特率
  airlink_adapter   : number  (UART模式可选) 网卡标识, 如 socket.LWIP_USER0
  auto_socket_switch: boolean (可选, 默认true)

  例 (Air8101 SPI 外挂 Air780EPM):
  net_4g_config = {
      type = "airlink",
      airlink_type = airlink.MODE_SPI_MASTER,
      airlink_spi_id = 0,
      airlink_cs_pin = 15,
      airlink_rdy_pin = 48,
  }
]]

--[[
============================= ui 条件显示 =============================
全部 boolean 类型。控制 idle_win 桌面状态栏和设置页的显示。

show_4g_icon           : 桌面是否显示 4G 信号图标
show_wifi_icon         : 桌面是否显示 WiFi 信号图标
show_buzzer_settings   : 设置页是否显示蜂鸣器开关
show_brightness_slider : 设置页是否显示亮度调节滑块
show_ethernet_settings : 设置页是否显示以太网设置入口
show_storage_settings  : 设置页是否显示存储信息
show_camera_preview    : 是否显示摄像头预览入口
show_sensor_panel      : 是否显示传感器数据面板
]]

--[[
============================= pins 引脚配置 =============================
数组格式，每个元素 { pin = number, func = string }
pin  : GPIO 引脚编号
func : 引脚功能字符串，如 "PWM0", "I2C1_SDA", "I2C1_SCL", "SPI0_CLK" 等

例:
pins = {
    { pin = 31, func = "PWM0" },
    { pin = 11, func = "I2C1_SDA" },
}
]]

-- 以下为完整模板示例（不可直接使用，需按实际硬件修改）
--[[
return {
    name = "Engine_Air8000W_4inch_320x480_000_V000",
    chip = "Air8000W",
    baseboard = "合宙引擎主机8000W_V000",

    pins = {
        { pin = 31, func = "PWM0" },
    },

    hw = {
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0, pin_rst = 36, pin_pwr = 28,
                direction = 0, w = 320, h = 480,
            },
            need_buffer = false,
            screen_size = 4.0,
            font = { size = 14 },
            backlight = { pwm_ch = 0, pwm_freq = 1000 },
        },
        tp = {
            model = "tp_gt911",
            params = { port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0, i2c_speed = i2c.SLOW },
        },
    },

    features = {
        net_4g = true, wifi = true, ethernet = false, buzzer = true,
        speaker = false, mic = false, sd_card = false, nand_flash = false,
        gnss = false, bluetooth = false, can = false, rs485 = false,
        usb_camera = false, spi_camera = false, i2c_sensor = false,
    },

    ui = {
        show_4g_icon = true, show_wifi_icon = true,
        show_buzzer_settings = true, show_brightness_slider = true,
        show_ethernet_settings = false, show_storage_settings = false,
        show_camera_preview = false, show_sensor_panel = false,
    },
}
]]
