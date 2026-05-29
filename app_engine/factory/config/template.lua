--[[
@module  config.template
@summary 项目配置文件完整参数手册（新建配置文件时对照填写）
@version 2.0
@date    2026.05.25
@author  江访

================================================================================
                              使 用 说 明
================================================================================

  本文件是参数参考手册，不可直接作为配置文件使用。
  新建配置文件时，对照本手册逐项填写对应的参数值。

  每个字段标注:
    [必填] = 必须有值
    [可选] = 可省略，省略时使用默认值
    [条件] = 仅当其他字段为特定值时才需要

================================================================================
                          一、顶层字段
================================================================================

  name        string  [必填] 项目命名，与硬件设计文档一致
                 格式: "{类型}_{芯片}_{尺寸}_{版本}"
                 例: "Engine_Air1602_7inch_1024x600_004_V000"
                      "EVB_Air8000A_3inch5_480x320_000_V020"

  chip        string  [必填] 主控芯片型号，必须是以下之一:
                 Air1601    RGB屏 + WiFi(airlink)       无4G
                 Air1602    同 Air1601
                 Air8000W   4G + WiFi(exnetif) + SPI屏  无蓝牙/以太网/CAN
                 Air8000A   4G + WiFi + GPS + SPI屏
                 Air8000D   4G + WiFi + GPS + SPI屏
                 Air8000    兼容 Air8000A/Air8000D
                 Air8101    WiFi(exnetif) + RGB屏       无4G
                 Air8101B   同 Air8101 (更小封装)
                 Air780EGG  4G + GPS + 以太网 + CAN     无WiFi
                 Air780EHV  4G + 以太网 + CAN           无WiFi/GPS
                 Air780EHU  同 Air780EHV
                 Air780EHM  同 Air780EHV
                 Air780EHN  同 Air780EHV
                 PC         PC 模拟器

  baseboard   string  [必填] 底板型号描述，自由文本
                 例: "合宙引擎AIR1602 V004"
                     "Air8000A trunkey 开发板 V020"

================================================================================
                          二、pins — 引脚功能复用
================================================================================

  pins        table   [可选] 引脚复用配置数组，不设则为空表 {}
                 每个元素 { pin = GPIO编号, func = 功能字符串 }
                 用于告诉芯片该引脚工作在哪种功能模式(PWM/I2C/SPI等)

                 常用 func 值:
                   "PWM0" ~ "PWM4"    PWM 输出通道
                   "I2C1_SDA"          I2C1 数据线
                   "I2C1_SCL"          I2C1 时钟线
                   "SPI0_CLK"          SPI0 时钟
                   "SPI0_MOSI"         SPI0 主机输出
                   "SPI0_MISO"         SPI0 主机输入

                 例: pins = {
                     { pin = 31, func = "PWM0" },
                     { pin = 11, func = "I2C1_SDA" },
                 }

================================================================================
                          三、power_on — GPIO 上电时序
================================================================================

  power_on    table   [可选] GPIO 上电步骤数组，不设则省略整个字段
                 上电时按数组顺序依次执行，每个步骤格式:

                 { pin = GPIO编号, dir = 方向, level = 电平, delay = 延时ms }

                 pin    number  [必填] GPIO 引脚号 (0~255)
                 dir    number  [必填] 0=输出模式, 1=输入模式
                 level  number  [必填] 输出模式: 0=低电平, 1=高电平
                                      输入模式: 0=下拉, 1=上拉
                 delay  number  [可选] 本步完成后等待的毫秒数(ms)

                 适用场景:
                 - LCD 供电 GPIO 使能
                 - TP 触摸 I2C 总线上拉
                 - WiFi/4G 模组上电复位时序
                 - NAND Flash 供电使能

                 注意: 由 platform_loader 在协程中异步执行，不阻塞主线程

                 例1 — Air1602 WiFi 模组上电(高电平有效):
                 power_on = {
                     { pin = 55, dir = 0, level = 0, delay = 50  },  -- 拉低 50ms 复位
                     { pin = 55, dir = 0, level = 1, delay = 120 },  -- 拉高 120ms 使能
                 }

                 例2 — Air8000A LCD供电 + TP I2C上拉 + 100ms稳定等待:
                 power_on = {
                     { pin = 141, dir = 0, level = 1             },  -- LCD 供电开
                     { pin = 147, dir = 1, level = 1             },  -- TP I2C SDA 上拉
                     { pin = 164, dir = 1, level = 1             },  -- TP I2C SCL 上拉
                     { pin = 17,  dir = 1, level = 1             },
                     { pin = 16,  dir = 1, level = 1, delay = 100 }, -- 最后一步等 100ms
                 }

================================================================================
                          四、hw.lcd — 屏幕驱动
================================================================================

  hw.lcd      table   [必填] 屏幕硬件配置

  ├─ model    string  [必填] 屏幕驱动模块名，必须是以下之一:
  │               "lcd_st7796"       SPI 屏 ST7796  (3.5寸/4寸, 320×480 或 480×320)
  │               "lcd_nv3052c_5in"  RGB 屏 NV3052C (5寸, 720×1280)
  │               "lcd_st7701s_5in"  RGB 屏 ST7701S (5寸, 480×854)
  │               "lcd_hx8282_10in"  RGB 屏 HX8282  (7寸/10.1寸, 1024×600, 四合一)
  │
  ├─ params   table   [必填] 传给驱动 init() 的引脚和时序参数
  │   │
  │   │  ———— 以下参数所有 model 通用 ————
  │   │
  │   ├─ port       any    [必填] 接口类型:
  │   │                 SPI屏: lcd.HWID_0 (硬件SPI端口0)
  │   │                 RGB屏: lcd.RGB
  │   │
  │   ├─ pin_rst    number [必填] LCD 复位引脚 GPIO 编号 (0~255)
  │   │
  │   ├─ direction  number [必填] 屏幕显示方向:
  │   │                 0 = 0°   1 = 90°   2 = 180°   3 = 270°
  │   │                 注意: w/h 参数填的是物理分辨率,方向由芯片内部旋转
  │   │
  │   ├─ w          number [必填] 水平分辨率 (像素), 如 480 / 720 / 1024
  │   ├─ h          number [必填] 竖直分辨率 (像素), 如 320 / 1280 / 600
  │   │
  │   ├─ xoffset    number [可选,默认0] X 方向像素偏移 (通常不填)
  │   ├─ yoffset    number [可选,默认0] Y 方向像素偏移 (通常不填)
  │   │
  │   │  ———— lcd_st7796 SPI 屏专属 ————
  │   │
  │   ├─ pin_pwr    number [可选] 背光/供电 GPIO (设为输出高)
  │   │                 注: 如果供电在 power_on 中已处理,则此处不填
  │   │
  │   ├─ bus_speed  number [可选] SPI 总线时钟频率 (Hz)
  │   │                 推荐值: 80000000 (80MHz)
  │   │                 不填则使用内核默认速度
  │   │
  │   │  ———— lcd_nv3052c_5in / lcd_st7701s_5in / lcd_hx8282_10in RGB 屏专属 ————
  │   │
  │   ├─ pin_clk    number [条件] SPI 时钟引脚 (RGB屏初始化通信用)
  │   ├─ pin_sda    number [条件] SPI 数据引脚
  │   ├─ pin_cs     number [条件] SPI 片选引脚
  │   │                 注: hx8282 屏不需要这三个引脚(内部 HX8282 芯片初始化)
  │   │
  │   ├─ hbp        number [可选] 水平后沿 (Horizontal Back Porch)
  │   ├─ hspw       number [可选] 水平同步脉宽 (Horizontal Sync Pulse Width)
  │   ├─ hfp        number [可选] 水平前沿 (Horizontal Front Porch)
  │   ├─ vbp        number [可选] 垂直后沿 (Vertical Back Porch)
  │   ├─ vspw       number [可选] 垂直同步脉宽 (Vertical Sync Pulse Width)
  │   ├─ vfp        number [可选] 垂直前沿 (Vertical Front Porch)
  │   │                 注: 以上时序参数有默认值,通常无需填写
  │   │                    hx8282 默认: hbp=120 hspw=40 hfp=150 vbp=23 vspw=10 vfp=12
  │   │                    nv3052c 默认: hbp=46  hspw=2  hfp=48  vbp=24 vspw=2  vfp=24
  │   │
  │   ├─ bus_speed  number [可选] RGB 总线时钟频率 (Hz), 默认 51000000 (51MHz)
  │   ├─ pclk       any    [可选] 像素时钟边沿: lcd.PCLK_RISING / lcd.PCLK_FALLING
  │   │
  │   │  ———— 各驱动典型配置示例 ————
  │   │
  │   │  [st7796 SPI, 3.5寸 480×320 横屏]:
  │   │  params = {
  │   │      port = lcd.HWID_0, pin_rst = 36, direction = 1,
  │   │      w = 480, h = 320, bus_speed = 80000000,
  │   │  }
  │   │
  │   │  [nv3052c RGB, 5寸 720×1280 竖屏]:
  │   │  params = {
  │   │      port = lcd.RGB, pin_clk = 23, pin_sda = 22, pin_cs = 2,
  │   │      pin_rst = 15, direction = 0, w = 720, h = 1280,
  │   │  }
  │   │
  │   │  [hx8282 RGB, 7寸 1024×600]:
  │   │  params = { port = lcd.RGB, pin_rst = 15, direction = 0, w = 1024, h = 600 }
  │   │
  │   │  [st7701s RGB, 5寸 480×854, Air8101]:
  │   │  params = {
  │   │      port = lcd.RGB, pin_clk = 72, pin_sda = 71, pin_cs = 6,
  │   │      pin_rst = 28, direction = 0, w = 480, h = 854,
  │   │  }
  │
  ├─ need_buffer  boolean [必填] 是否启用帧缓冲:
  │                   RGB 屏必须填 true  (防止画面撕裂)
  │                   SPI 屏必须填 false (直刷更快)
  │
  ├─ screen_size  number  [必填] 屏幕物理尺寸(英寸), 用于计算 UI 缩放比例:
  │                   3.5  3.5寸屏
  │                   4.0  4寸屏
  │                   5.0  5寸屏
  │                   7.0  7寸屏
  │                   10.0 10.1寸屏
  │
  ├─ font         table   [必填] 字体配置:
  │   ├─ size       number [必填] 默认字号:
  │   │                 低分辨率屏(≤480px): 14
  │   │                 高分辨率屏(≥720px): 20
  │   │
  │   ├─ path       string [可选] 外部字体文件路径, 如 "/MiSans_gb2312.ttf"
  │   │                 填了路径 → 从文件系统加载 ttf 字体 (如 Air8101)
  │   │                 不填     → 使用固件编译时内置的字库 (其他平台)
  │   │
  │   ├─ type       string [可选,默认"hzfont"] 字体类型
  │   ├─ cache_size number [可选,默认1024]     字形缓存数量
  │   ├─ antialias  number [可选,默认1]        抗锯齿等级 (1~4)
  │   └─ global     boolean [可选]             是否注册为全局字体
  │
  ├─ backlight    table   [必填] 背光 PWM 配置:
  │   ├─ pwm_ch     number [必填] PWM 通道号 (0~N)
  │   └─ pwm_freq   number [必填] PWM 频率 (Hz), 常用 1000 或 10000
  │
  └─ rotation    number  [可选,默认0] 额外旋转角度 (0/90/180/270)
                     仅 Air8101 5寸 st7701s 屏需设为 180

================================================================================
                          五、hw.tp — 触摸驱动
================================================================================

  hw.tp       table   [可选] 触摸硬件配置，无触摸屏则省略整个 hw.tp

  ├─ model    string  [必填] 触摸驱动模块名，目前唯一值: "tp_gt911"
  │
  └─ params   table   [必填] 传给 tp_gt911.init() 的引脚参数:
      │
      ├─ port       number [必填] I2C 端口号 (0 / 1 / 2)
      │
      ├─ pin_rst    number [必填] GT911 复位引脚 GPIO 编号
      │                 填 0xff 表示不复位 (部分底板无需复位引脚)
      │
      ├─ pin_int    any    [必填] GT911 中断引脚:
      │                 普通 GPIO: 直接填编号, 如 51
      │                 唤醒引脚: gpio.WAKEUP0 (Air8000 系列常用)
      │
      ├─ int_type   any    [可选] 中断触发类型: tp.FALLING(下降沿) / tp.RISING(上升沿)
      │                 大屏(7寸/10寸)建议填 tp.FALLING
      │
      ├─ i2c_speed  any    [可选] I2C 通信速率:
      │                 i2c.SLOW  (低速, 推荐)
      │                 i2c.FAST  (快速)
      │                 i2c.HIGH  (高速)
      │                 不填则使用芯片默认速率
      │
      ├─ w          number [可选] 触摸面板物理宽度, 大屏(≥7寸)建议填写
      ├─ h          number [可选] 触摸面板物理高度, 大屏(≥7寸)建议填写
      │
      ├─ gpio_reset number [可选] 额外复位 GPIO:
      │                 初始化时先置低再释放 (Air1602 系列常用)
      │
      ├─ pwr_pins   table  [可选] I2C 供电 GPIO 上拉列表:
      │                 格式: { { pin = GPIO号 }, { pin = GPIO号 }, ... }
      │                 每个 pin 会执行 gpio.setup(pin, 1, gpio.PULLUP)
      │                 设置后自动等待 pwr_delay 毫秒再初始化 I2C
      │                 如果供电已在 power_on 中统一处理, 此处可省略
      │
      └─ pwr_delay  number [可选] I2C 上电后稳定等待时间(ms)
                      即使没有 pwr_pins, 设了 pwr_delay 也会等待
                      有 pwr_pins 时默认 100ms

      典型配置示例:

      [Air8000A trunkey, 不复位]:
      params = {
          port = 0, pin_rst = 0xff, pin_int = gpio.WAKEUP0,
          i2c_speed = i2c.SLOW, pwr_delay = 100,
      }

      [Air1602 7/10寸大屏, 带复位引脚]:
      params = {
          port = 1, pin_rst = 3, pin_int = 51, int_type = tp.FALLING,
          w = 1024, h = 600, gpio_reset = 3,
      }

      [Air8000W/Air8101 通用]:
      params = {
          port = 0, pin_rst = 26, pin_int = gpio.WAKEUP0,
          i2c_speed = i2c.SLOW,
      }

================================================================================
                          六、hw.battery — 电池管理 (条件)
================================================================================

  hw.battery   table   [条件] 仅 features.battery = true 时有效

    ├─ adc_channel         number [必填] ADC 通道号

    ├─ usb_detect_gpio     number [必填] USB 插入检测 GPIO 引脚号

    ├─ voltage_divider     number [可选,默认2] 电池电压分压比

    ├─ full_voltage        number [可选,默认4150] 电池充满判定电压 (mV)

    └─ no_battery_threshold number [可选,默认1500] 无电池判定电压阈值 (mV)

    例 (Air1602):
    hw = {
        -- ... lcd, tp 等其他配置 ...
        battery = {
            adc_channel = 7,
            usb_detect_gpio = 52,
            voltage_divider = 2,
            full_voltage = 4150,
        },
    }

================================================================================
                          七、features — 功能开关
================================================================================

  features    table   [必填] 硬件功能开关，全部 boolean 类型 (true/false)
                 只控制软件是否启用该功能,不会改变硬件

    字段名       默认值    说明
    ─────────────────────────────────────────────────────────────
     net_4g       false    是否启用 4G 蜂窝网络
                            原生4G:  Air8000W/Air8000A/Air780E 系列
                            airlink: Air8101/Air1601 外挂 Air780EPM (需另配 net_4g_config)
     wifi         false    是否启用 WiFi
     ethernet     false    是否启用以太网
     buzzer       false    是否有蜂鸣器(触摸反馈音)
                            无硬件时必须设为 false,否则启动报错
     speaker      false    是否有喇叭
     mic          false    是否有麦克风
     sd_card      false    是否有 SD/TF 卡槽
                            设为 true 时必须同时配置 storage.sd_card
     nand_flash   false    是否有 NAND Flash 存储
                            设为 true 时必须同时配置 storage.nand_flash
     gnss         false    是否有 GPS/北斗 定位
     bluetooth    false    是否有蓝牙
     can          false    是否有 CAN 总线接口
     rs485        false    是否有 RS485 接口
      usb_camera   false    是否有 USB 摄像头
      spi_camera   false    是否有 SPI 摄像头
      i2c_sensor   false    是否有 I2C 传感器 (SHT30温湿度/VOC等)
        nes          false    是否启用 NES 游戏实体按键（GPIO 按键注册 + 组合键处理）
                             设为 true 时必须同时配置 nes_keys 数组
                             加载 app/nes/nes_key_app.lua 模块
                             发布 NES_KEY/NES_DIR/NES_CTRL/NES_COMBO 全局事件
      battery      false    是否有电池管理（ADC 电压检测 + USB 充电检测）
                             设为 true 时必须同时配置 hw.battery

     例:
    features = {
        net_4g = true,  wifi = true,  ethernet = false, buzzer = false,
        speaker = false, mic = false, sd_card = false,  nand_flash = true,
        gnss = false,    bluetooth = false, can = false, rs485 = false,
        usb_camera = false, spi_camera = false, i2c_sensor = false,
        battery = false,  -- 是否启用电池管理（充电检测、电量显示）
    }

================================================================================
                                             八、net_4g_config — 4G 连接方式 (条件)
================================================================================

  net_4g_config  table  [条件] 仅 features.net_4g = true 时有效
                    不填或 type ~= "airlink" → 使用芯片内置4G
                    type = "airlink"          → 外挂 airlink 4G 模组

  [airlink 4G 参数 — 仅 type="airlink" 时需要]:

    type                string  [必填] "airlink"
    airlink_type        any     [必填] 通信模式:
                              airlink.MODE_SPI_MASTER  (SPI 主模式, 常用)
                              airlink.MODE_SPI_SLAVE   (SPI 从模式)
                              airlink.MODE_UART        (UART 模式)
    ── SPI 模式专属 ──
    airlink_spi_id      number  [条件] SPI 接口 ID
    airlink_cs_pin      number  [条件] 片选 GPIO
    airlink_rdy_pin     number  [条件] 就绪 GPIO
    ── UART 模式专属 ──
    airlink_uart_id     number  [条件] UART 接口 ID
    airlink_uart_baud   number  [可选,默认2000000] 波特率
    airlink_adapter     number  [可选] 网卡标识, 如 socket.LWIP_USER0
    ── 通用 ──
    auto_socket_switch  boolean [可选,默认true]

    例 (Air8101 SPI 外挂 Air780EPM):
    net_4g_config = {
        type = "airlink",
        airlink_type = airlink.MODE_SPI_MASTER,
        airlink_spi_id = 0,
        airlink_cs_pin = 15,
        airlink_rdy_pin = 48,
    }

================================================================================
                          九、ui — UI 界面显示控制
================================================================================

  ui          table   [必填] UI 界面元素显隐开关，全部 boolean 类型

    字段名                  默认值    说明
    ─────────────────────────────────────────────────────────────
     show_4g_icon            false    桌面顶栏是否显示 4G 信号图标
     show_wifi_icon          false    桌面顶栏是否显示 WiFi 信号图标
     show_buzzer_settings    false    设置页是否显示蜂鸣器(触摸声音)开关
     show_brightness_slider  false    设置页是否显示亮度调节滑块
     show_ethernet_settings  false    设置页是否显示以太网设置入口
     show_storage_settings   false    设置页是否显示存储空间查看入口
      show_camera_preview     false    是否显示摄像头预览入口
      show_sensor_panel       false    是否显示传感器数据面板
      show_battery_icon       false    桌面顶栏是否显示电池图标

     例 (Air1602 7寸 WiFi版):
    ui = {
        show_4g_icon = false, show_wifi_icon = true,
        show_buzzer_settings = false, show_brightness_slider = true,
        show_ethernet_settings = false, show_storage_settings = true,
        show_camera_preview = false, show_sensor_panel = false,
        show_battery_icon = true,
    }

================================================================================
                          十、storage — 存储设备配置 (条件)
================================================================================

  storage     table   [条件] 仅当 features.sd_card 或 features.nand_flash
                         为 true 时才需要配置此字段

  ├─ sd_card   table   [条件] SD/TF 卡 SPI 参数 (features.sd_card=true 时需要):
  │   ├─ spi_id    number [必填] SPI 接口 ID (0 / 1 / 2 / ...)
  │   ├─ pin_cs    number [必填] 片选 CS 引脚 GPIO 编号
  │   └─ speed     number [必填] SPI 时钟频率 (Hz)
  │                   推荐值: 20000000 (20MHz, 高速卡)
  │                         2000000  (2MHz,  兼容模式, Air8000 常用)
  │
  └─ nand_flash  table  [条件] NAND Flash SPI 参数 (features.nand_flash=true 时需要):
      ├─ spi_id    number [必填] SPI 接口 ID
      ├─ pin_cs    number [必填] 片选 CS 引脚 GPIO 编号
      ├─ speed     number [必填] SPI 时钟频率 (Hz), 推荐 20000000
      └─ pin_pwr   number [可选] NAND Flash 供电使能 GPIO
                      注: 如果供电在 power_on 中已统一处理,此处可省略

    例1 (SD 卡):
    storage = {
        sd_card = { spi_id = 0, pin_cs = 32, speed = 20000000 },
    }

    例2 (NAND Flash, 含供电引脚):
    storage = {
        nand_flash = { spi_id = 2, pin_cs = 4, speed = 20000000, pin_pwr = 50 },
    }

================================================================================
                                            十一、完整配置示例 (Air1602 7寸 NAND版)
================================================================================

return {
    name = "Engine_Air1602_7inch_1024x600_004_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V004",

    pins = {},

    -- WiFi 模组上电: GPIO55 先高后低 (低电平有效)
    power_on = {
        { pin = 55, dir = 0, level = 1, delay = 50 },
        { pin = 55, dir = 0, level = 0, delay = 120 },
    },

    hw = {
        lcd = {
            model = "lcd_hx8282_10in",
            params = { port = lcd.RGB, pin_rst = 15, direction = 0, w = 1024, h = 600 },
            need_buffer = true,
            screen_size = 7.0,
            font = { size = 20 },
            backlight = { pwm_ch = 3, pwm_freq = 1000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1, pin_rst = 3, pin_int = 51,
                int_type = tp.FALLING, w = 1024, h = 600, gpio_reset = 3,
            },
        },
    },

    features = {
        net_4g = false, wifi = true, ethernet = false, buzzer = false,
        speaker = false, mic = false, sd_card = false, nand_flash = true,
        gnss = false, bluetooth = false, can = false, rs485 = false,
        usb_camera = false, spi_camera = false, i2c_sensor = false,
        nes = false,  -- 是否启用NES游戏按键GPIO绑定（需同时配置 nes_keys）
    },

    -- NES游戏按键绑定（可选，GPIO引脚 → NES按键），不需要时设为 nil 或空数组 {}
    -- 按键类型根据 key 名称自动分类（nes_key_app v3.0）：
    --   方向键: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    --           → 支持8方向组合（同时按两个相邻方向键=对角线方向，如左上/右上/左下/右下）
    --           → 支持持续按住（nes_widget 状态型接口，无需重复发布）
    --   动作键: NES_KEY_A / NES_KEY_B
    --           → 200ms窗口内先后按下触发 NES_COMBO("AB") 组合事件（组合优先，抑制单键）
    --           → 超出窗口则正常发布 NES_KEY 单键事件
    --   控制键: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    --           → 仅单次触发（按下沿）+ 200ms软件防抖
    --
    -- 发布事件（供后装APP订阅）：
    --   NES_KEY(key, pressed)   — key="UP"/"DOWN"/"LEFT"/"RIGHT"/"A"/"B", pressed=1按下/0释放
    --   NES_DIR(direction)      — 0=NONE, 1=UP, 2=UP_RIGHT, 3=RIGHT, 4=DOWN_RIGHT,
    --                                    5=DOWN, 6=DOWN_LEFT, 7=LEFT, 8=UP_LEFT
    --   NES_CTRL(key)           — key="RETURN"/"START"/"SELECT"，仅按下沿发布
    --   NES_COMBO(combo)        — combo="AB"，A+B同时按下时发布
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        { pin =  1, key = "NES_KEY_RETURN" }, -- 返回（退出APP）
        { pin =  0, key = "NES_KEY_START" },  -- 开始
        { pin = 22, key = "NES_KEY_SELECT"},  -- 选择
        { pin = 23, key = "NES_KEY_A"     },  -- A
        { pin = 13, key = "NES_KEY_B"     },  -- B
    },

    ui = {
        show_4g_icon = false, show_wifi_icon = true,
        show_buzzer_settings = false, show_brightness_slider = true,
        show_ethernet_settings = false, show_storage_settings = true,
        show_camera_preview = false, show_sensor_panel = false,
    },

    storage = {
        nand_flash = { spi_id = 2, pin_cs = 4, speed = 20000000, pin_pwr = 50 },
    },
}
]]
