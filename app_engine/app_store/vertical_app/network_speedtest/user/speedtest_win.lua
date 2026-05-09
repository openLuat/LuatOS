--[[
@module  speedtest_win
@summary 网络测速窗口模块
@version 2.0.0
@date    2026.05.09
@author  拓毅恒
@usage
实现网络速度测试功能，包括：
1. 下载速度测试 - 多次测试取平均
2. 上传速度测试 - 多次测试取平均
3. 延迟测试 - 使用固定节点ping
4. 抖动测试

改进点：
- 使用mcu.tick64()高精度计时
- 加大测试数据量(256KB下载/128KB上传)
- 3次测试取平均值，剔除失败结果
- 使用httpbin.org节点，更稳定

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

-- 测试配置
local TEST_CONFIG = {
    download_size = 256 * 1024,       -- 256KB 下载测试
    upload_size = 128 * 1024,          -- 128KB 上传测试
    test_rounds = 3,                   -- 测试3次取平均
    timeout_ms = 30000,                -- 30秒超时
    min_valid_time_ms = 100            -- 最小有效时间100ms
}

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
        return string.format("%.2f", kbps / 1000)
    else
        return string.format("%.0f", kbps)
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

-- 全局tick_per缓存
local g_tick_per = nil

-- 获取当前时间（tick64字符串和tick_per）
local function get_tick64()
    local tick_str, tick_per = mcu.tick64()
    if not g_tick_per and tick_per then
        g_tick_per = tick_per
    end
    return tick_str
end

-- 计算两个tick64的差值（返回毫秒）
local function get_elapsed_ms(start_tick, end_tick)
    local ok, diff_ticks = mcu.dtick64(end_tick, start_tick, 0)
    if not ok or diff_ticks < 0 then
        return 0
    end
    -- diff_ticks 是tick差值，需要除以 tick_per 得到微秒，再转换为毫秒
    if g_tick_per and g_tick_per > 0 then
        local us = diff_ticks / g_tick_per
        return us / 1000  -- 微秒转毫秒
    else
        -- 如果没有tick_per，假设1 tick = 1 us（常见配置）
        return diff_ticks / 1000
    end
end

-- 测量延迟和抖动（多次取平均）
local function measure_latency_and_jitter()
    local rtts = {}
    local sample_count = 5
    
    for i = 1, sample_count do
        local start_tick = get_tick64()
        local url = BASE_URL .. "/__down?bytes=0&nocache=" .. tostring(i)
        local result = http.request("GET", url, nil, nil, {timeout=5000})
        if result and result.wait then
            local code, headers, body = result.wait()
            local end_tick = get_tick64()
            if code == 200 then
                local rtt = get_elapsed_ms(start_tick, end_tick)
                table.insert(rtts, rtt)
                log.info("speedtest", "RTT sample " .. i .. ": " .. string.format("%.1f", rtt) .. " ms")
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
    
    -- 计算平均延迟（去掉最高和最低，取中间值的平均）
    local avg_ping
    if #rtts >= 3 then
        local sum = 0
        for i = 2, #rtts - 1 do
            sum = sum + rtts[i]
        end
        avg_ping = sum / (#rtts - 2)
    else
        local sum = 0
        for _, v in ipairs(rtts) do
            sum = sum + v
        end
        avg_ping = sum / #rtts
    end
    
    -- 计算抖动
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
    
    return avg_ping, jitter
end

-- 单次下载速度测试
local function measure_download_once()
    local test_bytes = TEST_CONFIG.download_size
    local url = BASE_URL .. "/__down?bytes=" .. tostring(test_bytes)
    
    local start_tick = get_tick64()
    local result = http.request("GET", url, nil, nil, {timeout=TEST_CONFIG.timeout_ms})
    if not result or not result.wait then
        log.error("speedtest", "Download request failed")
        return nil
    end
    local code, headers, body = result.wait()
    local end_tick = get_tick64()
    
    if code ~= 200 or not body then
        log.error("speedtest", "Download failed, code: " .. tostring(code))
        return nil
    end
    
    local elapsed_ms = get_elapsed_ms(start_tick, end_tick)
    if elapsed_ms < TEST_CONFIG.min_valid_time_ms then
        log.warn("speedtest", "Download time too short: " .. elapsed_ms .. "ms")
        elapsed_ms = TEST_CONFIG.min_valid_time_ms
    end
    
    local downloaded_bytes = #body
    local elapsed_sec = elapsed_ms / 1000
    local bits = downloaded_bytes * 8
    local speed_mbps = (bits / elapsed_sec) / 1000000
    
    log.info("speedtest", "Download: " .. string.format("%.2f", speed_mbps) .. 
             " Mbps, size: " .. downloaded_bytes .. " bytes, time: " .. string.format("%.1f", elapsed_ms) .. "ms")
    
    return speed_mbps
end

-- 多次下载测试取平均
local function measure_download()
    local speeds = {}
    
    for i = 1, TEST_CONFIG.test_rounds do
        update_status("测试下载速度 (" .. i .. "/" .. TEST_CONFIG.test_rounds .. ")...")
        local speed = measure_download_once()
        if speed then
            table.insert(speeds, speed)
            log.info("speedtest", "Download round " .. i .. ": " .. string.format("%.2f", speed) .. " Mbps")
        else
            log.warn("speedtest", "Download round " .. i .. " failed")
        end
        if i < TEST_CONFIG.test_rounds then
            sys.wait(500)
        end
    end
    
    if #speeds == 0 then return nil end
    
    local sum = 0
    for _, v in ipairs(speeds) do
        sum = sum + v
    end
    local avg_speed = sum / #speeds
    
    log.info("speedtest", "Download average: " .. string.format("%.2f", avg_speed) .. 
             " Mbps (" .. #speeds .. " successful rounds)")
    
    return avg_speed
end

-- 生成指定大小的测试数据
local function generate_test_data(size)
    local chunk = string.char(0xAA, 0x55, 0xAA, 0x55):rep(256)
    local chunks_needed = math.floor(size / 1024)
    local remainder = size % 1024
    local data = chunk:rep(chunks_needed)
    if remainder > 0 then
        data = data .. chunk:sub(1, remainder)
    end
    return data
end

-- 单次上传速度测试
local function measure_upload_once()
    local test_bytes = TEST_CONFIG.upload_size
    local test_data = generate_test_data(test_bytes)
    local url = BASE_URL .. "/__up"
    
    local start_tick = get_tick64()
    local result = http.request("POST", url,
                               {["Content-Type"] = "application/octet-stream"},
                               test_data,
                               {timeout=TEST_CONFIG.timeout_ms})
    if not result or not result.wait then
        log.error("speedtest", "Upload request failed")
        return nil
    end
    local code, headers, body = result.wait()
    local end_tick = get_tick64()
    
    if code ~= 200 then
        log.error("speedtest", "Upload failed, code: " .. tostring(code))
        return nil
    end
    
    local elapsed_ms = get_elapsed_ms(start_tick, end_tick)
    if elapsed_ms < TEST_CONFIG.min_valid_time_ms then
        log.warn("speedtest", "Upload time too short: " .. elapsed_ms .. "ms")
        elapsed_ms = TEST_CONFIG.min_valid_time_ms
    end
    
    local elapsed_sec = elapsed_ms / 1000
    local bits = TEST_CONFIG.upload_size * 8
    local speed_mbps = (bits / elapsed_sec) / 1000000
    
    log.info("speedtest", "Upload: " .. string.format("%.2f", speed_mbps) .. 
             " Mbps, size: " .. TEST_CONFIG.upload_size .. " bytes, time: " .. string.format("%.1f", elapsed_ms) .. "ms")
    
    return speed_mbps
end

-- 多次上传测试取平均
local function measure_upload()
    local speeds = {}
    
    for i = 1, TEST_CONFIG.test_rounds do
        update_status("测试上传速度 (" .. i .. "/" .. TEST_CONFIG.test_rounds .. ")...")
        local speed = measure_upload_once()
        if speed then
            table.insert(speeds, speed)
            log.info("speedtest", "Upload round " .. i .. ": " .. string.format("%.2f", speed) .. " Mbps")
        else
            log.warn("speedtest", "Upload round " .. i .. " failed")
        end
        if i < TEST_CONFIG.test_rounds then
            sys.wait(500)
        end
    end
    
    if #speeds == 0 then return nil end
    
    local sum = 0
    for _, v in ipairs(speeds) do
        sum = sum + v
    end
    local avg_speed = sum / #speeds
    
    log.info("speedtest", "Upload average: " .. string.format("%.2f", avg_speed) .. 
             " Mbps (" .. #speeds .. " successful rounds)")
    
    return avg_speed
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
        if jitter_label then jitter_label:set_text("--") end
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
        start_btn:set_style({ bg_color = COLORS.primary_dark, text_color = COLORS.white })
    end
    log.info("speedtest", "Speed test completed")
end

-- 创建 UI
local function create_ui()
    -- 获取屏幕尺寸，支持自适应分辨率
    local screen_w, screen_h = lcd.getSize()
    if not screen_w or not screen_h then
        screen_w, screen_h = 480, 800  -- 默认分辨率
    end
    
    -- 计算布局参数
    local header_h = 70
    local content_y = header_h + 10
    local content_h = screen_h - content_y
    local margin_x = 20  -- 左右边距
    local available_w = screen_w - margin_x * 2
    
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h, color = COLORS.white })

    -- 顶部标题栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = screen_w, h = header_h, color = COLORS.white })
    
    -- 返回按钮（靠右放置）
    local back_btn_w, back_btn_h = 70, 40
    local back_btn = airui.container({ 
        parent = header, 
        x = screen_w - back_btn_w - 20, y = 15, w = back_btn_w, h = back_btn_h, 
        color = COLORS.primary_dark, 
        radius = 8,
        on_click = function() 
            log.info("speedtest", "返回按钮点击")
            if win_id then 
                exwin.close(win_id) 
            end 
        end 
    })
    airui.label({ parent = back_btn, x = 0, y = 10, w = back_btn_w, h = 20, text = "返回", font_size = 18, color = COLORS.white, align = airui.TEXT_ALIGN_CENTER })
    
    -- 标题（居中）
    airui.label({ parent = header, x = (screen_w - 200) / 2, y = 20, w = 200, h = 40, text = "网络测速", font_size = 28, color = COLORS.text_primary, align = airui.TEXT_ALIGN_CENTER })

    -- 主内容区域
    local content = airui.container({ parent = main_container, x = 0, y = content_y, w = screen_w, h = content_h, color = COLORS.white })

    local start_y = 20

    -- ==================== 下载 & 上传====================
    local card_y = start_y
    local card_w = math.min(210, math.floor((available_w - 20) / 2))  -- 自适应卡片宽度
    local card_h = 180
    local card_gap = 20
    local card_start_x = (screen_w - (card_w * 2 + card_gap)) / 2

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
    local aux_w = math.min(210, math.floor((available_w - 20) / 2))  -- 自适应卡片宽度
    local aux_h = 120
    local aux_gap = 20
    local aux_start_x = (screen_w - (aux_w * 2 + aux_gap)) / 2

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
    local btn_w = math.min(280, screen_w - 80)  -- 自适应按钮宽度
    start_btn = airui.button({
        parent = content, 
        x = (screen_w - btn_w) / 2, 
        y = btn_y, 
        w = btn_w, 
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
        w = screen_w, 
        h = 30,
        text = "就绪", 
        font_size = 14, 
        color = COLORS.text_secondary, 
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 底部装饰线
    local deco_y = status_y + 40
    local deco_item_w = 28
    local deco_gap = 10
    local deco_count = 4
    local deco_total_w = deco_item_w * deco_count + deco_gap * (deco_count - 1)
    local deco_start_x = (screen_w - deco_total_w) / 2
    for i = 0, deco_count - 1 do
        airui.container({ 
            parent = content, 
            x = deco_start_x + i * (deco_item_w + deco_gap), 
            y = deco_y, 
            w = deco_item_w, 
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
