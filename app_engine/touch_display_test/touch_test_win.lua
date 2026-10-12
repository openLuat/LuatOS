--[[
@module  touch_test_win
@summary 触摸显示偏移测试界面：坐标网格 + 触摸十字标记 + 清屏按钮
@version 1.0
@date    2026.09.22
@author  江访
@usage
本文件为触摸显示偏移测试的UI模块，核心业务逻辑为：
1、touch_test_win.init 创建背景、坐标网格（含四边像素刻度）、分辨率标注和清屏按钮，
   然后通过 airui.touch_subscribe 订阅触摸回调，开始接收触摸点
2、屏幕被按下时，回调函数 on_touch 在触摸点画红色十字标记和黄色坐标文字，
   同时通过 log 打印触摸坐标；把十字标记位置与网格刻度对比，即可判断显示与触摸是否偏移
3、点击右下角"清屏"按钮，回调函数 clear_btn_click_func 调用 clear_marks 销毁所有触摸标记

本文件的对外接口有1个：
1、touch_test_win.init：创建测试界面并开始接收触摸
   （必须在 lcd_drv.init 和 tp_drv.init 之后调用）

注意：本界面不做密度缩放，所有坐标都是屏幕物理像素坐标，
保证网格刻度与触摸坐标一比一对应，才能准确判断偏移
]]

-- ==================== 颜色常量（RGB888） ====================
local COLOR_BG         = 0x101418   -- 背景深灰黑
local COLOR_GRID       = 0x3A4250   -- 网格线深灰（低调，不干扰标记）
local COLOR_GRID_EDGE  = 0x90A0B0   -- 屏幕边框浅灰
local COLOR_AXIS_TEXT  = 0xB0BAC6   -- 刻度文字灰白
local COLOR_MARK       = 0xFF3030   -- 十字标记红色
local COLOR_MARK_TEXT  = 0xFFD040   -- 坐标文字黄色
local COLOR_BTN_BG     = 0x2E6BE6   -- 清屏按钮蓝色
local COLOR_BTN_PRESS  = 0x1F4FBF   -- 清屏按钮按下色
local COLOR_BTN_TEXT   = 0xFFFFFF   -- 按钮文字白色

-- ==================== 布局常量（单位：像素） ====================
local LINE_THIN  = 1               -- 网格线粗细
local LINE_THICK = 2               -- 边框/十字标记粗细
local CROSS_HALF = 12              -- 十字臂长的一半（十字总长 25 像素）
local BTN_W      = 110             -- 清屏按钮宽度
local BTN_H      = 48              -- 清屏按钮高度
local EDGE_PAD   = 12              -- 按钮距屏幕边缘留白
local LABEL_PAD  = 8               -- 坐标文字距十字中心的偏移

-- ==================== 模块对外接口表 ====================
local touch_test_win = {}

-- ==================== 运行时状态变量 ====================
local screen_w = 0                 -- 逻辑屏幕宽度（含旋转），init 时从 _G.screen_w 读取
local screen_h = 0                 -- 逻辑屏幕高度（含旋转），init 时从 _G.screen_h 读取
local font_size = 16               -- 字体大小，init 时从 project_config 读取
local grid_step = 50               -- 网格间距（像素），init 时按分辨率计算
local main_container = nil         -- 背景主容器，所有子组件的父节点
local clear_btn = nil              -- 清屏按钮
local mark_list = {}               -- 触摸标记列表，每项 {竖条, 横条, 坐标文字}
local mark_count = 0               -- 触摸标记计数（清屏后归零）

--[[
把数值限制在 [min_val, max_val] 范围内
@param number val  原始值
@param number min_val  下限
@param number max_val  上限
@return number  限制后的值
]]
local function clamp_value(val, min_val, max_val)
    if val < min_val then return min_val end
    if val > max_val then return max_val end
    return val
end

--[[
根据分辨率选择网格间距：小屏 50 像素，大屏 100 像素
@param number w  屏幕宽
@param number h  屏幕高
@return number  网格间距（像素）
]]
local function get_grid_step(w, h)
    local min_side = math.min(w, h)
    if min_side <= 480 then
        return 50
    end
    return 100
end

--[[
创建一条实心矩形色条（用于网格线、边框和十字标记）
@param table parent  父容器
@param number x  左上角 x
@param number y  左上角 y
@param number w  宽度
@param number h  高度
@param number color  颜色（RGB888）
@return userdata  airui.container 组件对象
]]
local function create_bar(parent, x, y, w, h, color)
    return airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = color,
    })
end

--[[
创建一个文字标签
@param table parent  父容器
@param number x  左上角 x
@param number y  左上角 y
@param number w  宽度
@param number h  高度
@param string text  显示文字
@param number color  文字颜色（RGB888）
@param number align  对齐方式（airui.TEXT_ALIGN_*）
@return userdata  airui.label 组件对象
]]
local function create_label(parent, x, y, w, h, text, color, align)
    return airui.label({
        parent = parent,
        x = x, y = y, w = w, h = h,
        text = text,
        font_size = font_size,
        color = color,
        align = align,
    })
