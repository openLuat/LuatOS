> 当前exEasyUI的版本为1.6.1  
## 一、概述
- exEasyUI 是基于 LuatOS 打造的简化 UI 组件库，内聚了组件管理、渲染与触摸事件分发能力。
- 触摸层基于扩展库 extp（触摸识别/手势统一为 baseTouchEvent），UI 内部统一订阅并转发到组件。
- 主要组件：Button、CheckBox、Label、Picture、MessageBox、Window、ProgressBar。
- 设计目标：开箱即用、少依赖、跨屏易配置，支持滑动窗口（纵向滚动、横向平移/分页吸附）。
- v1.6.0新特性：Label/MessageBox智能换行、Button合并图片和Toggle功能、Windows 11风格配色。
- v1.6.1修复与增强：按钮防移出机制修复、MessageBox复用功能（show/hide/setTitle/setMessage）、图片占位符优化。

注意：工程需提供 `screen_data_table.lua`（LCD 与 TP 参数），`exeasyui.lua` 会自动从该文件读取并初始化硬件与触摸。

## 二、核心示例（滑动窗口从上到下展示各组件）
以下示例演示：创建一个窗口，开启纵向滚动，将各个组件的最小可用示例纵向排布，滑动浏览。

```
PROJECT = "exEasyUI_demo"
VERSION = "1.0.0"

sys = require("sys")
local ui = require("exeasyui")

sys.taskInit(function()
    sys.wait(500)
    -- 依赖 screen_data_table.lua 内的 lcdargs/touch 参数
    ui.hw.init({})
    ui.init({ theme = "light" })

    local win = ui.Window({ backgroundColor = ui.COLOR_WHITE })
    -- 内容高度较大，启用纵向滚动
    win:enableScroll({ direction = "vertical", contentHeight = 1000, threshold = 8 })

    local y = 20
    local function place(h)
        local cur = y; y = y + h + 16; return cur
    end

    -- 1) Button
    local btn = ui.Button({ x = 20, y = place(44), w = 280, h = 44, text = "Button", onClick = function(self)
        log.info("demo", "button clicked")
    end })
    win:add(btn)

    -- 2) Toggle按钮（v1.6.0：Button支持toggle功能）
    local tb = ui.Button({ x = 20, y = place(64), w = 64, h = 64, 
        src = "/luadb/icon.jpg", toggle = true, 
        onToggle = function(t) log.info("demo", "toggled", t) end 
    })
    win:add(tb)

    -- 3) CheckBox
    local cb = ui.CheckBox({ x = 20, y = place(24), text = "Check me", checked = false, onChange = function(v)
        log.info("demo", "checkbox", v)
    end })
    win:add(cb)

    -- 4) Label（v1.6.0：支持自动换行）
    local lbl = ui.Label({ x = 20, y = place(60), w = 280, wordWrap = true,
        text = "This is a long text that will wrap automatically within the specified width." })
    win:add(lbl)

    -- 5) Picture（示例：无实际图片时会显示占位框）
    local pic = ui.Picture({ x = 20, y = place(120), w = 160, h = 120, autoplay = false, src = "/luadb/sample.jpg" })
    win:add(pic)

    -- 6) MessageBox（作为静态面板展示）
    local box = ui.MessageBox({ x = 20, y = place(120), w = 280, h = 120, title = "MessageBox", message = "Info Panel", buttons = {"OK"}, onResult = function(r)
        log.info("demo", "msgbox", r)
    end })
    win:add(box)

    -- 7) ProgressBar
    local pb = ui.ProgressBar({ x = 20, y = place(26), w = 280, h = 26, progress = 35, text = "35%" })
    win:add(pb)

    ui.add(win)

    while true do
        ui.clear()
        ui.render()
        sys.wait(30)
    end
end)

sys.run()
```

## 三、常量详解

### 3.1 基础颜色常量

