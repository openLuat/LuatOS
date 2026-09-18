--[[
@module  ecsend
@summary 寄存柜存件窗口模块
@version 4.5 (优化版 - 回调改为命名函数)
@date    2026.05.12
@author  王城钧
@usage
订阅 "OPEN_EXPRESS_SEND_WIN" 消息打开存件窗口。
窗口左侧显示服务器下发的小程序码（/qr_code.jpeg），文件无效时自动重新获取。
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local density = _G.density_scale or 1

-- 二维码相关控件/参数（提升为文件级，供异步加载任务访问）
local qr_container = nil
local qr_code_path = "/qr_code.jpeg"
local qr_w = 0
local qr_y = 0

-- 返回按钮回调：关闭存件窗口
local function on_back_click()
    exwin.close(win_id)
end

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    density = _G.density_scale or 1
end

-- 解析 JPEG 文件宽高（读取文件头部的 SOF 段），解析失败返回 nil
-- airui 硬性要求：图片宽高必须为 16 的倍数，否则硬件解码失败无法显示
local function parse_jpeg_size(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local head = f:read(8192)
    f:close()
    if not head or #head < 4 then
        return nil
    end
    -- 校验 JPEG 文件头 FF D8 FF
    if head:byte(1) ~= 0xFF or head:byte(2) ~= 0xD8 then
        return nil
    end
    -- 遍历 JPEG 段，寻找 SOF 标记（FF C0~CF，排除 C4/C8/CC）
    local pos = 3
    while pos + 8 <= #head do
        if head:byte(pos) ~= 0xFF then
            pos = pos + 1
        else
            local marker = head:byte(pos + 1)
            -- 跳过可能的填充 FF
            while marker == 0xFF do
                pos = pos + 1
                if pos + 1 > #head then return nil end
                marker = head:byte(pos + 1)
            end
            -- SOS 表示图像数据开始，SOF 应在此之前；未找到则解析失败
            if marker == 0xDA then
                return nil
            end
            if marker >= 0xC0 and marker <= 0xCF
                and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
                -- SOF 段结构: FF Cx | 段长(2) | 精度(1) | 高(2) | 宽(2)
                if pos + 8 <= #head then
                    local height = head:byte(pos + 5) * 256 + head:byte(pos + 6)
                    local width = head:byte(pos + 7) * 256 + head:byte(pos + 8)
                    return width, height
                end
                return nil
            end
            -- 跳过当前段（段长含长度字段本身的 2 字节）
            if pos + 3 <= #head then
                local seg_len = head:byte(pos + 2) * 256 + head:byte(pos + 3)
                if seg_len < 2 then return nil end
                pos = pos + 2 + seg_len
            else
                return nil
            end
        end
    end
    return nil
end

-- 校验二维码文件：返回 (is_jpeg, width, height)
-- is_jpeg: 是否为有效 JPEG（FF D8 头且能解析出宽高）
-- width/height: 实际像素宽高，解析失败为 nil
-- 注意：airui 硬件解码要求宽高为 16 的倍数，但服务器返回的图片尺寸不可控，
--       因此这里只判断"是否为有效 JPEG"，16 倍数问题交由显示层打警告并尝试显示
local function qr_file_info(path)
    if not io.exists(path) then
        return false, nil, nil
    end
    local w, h = parse_jpeg_size(path)
    if w and h and w > 0 and h > 0 then
        return true, w, h
    end
    return false, nil, nil
end

-- 显示二维码图片（src 指向 /qr_code.jpeg）
local function show_qr_image()
    return airui.image({
        parent = qr_container,
        x = math.floor((qr_w - math.floor(300 * density)) / 2),
        y = math.floor(70 * density),
        w = math.floor(300 * density),
        h = math.floor(300 * density),
        src = qr_code_path,  -- 直接显示文件系统区的JPEG格式图片
        fit = "contain",  -- 图片适配模式（V1.2.1+）：contain 等比缩放完整显示
        color = 0xEFEFEF,
    })
end

-- 显示默认二维码兜底（docs.openluat.com）
local function show_default_qr()
    return airui.qrcode({
        parent = qr_container,
        x = math.floor((qr_w - math.floor(300 * density)) / 2),
        y = math.floor(70 * density),
        size = math.floor(300 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })
end

-- 异步加载小程序码任务：请求服务器生成二维码并显示
local function load_qr_code_task()
    local server_api = require "server_api"
    local new_image_data, err = server_api.generate_wechat_qr_code()
    local is_jpeg2, w2, h2 = qr_file_info(qr_code_path)
    if new_image_data and is_jpeg2 then
        log.info("ecsend", string.format("小程序码图片加载成功 (%dx%d)", w2, h2))
        -- 显示图片
        show_qr_image()
    else
        log.error("ecsend", string.format("小程序码图片加载失败: %s (数据=%s, JPEG=%s, 尺寸=%sx%s)",
            tostring(err or "未知错误"),
            tostring(new_image_data ~= nil),
            tostring(is_jpeg2),
            tostring(w2 or "?"),
            tostring(h2 or "?")))
        -- 显示默认二维码
        show_default_qr()
    end
end

local function create_ui()
    update_screen_size()

    -- 主容器 - 深蓝风格背景（与首页 ecabinet 一致）
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x08193A,
        parent = airui.screen
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
        shadow = {
            offset_x = 0,
            offset_y = math.floor(3 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.12,
        }
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
            text_color = 0x4A90E2, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = on_back_click
    })

    -- 标题
    airui.label({
        parent = header,
        text = "存件",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 左侧二维码区域
    local qr_x = math.floor(screen_w * 0.05)
    qr_y = header_h + math.floor(screen_h * 0.08)
    qr_w = math.floor(screen_w * 0.4)
    local qr_h = math.floor(screen_h * 0.72)

    qr_container = airui.container({
        parent = main_container,
        x = qr_x,
        y = qr_y,
        w = qr_w,
        h = qr_h,
        color = 0x0E3B5C,
        radius = math.floor(12 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(4 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.1,
        }
    })

    -- 卡片顶部装饰条
    local card_header = airui.container({
        parent = qr_container,
        x = 0,
        y = 0,
        w = qr_w,
        h = math.floor(4 * density),
        color = 0x4A90E2,
        radius = {math.floor(12 * density), math.floor(12 * density), 0, 0},
    })

    -- 二维码标题
    airui.label({
        parent = qr_container,
        text = "扫描二维码",
        x = 0,
        y = math.floor(30 * density),
        w = qr_w,
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x6FB5F5,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })

    -- 小程序码图片（服务器下发JPEG格式）
    -- 关键：必须校验文件"有效"（JPEG头 + 能解析出宽高）
    -- 旧代码只判断 io.exists()，导致坏文件永远走"直接显示"分支且显示失败
    local is_jpeg, img_w, img_h = qr_file_info(qr_code_path)
    if is_jpeg then
        -- 直接显示（服务器返回的图片尺寸以实际效果为准，不再提示 16 倍数）
        log.info("ecsend", string.format("小程序码图片文件有效，直接显示 (%dx%d)", img_w, img_h))
        -- 使用 airui.image 组件显示图片
        show_qr_image()
    else
        -- 文件不存在或无效：删除残留文件，重新请求服务器生成
        if io.exists(qr_code_path) then
            log.warn("ecsend", "小程序码图片文件无效，删除后重新获取")
            os.remove(qr_code_path)
        else
            log.warn("ecsend", "小程序码图片文件不存在，尝试获取")
        end
        -- 异步加载小程序码图片
        sys.taskInit(load_qr_code_task)
    end

    -- 小程序码下方文字（两行格式）
    airui.label({
        parent = qr_container,
        text = "扫描小程序码",
        x = 0,
        y = math.floor(380 * density),  -- 调整位置到图片下方
        w = qr_w,
        h = math.floor(20 * density),
        font_size = math.floor(15 * density),
        color = 0x6FB5F5,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    airui.label({
        parent = qr_container,
        text = "开始存件流程",
        x = 0,
        y = math.floor(410 * density),  -- 调整位置到图片下方
        w = qr_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9EB3CC,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })

    -- 右侧存件步骤区域 - 背景容器
    local steps_container = airui.container({
        parent = main_container,
        x = math.floor(screen_w * 0.48),
        y = qr_y,
        w = math.floor(screen_w * 0.47),
        h = qr_h,
        color = 0x0E3B5C,
        radius = math.floor(12 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(4 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.1,
        }
    })

    -- 卡片顶部装饰条
    local steps_card_header = airui.container({
        parent = steps_container,
        x = 0,
        y = 0,
        w = steps_container.w,
        h = math.floor(4 * density),
        color = 0x50C878,
        radius = {math.floor(12 * density), math.floor(12 * density), 0, 0},
    })

    -- 存件步骤标题 - 直接添加到main_container
    airui.label({
        parent = main_container,
        text = "存件步骤",
        x = math.floor(screen_w * 0.48) + math.floor(20 * density),
        y = qr_y + math.floor(25 * density),
        w = math.floor(screen_w * 0.43),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x6FB5F5,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 700,
    })

    -- 步骤列表
    local step_items = {
        "点击首页'存件'按钮",
        "扫描小程序码",
        "选择箱子大小，付款",
        "等待柜门打开",
        "放入物品后关闭柜门",
        "记录取件码"
    }

    local step_y_start = qr_y + math.floor(65 * density)
    local step_height = math.floor(42 * density)
    local steps_x = math.floor(screen_w * 0.48)

    for i, step_text in ipairs(step_items) do
        -- 步骤序号圆圈
        local num_circle = airui.container({
            parent = main_container,
            x = steps_x + math.floor(20 * density),
            y = step_y_start + (i-1) * step_height,
            w = math.floor(24 * density),
            h = math.floor(24 * density),
            color = 0x4A90E2,
            radius = math.floor(12 * density),
        })

        airui.label({
            parent = num_circle,
            text = tostring(i),
            x = 0,
            y = math.floor((24 * density - 16 * density) / 2),
            w = math.floor(24 * density),
            h = math.floor(16 * density),
            font_size = math.floor(12 * density),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600,
        })

        -- 步骤文字 - 直接添加到main_container
        airui.label({
            parent = main_container,
            text = step_text,
            x = steps_x + math.floor(55 * density),
            y = step_y_start + (i-1) * step_height + math.floor(3 * density),
            w = math.floor(screen_w * 0.4),
            h = math.floor(20 * density),
            font_size = math.floor(13 * density),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 500,
        })
    end

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示：请确保柜门完全关闭后再离开",
        x = 0,
        y = screen_h - math.floor(35 * density),
        w = screen_w,
        h = math.floor(25 * density),
        font_size = math.floor(12 * density),
        color = 0x9EB3CC,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })
end

local function on_create()
    log.info("ecsend", "打开存件窗口")
    update_screen_size()
    create_ui()
end

local function on_destroy()
    log.info("ecsend", "关闭存件窗口")
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
    log.info("ecsend", "存件窗口获得焦点")
end

local function on_lose_focus()
    log.info("ecsend", "存件窗口失去焦点")
end

local function open()
    log.info("ecsend", "准备打开存件窗口")
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("ecsend", "存件窗口已打开，ID:", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_SEND_WIN", open)
log.info("ecsend", "订阅 OPEN_EXPRESS_SEND_WIN 消息")
