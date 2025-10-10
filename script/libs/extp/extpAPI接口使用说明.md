# extp 触摸拓展库

## 一、概述

extp 触摸扩展库是 tp 核心库功能的扩展，调用初始化接口完成初始化后，当有触摸操作时，不用再写程序去分析触摸数据，只需接收触摸时 extp 扩展库发布的手势消息和数据，只管触摸结果反馈即可。

extp 触摸扩展库发布的消息有 10 种，可以通过接口查询消息开启状态，控制发布哪些消息和关闭哪些消息。也能通过接口修改默认判定阈值，以适配多种尺寸触摸屏。

### **1.1 extp 触摸拓展库支持功能**

1. 通过 extp.init(args)接口进行初始化触摸芯片
2. 触摸操作会自动转换为对应的手势，然后通过全局消息发布，并携带手势类型和坐标参数。

   1. 消息格式为：`sys.publish("baseTouchEvent", event_type, arg1, arg2)`
   2. `baseTouchEvent` 为：发布的消息标志
   3. `event_type` 为：事件类型
   4. `arg1, arg2` 为：事件类型携带的参数
   5. `event_type` 包含事件和参数 `arg1, arg2` 有：
      1. RAW_DATA：原始触摸数据，`arg1` 为 tp_device, `arg2` 为 tp_data；
      2. TOUCH_DOWN：按下瞬间事件，`arg1` 为按下 x 坐标, `arg2` 为按下 y 坐标；
      3. MOVE_X：水平移动，`arg1` 为为水平移动距离, `arg2` 为 0；
      4. MOVE_Y：垂直移动，`arg1` 为 0, `arg2` 为垂直移动距离；
      5. SWIPE_LEFT：向左滑动，`arg1` 为向左滑动距离, `arg2` 为 0；
      6. SWIPE_RIGHT：向右滑动，`arg1` 为向右滑动距离, `arg2` 为 0；
      7. SWIPE_UP：向上滑动，`arg1` 为 0, `arg2` 为向上滑动距离；
      8. SWIPE_DOWN：向下滑动，`arg1` 为 0, `arg2` 为向下滑动距离；
      9. SINGLE_TAP：单击，`arg1` 为点击 x 坐标, `arg2` 为点击 y 坐标；
      10. LONG_PRESS：长按，`arg1` 为点击 x 坐标, `arg2` 为点击 y 坐标；
3. 提供触摸后消息发布打开/关闭的接口：extp.setPublishEnabled(msg_type, enabled)，支持单个打开/关闭、全部打开/关闭。
4. 提供获取单个/全部消息当前是开启/关闭状态查询接口：extp.getPublishEnabled(msg_type)。
5. 提供滑动多少像素点后判定滑动方向阈值修改接口 extp.setSlideThreshold(threshold)，以适配不同尺寸的屏幕，默认为 45 像素。
6. 提供单击和长按判定阈值修改接口 extp.setSlideThreshold(threshold)，默认按下到抬手时间在 500ms 内为单击，大于等于 500ms 为长按。

### 1.2 **extp** 触摸判断逻辑

- TOUCH_DOWN、MOVE_X、MOVE_Y 是按下至抬手的中间状态
- 按下至抬手后只能触发事件 SWIPE_LEF、SWIPE_RIGHT、SWIPE_UP、SWIPE_DOWN、SINGLE_TAP、LONG_PRESS 中的一个事件
- 当按下并移动，移动像素超过滑动判定阈值，

  如果触发的是水平移动 MOVE_X，抬手只会返回 SWIPE_LEFT 和 SWIPE_RIGHT 事件，

  如果触发的是垂直移动 MOVE_Y，抬手只会返回 SWIPE_UP 和 SWIPE_DOWN 事件，
- 按下至抬手像素移动超过滑动判定阈值，

  如果按下至抬手时间小于 500ms 判定为单击，按下至抬手时间大于 500ms 判定为长按

## 二、核心示例

1、核心示例是指：使用本库文件提供的核心 API，开发的基础业务逻辑的演示代码；

2、核心示例的作用是：帮助开发者快速理解如何使用本库，所以核心示例的逻辑都比较简单；