| 常量名           | 说明         | RGB565值      |
|------------------|--------------|---------------|
| COLOR_WHITE      | 白色         | 0xFFFF        |
| COLOR_BLACK      | 黑色         | 0x0000        |
| COLOR_GRAY       | 灰色         | 0x8410        |
| COLOR_BLUE       | 蓝色         | 0x001F        |
| COLOR_RED        | 红色         | 0xF800        |
| COLOR_GREEN      | 绿色         | 0x07E0        |
| COLOR_YELLOW     | 黄色         | 0xFFE0        |
| COLOR_CYAN       | 青色         | 0x07FF        |
| COLOR_MAGENTA    | 品红         | 0xF81F        |
| COLOR_ORANGE     | 橙色         | 0xFC00        |
| COLOR_PINK       | 粉色         | 0xF81F        |

### 3.2 Windows 11 风格颜色（v1.6.0新增）

**Light模式**：
| 常量名                        | 说明           | RGB值              | RGB565值 |
|-------------------------------|----------------|--------------------|----------|
| COLOR_WIN11_LIGHT_DIALOG_BG   | 对话框背景     | RGB(243,243,243)   | 0xF79E   |
| COLOR_WIN11_LIGHT_BUTTON_BG   | 按钮背景       | RGB(251,251,252)   | 0xFFDF   |
| COLOR_WIN11_LIGHT_BUTTON_BORDER| 按钮边框      | RGB(229,229,229)   | 0xE73C   |

**Dark模式**：
| 常量名                        | 说明           | RGB值              | RGB565值 |
|-------------------------------|----------------|--------------------|----------|
| COLOR_WIN11_DARK_DIALOG_BG    | 对话框背景     | RGB(32,32,32)      | 0x2104   |
| COLOR_WIN11_DARK_BUTTON_BG    | 按钮背景       | RGB(51,51,51)      | 0x3186   |
| COLOR_WIN11_DARK_BUTTON_BORDER| 按钮边框       | RGB(76,76,76)      | 0x4A69   |

> 以上颜色常量均由 `ui` 导出，可直接通过 `ui.COLOR_WHITE` 等方式使用。  
> Window和Button组件在light主题下默认使用Windows 11 Light配色，dark主题下使用Dark配色。

## 四、组件 API 详解
本节对每个组件提供：功能说明、构造参数、方法、事件、示例。

### 4.1 Button（按钮）
**功能**

多功能按钮组件，支持文本按钮、图片按钮、Toggle切换按钮（v1.6.0合并ToolButton功能）。

**构造**：`ui.Button(args)`

**参数** ：**args**
```plain
{
    x = , y = ,
    -- 参数含义：左上角坐标；
    -- 数据类型：number；
    -- 是否必选：可选，默认0；

    w = , h = ,
    -- 参数含义：宽/高；
    -- 数据类型：number；
    -- 是否必选：可选，默认 w=100, h=36；

    -- 文本模式参数
    text = ,
    -- 参数含义：按钮文字；
    -- 数据类型：string；
    -- 是否必选：可选，默认"Button"；

    textSize = ,
    -- 参数含义：文字字号；
    -- 数据类型：number；
    -- 是否必选：可选；

    bgColor = , textColor = , borderColor = ,
    -- 参数含义：背景/文本/边框颜色；
    -- 数据类型：number（RGB565）；
    -- 是否必选：可选，浅色主题默认Windows 11配色；

    -- 图片模式参数（v1.6.0新增）
    src = ,
    -- 参数含义：普通态图片路径；
    -- 数据类型：string；
    -- 是否必选：可选，有此参数时按钮显示为图片；
    -- 说明：v1.6.1起会检查文件是否存在，不存在时显示占位符并输出警告日志；

    src_pressed = ,
    -- 参数含义：按下态图片路径；
    -- 数据类型：string；
    -- 是否必选：可选；

    src_toggled = ,
    -- 参数含义：切换态图片路径（toggle=true时使用）；
    -- 数据类型：string；
    -- 是否必选：可选；

    -- Toggle模式参数（v1.6.0新增）
    toggle = ,
    -- 参数含义：是否为Toggle切换按钮；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认false；

    toggled = ,
    -- 参数含义：初始切换状态；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认false；

    onToggle = ,
    -- 参数含义：切换回调；
    -- 数据类型：function(toggled, self)；
    -- 是否必选：可选；

    onClick = 
    -- 参数含义：点击回调；
    -- 数据类型：function(self)；
    -- 是否必选：可选；
}
```

**方法**
```plain
setText(newText)         -- 设置按钮文字
```

