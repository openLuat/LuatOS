local all_app_page = {}

local main_container
local time_label
local signal_img -- 信号图标控件
local time_timer
local signal_timer


function all_app_page.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = 480, h = 320,
        color = 0xF8F9FA,
        parent = airui.screen,
    })

    local msg = airui.msgbox({
        text = "功能正在开发中，近期会进行更新！",
        buttons = { "确定" },
        on_action = function(self, label) self:hide() end
    })
    msg:hide()

    -- ==================== 顶部状态栏 ====================
    local status_bar = airui.container({
        parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5,
    })

    signal_img = airui.image({
        parent = status_bar, x = 430, y = 4, w = 32, h = 32,
        src = "/luadb/4Gxinghao6.png",  -- 默认无卡图标，稍后更新
    })

    time_label = airui.label({
        parent = status_bar, x = 188, y = 4, w = 100, h = 32,
        text = "--:--", font_size = 30, color = 0xfefefe,
    })

    -- ==================== 中间内容区域 ====================
    local content = airui.container({
        parent = main_container, x = 0, y = 40, w = 480, h = 240, color = 0xF3F4F6,
    })

    -- 列中心点（5列均匀分布，左右边距50，列中心间距95）
    local col_centers = { 50, 145, 240, 335, 430 }

    -- 图标通用宽度，特殊处理40x40的图标
    local icon_size_default = 32
    local icon_special_index = 4  -- 第二行第四列（从0开始计数）
    local icon_special_width = 40

    -- 垂直位置（基于计算：topMargin=24, gap1=6, gap2=12）
    local row_y_icons = { 24, 100, 176 }          -- 三行图标Y坐标
    local row_y_labels = { 62, 138, 214 }         -- 三行文字Y坐标

    -- 第一行图标 (5个, 32x32)
    local row1_icons = {
        "/luadb/tonghuazhong.png",
        "/luadb/paizhao.png",
        "/luadb/Internet.png",
        "/luadb/dingwei.png",
        "/luadb/chuanganqi.png"
    }
    for i = 1, 5 do
        local center = col_centers[i]
        local icon_x = center - icon_size_default / 2
        airui.image({
            parent = content,
            x = icon_x,
            y = row_y_icons[1],
            w = icon_size_default,
            h = icon_size_default,
            src = row1_icons[i],
            on_click = function() msg:show() end
        })

        -- 文字标签（宽度80，居中）
        local label_x = center - 40
        airui.label({
            parent = content,
            x = label_x,
            y = row_y_labels[1],
            w = 80,
            h = 26,
            text = (i == 1 and "通话") or
                   (i == 2 and "拍照") or
                   (i == 3 and "多网融合") or
                   (i == 4 and "定位") or
                   "传感器",
            font_size = 16,
            color = 0x000000,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 第二行图标 (5个，注意第四个为40x40)
    local row2_icons = {
        "/luadb/denglu.png",
        "/luadb/lanya.png",
        "/luadb/chuankou.png",  -- 特殊40x40
        "/luadb/luyin.png",
        "/luadb/TTS.png"
    }
    for i = 1, 5 do
        local center = col_centers[i]
        local width = (i == 3) and icon_special_width or icon_size_default  -- 注意第三个是特殊（对应第四列，索引3）
        local icon_x = center - width / 2
        airui.image({
            parent = content,
            x = icon_x,
            y = row_y_icons[2],
            w = width,
            h = width,
            src = row2_icons[i],
            on_click = function() msg:show() end
        })

        local label_text
        if i == 1 then label_text = "IoT账户"
        elseif i == 2 then label_text = "蓝牙"
        elseif i == 3 then label_text = "串口"
        elseif i == 4 then label_text = "录音"
        else label_text = "TTS"
        end

        airui.label({
            parent = content,
            x = center - 40,
            y = row_y_labels[2],
            w = 80,
            h = 26,
            text = label_text,
            font_size = 16,
            color = 0x000000,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 第三行图标 (3个，与前3列对齐)
    local row3_icons = {
        "/luadb/APN.png",
        "/luadb/yitaiwang.png",
        "/luadb/wifi.png"
    }
    for i = 1, 3 do
        local center = col_centers[i]
        local icon_x = center - icon_size_default / 2
        airui.image({
            parent = content,
            x = icon_x,
            y = row_y_icons[3],
            w = icon_size_default,
            h = icon_size_default,
            src = row3_icons[i],
            on_click = function() msg:show() end
        })

        local label_text
        if i == 1 then label_text = "APN配置"
        elseif i == 2 then label_text = "以太网"
        else label_text = "WIFI"
        end

        airui.label({
            parent = content,
            x = center - 40,
            y = row_y_labels[3],
            w = 80,
            h = 26,
            text = label_text,
            font_size = 16,
            color = 0x000000,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- ==================== 底部按钮区域 ====================
    local bottom_bar = airui.container({
        parent = main_container, x = 0, y = 280, w = 480, h = 40, color = 0xffffff,
    })

    -- 左侧按钮（首页）
    local btn_left = airui.container({
        parent = bottom_bar, x = 0, y = 0, w = 240, h = 40, color = 0x2195F6,
        on_click = function() _G.show_page("home") end
    })
    airui.image({ parent = btn_left, x = 53, y = 4, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 100, y = 10, w = 80, h = 30,
        text = "首页", font_size = 20, color = 0xfefefe })

    -- 右侧按钮（全部应用）
    local btn_right = airui.container({
        parent = bottom_bar, x = 240, y = 0, w = 240, h = 40, color = 0xFF9A27,
    })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 100, y = 10, w = 100, h = 30,
        text = "全部应用", font_size = 20, color = 0xfefefe })
end

-- 更新时间标签
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        local time_str = string.format("%02d:%02d", dt.hour, dt.min)
        if time_label then
            time_label:set_text(time_str)
        end
    end
end


-- 更新信号图标
local function update_signal()
    local img_name
    if not sim_present then
        img_name = "4Gxinghao6.png"
    else
        local csq = mobile.csq()  -- 实时获取信号强度
        if csq == 99 or csq <= 5 then
            img_name = "4Gxinghao5.png"
        elseif csq <= 10 then
            img_name = "4Gxinghao1.png"
        elseif csq <= 15 then
            img_name = "4Gxinghao2.png"
        elseif csq <= 20 then
            img_name = "4Gxinghao3.png"
        else
            img_name = "4Gxinghao4.png"
        end
    end
    if img_name then
        signal_img:set_src("/luadb/" .. img_name)
    end
end

-- 处理SIM卡状态变化
local function handle_sim_ind(status, value)

    if status  == "RDY" then
        sim_present = true
    end

    if status  == "NORDY" then
        sim_present = false
    end
    update_signal()  -- 立即更新图标
end

function all_app_page.init(params)
    all_app_page.create_ui()

    -- 订阅SIM卡状态事件，不保存返回值
    sys.subscribe("SIM_IND", handle_sim_ind)

    update_time()
    update_signal()
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)
end

function all_app_page.cleanup()
    if time_timer then sys.timerStop(time_timer); time_timer = nil end
    if signal_timer then sys.timerStop(signal_timer); signal_timer = nil end

    -- 取消SIM卡事件订阅（直接使用函数名）
    sys.unsubscribe("SIM_IND", handle_sim_ind)

    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return all_app_page