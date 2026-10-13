--[[
@module  eccourier_detail
@summary 寄存柜管理员功能页面
@version 1.6
@date    2026.10.16
@author  王城钧
@usage
寄存柜管理员功能页面：管理柜子状态/取件码/人脸等。订阅 OPEN_COURIER_DETAIL_WIN 打开
]]

local win_id = nil
local main_container
local screen_w, screen_h = 1024, 600
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local keyboard = nil
local box_number_textarea = nil
local current_result_modal = nil

-- ==================== 维护工具用的提示/确认弹窗 ====================
local tip_modal = nil
local confirm_modal = nil

-- 简易提示（自动关闭）
local function show_tip(text)
    if tip_modal then
        pcall(function() tip_modal:destroy() end)
        tip_modal = nil
    end
    local density = _G.density_scale or 1
    local w = math.floor(460 * density)
    local h = math.floor(110 * density)
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0x000000, opacity = 0.5
    })
    local box = airui.container({
        parent = modal,
        x = math.floor((screen_w - w) / 2),
        y = math.floor((screen_h - h) / 2),
        w = w, h = h,
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })
    airui.label({
        parent = box,
        x = math.floor(10 * density), y = math.floor(20 * density),
        w = w - math.floor(20 * density), h = h - math.floor(40 * density),
        text = text,
        font_size = math.floor(16 * density),
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER
    })
    tip_modal = modal
    sys.timerStart(function()
        if tip_modal == modal then
            tip_modal = nil
        end
        pcall(function() modal:destroy() end)
    end, 3000)
end

-- 二次确认弹窗（危险操作前使用）
local function show_confirm(text, on_ok)
    if confirm_modal then
        pcall(function() confirm_modal:destroy() end)
        confirm_modal = nil
    end
    local density = _G.density_scale or 1
    local w = math.floor(460 * density)
    local h = math.floor(170 * density)
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0x000000, opacity = 0.5
    })
    local box = airui.container({
        parent = modal,
        x = math.floor((screen_w - w) / 2),
        y = math.floor((screen_h - h) / 2),
        w = w, h = h,
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })
    airui.label({
        parent = box,
        x = math.floor(10 * density), y = math.floor(20 * density),
        w = w - math.floor(20 * density), h = math.floor(60 * density),
        text = text,
        font_size = math.floor(16 * density),
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = box,
        x = math.floor(30 * density), y = math.floor(100 * density),
        w = math.floor(180 * density), h = math.floor(45 * density),
        text = "确认执行",
        style = {
            bg_color = 0xDC3545, text_color = 0xFFFFFF,
            radius = math.floor(6 * density), font_size = math.floor(15 * density),
        },
        on_click = function()
            pcall(function() modal:destroy() end)
            confirm_modal = nil
            if on_ok then on_ok() end
        end
    })
    airui.button({
        parent = box,
        x = w - math.floor(210 * density), y = math.floor(100 * density),
        w = math.floor(180 * density), h = math.floor(45 * density),
        text = "取消",
        style = {
            bg_color = 0xF0F0F0, text_color = 0x666666,
            radius = math.floor(6 * density), font_size = math.floor(15 * density),
        },
        on_click = function()
            pcall(function() modal:destroy() end)
            confirm_modal = nil
        end
    })
    confirm_modal = modal
end

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = display.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, phys_h = phys_w, phys_h
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    title_h = math.floor(60 * _G.density_scale)
end