end

--[[
安全销毁一个 airui 组件（组件不存在或已销毁时不报错）
@param userdata obj  airui 组件对象
@return 无
]]
local function safe_destroy(obj)
    if obj == nil then
        return
    end
    pcall(obj.destroy, obj)
end

--[[
清屏按钮点击回调：销毁所有触摸标记并归零计数
]]
local function clear_btn_click_func()
    for i = 1, #mark_list do
        safe_destroy(mark_list[i][1])   -- 竖条
        safe_destroy(mark_list[i][2])   -- 横条
        safe_destroy(mark_list[i][3])   -- 坐标文字
    end
    mark_list = {}
    mark_count = 0
    log.info("touch_test_win", "清屏完成，已清除所有触摸标记")
end

--[[
判断坐标是否落在清屏按钮区域内（按钮区域不画标记，避免标记遮挡按钮）
@param number x  触摸 x
@param number y  触摸 y
@return boolean  true=在按钮区域内，false=不在
]]
local function is_in_clear_btn(x, y)
    local btn_x = screen_w - BTN_W - EDGE_PAD
    local btn_y = screen_h - BTN_H - EDGE_PAD
    return x >= btn_x and x < btn_x + BTN_W and y >= btn_y and y < btn_y + BTN_H
end

--[[
在触摸点画十字标记和坐标文字，并记录到 mark_list 供清屏销毁
十字由 1 条竖条和 1 条横条交叉构成，交点即触摸坐标；
坐标文字放在十字右下角，靠屏幕边缘时自动翻到左上角，保证文字不出界
@param number x  触摸 x（像素）
@param number y  触摸 y（像素）
@return 无
]]
local function add_mark(x, y)
    mark_count = mark_count + 1

    -- 竖条：宽 2、长 25，以 (x, y) 为中心
    local v_bar = create_bar(main_container,
        clamp_value(x - 1, 0, screen_w - LINE_THICK),
        clamp_value(y - CROSS_HALF, 0, screen_h - 2 * CROSS_HALF),
        LINE_THICK, 2 * CROSS_HALF + 1, COLOR_MARK)

    -- 横条：宽 25、长 2，以 (x, y) 为中心
    local h_bar = create_bar(main_container,
        clamp_value(x - CROSS_HALF, 0, screen_w - 2 * CROSS_HALF),
        clamp_value(y - 1, 0, screen_h - LINE_THICK),
        2 * CROSS_HALF + 1, LINE_THICK, COLOR_MARK)

    -- 坐标文字："序号:(x,y)"，与日志序号一一对应，方便比对
    local mark_text = string.format("%d:(%d,%d)", mark_count, x, y)
    local label_w = font_size * 7                -- 足够容纳 "99:(999,999)" 级别的文字
    local label_h = font_size + 6
    local label_x = x + LABEL_PAD                -- 默认放十字右下角
    local label_y = y + LABEL_PAD
    if label_x + label_w > screen_w then         -- 靠右边缘时翻到左侧
        label_x = x - LABEL_PAD - label_w
    end
    if label_y + label_h > screen_h then         -- 靠下边缘时翻到上方
        label_y = y - LABEL_PAD - label_h
    end
    label_x = clamp_value(label_x, 0, screen_w - label_w)
    label_y = clamp_value(label_y, 0, screen_h - label_h)
    local coord_label = create_label(main_container,
        label_x, label_y, label_w, label_h,
        mark_text, COLOR_MARK_TEXT, airui.TEXT_ALIGN_LEFT)

    -- 记录组件引用，清屏时销毁
    mark_list[#mark_list + 1] = { v_bar, h_bar, coord_label }

    log.info("touch_test_win", string.format("第%d个触摸标记 已画在 x=%d y=%d", mark_count, x, y))
end

--[[
触摸回调函数（airui.touch_subscribe 注册）：
每次触摸事件打印坐标日志，按下（TP_DOWN）时在触摸点画十字标记
@param number state  触摸状态：airui.TP_DOWN 按下 / airui.TP_MOVE 移动 / airui.TP_UP 抬起
@param number x  触摸 x（像素）
@param number y  触摸 y（像素）
@param number track_id  多点触控的触点 ID（单点触摸屏一般为 0）
@param number timestamp  触摸时间戳
@return 无
]]
local function on_touch(state, x, y, track_id, timestamp)
    -- 触摸坐标统一取整，方便与网格刻度比对
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)

    if state == airui.TP_DOWN then
        -- 按下事件：打印坐标 + 画标记（按钮区域只打印不画标记）
        log.info("touch_test_win", string.format("触摸按下 x=%d y=%d track=%s", x, y, tostring(track_id)))
        if not is_in_clear_btn(x, y) then
            add_mark(x, y)
        end
    elseif state ~= airui.TP_MOVE then
        -- 抬起等事件打印坐标；移动事件不打印，避免刷屏
        log.info("touch_test_win", string.format("触摸抬起/其他 state=%s x=%d y=%s",
            tostring(state), x, tostring(y)))
    end
end

