--[[
@module  speedtest_win
@summary 网络测速窗口模块
@version 1.0.0
@date    2026.04.08
@author  拓毅恒
@usage
实现网络速度测试功能，包括：
1. 下载速度测试
2. 上传速度测试
3. 延迟测试
4. 抖动测试

界面风格：双核心对称布局，下载上传地位完全相等
]]

local win_id = nil
local main_container = nil

-- UI 组件引用
local download_label = nil
local upload_label = nil
local ping_label = nil
local jitter_label = nil
local status_label = nil
local start_btn = nil
local download_unit_label = nil
local upload_unit_label = nil

local is_testing = false

local test_results = {
    download = nil,
    upload = nil,
    ping = nil,
    jitter = nil
}

-- 使用 HTTP 而不是 HTTPS，避免 TLS 握手问题
local BASE_URL = "http://speed.cloudflare.com"

-- 颜色配置 (参考 speedtest.html)
local COLORS = {
    -- 主色调
    download_green = 0x1E6F5C,    -- 下载卡片绿色
    upload_red = 0xC4452C,        -- 上传卡片红色
    primary_dark = 0x222F44,      -- 按钮深色
    primary_darker = 0x17212E,    -- 按钮按下色
    
    -- 文字颜色
    text_primary = 0x1E2A44,      -- 主文字
    text_secondary = 0x6A7A99,    -- 次要文字
    text_aux = 0x2C3E66,          -- 辅助指标文字
    text_label = 0x7A89A8,        -- 标签文字
    
    -- 背景颜色
    white = 0xFFFFFF,             -- 纯白背景
    bg_card = 0xF8FAFE,           -- 卡片背景
    bg_light = 0xF5F7FB,          -- 浅色背景
    border = 0xEFF3F9,            -- 边框色
    
    -- 状态颜色
    success = 0x27AE60,           -- 成功/就绪
    warning = 0xE67E22,           -- 测试中
    danger = 0xEF4444             -- 失败
}

local function format_speed(value)
    if value == nil then return "--" end
    local kbps = value * 1000
    -- 大于等于 1000 Kbps 时显示为 Mbps
    if kbps >= 1000 then
        return string.format("%.1f", kbps / 1000)
    else
        return string.format("%d", math.floor(kbps))
    end
end

local function get_speed_unit(value)
    if value == nil then return "Kbps" end
    local kbps = value * 1000
    if kbps >= 1000 then
        return "Mbps"
    else
        return "Kbps"
    end
end

local function format_latency(value)
    if value == nil then return "--" end
    return string.format("%d", math.floor(value))
end

local function update_status(status)
    if not status_label then return end
    status_label:set_text(status)
end

local function reset_display()
    test_results = { download = nil, upload = nil, ping = nil, jitter = nil }
    if download_label then download_label:set_text("--") end
    if upload_label then upload_label:set_text("--") end
    if ping_label then ping_label:set_text("--") end
    if jitter_label then jitter_label:set_text("--") end
    update_status("就绪")
end

-- 测量延迟和抖动
local function measure_latency_and_jitter()
    local rtts = {}
    local sample_count = 5
    for i = 1, sample_count do
        local start_time = mcu.ticks()
        local result = http.request("GET", BASE_URL .. "/__down?bytes=0&nocache=" .. tostring(mcu.ticks()), nil, nil, {timeout=5000})
        if result and result.wait then
            local code, headers, body = result.wait()
            local end_time = mcu.ticks()
            if code == 200 then
                local rtt = end_time - start_time
                table.insert(rtts, rtt)
                log.info("speedtest", "RTT sample " .. i .. ": " .. rtt .. " ms")
            else
                log.warn("speedtest", "Latency request failed, code: " .. tostring(code))
            end
        else
            log.warn("speedtest", "Latency request failed, no result object")
        end
        if i < sample_count then
            sys.wait(150)
        end
    end
    if #rtts == 0 then return nil, nil end
    table.sort(rtts)
    local min_latency = rtts[1]
    local jitter = 0
    if #rtts >= 2 then
        local diffs = {}
        for i = 1, #rtts - 1 do
            table.insert(diffs, math.abs(rtts[i + 1] - rtts[i]))
        end
        local sum = 0
        for _, v in ipairs(diffs) do sum = sum + v end
        jitter = sum / #diffs
    end
    return min_latency, jitter