**事件**
```plain
SINGLE_TAP: 调用 onClick(self)
```

**示例**
```plain
-- 1. 文本按钮（使用默认配色）
local btn1 = ui.Button({
    x = 20, y = 40, w = 120, h = 44,
    text = "确定",
    onClick = function() log.info("btn", "clicked") end
})

-- 2. 图片按钮（有按下态）
local btn2 = ui.Button({
    x = 20, y = 100, w = 64, h = 64,
    src = "/luadb/icon.jpg",
    src_pressed = "/luadb/icon_pressed.jpg",
    onClick = function() log.info("img btn", "clicked") end
})

-- 3. Toggle按钮
local btn3 = ui.Button({
    x = 20, y = 180, w = 64, h = 64,
    src = "/luadb/off.jpg",
    src_toggled = "/luadb/on.jpg",
    toggle = true,
    onToggle = function(state)
        log.info("toggle", state and "ON" or "OFF")
    end
})
```

#### Button.setText
**功能**

设置按钮文字。

**签名**
```plain
Button:setText(newText)
```

**参数**
```plain
newText
-- 参数含义：新的按钮文本
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
local b = ui.Button({ x = 20, y = 40, text = "原文" })
b:setText("确定")
```

### 4.2 CheckBox（复选框）
**功能**

布尔选择控件。

**构造**：`ui.CheckBox(args)`

**参数** ：**args**
```plain
{
    x = , y = ,
    -- 参数含义：位置；
    -- 数据类型：number；

    boxSize = ,
    -- 参数含义：复选框边长；
    -- 数据类型：number；
    -- 是否必选：可选，默认16；

    text = ,
    -- 参数含义：右侧文本；
    -- 数据类型：string；

    checked = ,
    -- 参数含义：初始选中状态；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认false；

    onChange = ,
    -- 参数含义：状态改变回调；
    -- 数据类型：function(checked)；

    textColor = , borderColor = , bgColor = , tickColor = ,
    -- 参数含义：颜色（文本/边框/背景/选中块）；
    -- 数据类型：number；
}
```

**方法**
```plain
setChecked(v)
toggle()
```

#### CheckBox.setChecked
**功能**

设置复选框选中状态。

**签名**
```plain
CheckBox:setChecked(v)
```

**参数**
```plain
v
-- 参数含义：目标选中状态
-- 数据类型：boolean
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
local cb = ui.CheckBox({ x=20, y=160, text="启用" })
cb:setChecked(true)
```

#### CheckBox.toggle
**功能**

切换当前选中状态。

**签名**
```plain
CheckBox:toggle()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
cb:toggle()
```

**事件**
```plain
SINGLE_TAP: 点击区域内部时切换并调用 onChange(checked)
```

**示例**
```plain
local cb = ui.CheckBox({ 
    x = 20, y = 160, text = "启用", 
    onChange = function(v) log.info("cb", v) end 
})
```

### 4.3 Label（文本标签）
**功能**

静态文本显示，支持自动换行（v1.6.0新增）。

**构造**：`ui.Label(args)`

**参数** ：**args**
```plain
{
    x = , y = ,
    -- 参数含义：位置；
    -- 数据类型：number；

    text = ,
    -- 参数含义：文本内容；
    -- 数据类型：string；

    w = ,
    -- 参数含义：最大宽度（v1.6.0）；
    -- 数据类型：number；
    -- 是否必选：可选，未指定时自动计算；
    -- 说明：指定后，无换行时超出部分截断，有换行时在此宽度内换行；

    wordWrap = ,
    -- 参数含义：是否启用自动换行（v1.6.0）；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认false；
    -- 说明：启用后在w宽度内智能换行（英文按单词，中文按字符）；

    color = ,
    -- 参数含义：文本颜色；
    -- 数据类型：number；
    -- 是否必选：可选，默认随主题；

    size = ,
    -- 参数含义：字号；
    -- 数据类型：number；
    -- 是否必选：可选；

    font = 
    -- 参数含义：自定义字体句柄（默认后端时生效）；
    -- 数据类型：userdata；
}
```

**方法**
```plain
setText(t)
setSize(sz)
```

#### Label.setText
**功能**

设置文本内容。

**签名**
```plain
Label:setText(t)
```

