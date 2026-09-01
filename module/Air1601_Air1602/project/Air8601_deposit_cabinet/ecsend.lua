--[[
@module  ecsend
@summary 寄存柜存件窗口模块
@version 4.4 (优化版 - 在稳定版本上微调美化)
@date    2026.05.12
@author  王城钧
@usage
寄存柜存件窗口：存件流程（选择柜型/取件码生成/开柜）。订阅 OPEN_EXPRESS_SEND_WIN 打开
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local density = _G.density_scale or 1

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

local function create_ui()
    update_screen_size()

    -- 主容器 - 蓝白风格背景
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA,
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
        on_click = function()
            exwin.close(win_id)
        end
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
    local qr_y = header_h + math.floor(screen_h * 0.08)
    local qr_w = math.floor(screen_w * 0.4)
    local qr_h = math.floor(screen_h * 0.72)
    
    local qr_container = airui.container({
        parent = main_container,
        x = qr_x,
        y = qr_y,
        w = qr_w,
        h = qr_h,
        color = 0xFFFFFF,
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
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })

    -- 小程序码图片（服务器下发JPEG/PNG格式）
    -- 注意：airui.image 图片适配参数是 fit（"contain"/"center"/"cover"/"stretch"），
    --       不是 mode/IMAGE_SCALE_CENTER；且 jpg 宽高必须是 16 的倍数，
    --       故请求 width=288（微信接口最小 280，288=18*16 满足两者）
    local qr_image = nil
    local qr_placeholder = nil   -- 占位容器（加载中状态）
    local qr_status_label = nil  -- 二维码状态提示文字
    local qr_size = math.floor(256 * density)  -- 16的倍数，保证jpg解码正常
    local qr_img_x = math.floor((qr_w - qr_size) / 2)
    local qr_img_y = math.floor(70 * density)
    -- 文件名带版本号：与 server_api.generate_wechat_qr_code 保存路径保持一致，
    -- 避免旧代码下载的 280x280 文件被复用（280 非 16 倍数，airui 无法解码）
    local qr_code_path = "/qr_code_v288.jpeg"

    -- 创建/更新二维码图片组件（文件已存在时直接显示，异步加载成功后调用）
    local function show_qr_image()
        -- 先销毁占位容器与状态提示，再显示真实图片
        if qr_placeholder then
            pcall(function() qr_placeholder:destroy() end)
            qr_placeholder = nil
        end
        if qr_status_label then
            pcall(function() qr_status_label:destroy() end)
            qr_status_label = nil
        end
        if qr_image then
            pcall(function() qr_image:destroy() end)
            qr_image = nil
        end
        qr_image = airui.image({
            parent = qr_container,
            x = qr_img_x,
            y = qr_img_y,
            w = qr_size,
            h = qr_size,
            src = qr_code_path,  -- 直接显示文件系统区的图片文件
            fit = "contain",     -- 等比缩放完整显示
        })
    end

    -- 占位区域（加载中状态）：不显示可扫的错误二维码，避免用户扫到无效码
    qr_placeholder = airui.container({
        parent = qr_container,
        x = qr_img_x,
        y = qr_img_y,
        w = qr_size,
        h = qr_size,
        color = 0xF0F2F5,
        radius = math.floor(8 * density),
    })
    airui.label({
        parent = qr_placeholder,
        text = "加载中",
        x = 0,
        y = 0,
        w = qr_size,
        h = qr_size,
        font_size = math.floor(16 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 500,
    })
    -- 二维码状态提示（加载中/失败重试）
    qr_status_label = airui.label({
        parent = qr_container,
        text = "二维码加载中...",
        x = 0,
        y = qr_img_y + qr_size + math.floor(10 * density),
        w = qr_w,
        h = math.floor(22 * density),
        font_size = math.floor(14 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 500,
    })

    -- 检查本地二维码图片文件是否完整（防止上次下载截断的坏文件被"文件存在"逻辑复用）
    -- JPEG 必须以 FFD8 开头、FFD9 结尾；PNG 必须以 89504E47 开头、IEND 数据块结尾
    local function is_qr_file_valid()
        local f = io.readFile(qr_code_path)
        if not f or #f < 8 then return false end
        if f:sub(1, 2) == "\255\216" then
            return f:sub(-2) == "\255\217"
        elseif f:sub(1, 4) == "\137PNG" then
            return f:sub(-8) == "\0\0\0\0IEND\174\66\96\130"
        end
        return false
    end

    if io.exists(qr_code_path) and is_qr_file_valid() then
        log.info("ecsend", "小程序码图片文件存在且完整，直接显示")
        show_qr_image()
    else
        -- 文件存在但不完整时删除，避免坏文件被反复复用
        if io.exists(qr_code_path) then
            log.warn("ecsend", "本地小程序码文件不完整，删除后重新获取")
            os.remove(qr_code_path)
        end
        log.warn("ecsend", "小程序码图片文件不存在，尝试获取")
        -- 异步加载小程序码图片：成功后替换占位区域；失败自动重试（最多3次）
        sys.taskInit(function()
            local server_api = require "server_api"
            local max_retry = 3
            for attempt = 1, max_retry do
                -- 窗口已关闭则终止下载任务，避免组件挂在已销毁的父容器上
                if not win_id or not exwin.is_active(win_id) then
                    log.warn("ecsend", "存件窗口已关闭，终止小程序码下载")
                    return
                end
                local new_image_data, err = server_api.generate_wechat_qr_code()
                if new_image_data and io.exists(qr_code_path) then
                    log.info("ecsend", "小程序码图片加载成功")
                    -- 稍等系统稳定（内存回收、网络恢复）后再解码显示，提高解码成功率
                    sys.wait(2000)
                    -- 显示前再次确认窗口仍打开
                    if win_id and exwin.is_active(win_id) then
                        pcall(show_qr_image)
                    end
                    return
                end
                log.error("ecsend", "小程序码图片加载失败(第" .. attempt .. "次): " .. tostring(err or "未知错误"))
                if attempt < max_retry then
                    pcall(function()
                        if qr_status_label then
                            qr_status_label:set_text("二维码加载失败，正在重试(" .. attempt .. "/" .. (max_retry - 1) .. ")...")
                        end
                    end)
                    sys.wait(10000)
                else
                    pcall(function()
                        if qr_status_label then
                            qr_status_label:set_text("二维码加载失败，请检查网络后重试")
                        end
                    end)
                end
            end
        end)
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
        color = 0x4A90E2,
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
        color = 0x999999,
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
        color = 0xFFFFFF,
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
        color = 0x4A90E2,
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
            color = 0x333333,
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
        color = 0x999999,
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