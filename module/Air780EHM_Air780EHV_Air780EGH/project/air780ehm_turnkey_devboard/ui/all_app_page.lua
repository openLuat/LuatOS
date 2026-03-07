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
    local icon_special_width = 40

    -- 垂直位置（基于计算：topMargin=24, gap1=6, gap2=12）
    local row_y_icons = { 9, 86, 163 }          -- 三行图标Y坐标
    local row_y_labels = { 62, 138, 214 }         -- 三行文字Y坐标

    -- 页面映射表，与 ui_main 中的 pages 保持一致
    local page_map = {
        [1] = { "call", "camera", "network_select", "gps", "sensor" },
        [2] = { "iot_account", "bluetooth", "uart", "record", "tts" },
        [3] = { "apn", "ethernet", "wifi" }  -- 第三行只有三列
    }

    -- 图标文件名（仅用于显示，不用于点击）
    local icon_files = {
        [1] = { "/luadb/tonghuazhong.png", "/luadb/paizhao.png", "/luadb/Internet.png", "/luadb/dingwei.png", "/luadb/chuanganqi.png" },
        [2] = { "/luadb/denglu.png", "/luadb/lanya.png", "/luadb/chuankou.png", "/luadb/luyin.png", "/luadb/TTS.png" },
        [3] = { "/luadb/APN.png", "/luadb/yitaiwang.png", "/luadb/wifi.png" }
    }

    -- 标签文字
    local label_texts = {
        [1] = { "通话", "拍照", "多网融合", "定位", "传感器" },
        [2] = { "IoT账户", "蓝牙", "串口", "录音", "TTS" },
        [3] = { "APN配置", "以太网", "WIFI" }
    }

    -- 定义每个格子的宽高（覆盖图标和标签）
    local cell_w = 90
    local cell_h = 70

    -- 遍历三行
    for row = 1, 3 do
        local cols = (row == 3) and 3 or 5
        for col = 1, cols do
            local center_x = col_centers[col]
            -- 格子左上角坐标，使图标和标签大致居中
            local cell_x = center_x - cell_w / 2
            local cell_y = row_y_icons[row] - 5  -- 让格子顶部略高于图标顶部

            -- 创建格子容器，背景色透明（可设半透明以便调试，正式使用透明）
            local cell = airui.container({
                parent = content,
                x = cell_x,
                y = cell_y,
                w = cell_w,
                h = cell_h,
                color = 0xF3F4F6,  -- 与背景保持一致
                on_click = function()
                    local page_name = page_map[row][col]
                    if page_name then
                        _G.show_page(page_name)
                    end
                end
            })

            -- 图标尺寸
            local icon_w = icon_size_default
            local icon_h = icon_size_default
            -- 第二行第三列（row=2, col=3）使用特殊宽度
            if row == 2 and col == 3 then
                icon_w = icon_special_width
                icon_h = icon_special_width
            end

            -- 图标在格子内的水平居中
            local icon_x = (cell_w - icon_w) / 2
            -- 图标在格子内的垂直位置：距离顶部5px
            local icon_y = 5

            airui.image({
                parent = cell,
                x = icon_x,
                y = icon_y,
                w = icon_w,
                h = icon_h,
                src = icon_files[row][col],
                -- 不设置点击，由容器处理
            })

            -- 标签在格子内的水平居中（标签宽80）
            local label_x = (cell_w - 80) / 2
            -- 标签在图标下方，间隔约6px
            local label_y = icon_y + icon_h + 6

            airui.label({
                parent = cell,
                x = label_x,
                y = label_y,
                w = 80,
                h = 16,
                text = label_texts[row][col],
                font_size = 16,
                color = 0x000000,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
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
    if img_name and signal_img then
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

    -- 订阅SIM卡状态事件
    sys.subscribe("SIM_IND", handle_sim_ind)

    update_time()
    update_signal()
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)
end

function all_app_page.cleanup()
    if time_timer then sys.timerStop(time_timer); time_timer = nil end
    if signal_timer then sys.timerStop(signal_timer); signal_timer = nil end

    -- 取消SIM卡事件订阅
    sys.unsubscribe("SIM_IND", handle_sim_ind)

    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return all_app_page