**参数**
```plain
t
-- 参数含义：新文本
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
local lbl = ui.Label({ x = 20, y = 200, text = "Hello" })
lbl:setText("World")
```

#### Label.setSize
**功能**

设置字号，并按需调整宽高。

**签名**
```plain
Label:setSize(sz)
```

**参数**
```plain
sz
-- 参数含义：字号
-- 数据类型：number
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
lbl:setSize(20)
```

**示例**
```plain
-- 1. 基础文本
local lbl1 = ui.Label({ x = 20, y = 200, text = "Hello exEasyUI" })

-- 2. 文本截断（超出w则截断）
local lbl2 = ui.Label({ 
    x = 20, y = 230, w = 200,
    text = "这是一段很长的文本会被截断" 
})

-- 3. 自动换行（v1.6.0）
local lbl3 = ui.Label({ 
    x = 20, y = 260, w = 280, wordWrap = true,
    text = "This is a long text that demonstrates automatic word wrapping feature in exEasyUI v1.6.0."
})
```

### 4.4 Picture（图片/轮播）
**功能**

显示单图或多图轮播。v1.6.1起，图片文件不存在时会显示占位符（灰色背景+白色边框+X叉）。

**构造**：`ui.Picture(args)`

**参数** ：**args**
```plain
{
    x = , y = , w = , h = ,
    -- 参数含义：位置与尺寸；
    -- 数据类型：number；
    -- 说明：v1.6.1建议使用正方形或接近正方形尺寸以获得最佳占位符显示效果；

    src = ,
    -- 参数含义：单张图片路径；
    -- 数据类型：string；
    -- 说明：v1.6.1起会检查文件是否存在，不存在时显示占位符并输出警告日志；

    sources = ,
    -- 参数含义：多张图片路径列表；
    -- 数据类型：table，如 { "/luadb/a.jpg", "/luadb/b.jpg" }；

    autoplay = ,
    -- 参数含义：是否自动轮播（sources 有多图时生效）；
    -- 数据类型：boolean，默认false；

    interval = 
    -- 参数含义：轮播间隔（毫秒）；
    -- 数据类型：number，默认1000；
}
```

**方法**
```plain
setSources(list)
next()
prev()
play()
pause()
```

#### Picture.setSources
**功能**

设置图片列表并重置索引。

**签名**
```plain
Picture:setSources(list)
```

**参数**
```plain
list
-- 参数含义：图片路径数组
-- 数据类型：table，如 {"/luadb/a.jpg", "/luadb/b.jpg"}
```

**返回值**
```plain
无
```

**示例**
```plain
pic:setSources({ "/luadb/1.jpg", "/luadb/2.jpg" })
```

#### Picture.next / Picture.prev
**功能**

切换到下一张 / 上一张（在 sources 存在时）。

**签名**
```plain
Picture:next()
Picture:prev()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
pic:next()
pic:prev()
```

#### Picture.play / Picture.pause
**功能**

开启 / 暂停自动轮播。

**签名**
```plain
Picture:play()
Picture:pause()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
pic:play()
sys.wait(2000)
pic:pause()
```

**示例**
```plain
-- 单图显示
local pic1 = ui.Picture({ 
    x = 20, y = 240, w = 120, h = 90,
    src = "/luadb/image.jpg" 
})

-- 自动轮播
local pic2 = ui.Picture({ 
    x = 20, y = 350, w = 120, h = 90,
    sources = {"/luadb/a.jpg", "/luadb/b.jpg"}, 
    autoplay = true 
})
```

### 4.5 MessageBox（消息框/面板）
**功能**

展示标题、内容与按钮组，支持消息自动换行（v1.6.0新增），支持复用与动态更新（v1.6.1新增）。

**构造**：`ui.MessageBox(args)`

