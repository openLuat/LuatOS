--[[
@module  ecabinet
@summary 快递柜主窗口模块
@version 1.0
@date    2026.04.29
]]

local win_id = nil
local main_container = nil
local timer_id = nil
local screen_w, screen_h = 1024, 600

-- 引入其他窗口模块
local ecsend = require "ecsend"
local ecrecv = require "ecrecv"
local eccourier = require "eccourier"
local ecsettings = require "ecsettings"

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

local function create_ui()
    local density = _G.density_scale or 1

    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x1E3A5F,
        parent = airui.screen
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x1E3A5F,
        radius = 0,
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = math.floor(15 * density),
        y = math.floor((header_h - 35 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(35 * density),
        text = "返回",
        style = {
            bg_color = 0xFFFFFF, pressed_bg_color = 0xEFEFEF,
            text_color = 0x333333, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })
    
    -- 标题居中
    airui.label({
        parent = header,
        text = "智能快递柜",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 时间显示 - 增大宽度以显示完整时间
    local time_display = airui.label({
        parent = header,
        text = "2023年1月1日 12:00:00",
        x = screen_w - math.floor(180 * density),
        y = math.floor((header_h - 18 * density) / 2),
        w = math.floor(170 * density),
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xFFFFFF,
        opacity = 0.8,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 更新时间显示
    local function update_time()
        local now = os.date("%Y年%m月%d日 %H:%M")
        time_display:set_text(now)
    end
    update_time()
    timer_id = sys.timerLoopStart(update_time, 1000)

    -- 主内容区域 - 左边区域（广告）
    local left_w = math.floor(screen_w * 0.38)  -- 进一步减小左半部分宽度，确保整体布局不超出
    local left_container = airui.container({
        parent = main_container,
        x = 0,
        y = header_h,
        w = left_w,
        h = screen_h - header_h,
        color = 0x1E3A5F,
    })

    -- Logo区域
    local logo_y = math.floor(25 * density)
    airui.image({
        parent = left_container,
        x = math.floor((left_w - 50 * density) / 2),
        y = logo_y,
        w = math.floor(50 * density),
        h = math.floor(50 * density),
        src = "/luadb/xiangzi.png",
    })
    
    airui.label({
        parent = left_container,
        text = "智能快递柜系统",
        x = 0,
        y = logo_y + math.floor(60 * density),
        w = left_w,
        h = math.floor(30 * density),
        font_size = math.floor(26 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = left_container,
        text = "24小时自助服务",
        x = 0,
        y = logo_y + math.floor(95 * density),
        w = left_w,
        h = math.floor(22 * density),
        font_size = math.floor(18 * density),
        color = 0xFFFFFF,
        opacity = 0.8,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 广告栏
    local ad_h = math.floor(95 * density)
    local ad_top = logo_y + math.floor(130 * density)
    local ad_banner = airui.container({
        parent = left_container,
        x = math.floor(25 * density),
        y = ad_top,
        w = left_w - math.floor(50 * density),
        h = ad_h,
        color = 0xFFFFFF,
        radius = math.floor(14 * density),
        border_width = 0,
    })
    
    -- 广告图标
    airui.container({
        parent = ad_banner,
        x = math.floor(18 * density),
        y = math.floor((ad_h - 55 * density) / 2),
        w = math.floor(55 * density),
        h = math.floor(55 * density),
        color = 0x3498DB,
        radius = math.floor(27 * density),
    })
    
    airui.image({
        parent = ad_banner,
        x = math.floor(25 * density),
        y = math.floor((ad_h - 45 * density) / 2),
        w = math.floor(45 * density),
        h = math.floor(45 * density),
        src = "/luadb/libao.png",
    })
    
    -- 广告文字
    airui.label({
        parent = ad_banner,
        text = "新用户专享",
        x = math.floor(85 * density),
        y = math.floor(18 * density),
        w = math.floor(180 * density),
        h = math.floor(22 * density),
        font_size = math.floor(20 * density),
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
    
    airui.label({
        parent = ad_banner,
        text = "首单寄件立减5元",
        x = math.floor(85 * density),
        y = math.floor(48 * density),
        w = math.floor(200 * density),
        h = math.floor(20 * density),
        font_size = math.floor(16 * density),
        color = 0x3498DB,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 二维码区域
    local qr_y = ad_top + ad_h + math.floor(30 * density)  -- 广告下方30px间距
    local qr_size = math.floor(120 * density)  -- 增大二维码尺寸
    airui.qrcode({
        parent = left_container,
        x = math.floor((left_w - qr_size) / 2),  -- 水平居中
        y = qr_y,
        size = qr_size,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 右边按钮区域
    local right_x = left_w
    local content_start_y = header_h
    
    -- 功能按钮区域 - 增大按钮尺寸和间距
    local func_size = math.floor(180 * density)  -- 显著增大按钮尺寸
    local btn_gap = math.floor(50 * density)  -- 进一步增大间距
    local content_padding = math.floor(90 * density)  -- 整体右移50
    
    -- 寄件容器 - 使用容器点击事件（简化层次结构）
    local send_container = airui.container({
        parent = main_container,
        x = right_x + content_padding,
        y = content_start_y + content_padding - math.floor(30 * density),  -- 整体向上移动30
        w = func_size,
        h = func_size,
        color = 0xFFFFFF,
        radius = func_size / 2,
        border_color = 0xE0E0E0,
        border_width = 1,
        on_click = function()
            log.info("寄件按键触发")
            sys.publish("OPEN_EXPRESS_SEND_WIN")
        end
    })
    
    -- 寄件图标（直接在send_container中）
    airui.image({
        parent = send_container,
        x = math.floor((func_size - math.floor(70 * density)) / 2),
        y = math.floor(25 * density),
        w = math.floor(70 * density),
        h = math.floor(70 * density),
        src = "/luadb/jijian.png",
        radius = math.floor(35 * density),
    })
    
    -- 寄件文字（直接在send_container中）
    airui.label({
        parent = send_container,
        text = "寄件",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(85 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(18 * density),  -- 显著缩小文字高度
        font_size = math.floor(18 * density),  -- 显著缩小字体
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = send_container,
        text = "快速寄件",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(110 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(14 * density),  -- 显著缩小文字高度
        font_size = math.floor(11 * density),  -- 显著缩小字体
        color = 0x95A5A6,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 取件容器 - 使用容器点击事件（简化层次结构）
    local receive_container = airui.container({
        parent = main_container,
        x = right_x + content_padding + func_size + btn_gap,
        y = content_start_y + content_padding - math.floor(30 * density),  -- 整体向上移动30
        w = func_size,
        h = func_size,
        color = 0xFFFFFF,
        radius = func_size / 2,
        border_color = 0xE0E0E0,
        border_width = 1,
        on_click = function()
            log.info("取件按键触发")
            sys.publish("OPEN_EXPRESS_RECEIVE_WIN")
        end
    })
    
    -- 取件图标（直接在receive_container中）
    airui.image({
        parent = receive_container,
        x = math.floor((func_size - math.floor(70 * density)) / 2),
        y = math.floor(25 * density),
        w = math.floor(70 * density),
        h = math.floor(70 * density),
        src = "/luadb/qujian.png",
        radius = math.floor(35 * density),
    })
    
    -- 取件文字（直接在receive_container中）
    airui.label({
        parent = receive_container,
        text = "取件",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(85 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(18 * density),  -- 显著缩小文字高度
        font_size = math.floor(18 * density),  -- 显著缩小字体
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = receive_container,
        text = "扫码取件",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(110 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(14 * density),  -- 显著缩小文字高度
        font_size = math.floor(11 * density),  -- 显著缩小字体
        color = 0x95A5A6,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 快递员容器 - 使用容器点击事件（简化层次结构）
    local courier_container = airui.container({
        parent = main_container,
        x = right_x + content_padding,
        y = content_start_y + content_padding - math.floor(30 * density) + func_size + btn_gap,
        w = func_size,
        h = func_size,
        color = 0xFFFFFF,
        radius = func_size / 2,
        border_color = 0xE0E0E0,
        border_width = 1,
        on_click = function()
            log.info("快递员按键触发")
            sys.publish("OPEN_EXPRESS_COURIER_WIN")
        end
    })
    
    -- 快递员图标（直接在courier_container中）
    airui.image({
        parent = courier_container,
        x = math.floor((func_size - math.floor(70 * density)) / 2),
        y = math.floor(25 * density),
        w = math.floor(70 * density),
        h = math.floor(70 * density),
        src = "/luadb/kuaidiyuan.png",
        radius = math.floor(35 * density),
    })
    
    -- 快递员文字（直接在courier_container中）
    airui.label({
        parent = courier_container,
        text = "快递员",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(85 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(18 * density),  -- 显著缩小文字高度
        font_size = math.floor(18 * density),  -- 显著缩小字体
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = courier_container,
        text = "投递管理",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(110 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(14 * density),  -- 显著缩小文字高度
        font_size = math.floor(11 * density),  -- 显著缩小字体
        color = 0x95A5A6,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 设置容器 - 使用容器点击事件（简化层次结构）
    local settings_container = airui.container({
        parent = main_container,
        x = right_x + content_padding + func_size + btn_gap,
        y = content_start_y + content_padding - math.floor(30 * density) + func_size + btn_gap,
        w = func_size,
        h = func_size,
        color = 0xFFFFFF,
        radius = func_size / 2,
        border_color = 0xE0E0E0,
        border_width = 1,
        on_click = function()
            log.info("设置按键触发")
            sys.publish("OPEN_EXPRESS_SETTINGS_WIN")
        end
    })
    
    -- 设置图标（直接在settings_container中）
    airui.image({
        parent = settings_container,
        x = math.floor((func_size - math.floor(70 * density)) / 2),
        y = math.floor(25 * density),
        w = math.floor(70 * density),
        h = math.floor(70 * density),
        src = "/luadb/shezhi.png",
        radius = math.floor(35 * density),
    })
    
    -- 设置文字（直接在settings_container中）
    airui.label({
        parent = settings_container,
        text = "设置",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(85 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(18 * density),  -- 显著缩小文字高度
        font_size = math.floor(18 * density),  -- 显著缩小字体
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = settings_container,
        text = "系统设置",
        x = math.floor((func_size - func_size * 0.8) / 2),  -- 居中对齐
        y = math.floor(110 * density),  -- 进一步缩小文字间距
        w = math.floor(func_size * 0.8),  -- 减少文字标签宽度
        h = math.floor(14 * density),  -- 显著缩小文字高度
        font_size = math.floor(11 * density),  -- 显著缩小字体
        color = 0x95A5A6,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 底部版权信息
    airui.label({
        parent = main_container,
        text = "2026 智能快递柜系统 v1.0",
        x = 0,
        y = screen_h - math.floor(26 * density),
        w = screen_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0xBDC3C7,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

local function on_create()
    log.info("ecabinet", "快递柜主窗口创建")
    update_screen_size()
    create_ui()
end

local function on_destroy()
    log.info("ecabinet", "快递柜主窗口销毁")
    -- 停止定时器
    if timer_id then
        sys.timerStop(timer_id)
        timer_id = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
    log.info("ecabinet", "快递柜主窗口获得焦点")
end

local function on_lose_focus()
    log.info("ecabinet", "快递柜主窗口失去焦点")
end

local function open()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("ecabinet", "快递柜主窗口打开，ID:", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_CABINET_WIN", open)
log.info("ecabinet", "订阅 OPEN_EXPRESS_CABINET_WIN 消息")