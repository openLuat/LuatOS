--[[
@module  home_page
@summary 酷炫版首页（UI+UART独立版本）
@version 2.0
@date    2026.03.17
]]

local home_page = {}

-- UI控件引用
local main_container
local time_label
local signal_img
local uart_card

-- 定时器句柄
local time_timer
local signal_timer
local pulse_timer
local particle_timer

-- 状态标志
local active = false
local pulse_state = 0
local pulse_direction = 1

-- 更新时间标签
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        local hour = dt.hour
        local min = dt.min
        local sec = dt.sec
        local time_str = string.format("%02d:%02d:%02d", hour, min, sec)
        if time_label then
            time_label:set_text(time_str)
        end
    end
end

-- 更新信号图标
local function update_signal()
    if not signal_img then return end
    local img_name
    if not sim_present then
        img_name = "4Gxinghao6.png"
    else
        local csq = mobile.csq()
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
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    if active and signal_img then
        update_signal()
    end
end

-- 卡片脉冲动画
local function pulse_animation()
    if not active or not uart_card then return end

    pulse_state = pulse_state + pulse_direction * 5
    if pulse_state >= 100 then
        pulse_direction = -1
    elseif pulse_state <= 50 then
        pulse_direction = 1
    end

    -- 颜色渐变效果
    local r, g, b = 33, 150, 243
    local intensity = pulse_state / 100
    local color = (math.floor(r * intensity) << 16) + (math.floor(g * intensity) << 8) + math.floor(b * intensity)
    uart_card:set_color(color)
end

-- 粒子效果
local particles = {}
local particle_count = 20

-- 初始化粒子
local function init_particles()
    particles = {}
    for i = 1, particle_count do
        table.insert(particles, {
            x = math.random(0, 480),
            y = math.random(0, 320),
            vx = (math.random() - 0.5) * 0.5,
            vy = (math.random() - 0.5) * 0.5,
            size = math.random(1, 3),
            alpha = math.random(50, 150),
            speed = math.random(1, 3) * 0.1
        })
    end
end

-- 粒子容器
local particle_containers = {}

-- 更新粒子
local function update_particles()
    if not active or not main_container then return end
    
    -- 清理旧粒子
    for i, container in ipairs(particle_containers) do
        if container then
            container:destroy()
        end
    end
    particle_containers = {}
    
    for i, p in ipairs(particles) do
        p.x = p.x + p.vx * p.speed
        p.y = p.y + p.vy * p.speed
        
        -- 边界检测
        if p.x < 0 or p.x > 480 then
            p.vx = -p.vx
        end
        if p.y < 0 or p.y > 320 then
            p.vy = -p.vy
        end
        
        -- 绘制粒子
        local particle = airui.container({
            parent = main_container,
            x = p.x - p.size/2,
            y = p.y - p.size/2,
            w = p.size,
            h = p.size,
            color = 0x00d4ff,
            radius = p.size/2
        })
        table.insert(particle_containers, particle)
    end
end