**参数** ：**args**
```plain
{
    x = , y = , w = , h = ,
    -- 参数含义：位置与尺寸；
    -- 数据类型：number；

    title = ,
    -- 参数含义：标题文本；
    -- 数据类型：string，默认"Info"；

    message = ,
    -- 参数含义：内容文本；
    -- 数据类型：string；

    wordWrap = ,
    -- 参数含义：消息是否自动换行（v1.6.0）；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认true（v1.6.1起）；
    -- 说明：启用后消息在固定高度内智能换行，超出部分截断；

    visible = ,
    -- 参数含义：初始是否可见（v1.6.1修复）；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认true；

    enabled = ,
    -- 参数含义：初始是否可交互（v1.6.1修复）；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认true；

    textSize = ,
    -- 参数含义：文本字号；
    -- 数据类型：number；
    -- 是否必选：可选；

    buttons = ,
    -- 参数含义：按钮文本数组；
    -- 数据类型：table，默认 {"OK"}；
    -- 说明：可传入空数组 {} 创建无按钮的MessageBox；

    onResult = ,
    -- 参数含义：按钮点击回调；
    -- 数据类型：function(label)；

    borderColor = , textColor = , bgColor = ,
    -- 参数含义：边框/文本/背景颜色；
    -- 数据类型：number；
}
```

**方法**
```plain
show()                   -- 显示MessageBox（v1.6.1新增）
hide()                   -- 隐藏MessageBox（v1.6.1新增）
setTitle(title)          -- 动态更新标题（v1.6.1新增）
setMessage(message)      -- 动态更新消息内容（v1.6.1新增）
```

**事件**
```plain
内部按钮 SINGLE_TAP: 调用 onResult(label)
```

#### MessageBox 子方法

#### MessageBox.show
**功能**

显示MessageBox（设置visible和enabled为true）。v1.6.1新增，用于MessageBox复用。

**签名**
```plain
MessageBox:show()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
msgbox:show()
```

#### MessageBox.hide
**功能**

隐藏MessageBox（设置visible为false）。v1.6.1新增，用于MessageBox复用。

**签名**
```plain
MessageBox:hide()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
msgbox:hide()
```

#### MessageBox.setTitle
**功能**

动态更新MessageBox标题。v1.6.1新增。

**签名**
```plain
MessageBox:setTitle(title)
```

**参数**
```plain
title
-- 参数含义：新标题文本
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
msgbox:setTitle("警告")
```

#### MessageBox.setMessage
**功能**

动态更新MessageBox消息内容。v1.6.1新增，如启用了自动换行会自动重新计算行数。

**签名**
```plain
MessageBox:setMessage(message)
```

**参数**
```plain
message
-- 参数含义：新消息文本
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
msgbox:setMessage("更新后的消息内容")
```

**示例**
```plain
-- 1. 简单提示
local box1 = ui.MessageBox({ 
    x = 20, y = 340, w = 280, h = 120,
    title = "提示", message = "操作成功", 
    buttons = {"确定"},
    onResult = function(r) log.info("msg", r) end 
})

-- 2. 长消息自动换行（v1.6.0，v1.6.1起默认开启）
local box2 = ui.MessageBox({ 
    x = 20, y = 340, w = 280, h = 160,
    title = "提示",
    message = "这是一段很长的提示消息，启用自动换行后会在固定宽度内智能分行显示，超出高度的部分会被截断。",
    buttons = {"知道了"}
})

-- 3. MessageBox复用（v1.6.1推荐方式）
-- 创建时设置为初始隐藏
local msgbox = ui.MessageBox({ 
    x = 20, y = 340, w = 280, h = 120,
    title = "提示", 
    message = "初始消息", 
    visible = false,  -- 初始隐藏
    buttons = {"确定"},
    onResult = function(r) 
        msgbox:hide()  -- 点击后隐藏而非禁用
    end 
})
win:add(msgbox)

-- 多次复用同一个MessageBox
local btn1 = ui.Button({ 
    x = 20, y = 40, w = 120, h = 44, 
    text = "显示消息1",
    onClick = function()
        msgbox:setTitle("通知")
        msgbox:setMessage("这是第一条消息")
        msgbox:show()
    end 
})

local btn2 = ui.Button({ 
    x = 160, y = 40, w = 120, h = 44, 
    text = "显示消息2",
    onClick = function()
        msgbox:setTitle("警告")
        msgbox:setMessage("这是第二条消息")
        msgbox:show()
    end 
})

-- 4. 无按钮MessageBox（信息面板）
local infoPanel = ui.MessageBox({ 
    x = 20, y = 480, w = 280, h = 100,
    title = "系统状态",
    message = "运行正常\n内存使用: 45%",
    buttons = {}  -- 无按钮
})

-- 5. 动态更新示例（如实时显示时间）
sys.taskInit(function()
    while true do
        local time = os.date("%H:%M:%S")
        msgbox:setMessage("当前时间: " .. time)
        sys.wait(1000)
    end
end)
```