3、更加完整和详细的 demo，请参考 [LuatOS 仓库](https://gitee.com/openLuat/LuatOS/tree/master/module) 中各个产品目录下的 demo/extp

```lua
-- 触摸功能演示
local function touch_demo()
    -- 初始化I2C总线
    i2c.setup(1, i2c.SLOW)
    
    -- 初始化触摸屏
    local result = extp.init({
        TP_MODEL = "Air780EHM_LCD_4", 
        port = 1, 
        pin_rst = 20, 
        pin_int = 22
    })
    
    if result then
        log.info("触摸屏初始化成功")
    else
        log.error("触摸屏初始化失败")
        return
    end
    
    -- 订阅触摸事件
    while true do
        local result, event_type, arg1, arg2 = sys.waitUntil("baseTouchEvent", 1000)
        if result then
            if event_type == "TOUCH_DOWN" then
                log.info("按下事件", "X:", arg1, "Y:", arg2)
            elseif event_type == "SWIPE_LEFT" then
                log.info("向左滑动")
            elseif event_type == "SWIPE_RIGHT" then
                log.info("向右滑动")
            elseif event_type == "MOVE_X" then
                log.info("水平移动", "距离:", arg1)
            elseif event_type == "MOVE_Y" then
                log.info("垂直移动", "距离:", arg2)
            elseif event_type == "SINGLE_TAP" then
                log.info("单击", "X:", arg1, "Y:", arg2)
            elseif event_type == "LONG_PRESS" then
                log.info("长按", "X:", arg1, "Y:", arg2)
            elseif event_type == "RAW_DATA" then
                log.info("原始触摸数据", arg1, arg2)
            end
        end
    end
end

-- 创建触摸任务
sys.taskInit(touch_demo)
```

## 三、常量详解

**扩展库常量，顾名思义是由合宙 LuatOS 扩展库中定义的、不可重新赋值或修改的固定值，在脚本代码中不需要声明，可直接调用；**

extp 扩展库没有常量。

## 四、函数详解

### 4.1 extp.init(args)

**功能**

初始化触摸设备，配置相应的触摸芯片

**参数**  ：**args**

```lua
含义说明：args：table类型，初始化参数配置表，table内容格式说明如下：
{
    TP_MODEL = ,
    -- 参数含义：触摸芯片型号；
    -- 数据类型：string；
    -- 取值范围："cst820"、"cst9220"、"gt9157"、"jd9261t"、"AirLCD_1001"、"Air780EHM_LCD_3"、"Air780EHM_LCD_4"等；
    -- 是否必选：必须传入此参数；
    -- 注意事项：必须使用支持的型号，否则初始化失败；
    -- 参数示例："Air780EHM_LCD_4"

    port = ,
    -- 参数含义：I2C总线ID；
    -- 数据类型：number；
    -- 取值范围：有效的I2C总线编号,或者软件I2C，软件I2C会比硬件慢；
    -- 是否必选：必须传入此参数；
    -- 注意事项：需要先使用i2c.setup初始化对应的I2C总线；
    -- 参数示例：硬件I2C：0、1  软件I2C:i2c.createSoft(20, 21)

    pin_rst = ,
    -- 参数含义：复位引脚编号；
    -- 数据类型：number；
    -- 取值范围：有效的GPIO引脚编号；
    -- 是否必选：必须传入此参数；
    -- 注意事项：引脚需要正确连接到触摸芯片的复位引脚；
    -- 参数示例：20

    pin_int = 
    -- 参数含义：中断引脚编号；
    -- 数据类型：number；
    -- 取值范围：有效的GPIO引脚编号；
    -- 是否必选：必须传入此参数；
    -- 注意事项：引脚需要正确连接到触摸芯片的中断引脚；
    -- 参数示例：22
}
```

**返回值**

- boolean 类型，初始化是否成功
  - true：初始化成功
  - false：初始化失败

**示例 1 硬件 I2C 初始化**

```lua
i2c.setup(1, i2c.SLOW)
local result = extp.init({
    TP_MODEL = "Air780EHM_LCD_4", 
    port = 1, 
    pin_rst = 20, 
    pin_int = 22
})
log.info("初始化结果", result)
```

**示例 2 软件 I2C 初始化**

```lua
-- 创建软件I2C对象
local softI2C = i2c.createSoft(20, 21)  -- SCL=20, SDA=21

-- 初始化
local result = extp.init({
    TP_MODEL = "Air780EHM_LCD_4", 
    port = softI2C, 
    pin_rst = 20, 
    pin_int = 22
})
log.info("初始化结果", result)
```

### 4.2 extp.setPublishEnabled(msg_type, enabled)

**功能**

设置指定消息类型的发布状态，控制是否发布特定类型的触摸事件

**参数  ：msg_type**

```lua
含义说明：msg_type：string类型，消息类型
参数含义：要设置发布状态的消息类型；
数据类型：string；
取值范围："RAW_DATA"、"TOUCH_DOWN"、"MOVE_X"、"MOVE_Y"、"SWIPE_LEFT"、"SWIPE_RIGHT"、"SWIPE_UP"、"SWIPE_DOWN"、"SINGLE_TAP"、"LONG_PRESS"、"all"；
是否必选：必须传入此参数；
注意事项："all"表示设置所有消息类型的发布状态；
参数示例："MOVE_X"
```

**参数  ：enabled**

```lua
enabled：boolean类型，是否启用发布
参数含义：是否启用该消息类型的发布；
数据类型：boolean；
取值范围：true表示启用发布，false表示禁用发布；
是否必选：必须传入此参数；
注意事项：设置后会立即生效；
参数示例：true
```

**返回值**

- boolean 类型，操作是否成功
  - true：操作成功
  - false：操作失败

**示例**

```lua
-- 启用所有消息发布
extp.setPublishEnabled("all", true)

-- 禁用原始数据发布
extp.setPublishEnabled("RAW_DATA", false)

-- 启用水平移动消息发布
extp.setPublishEnabled("MOVE_X", true)
```

### 4.3 extp.getPublishEnabled(msg_type)

**功能**

获取指定消息类型的发布状态或所有消息类型的发布状态

**参数**  **:msg_type**

```go
含义说明：msg_type：string或nil类型，消息类型
参数含义：要获取发布状态的消息类型；
数据类型：string或nil；
取值范围：当为具体消息类型时，取值范围同setPublishEnabled；当为nil时表示获取所有消息状态；
是否必选：可选传入此参数；
注意事项：如果传入nil，则返回所有消息类型的发布状态表；
参数示例：nil 或 "MOVE_X"
```

**返回值**

- 当 msg_type 为具体消息类型时：boolean 类型，该消息类型的发布状态
- 当 msg_type 为 nil 时：table 类型，所有消息类型的发布状态表
- 当 msg_type 无效时：false，表示操作失败

**示例**

```lua
-- 获取所有消息类型的发布状态
local all_status = extp.getPublishEnabled()
log.info("所有消息状态", json.encode(all_status))

-- 获取水平移动消息的发布状态
local movex_enabled = extp.getPublishEnabled("MOVE_X")
log.info("MOVE_X状态", movex_enabled)
```

### 4.4 extp.setSlideThreshold(threshold)

**功能**

设置滑动判定阈值，用于确定何时将触摸移动识别为滑动事件

**参数** ** ：threshold**

```lua
含义说明：threshold：number类型，滑动判定阈值
参数含义：滑动判定的像素阈值；
数据类型：number；
取值范围：必须大于0的数值；
是否必选：必须传入此参数；
注意事项：阈值设置过小可能导致误识别，过大可能导致滑动不灵敏；
参数示例：30
```

**返回值**

- boolean 类型，操作是否成功
  - true：操作成功
  - false：操作失败

**示例**

```lua
-- 设置滑动判定阈值为30像素
local success = extp.setSlideThreshold(30)
if success then
    log.info("滑动阈值设置成功")
else
    log.error("滑动阈值设置失败")
end
```

### 4.5 extp.setLongPressThreshold(threshold)

**功能**

修改长按判定阈值，用于确定何时将长按识别为长按事件而非单击事件

**参数  ：threshold**

```lua
含义说明：threshold：number类型，长按判定阈值
参数含义：长按判定的时间阈值；
数据类型：number；
取值范围：必须大于0的数值，单位毫秒；
是否必选：必须传入此参数；
注意事项：阈值设置过小可能导致长按被误识别为单击，过大可能导致用户体验不佳；
参数示例：800
```

**返回值**

- boolean 类型，操作是否成功
  - true：操作成功
  - false：操作失败

**示例**

```lua
-- 设置长按判定阈值为800毫秒
local success = extp.setLongPressThreshold(800)
if success then
    log.info("长按阈值设置成功")
else
    log.error("长按阈值设置失败")
end
```

## 五、完整使用示例

```lua
-- 完整的触摸应用示例
local function ui_main()
    
    -- 初始化触摸屏
    if not extp.init({TP_MODEL = "Air780EHM_LCD_4", port=1, pin_rst=20, pin_int=22}) then
        log.error("触摸屏初始化失败")
        return
    end
    
    -- 自定义配置
    extp.setSlideThreshold(40)        -- 设置滑动阈值为40像素
    extp.setLongPressThreshold(600)   -- 设置长按阈值为600毫秒
    
    -- 禁用不需要的事件类型
    extp.setPublishEnabled("RAW_DATA", false)
    
    -- 事件处理循环
    while true do
        local result, event_type, arg1, arg2 = sys.waitUntil("baseTouchEvent")
        if result then
            -- 根据事件类型处理不同的触摸动作
            if event_type == "SINGLE_TAP" then
                -- 处理单击事件
                handle_single_tap(arg1, arg2)
            elseif event_type == "LONG_PRESS" then
                -- 处理长按事件
                handle_long_press(arg1, arg2)
            elseif event_type == "SWIPE_LEFT" then
                -- 处理左滑事件
                handle_swipe_left()
            -- 其他事件处理...
            end
        end
    end
end

sys.taskInit(ui_main)
```

## 六、产品支持说明

支持 TP 核心库的产品，具体可以查看[选型手册](https://docs.openluat.com/air780epm/common/product/)中对应型号是否支持 TP 核心库。