local function show_result_dialog(box_number, success, error_msg)
    -- 销毁之前的弹窗
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end
    
    local density = _G.density_scale or 1
    
    -- 开箱结果弹窗
    local result_modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })
    
    local result_content = airui.container({
        parent = result_modal,
        x = math.floor((screen_w - math.floor(300 * density)) / 2),
        y = math.floor((screen_h - math.floor(200 * density)) / 2),
        w = math.floor(300 * density),
        h = math.floor(200 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density)
    })
    
    if success then
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density),
            w = math.floor(300 * density),
            h = math.floor(30 * density),
            text = "柜门已打开",
            font_size = math.floor(20 * density),
            color = 0x28A745,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })
        
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density),
            w = math.floor(300 * density),
            h = math.floor(40 * density),
            text = "第" .. box_number .. "号箱门已打开",
            font_size = math.floor(14 * density),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(40 * density),
            w = math.floor(300 * density),
            h = math.floor(30 * density),
            text = "开柜失败",
            font_size = math.floor(20 * density),
            color = 0xD32F2F,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600
        })
        
        local error_text = error_msg or "未知错误"
        airui.label({
            parent = result_content,
            x = 0, y = math.floor(80 * density),
            w = math.floor(300 * density),
            h = math.floor(40 * density),
            text = error_text,
            font_size = math.floor(14 * density),
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    airui.button({
        parent = result_content,
        x = math.floor(75 * density),
        y = math.floor(130 * density),
        w = math.floor(150 * density),
        h = math.floor(45 * density),
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600
        },
        on_click = function()
            result_modal:destroy()
            current_result_modal = nil
            if box_number_textarea then
                box_number_textarea:set_text("")
            end
        end
    })
    
    current_result_modal = result_modal
end

--[[
开柜结果回调处理
]]
local function on_box_open_result(data)
    -- 仅当快递员详情窗口为活动窗口时才处理
    if not exwin.is_active(win_id) then return end
    log.info("eccourier_detail", "开柜结果", json.encode(data))
    show_result_dialog(data.box_num, data.success, data.error)
end

local function create_ui()
    update_screen_size()
    local density = _G.density_scale or 1
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA
    })

    -- 数字键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
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
        on_click = function() exwin.close(win_id) end
    })

    -- 标题
    airui.label({
        parent = header,
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        text = "管理中心",
        color = 0xFFFFFF,
        font_size = math.floor(24 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域（不滚动）
    local content = airui.container({
        parent = main_container,
        x = 0, y = header_h,
        w = screen_w, h = screen_h - header_h,
        color = 0xF8F9FA,
        scroll = false
    })
    
    -- 查看所有箱子状态按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(30 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "查看所有箱子状态",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600,
        },
        on_click = function()
            sys.publish("OPEN_EXPRESS_BOXSTATUS_WIN")
        end
    })

    -- 人脸管理按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(90 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "人脸管理",
        style = {
            bg_color = 0x667EEA,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600,
        },
        on_click = function()
            sys.publish("OPEN_FACE_MANAGE_WIN")
        end
    })

    -- 箱子编号标签
    airui.label({
        parent = content,
        x = margin, y = math.floor(160 * density),
        w = screen_w - 2 * margin, h = math.floor(25 * density),
        text = "箱子编号",
        color = 0x4A90E2,
        font_size = math.floor(14 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 箱子编号输入框（使用数字键盘）
    box_number_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(190 * density),
        w = screen_w - 2 * margin, h = math.floor(50 * density),
        placeholder = "请输入箱子编号",
        style = {
            bg_color = 0xFFFFFF,
            border_color = 0xDDDDDD,
            border_width = 1,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            text_color = 0x000000,
        },
        keyboard = keyboard,
    })

    -- 开箱按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(260 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "开箱",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600,
        },
        on_click = function()
            local box_number = box_number_textarea:get_text()
            if not box_number or box_number == "" then
                local toast_modal = airui.container({
                    parent = airui.screen,
                    x = 0, y = 0,
                    w = screen_w, h = screen_h,
                    color = 0x000000,
                    opacity = 0.5
                })
                
                local toast_content = airui.container({
                    parent = toast_modal,
                    x = math.floor((screen_w - math.floor(250 * density)) / 2),
                    y = math.floor((screen_h - math.floor(100 * density)) / 2),
                    w = math.floor(250 * density),
                    h = math.floor(100 * density),
                    color = 0xFFFFFF,
                    radius = math.floor(10 * density)
                })
                
                airui.label({
                    parent = toast_content,
                    x = 0, y = math.floor(30 * density),
                    w = math.floor(250 * density),
                    h = math.floor(40 * density),
                    text = "请输入箱子编号",
                    font_size = math.floor(16 * density),
                    color = 0xD32F2F,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                return
            end
            
            local box_num = tonumber(box_number)
            if not box_num or box_num < 1 or box_num > 30 then
                local toast_modal = airui.container({
                    parent = airui.screen,
                    x = 0, y = 0,
                    w = screen_w, h = screen_h,
                    color = 0x000000,
                    opacity = 0.5
                })
                
                local toast_content = airui.container({
                    parent = toast_modal,
                    x = math.floor((screen_w - math.floor(250 * density)) / 2),
                    y = math.floor((screen_h - math.floor(100 * density)) / 2),
                    w = math.floor(250 * density),
                    h = math.floor(100 * density),
                    color = 0xFFFFFF,
                    radius = math.floor(10 * density)
                })
                
                airui.label({
                    parent = toast_content,
                    x = 0, y = math.floor(30 * density),
                    w = math.floor(250 * density),
                    h = math.floor(40 * density),
                    text = "箱子编号必须在1-30之间",
                    font_size = math.floor(16 * density),
                    color = 0xD32F2F,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                return
            end
            
            -- 通过消息发布开柜请求
            log.info("eccourier_detail", "发布开柜请求", box_num)
            sys.publish("OPEN_BOX", box_num)
        end
    })

    -- ==================== 维护工具（现场自愈） ====================
    -- 断网期间做的存件/取件若上报失败，服务器侧柜子状态会残留"占用"，表现为"无可用箱子"。
    -- 三个动作供现场排障（管理页已由密码保护）：
    --   服务器对账   → POST /sync，上报"设备侧空闲柜号"（需服务器支持该接口；以设备数据为准覆盖）
    --   重初始化柜子 → POST /init，重新登记柜子配置（接口一直在用，最可靠）
    --   清空本地记录 → 清 fskv 的 face_bind_* / pickup_code_*（纯本地，零风险，有二次确认）
    local m_btn_y = math.floor(320 * density)
    local m_btn_h = math.floor(40 * density)
    local m_gap = math.floor(10 * density)
    local m_btn_w = math.floor((screen_w - 2 * margin - 2 * m_gap) / 3)

    airui.button({
        parent = content,
        x = margin, y = m_btn_y, w = m_btn_w, h = m_btn_h,
        text = "服务器对账",
        style = {
            bg_color = 0x17A2B8, text_color = 0xFFFFFF,
            radius = math.floor(5 * density), font_size = math.floor(14 * density),
            font_weight = 600,
        },
        on_click = function()
            show_tip("对账中，请稍候…")
            sys.taskInit(function()
                local ecbusiness = require "ecbusiness"
                local ok, err = ecbusiness.sync_boxes_to_server()
                if ok then
                    show_tip("对账完成：已上报空闲柜号")
                else
                    show_tip("对账失败：" .. tostring(err))
                end
            end)
        end
    })

    airui.button({
        parent = content,
        x = margin + m_btn_w + m_gap, y = m_btn_y, w = m_btn_w, h = m_btn_h,
        text = "重初始化柜子",
        style = {
            bg_color = 0x28A745, text_color = 0xFFFFFF,
            radius = math.floor(5 * density), font_size = math.floor(14 * density),
            font_weight = 600,
        },
        on_click = function()
            show_confirm("重新初始化柜子？（向服务器重新上报柜子配置）", function()
                show_tip("初始化中，请稍候…")
                sys.taskInit(function()
                    local ecbusiness = require "ecbusiness"
                    local ok, err = ecbusiness.force_locker_init()
                    if ok then
                        show_tip("重新初始化成功")
                    else
                        show_tip("重新初始化失败：" .. tostring(err))
                    end
                end)
            end)
        end
    })

    airui.button({
        parent = content,
        x = margin + (m_btn_w + m_gap) * 2, y = m_btn_y, w = m_btn_w, h = m_btn_h,
        text = "清空本地记录",
        style = {
            bg_color = 0xDC3545, text_color = 0xFFFFFF,
            radius = math.floor(5 * density), font_size = math.floor(14 * density),
            font_weight = 600,
        },
        on_click = function()
            show_confirm("清空本地记录？（删本机人脸绑定/取件码，不动服务器与人脸模板）", function()
                local ecbusiness = require "ecbusiness"
                local n = ecbusiness.clear_local_records()
                show_tip("已清理 " .. tostring(n) .. " 条本地记录")
            end)
        end
    })

    -- 二维码
    airui.qrcode({
        parent = content,
        x = math.floor((screen_w - math.floor(132 * density)) / 2),
        y = math.floor(372 * density),
        size = math.floor(132 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码说明
    airui.label({
        parent = content,
        x = math.floor((screen_w - math.floor(180 * density)) / 2),
        y = math.floor(510 * density),
        w = math.floor(180 * density),
        h = math.floor(20 * density),
        text = "公众号二维码",
        color = 0x666666,
        font_size = math.floor(12 * density),
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end
    -- 提示/确认弹窗挂在 airui.screen 上，不属于 main_container，需单独销毁
    if tip_modal then
        pcall(function() tip_modal:destroy() end)
        tip_modal = nil
    end
    if confirm_modal then
        pcall(function() confirm_modal:destroy() end)
        confirm_modal = nil
    end
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

-- 订阅开柜结果消息
sys.subscribe("BOX_OPEN_RESULT", on_box_open_result)

-- 订阅打开窗口消息
sys.subscribe("OPEN_EXPRESS_COURIER_DETAIL_WIN", open_handler)