### 4.6 ProgressBar（进度条）
**功能**

显示百分比进度，可附带文本。

**构造**：`ui.ProgressBar(args)`

**参数** ：**args**
```plain
{
    x = , y = , w = , h = ,
    -- 参数含义：位置与尺寸；
    -- 数据类型：number；

    progress = ,
    -- 参数含义：进度百分比 0~100；
    -- 数据类型：number，默认0；

    text = , textSize = ,
    -- 参数含义：文本与字号；
    -- 数据类型：string/number；

    backgroundColor = , progressColor = , borderColor = , textColor = ,
    -- 参数含义：配色（背景/进度/边框/文本）；
    -- 数据类型：number；

    showPercentage = 
    -- 参数含义：是否显示百分比文本；
    -- 数据类型：boolean，默认true；
}
```

**方法**
```plain
setProgress(v)
getProgress()
setText(text)
```

#### ProgressBar.setProgress
**功能**

设置进度百分比。

**签名**
```plain
ProgressBar:setProgress(v)
```

**参数**
```plain
v
-- 参数含义：目标进度 0~100
-- 数据类型：number
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
pb:setProgress(75)
```

#### ProgressBar.getProgress
**功能**

获取当前进度值。

**签名**
```plain
ProgressBar:getProgress()
```

**参数**
```plain
无
```

**返回值**
```plain
number -- 当前进度 0~100
```

**示例**
```plain
local v = pb:getProgress()
log.info("pb", v)
```

#### ProgressBar.setText
**功能**

设置显示文本（可覆盖百分比显示）。

**签名**
```plain
ProgressBar:setText(text)
```

**参数**
```plain
text
-- 参数含义：文本内容
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
pb:setText("下载中...")
```

**示例**
```plain
-- 基础进度条
local pb = ui.ProgressBar({ 
    x = 20, y = 480, w = 280, h = 26, 
    progress = 40 
})

-- 带自定义文本
local pb2 = ui.ProgressBar({ 
    x = 20, y = 520, w = 280, h = 26, 
    progress = 65, text = "下载中..." 
})
```

## 五、Window 使用模式说明
本节采用与上文一致的结构，分别介绍 Window 的创建与参数、子方法以及子页面（子窗口）使用方式。

### 5.1 Window（窗口容器）创建与参数
**功能**

窗口容器，用作页面根节点或子页面载体。支持背景色/背景图、子组件管理、滚动与分页、子页面导航等。

**构造**：`ui.Window(args)`

**参数** ：**args**
```plain
{
    x = , y = ,
    -- 参数含义：窗口左上角坐标；
    -- 数据类型：number；
    -- 是否必选：可选，默认0；

    w = , h = ,
    -- 参数含义：窗口宽/高；
    -- 数据类型：number；
    -- 是否必选：可选，默认填满屏幕（lcd.getSize()）；

    backgroundImage = ,
    -- 参数含义：背景图片路径（.jpg）；
    -- 数据类型：string；
    -- 是否必选：可选；

    backgroundColor = ,
    -- 参数含义：背景颜色（RGB565）；
    -- 数据类型：number；
    -- 是否必选：可选，浅色主题默认Windows 11配色；

    visible = , enabled = ,
    -- 参数含义：可见/可交互；
    -- 数据类型：boolean；
    -- 是否必选：可选，默认 true；
}
```

**示例**
```plain
-- 使用默认配色（v1.6.0：浅色主题自动使用Windows 11配色）
local win = ui.Window()
ui.add(win)
```