--[[
绘制坐标网格：
1、屏幕四周画 2 像素边框，边框即坐标范围 0 ~ w-1 / 0 ~ h-1 的边界
2、每隔 grid_step 像素画横竖网格线，四边标注对应像素坐标
3、右上角标注屏幕分辨率，左上角标注原点 "0"
@param 无
@return 无
]]
local function draw_grid()
    local step = grid_step
    local axis_h = font_size + 6                 -- 刻度文字条带高度
    local axis_w = font_size * 3                 -- 刻度文字条带宽度

    -- 屏幕边框（上、下、左、右各一条）
    create_bar(main_container, 0, 0, screen_w, LINE_THICK, COLOR_GRID_EDGE)
    create_bar(main_container, 0, screen_h - LINE_THICK, screen_w, LINE_THICK, COLOR_GRID_EDGE)
    create_bar(main_container, 0, 0, LINE_THICK, screen_h, COLOR_GRID_EDGE)
    create_bar(main_container, screen_w - LINE_THICK, 0, LINE_THICK, screen_h, COLOR_GRID_EDGE)

    -- 竖向网格线 + 上下两边的 x 坐标刻度
    local px = step
    while px < screen_w do
        create_bar(main_container, px, 0, LINE_THIN, screen_h, COLOR_GRID)
        -- 顶部刻度：文字以网格线为中心
        create_label(main_container, px - axis_w / 2, 4, axis_w, axis_h,
            tostring(px), COLOR_AXIS_TEXT, airui.TEXT_ALIGN_CENTER)
        -- 底部刻度：避开清屏按钮区域
        local bottom_y = screen_h - axis_h - 4
        if not (px + axis_w / 2 > screen_w - BTN_W - EDGE_PAD * 2 and
                bottom_y > screen_h - BTN_H - EDGE_PAD * 2) then
            create_label(main_container, px - axis_w / 2, bottom_y, axis_w, axis_h,
                tostring(px), COLOR_AXIS_TEXT, airui.TEXT_ALIGN_CENTER)
        end
        px = px + step
    end

    -- 横向网格线 + 左右两边的 y 坐标刻度
    local py = step
    while py < screen_h do
        create_bar(main_container, 0, py, screen_w, LINE_THIN, COLOR_GRID)
        create_label(main_container, 4, py - axis_h / 2, axis_w, axis_h,
            tostring(py), COLOR_AXIS_TEXT, airui.TEXT_ALIGN_LEFT)
        create_label(main_container, screen_w - axis_w - 4, py - axis_h / 2, axis_w, axis_h,
            tostring(py), COLOR_AXIS_TEXT, airui.TEXT_ALIGN_RIGHT)
        py = py + step
    end

    -- 原点 "0" 标注（左上角）
    create_label(main_container, 4, 4, axis_w, axis_h,
        "0", COLOR_AXIS_TEXT, airui.TEXT_ALIGN_LEFT)

    -- 分辨率标注（右上角，压低透明感用低调颜色）
    local res_text = string.format("%dx%d", screen_w, screen_h)
    create_label(main_container, screen_w - font_size * 5 - 4, 4, font_size * 5, axis_h,
        res_text, COLOR_AXIS_TEXT, airui.TEXT_ALIGN_RIGHT)

    log.info("touch_test_win", string.format("坐标网格绘制完成 %dx%d 网格间距=%d",
        screen_w, screen_h, step))
end

--[[
创建测试界面并开始接收触摸（对外接口）：
背景 → 坐标网格 → 清屏按钮 → 订阅触摸回调
必须在 lcd_drv.init 和 tp_drv.init 之后调用，此时 AirUI 和触摸设备已就绪
@param 无
@return 无
]]
function touch_test_win.init()
    -- 读取逻辑分辨率（lcd_common 已按旋转方向换算好宽高）
    screen_w = _G.screen_w
    screen_h = _G.screen_h

    -- 字体大小取工程配置（各型号 config 中按屏幕分辨率设定），不做密度缩放
    local font_cfg = _G.project_config.hw.lcd.font or {}
    font_size = font_cfg.size or 16

    -- 网格间距按分辨率自适应
    grid_step = get_grid_step(screen_w, screen_h)

    -- 背景主容器：覆盖全屏，网格和标记都是它的子组件
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    -- 坐标网格
    draw_grid()

    -- 清屏按钮（右下角，最后创建保证显示在最上层）
    clear_btn = airui.button({
        parent = main_container,
        x = screen_w - BTN_W - EDGE_PAD,
        y = screen_h - BTN_H - EDGE_PAD,
        w = BTN_W, h = BTN_H,
        text = "清屏",
        font_size = font_size,
        style = {
            bg_color = COLOR_BTN_BG,
            pressed_bg_color = COLOR_BTN_PRESS,
            text_color = COLOR_BTN_TEXT,
            radius = 8,
        },
        on_click = clear_btn_click_func,
    })

    -- 订阅触摸回调：之后所有触摸事件都会进入 on_touch
    airui.touch_subscribe(on_touch)

    log.info("touch_test_win", "触摸显示偏移测试界面就绪，等待触摸...")
end

return touch_test_win