-- 创建酷炫UI
function home_page.create_ui()
    -- 主容器 - 使用深色渐变背景风格
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0x1a1a2e,
        parent = airui.screen,
    })

    -- 背景渐变效果
    local gradient = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0x0f1629,
    })

    -- 顶部状态栏 - 现代化设计
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x16213e,
        radius = 0
    })

    -- 左侧：项目标题
    airui.label({
        parent = status_bar,
        x = 15,
        y = 10,
        w = 150,
        h = 30,
        text = "UART Tool",
        font_size = 20,
        color = 0x00d4ff,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 中间：时间显示（带边框效果）
    local time_box = airui.container({
        parent = status_bar,
        x = 170,
        y = 8,
        w = 140,
        h = 34,
        color = 0x0f3460,
        radius = 8,
    })
    time_label = airui.label({
        parent = time_box,
        x = 5,
        y = 2,
        w = 130,
        h = 30,
        text = "--:--:--",
        font_size = 20,
        color = 0xe94560,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 右侧：信号图标
    signal_img = airui.image({
        parent = status_bar,
        x = 425,
        y = 8,
        w = 32,
        h = 32,
        src = "/luadb/4Gxinghao6.png",
    })

    -- 中间内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 480,
        h = 220,
        color = 0x1a1a2e,
    })

    -- 装饰性线条
    airui.container({
        parent = content,
        x = 0,
        y = 20,
        w = 480,
        h = 2,
        color = 0x0f3460,
    })

    -- 主标题区域
    local title_container = airui.container({
        parent = content,
        x = 20,
        y = 40,
        w = 440,
        h = 60,
    })

    airui.label({
        parent = title_container,
        x = 0,
        y = 0,
        w = 440,
        h = 35,
        text = "串口通信工具",
        font_size = 28,
        color = 0x00d4ff,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = title_container,
        x = 0,
        y = 35,
        w = 440,
        h = 20,
        text = "Serial Communication Tool",
        font_size = 12,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 状态指示器
    local status_dot1 = airui.container({
        parent = content,
        x = 140,
        y = 115,
        w = 12,
        h = 12,
        color = 0x00ff88,
        radius = 6,
    })

    airui.label({
        parent = content,
        x = 160,
        y = 110,
        w = 160,
        h = 20,
        text = "系统运行中",
        font_size = 14,
        color = 0x00ff88,
    })

    -- UART功能入口卡片 - 大尺寸、带圆角和阴影效果
    uart_card = airui.container({
        parent = content,
        x = 40,
        y = 145,
        w = 400,
        h = 65,
        color = 0x0f3460,
        radius = 16,
        on_click = function() _G.show_page("uart") end
    })

    -- 卡片图标
    airui.image({
        parent = uart_card,
        x = 20,
        y = 12,
        w = 42,
        h = 42,
        src = "/luadb/chuankou.png",
    })

    -- 卡片标题
    airui.label({
        parent = uart_card,
        x = 80,
        y = 8,
        w = 200,
        h = 25,
        text = "串口调试",
        font_size = 22,
        color = 0x00d4ff,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 卡片副标题
    airui.label({
        parent = uart_card,
        x = 80,
        y = 35,
        w = 200,
        h = 18,
        text = "UART1/2/3 · 点击进入",
        font_size = 12,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 箭头图标
    airui.label({
        parent = uart_card,
        x = 350,
        y = 20,
        w = 35,
        h = 25,
        text = "→",
        font_size = 24,
        color = 0x00d4ff,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 底部按钮区域 - 现代化设计
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 270,
        w = 480,
        h = 50,
        color = 0x16213e,
    })

    -- 分割线
    airui.container({
        parent = main_container,
        x = 0,
        y = 270,
        w = 480,
        h = 2,
        color = 0x0f3460,
    })

    -- 首页按钮
    local btn_left = airui.container({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 50,
        color = 0x16213e,
    })
    airui.image({
        parent = btn_left,
        x = 70,
        y = 8,
        w = 34,
        h = 34,
        src = "/luadb/home.png"
    })
    airui.label({
        parent = btn_left,
        x = 115,
        y = 12,
        w = 80,
        h = 26,
        text = "首页",
        font_size = 20,
        color = 0x00d4ff,
    })

    -- 设置按钮
    local btn_right = airui.container({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 50,
        color = 0x16213e,
        on_click = function()
            local msg = airui.msgbox({
                title = "关于",
                text = "UART Tool v2.0\n\n基于AirUI框架开发\n支持串口通信调试",
                buttons = { "确定" },
                on_action = function(self, label)
                    if label == "确定" then
                        self:hide()
                    end
                end
            })
            msg:show()
        end
    })
    airui.label({
        parent = btn_right,
        x = 170,
        y = 12,
        w = 60,
        h = 26,
        text = "关于",
        font_size = 20,
        color = 0xe94560,
    })

    -- 初始化粒子
    init_particles()
end

-- 页面初始化
function home_page.init()
    home_page.create_ui()
    active = true

    -- 立即刷新一次
    update_time()
    update_signal()

    -- 启动定时器
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)
    pulse_timer = sys.timerLoopStart(pulse_animation, 100)
    particle_timer = sys.timerLoopStart(update_particles, 50)

    -- 订阅SIM卡事件
    sys.subscribe("SIM_IND", handle_sim_ind)
end

-- 页面清理
function home_page.cleanup()
    active = false

    -- 停止定时器
    if time_timer then
        sys.timerStop(time_timer)
        time_timer = nil
    end
    if signal_timer then
        sys.timerStop(signal_timer)
        signal_timer = nil
    end
    if pulse_timer then
        sys.timerStop(pulse_timer)
        pulse_timer = nil
    end
    if particle_timer then
        sys.timerStop(particle_timer)
        particle_timer = nil
    end

    -- 取消SIM事件订阅
    sys.unsubscribe("SIM_IND", handle_sim_ind)

    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 清空控件引用
    time_label = nil
    signal_img = nil
    uart_card = nil
    particles = {}
    
    -- 清理粒子容器
    for i, container in ipairs(particle_containers) do
        if container then
            container:destroy()
        end
    end
    particle_containers = {}
end

return home_page