### 5.2 Window 子方法
**方法**
```plain
add(child)                    -- 添加子组件
remove(child)                 -- 移除子组件
clear()                       -- 清空子组件

setBackgroundImage(path)      -- 设置背景图
setBackgroundColor(color)     -- 设置背景色（并清除背景图）

enableScroll(opts)            -- 启用滚动/分页（纵向/横向/双向）
setContentSize(w, h)          -- 设置内容区尺寸（影响滚动边界）

enableSubpageManager(opts)    -- 启用子页面管理（一次开启即可）
configureSubpages(factories)  -- 注册子页面工厂{name->function}
showSubpage(name[, factory])  -- 显示子页面；如未缓存则调用工厂创建
back()                        -- 关闭当前子页面，返回父窗口
closeSubpage(name, opts)      -- 关闭指定子页面；opts.destroy=true 彻底销毁
```

**enableScroll(opts)**
```plain
opts = {
    direction = "vertical" | "horizontal" | "both", -- 滚动方向，默认 "vertical"
    contentWidth  = <number>,  -- 内容宽度（默认等于窗口宽度）
    contentHeight = <number>,  -- 内容高度（默认等于窗口高度）
    threshold = <number>,      -- 判定拖拽门限像素，默认10
    pagingEnabled = <boolean>, -- 横向分页吸附开关（横向/双向时生效）
    pageWidth = <number>,      -- 分页宽度，默认窗口宽度
}
```

**示例：纵向滚动列表**
```plain
local win = ui.Window({ backgroundColor = ui.COLOR_WHITE })
win:enableScroll({ direction = "vertical", contentHeight = 1200, threshold = 8 })
-- 之后 add 的子组件会随滚动偏移显示
```

**示例：横向分页（桌面式）**
```plain
local win = ui.Window({ backgroundColor = ui.COLOR_WHITE })
win:enableScroll({ direction = "horizontal", pagingEnabled = true, pageWidth = 320, contentWidth = 320 * 3 })
```

### 5.2.1 Window.add
**功能**

向窗口添加一个子组件（任何实现了 draw/handleEvent 的组件）。

**签名**
```plain
Window:add(child)
```

**参数**
```plain
child
-- 参数含义：要添加的组件实例
-- 数据类型：table（组件对象）
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
local btn = ui.Button({ x=20, y=40, w=120, h=44, text="OK" })
win:add(btn)
```

#### 5.2.2 Window.remove
**功能**

从窗口中移除一个已添加的子组件。

**签名**
```plain
Window:remove(child)
```

**参数**
```plain
child
-- 参数含义：要移除的组件实例
-- 数据类型：table（组件对象）
-- 是否必选：是
```

**返回值**
```plain
boolean -- 是否成功移除
```

**示例**
```plain
win:remove(btn)
```

#### 5.2.3 Window.clear
**功能**

清空窗口的所有子组件。

**签名**
```plain
Window:clear()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
win:clear()
```

#### 5.2.4 Window.setBackgroundImage
**功能**

设置窗口背景图。

**签名**
```plain
Window:setBackgroundImage(path)
```

**参数**
```plain
path
-- 参数含义：.jpg 图片路径
-- 数据类型：string
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
win:setBackgroundImage("/luadb/wallpaper.jpg")
```

#### 5.2.5 Window.setBackgroundColor
**功能**

设置窗口背景色，并清除已设置的背景图。

**签名**
```plain
Window:setBackgroundColor(color)
```

**参数**
```plain
color
-- 参数含义：RGB565 颜色值
-- 数据类型：number
-- 是否必选：是
```

**返回值**
```plain
无
```

**示例**
```plain
win:setBackgroundColor(ui.COLOR_WHITE)
```

#### 5.2.6 Window.enableScroll
**功能**

启用窗口内容的拖拽滚动与可选的横向分页吸附。

**签名**
```plain
Window:enableScroll(opts)
```

**参数**
```plain
opts
-- 参数含义：滚动/分页配置
-- 数据类型：table（见上文 enableScroll(opts) 配置项）
-- 是否必选：否
```

**返回值**
```plain
Window -- 返回自身，便于链式调用
```

**示例**
```plain
win:enableScroll({ direction = "vertical", contentHeight = 1200 })
```

#### 5.2.7 Window.setContentSize
**功能**

设置内容区尺寸（影响滚动边界的计算），通常在 enableScroll 后调用。

**签名**
```plain
Window:setContentSize(w, h)
```

**参数**
```plain
w, h
-- 参数含义：内容宽/高
-- 数据类型：number
-- 是否必选：至少提供其一
```

**返回值**
```plain
无
```