end

-- 测量下载速度 (32KB)
local function measure_download()
    local test_bytes = 32 * 1024  -- 32 KB
    local url = BASE_URL .. "/__down?bytes=" .. tostring(test_bytes) .. "&t=" .. tostring(mcu.ticks())
    log.info("speedtest", "Starting download test, size: 32KB")
    local start_time = mcu.ticks()
    local result = http.request("GET", url, nil, nil, {timeout=15000})
    if not result or not result.wait then
        log.error("speedtest", "Download request failed, no result object")
        return nil
    end
    local code, headers, body = result.wait()
    local end_time = mcu.ticks()
    if code ~= 200 or not body then
        log.error("speedtest", "Download test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = end_time - start_time
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local bits = #body * 8
    local speed_mbps = (bits / duration_sec) / 1000000
    log.info("speedtest", "Download: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

-- 测量上传速度 (16KB)
local function measure_upload()
    local test_bytes = 16 * 1024  -- 16 KB
    local url = BASE_URL .. "/__up"
    local test_data = string.char(0xAA):rep(test_bytes)
    
    log.info("speedtest", "Starting upload test, size: 16KB")
    local start_time = mcu.ticks()
    local result = http.request("POST", url, {["Content-Type"] = "application/octet-stream"}, test_data, {timeout=15000})
    if not result or not result.wait then
        log.error("speedtest", "Upload request failed, no result object")
        return nil
    end
    local code, headers, body = result.wait()
    local end_time = mcu.ticks()
    if code ~= 200 then
        log.error("speedtest", "Upload test failed, code: " .. tostring(code))
        return nil
    end
    local duration_ms = end_time - start_time
    if duration_ms < 10 then duration_ms = 10 end
    local duration_sec = duration_ms / 1000
    local bits = test_bytes * 8
    local speed_mbps = (bits / duration_sec) / 1000000
    log.info("speedtest", "Upload: " .. string.format("%.2f", speed_mbps) .. " Mbps, time: " .. duration_ms .. "ms")
    return speed_mbps
end

-- 运行完整测速（在协程中执行）
local function run_speed_test_task()
    if is_testing then return end
    is_testing = true
    
    if start_btn then
        start_btn:set_text("测速中...")
        start_btn:set_style({ bg_color = COLORS.text_secondary })
    end
    reset_display()

    update_status("测延迟 & 抖动...")
    sys.wait(100)
    local ping, jitter = measure_latency_and_jitter()
    if ping then
        test_results.ping = ping
        if ping_label then ping_label:set_text(format_latency(ping)) end
    else
        if ping_label then ping_label:set_text("ERR") end
    end
    if jitter then
        test_results.jitter = jitter
        if jitter_label then jitter_label:set_text(string.format("%.1f", jitter)) end
    else
        if jitter_label then jitter_label:set_text("ERR") end
    end

    update_status("测试下载速度...")
    sys.wait(100)
    local download = measure_download()
    if download then
        test_results.download = download
        if download_label then download_label:set_text(format_speed(download)) end
        if download_unit_label then download_unit_label:set_text(get_speed_unit(download)) end
    else
        if download_label then download_label:set_text("失败") end
        if download_unit_label then download_unit_label:set_text("") end
    end

    update_status("测试上传速度...")
    sys.wait(100)
    local upload = measure_upload()
    if upload then
        test_results.upload = upload
        if upload_label then upload_label:set_text(format_speed(upload)) end
        if upload_unit_label then upload_unit_label:set_text(get_speed_unit(upload)) end
    else
        if upload_label then upload_label:set_text("失败") end
        if upload_unit_label then upload_unit_label:set_text("") end
    end

    if test_results.download or test_results.upload then
        update_status("测速完成")
    else
        update_status("部分失败，请重试")
    end
    
    is_testing = false
    if start_btn then
        start_btn:set_text("重新测速")
        start_btn:set_style({ bg_color = COLORS.primary_dark })
    end
    log.info("speedtest", "Speed test completed")
end

-- 创建 UI
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = COLORS.white })

    -- 顶部标题栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 70, color = COLORS.white })
    
    -- 返回按钮
    local back_btn = airui.container({ 
        parent = header, 
        x = 390, y = 15, w = 70, h = 40, 
        color = COLORS.primary_dark, 
        radius = 8,
        on_click = function() 
            log.info("speedtest", "返回按钮点击")
            if win_id then 
                exwin.close(win_id) 
            end 
        end 
    })
    airui.label({ parent = back_btn, x = 0, y = 10, w = 70, h = 20, text = "返回", font_size = 18, color = COLORS.white, align = airui.TEXT_ALIGN_CENTER })
    
    -- 标题
    airui.label({ parent = header, x = 140, y = 20, w = 200, h = 40, text = "网络测速", font_size = 28, color = COLORS.text_primary, align = airui.TEXT_ALIGN_CENTER })

    -- 主内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 80, w = 480, h = 720, color = COLORS.white })

    local start_y = 20

    -- ==================== 下载 & 上传====================
    local card_y = start_y
    local card_w = 210
    local card_h = 180
    local card_gap = 20
    local card_start_x = (480 - (card_w * 2 + card_gap)) / 2

    -- 下载卡片 (绿色主题)
    local download_card = airui.container({ 
        parent = content, 
        x = card_start_x, 
        y = card_y, 
        w = card_w, 
        h = card_h, 
        color = COLORS.bg_card, 
        radius = 48 
    })
    airui.image({ parent = download_card, x = (card_w - 40) / 2, y = 20, w = 40, h = 40, src = "/luadb/DOWNLOAD.png", opacity = 255 })
    airui.label({ parent = download_card, x = 0, y = 65, w = card_w, h = 24, text = "下载速度", font_size = 16, color = COLORS.text_secondary, align = airui.TEXT_ALIGN_CENTER })
    download_label = airui.label({ parent = download_card, x = 0, y = 95, w = card_w, h = 50, text = "--", font_size = 48, color = COLORS.download_green, align = airui.TEXT_ALIGN_CENTER, font_weight = 2 })
    download_unit_label = airui.label({ parent = download_card, x = 0, y = 145, w = card_w, h = 24, text = "Kbps", font_size = 16, color = COLORS.text_secondary, align = airui.TEXT_ALIGN_CENTER })

    -- 上传卡片 (红色主题)
    local upload_card = airui.container({ 
        parent = content, 
        x = card_start_x + card_w + card_gap, 
        y = card_y, 
        w = card_w, 
        h = card_h, 
        color = COLORS.bg_card, 
        radius = 48 
    })
    airui.image({ parent = upload_card, x = (card_w - 40) / 2, y = 20, w = 40, h = 40, src = "/luadb/UPLOAD.png", opacity = 255 })
    airui.label({ parent = upload_card, x = 0, y = 65, w = card_w, h = 24, text = "上传速度", font_size = 16, color = COLORS.text_secondary, align = airui.TEXT_ALIGN_CENTER })
    upload_label = airui.label({ parent = upload_card, x = 0, y = 95, w = card_w, h = 50, text = "--", font_size = 48, color = COLORS.upload_red, align = airui.TEXT_ALIGN_CENTER, font_weight = 2 })
    upload_unit_label = airui.label({ parent = upload_card, x = 0, y = 145, w = card_w, h = 24, text = "Kbps", font_size = 16, color = COLORS.text_secondary, align = airui.TEXT_ALIGN_CENTER })

    -- ==================== 延迟 + 抖动 ====================
    local aux_y = card_y + card_h + 24
    local aux_w = 210
    local aux_h = 120
    local aux_gap = 20
    local aux_start_x = (480 - (aux_w * 2 + aux_gap)) / 2

    -- 延迟卡片
    local ping_card = airui.container({ 
        parent = content, 
        x = aux_start_x, 
        y = aux_y, 
        w = aux_w, 
        h = aux_h, 
        color = COLORS.bg_card, 
        radius = 36 
    })
    airui.image({ parent = ping_card, x = (aux_w - 28) / 2, y = 15, w = 28, h = 28, src = "/luadb/PING.png", opacity = 255 })
    airui.label({ parent = ping_card, x = 0, y = 45, w = aux_w, h = 20, text = "延迟 (Ping)", font_size = 13, color = COLORS.text_label, align = airui.TEXT_ALIGN_CENTER })
    ping_label = airui.label({ parent = ping_card, x = 0, y = 68, w = aux_w, h = 36, text = "--", font_size = 28, color = COLORS.text_aux, align = airui.TEXT_ALIGN_CENTER, font_weight = 2 })
    airui.label({ parent = ping_card, x = 0, y = 100, w = aux_w, h = 18, text = "ms", font_size = 14, color = COLORS.text_label, align = airui.TEXT_ALIGN_CENTER })

    -- 抖动卡片
    local jitter_card = airui.container({ 
        parent = content, 
        x = aux_start_x + aux_w + aux_gap, 
        y = aux_y, 
        w = aux_w, 
        h = aux_h, 
        color = COLORS.bg_card, 
        radius = 36 
    })
    airui.image({ parent = jitter_card, x = (aux_w - 28) / 2, y = 15, w = 28, h = 28, src = "/luadb/JITTER.png", opacity = 255 })
    airui.label({ parent = jitter_card, x = 0, y = 45, w = aux_w, h = 20, text = "抖动 (Jitter)", font_size = 13, color = COLORS.text_label, align = airui.TEXT_ALIGN_CENTER })
    jitter_label = airui.label({ parent = jitter_card, x = 0, y = 68, w = aux_w, h = 36, text = "--", font_size = 28, color = COLORS.text_aux, align = airui.TEXT_ALIGN_CENTER, font_weight = 2 })
    airui.label({ parent = jitter_card, x = 0, y = 100, w = aux_w, h = 18, text = "ms", font_size = 14, color = COLORS.text_label, align = airui.TEXT_ALIGN_CENTER })

    -- ==================== 测速按钮 ====================
    local btn_y = aux_y + aux_h + 40
    start_btn = airui.button({
        parent = content, 
        x = 100, 
        y = btn_y, 
        w = 280, 
        h = 60,
        text = "开始测速", 
        font_size = 20, 
        font_color = COLORS.white, 
        bg_color = COLORS.primary_dark, 
        radius = 60,
        on_click = function()
            sys.publish("SPEEDTEST_START")
        end
    })

    -- ==================== 状态栏 ====================
    local status_y = btn_y + 80
    status_label = airui.label({
        parent = content, 
        x = 0, 
        y = status_y, 
        w = 480, 
        h = 30,
        text = "就绪", 
        font_size = 14, 
        color = COLORS.text_secondary, 
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 底部装饰线
    local deco_y = status_y + 40
    local deco_start_x = (480 - (28 * 4 + 10 * 3)) / 2
    for i = 0, 3 do
        airui.container({ 
            parent = content, 
            x = deco_start_x + i * (28 + 10), 
            y = deco_y, 
            w = 28, 
            h = 3, 
            color = 0xE6ECF5, 
            radius = 3 
        })
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    is_testing = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
end

local function on_lose_focus()
end

-- 初始化：创建窗口并订阅测速消息
sys.taskInit(function()
    sys.subscribe("OPEN_SPEEDTEST_WIN", function()
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end)
    
    sys.subscribe("SPEEDTEST_START", function()
        sys.taskInit(run_speed_test_task)
    end)
end)

return {
    on_create = on_create,
    on_destroy = on_destroy,
    on_get_focus = on_get_focus,
    on_lose_focus = on_lose_focus,
}
