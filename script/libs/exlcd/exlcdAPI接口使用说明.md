# exlcd 显示拓展库

## 一、概述

exlcd 显示拓展库是 LuatOS 的 LCD 显示扩展模块，提供 LCD 显示屏初始化、背光亮度 0-100 级控制、屏幕休眠、屏幕休眠唤醒、查询休眠状态等功能。

## 二、核心示例

1、核心示例是指：使用本库文件提供的核心 API，开发的基础业务逻辑的演示代码；

2、核心示例的作用是：帮助开发者快速理解如何使用本库，所以核心示例的逻辑都比较简单；

3、更加完整和详细的 demo，请参考 [LuatOS 仓库](https://gitee.com/openLuat/LuatOS/tree/master/module) 中各个产品目录下的 demo/exlcd

```lua
-- LCD显示功能演示
local function lcd_demo()
    -- 初始化SPI总线（SPI屏幕需要）
    spi.deviceSetup(lcd.HWID_0, 20, 0, 0, 8, 2000000, spi.MSB, 1, 1)
    
    -- 初始化LCD显示屏
    local result = exlcd.init({
        LCD_MODEL = "AirLCD_1000",
        port = lcd.HWID_0,
        pin_vcc = 141, 
        pin_pwm = 2, 
        pin_pwr = 25,
        pin_rst = 19,
        direction = 1,
        w = 480,
        h = 320,
        xoffset = 0,
        yoffset = 0
    })
    
    if result then
        log.info("LCD初始化成功")
        
        -- 设置背光亮度为50%
        exlcd.bkl(50)
        
        -- 在屏幕上显示内容
        lcd.clear(0x00FF)  -- 蓝色背景
        lcd.setFont(lcd.font_opposansm32) -- 设置32号英文字体
        lcd.setColor(0xFFFF, 0x0000)  -- 白底黑字
        lcd.drawStr(20,172,"hello hezhou") -- 使用默认颜色绘制32号"hello hezhou"
        
        lcd.setFont(lcd.font_opposansm12_chinese) -- 设置12号中文字体
        lcd.drawStr(230, 420, "你好合宙", 0xFFFF)  -- 绘制白色文字"你好合宙"
        
        lcd.flush()  --更新数据到屏幕
        
        -- 5秒后进入休眠
        sys.wait(5000)
        exlcd.sleep()
        
        -- 10秒后唤醒
        sys.wait(10000)
        exlcd.wakeup()
        exlcd.bkl(80)  -- 设置背光为80%
    else
        log.error("LCD初始化失败")
    end
end

-- 创建LCD任务
sys.taskInit(lcd_demo)
```

## 三、常量详解

exlcd 显示拓展库没有常量。

## 四、函数详解

### exlcd.init(args)

**功能**

初始化 LCD 显示屏，配置相应的显示芯片和参数

**参数 ：args**

```lua
含义说明：args：table类型，LCD初始化参数配置表，table内容格式说明如下：
{
    LCD_MODEL = ,
    -- 参数含义：LCD显示屏型号；
    -- 数据类型：string；
    -- 取值范围："AirLCD_1000"、"AirLCD_1001"、"Air780EHM_LCD_1"、"Air780EHM_LCD_2"、"Air780EHM_LCD_3"、"Air780EHM_LCD_4"、"AirLCD_1020"、"st7735s"、"h050iwv"、"custom"等；
    -- 是否必选：必须传入此参数；
    -- 注意事项：必须使用支持的型号，否则初始化失败；
    -- 参数示例："AirLCD_1000"
    
    port = ,
    -- 参数含义：LCD端口标识；
    -- 数据类型：string或number；
    -- 取值范围：lcd.HWID_0、lcd.RGB、（SPI设备号）0、1、2或"device"；
    -- 是否必选：必须传入此参数；
    -- 注意事项：SPI屏幕需要先初始化SPI总线；
    -- 参数示例：lcd.HWID_0 或 "device"


    pin_vcc = ,
    -- 参数含义：电源控制引脚；
    -- 数据类型：number；
    -- 取值范围：有效的GPIO引脚编号；
    -- 是否必选：必须传入此参数；
    -- 注意事项：用于控制LCD模块的整体电源；
    -- 参数示例：141

    pin_pwm = ,
    -- 参数含义：PWM背光控制引脚；
    -- 数据类型：number；
    -- 取值范围：有效的引脚PWM编号；
    -- 是否必选：可选传入此参数；
    -- 注意事项：用于PWM调光，需要支持PWM功能的引脚；
    -- 参数示例：2

    pin_pwr = ,
    -- 参数含义：背光电源控制引脚；
    -- 数据类型：number；
    -- 取值范围：有效的GPIO引脚编号；
    -- 是否必选：LCD屏幕必须传入此参数传入此参数；
    -- 注意事项：用于背光的开关控制；
    -- 参数示例：25

    pin_rst = ,
    -- 参数含义：复位引脚；
    -- 数据类型：number；
    -- 取值范围：有效的GPIO引脚编号；
    -- 是否必选：LCD屏必须传入此参数；
    -- 注意事项：用于LCD芯片的硬件复位；
    -- 参数示例：19

    direction = ,
    -- 参数含义：屏幕显示方向；
    -- 数据类型：number；
    -- 取值范围：0-3，分别对应不同的旋转角度；
    -- 是否必选：LCD屏必须传入此参数；
    -- 注意事项：不同LCD芯片支持的方向可能不同；
    -- 参数示例：1

    w = ,
    -- 参数含义：屏幕宽度；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：必须传入此参数；
    -- 注意事项：必须与实际屏幕分辨率一致；
    -- 参数示例：480

    h = ,
    -- 参数含义：屏幕高度；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：必须传入此参数；
    -- 注意事项：必须与实际屏幕分辨率一致；
    -- 参数示例：320

    xoffset = ,
    -- 参数含义：X轴偏移量；
    -- 数据类型：number；
    -- 取值范围：非负整数；
    -- 是否必选：LCD屏必须传入此参数；
    -- 注意事项：用于调整显示位置；
    -- 参数示例：0

    yoffset = ,
    -- 参数含义：Y轴偏移量；
    -- 数据类型：number；
    -- 取值范围：非负整数；
    -- 是否必选：LCD屏必须传入此参数；
    -- 注意事项：用于调整显示位置；
    -- 参数示例：0

    hbp = ,
    -- 参数含义：水平后廊；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：46

    hspw = ,
    -- 参数含义：水平同步脉冲宽度；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：2

    hfp = ,
    -- 参数含义：水平前廊；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：48

    vbp = ,
    -- 参数含义：垂直后廊；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：24

    vspw = ,
    -- 参数含义：垂直同步脉冲宽度；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：2

    vfp = ,
    -- 参数含义：垂直前廊；
    -- 数据类型：number；
    -- 取值范围：正整数；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：24

    bus_speed = ,
    -- 参数含义：总线速度；
    -- 数据类型：number；
    -- 取值范围：正整数，单位Hz；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：60000000

    initcmd = ,
    -- 参数含义：初始化命令序列；
    -- 数据类型：table；
    -- 取值范围：命令字节数组；
    -- 是否必选：可选传入此参数；
    -- 注意事项：自定义驱动时使用；
    -- 参数示例：{0xAE, 0x20, 0x10, 0x00}
    
    spi_dev = ,   
    -- 参数含义：SPI设备对象；
    -- 数据类型：userdata；
    -- 取值范围：有效的SPI设备对象；
    -- 是否必选：可选传入此参数；
    -- 注意事项：当port = "device"时有效，当port ≠ "device"时可不填或者填nil；
    -- 参数示例：spi_lcd

    init_in_service = ,
    -- 参数含义：是否在LCD服务中初始化；
    -- 数据类型：boolean；
    -- 取值范围：true或false；
    -- 是否必选：可选传入此参数，默认值为false；
    -- 注意事项：允许初始化在lcd service里运行，在后台初始化LCD；Air8000/G/W/T/A、Air780EHM/EGH/EHV 支持填true，可加快初始化速度；
    -- 参数示例：true

}
```

**返回值**

- boolean 类型，初始化是否成功
  - true：初始化成功
  - false：初始化失败

**示例**

```lua
-- SPI屏幕初始化
spi.deviceSetup(lcd.HWID_0, 20, 0, 0, 8, 2000000, spi.MSB, 1, 1)
local result = exlcd.init({
    LCD_MODEL = "AirLCD_1000",
    port = lcd.HWID_0,
    pin_vcc = 141, 
    pin_pwm = 2, 
    pin_pwr = 25,
    pin_rst = 19,
    direction = 1,
    w = 480,
    h = 320,
    xoffset = 0,
    yoffset = 0
})
log.info("LCD初始化结果", result)

-- RGB屏幕初始化
local result = exlcd.init({
    LCD_MODEL = "AirLCD_1020",
    port = lcd.RGB,
    w = 800,
    h = 480
})
```

### exlcd.bkl(level)

**功能**

设置 LCD 背光亮度级别

**参数**

```lua
level：number类型，背光亮度级别
参数含义：背光亮度百分比；
数据类型：number；
取值范围：0-100，0表示关闭背光，100表示最大亮度；
是否必选：必须传入此参数；
注意事项：屏幕休眠状态下无法调节背光；
参数示例：50
```

**返回值**

- boolean 类型，操作是否成功
  - true：操作成功
  - false：操作失败

**示例**

```lua
-- 设置背光亮度为50%
local success = exlcd.bkl(50)
if success then
    log.info("背光设置成功")
else
    log.error("背光设置失败")
end

-- 关闭背光
exlcd.bkl(0)

-- 最大亮度
exlcd.bkl(100)
```

### exlcd.sleep()

**功能**

使 LCD 显示屏进入休眠状态

**参数**

无

**返回值**

无

**示例**

```lua
-- 使屏幕进入休眠
exlcd.sleep()
log.info("屏幕已进入休眠状态")
```

### exlcd.wakeup()

**功能**

从休眠状态唤醒 LCD 显示屏

**参数**

无

**返回值**

无

**示例**

```lua
-- 唤醒屏幕
exlcd.wakeup()
log.info("屏幕已唤醒")

-- 唤醒后恢复之前的背光设置
exlcd.bkl(exlcd.get_brightness())
```

### exlcd.get_brightness()

**功能**

获取当前背光亮度级别

**参数**

无

**返回值**

- number 类型，当前背光亮度级别（0-100）

**示例**

```lua
local brightness = exlcd.get_brightness()
log.info("当前背光亮度", brightness, "%")
```

### exlcd.is_sleeping()

**功能**

获取当前 LCD 休眠状态

**参数**

无

**返回值**

- boolean 类型，当前休眠状态
  - true：屏幕处于休眠状态
  - false：屏幕处于唤醒状态

**示例**

```lua
local sleeping = exlcd.is_sleeping()
if sleeping then
    log.info("屏幕处于休眠状态")
else
    log.info("屏幕处于唤醒状态")
end
```

## 完整使用示例

```lua
-- 完整的LCD应用示例
local function complete_lcd_demo()
    -- 初始化SPI
    spi_lcd = spi.deviceSetup(0, 20, 0, 0, 8, 2000000, spi.MSB, 1, 1)
    
    -- 初始化LCD
    if not exlcd.init({
        LCD_MODEL = "Air780EHM_LCD_4",
        port = "device",
        pin_dc = 17, 
        pin_pwr = 7,
        pin_rst = 19,
        direction = 1,
        w = 480,
        h = 320,
        xoffset = 0,
        yoffset = 0,
    }) then
        log.error("LCD初始化失败")
        return
    end
    
    -- 在屏幕上显示内容
        lcd.clear(0x00FF)  -- 蓝色背景
        lcd.setFont(lcd.font_opposansm32) -- 设置32号英文字体
        lcd.setColor(0xFFFF, 0x0000)  -- 白底黑字
        lcd.drawStr(20,172,"hello hezhou") -- 使用默认颜色绘制32号"hello hezhou"
        
        lcd.setFont(lcd.font_opposansm12_chinese) -- 设置12号中文字体
        lcd.drawStr(230, 420, "你好合宙", 0xFFFF)  -- 绘制白色文字"你好合宙"
        
        lcd.flush()  --更新数据到屏幕
    
    -- 背光控制演示
    for i = 0, 100, 1 do
        exlcd.bkl(i)
        log.info("背光亮度", i, "%")
        sys.wait(500)
    end
    
    -- 休眠唤醒演示
    log.info("准备进入休眠")
    sys.wait(2000)
    exlcd.sleep()
    
    log.info("休眠5秒后唤醒")
    sys.wait(5000)
    exlcd.wakeup()
    exlcd.bkl(80)
    
    -- 显示唤醒后的内容
    lcd.clear(0x00FF00)
    lcd.drawStr(10, 30, "Welcome Back!", 0x000000, 0x00FF00)
    lcd.update()
end

sys.taskInit(complete_lcd_demo)
```

## 产品支持说明

支持 LuatOS 开发且能够支持 LCD 屏幕的模组。