**示例**
```plain
win:setContentSize(320, 1200)
```

### 5.3 子页面（Subpage）使用
Window 内置子页面管理能力，便于在单窗口内组织多级页面与导航返回。

**启用与注册**
```plain
local home = ui.Window({ backgroundColor = 0xFFFF })
-- 一次启用（可省略，首次调用会自动启用）
home:enableSubpageManager({
    backEventName = "NAV.BACK",          -- 可选；默认 "NAV.BACK"
    onBack = function() log.info("nav", "back pressed") end, -- 可选
})

-- 注册子页面工厂（返回一个 Window 实例）
home:configureSubpages({
    settings = function() return require("settings_page").create(ui) end,
    about    = function() return require("about_page").create(ui) end,
})
```

#### 5.3.1 Window.enableSubpageManager
**功能**

启用子页面管理能力，注册返回事件及可选回调；通常调用一次即可。

**签名**
```plain
Window:enableSubpageManager(opts)
```

**参数**
```plain
opts
-- 参数含义：可选项
-- 数据类型：table
-- 字段：
--   backEventName: string，返回事件名，默认 "NAV.BACK"
--   onBack: function()，收到返回事件时回调（在父窗口范围）
```

**返回值**
```plain
Window -- 返回自身
```

**示例**
```plain
home:enableSubpageManager({ backEventName = "NAV.BACK" })
```

#### 5.3.2 Window.configureSubpages
**功能**

注册子页面工厂表；当使用 showSubpage 时按名称创建并缓存子页面。

**签名**
```plain
Window:configureSubpages(factories)
```

**参数**
```plain
factories
-- 参数含义：工厂表 { name -> function() return Window end }
-- 数据类型：table
-- 是否必选：是
```

**返回值**
```plain
Window -- 返回自身
```

**示例**
```plain
home:configureSubpages({ settings = function() return require("settings_page").create(ui) end })
```

#### 5.3.3 Window.showSubpage
**功能**

显示指定名称的子页面；如未创建则调用工厂创建并缓存；显示子页面时会隐藏当前窗口。

**签名**
```plain
Window:showSubpage(name[, factory])
```

**参数**
```plain
name
-- 参数含义：子页面名称
-- 数据类型：string
-- 是否必选：是

factory
-- 参数含义：备用工厂（当未通过 configureSubpages 注册时提供）
-- 数据类型：function() -> Window
-- 是否必选：否
```

**返回值**
```plain
无
```

**示例**
```plain
home:showSubpage("settings")
```

#### 5.3.4 Window.back
**功能**

在子页面中调用，使当前子页面隐藏，并在父窗口无其他子页面可见时恢复父窗口可见/可交互。

**签名**
```plain
Window:back()
```

**参数 / 返回值**
```plain
无
```

**示例**
```plain
self:back()
```

#### 5.3.5 Window.closeSubpage
**功能**

关闭指定名称的子页面；当 opts.destroy=true 时从缓存中删除并触发垃圾回收。

**签名**
```plain
Window:closeSubpage(name, opts)
```

**参数**
```plain
name
-- 参数含义：子页面名称
-- 数据类型：string
-- 是否必选：是

opts
-- 参数含义：关闭选项
-- 数据类型：table
-- 字段：
--   destroy: boolean，是否销毁缓存
```

**返回值**
```plain
boolean -- 是否存在并处理该子页面
```

**示例**
```plain
home:closeSubpage("settings", { destroy = true })
```

#### 5.3.6 返回事件（NAV.BACK）
**功能**

通过发布返回事件触发 onBack 回调；若没有任一子页面可见，则自动恢复父窗口可见。

**签名**
```plain
sys.publish("NAV.BACK")
```

**示例**
```plain
sys.publish("NAV.BACK")
```

**完整示例**
```plain
local home = ui.Window({ backgroundColor = 0xFFFF })
home:configureSubpages({
    checkbox = function() return require("checkbox_page").create(ui) end,
    msgbox   = function() return require("msgbox_page").create(ui) end,
})

local btn = ui.Button({ x = 20, y = 60, w = 280, h = 50, text = "进入子页", onClick = function()
    home:showSubpage("checkbox")
end })
home:add(btn)
ui.add(home)
```
