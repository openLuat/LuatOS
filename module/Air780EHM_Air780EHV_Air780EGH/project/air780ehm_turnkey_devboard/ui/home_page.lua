local home_page = {}

local main_container
local time_label
local temp_label, hum_label, air_label
local signal_img -- 信号图标控件
local time_timer
local signal_timer
local aircloud_qr, qrcode1
local active = false -- 控制任务是否运行
local temp_val, hum_val, voc_val = "未接入传感器", "未接入传感器", "未接入传感器"
local card_temp, card_hum, card_air


-- 更新时间标签
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        local hour = dt.hour
        local min = dt.min
        local time_str = string.format("%02d:%02d", hour, min)
        if time_label then
            time_label:set_text(time_str)
        end
    end
end

function home_page.create_ui()
    -- 主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xF8F9FA,
        parent = airui.screen,
    })

    local msg = airui.msgbox({
        text = "功能正在开发中，近期会进行更新！",
        buttons = { "确定" },
        on_action = function(self, label)
            self:hide()
        end
    })
    msg:hide()

    -- 顶部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 40,
        color = 0x3F51B5,
    })

    -- 信号图标
    signal_img = airui.image({
        parent = status_bar,
        x = 430,
        y = 4,
        w = 32,
        h = 32,
        src = "/luadb/4Gxinghao6.png", -- 默认无卡图标，稍后会被更新
    })

    -- 时间标签
    time_label = airui.label({
        parent = status_bar,
        x = 188,
        y = 4,
        w = 100,
        h = 32,
        text = "--:--",
        font_size = 30,
        color = 0xfefefe,
    })

    -- 中间内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 40,
        w = 480,
        h = 240,
        color = 0xF3F4F6,
    })

    -- 三个卡片容器
    card_temp = airui.container({
        parent = content,
        x = 15,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function(self) msg:show() end
    })
    card_hum = airui.container({
        parent = content,
        x = 170,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function(self) msg:show() end
    })
    card_air = airui.container({
        parent = content,
        x = 325,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function(self) msg:show() end
    })

    -- 温度卡片
    airui.image({ parent = card_temp, x = 54, y = 8, w = 32, h = 32, src = "/luadb/wendu_1.png" })
    temp_label = airui.label({
        parent = card_temp,
        x = 10,
        y = 45,
        w = 80,
        h = 35,
        text = temp_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_temp,
        x = 100,
        y = 60,
        w = 30,
        h = 16,
        text = "℃",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_temp,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前温度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 54, y = 8, w = 32, h = 32, src = "/luadb/shidu.png" })
    hum_label = airui.label({
        parent = card_hum,
        x = 10,
        y = 45,
        w = 80,
        h = 35,
        text = hum_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_hum,
        x = 100,
        y = 60,
        w = 30,
        h = 18,
        text = "%",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_hum,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前湿度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 54, y = 8, w = 32, h = 32, src = "/luadb/kongqizhiliang.png" })
    air_label = airui.label({
        parent = card_air,
        x = 10,
        y = 45,
        w = 80,
        h = 36,
        text = voc_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_air,
        x = 95,
        y = 60,
        w = 40,
        h = 16,
        text = "ppb",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_air,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "空气质量",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题: 常用应用
    airui.label({
        parent = content,
        x = 0,
        y = 130,
        w = 240,
        h = 20,
        text = "扫码查看设备云端数据",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = content,
        x = 240,
        y = 130,
        w = 240,
        h = 20,
        text = "扫码查看设备使用说明",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    qrcode1 = airui.qrcode({
        parent = content,
        x = 80,
        y = 150,
        size = 90,
        data = aircloud_qr,
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    local qrcode2 = airui.qrcode({
        parent = content,
        x = 320,
        y = 150,
        size = 90,
        data = "https://docs.openluat.com/air780epm/product/air780ehm_turnkey_devboard/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 底部按钮区域
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 280,
        w = 480,
        h = 40,
        color = 0xffffff,
    })

    -- 左侧按钮
    local btn_left = airui.container({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 40,
        color = 0xFF9A27,
    })
    airui.image({ parent = btn_left, x = 53, y = 4, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({
        parent = btn_left,
        x = 100,
        y = 10,
        w = 80,
        h = 30,
        text = "首页",
        font_size = 20,
        color = 0xfefefe,
    })

    -- 右侧按钮
    local btn_right = airui.container({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 40,
        color = 0x2195F6,
        on_click = function() _G.show_page("all_app") end
    })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({
        parent = btn_right,
        x = 100,
        y = 10,
        w = 100,
        h = 30,
        text = "全部应用",
        font_size = 20,
        color = 0xfefefe,
    })
end

local function aircloud_qr_task()
    local result
    result, aircloud_qr = sys.waitUntil("aircloud_qrinfo")
    if qrcode1 then
        qrcode1:set_data(aircloud_qr)
    end
end

-- 传感器读取任务（UI更新）
local function sensor_read_task()
    while true do
        local result, temp_val, hum_val, voc_val = sys.waitUntil("ui_sensor_data")
        if active then
            -- 温度
            if temp_val ~= nil then
                temp_label:set_text(string.format("%.1f", temp_val))
                temp_label:set_color(0x000000)
                temp_label:set_font_size(36)
            else
                temp_label:set_text("未接入传感器")
                temp_label:set_color(0xFF0000)
                temp_label:set_font_size(16)
            end

            -- 湿度
            if hum_val ~= nil then
                hum_label:set_text(string.format("%.0f", hum_val))
                hum_label:set_color(0x000000)
                hum_label:set_font_size(36)
            else
                hum_label:set_text("未接入传感器")
                hum_label:set_color(0xFF0000)
                hum_label:set_font_size(16)
            end

            -- VOC
            if voc_val ~= nil then
                air_label:set_text(string.format("%d", voc_val))
                air_label:set_color(0x000000)
                air_label:set_font_size(36)
            else
                air_label:set_text("未接入传感器")
                air_label:set_color(0xFF0000)
                air_label:set_font_size(16)
            end
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

    log.info("插卡情况",status)

    if status  == "RDY" then
        sim_present = true
    end

    if status  == "NORDY" then
        sim_present = false
    end
    update_signal()  -- 立即更新图标
end

function home_page.init()
    home_page.create_ui()
    active = true

    -- 订阅SIM卡状态事件，不保存返回值
    sys.subscribe("SIM_IND", handle_sim_ind)

    -- 立即刷新一次
    update_time()
    update_signal()

    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)

    sys.publish("read_sensors_req")
end

function home_page.cleanup()
    active = false

    -- 停止定时器
    if time_timer then sys.timerStop(time_timer); time_timer = nil end
    if signal_timer then sys.timerStop(signal_timer); signal_timer = nil end

    -- 取消SIM卡事件订阅（直接使用函数名）
    sys.unsubscribe("SIM_IND", handle_sim_ind)

    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

-- 启动后台任务
sys.taskInit(aircloud_qr_task)
sys.taskInit(sensor_read_task)

return home_page