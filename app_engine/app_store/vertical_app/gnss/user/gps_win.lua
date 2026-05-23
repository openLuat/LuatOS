--[[
GPS定位页面

@module gps_win
@summary GPS定位页面实现
@version 1.0
@date 2026.03.24
@author 李源龙
@usage
本文件实现了GPS定位页面的UI和功能，包括获取位置、立即关闭、配置和卫星信息按钮，以及地图和卫星状态面板。
]]
-- 引入必要的库
local exgnss = require "exgnss"
local mapTile = require("mapTile")
-- -- exwin 由 exapp 沙箱环境自动注入，不需要 require
-- -- 需要使用exvib库来检测震动
local exvib = require "exvib"
local exmux = require "exmux"
local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位
local ipready=false --网络是否连接成功标志位
local tickid
local config_win = require "config_win"
-- 硬件I2C/SPI配置，当您使用合宙开发板时，请根据具体的开发板版本选择对应的变量，
-- exmux库将会自动处理开发板上的I2C/SPI外设，确保总线通讯正常
-- 当您使用自己的制作的板子，请参考exmux库的文档，配置对应的变量：https://docs.openluat.com/osapi/ext/exmux/
local HARDWARE_ENV = "DEV_BOARD_8000_V2.0"
-- local HARDWARE_ENV = "DEV_BOARD_780_V1.2"
-- local HARDWARE_ENV = "DEV_BOARD_780_V1.3"


-- 全局变量
local win_id
local content
local main_container
local locate_btn
local stop_btn
local config_btn
local satellite_btn
local map_toggle_btn
local map_toggle_label
local latitude_label
local longitude_label
local address_label
local map_container
local map_img
local satellite_count_label
local speed_label
local fix_status_label
local fix_time_label
local visible_satellite_label
local speed_info_label
local fix_status_info_label
local fix_time_info_label
local right_panel
local is_map_visible = false
local is_gps_enabled = true
local current_lat = 0
local current_lng = 0
local gps_timer
local config
local gnss_timer

-- 定位耗时计时器变量
local location_duration = 0
local duration_timer = nil
local is_first_fix = false  -- 首次定位成功标志

-- 屏幕尺寸和密度计算
local screen_w, screen_h = 480, 320

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

-- 密度计算
local function get_density_scale()
    -- 以480x320为基准
    local base_w, base_h = 480, 320
    local current_w, current_h = screen_w, screen_h
    
    -- 计算宽度和高度比例
    local w_scale = current_w / base_w
    local h_scale = current_h / base_h
    
    -- 使用最小比例以保持一致性
    return math.min(w_scale, h_scale)
end

--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
local function tick()
    num=num+1
end
-- --每秒运行一次计时
tickid=sys.timerLoopStart(tick,1000)
-- 设置GNSS参数
local gnssotps={
    gnssmode=1, --1为卫星全定位，2为单北斗
    agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
    debug=true,    --是否输出调试信息
}
exgnss.setup(gnssotps)


--[[
定位耗时更新函数

@local
@function update_location_duration
@return nil
@usage
-- 每1秒调用一次，更新定位耗时显示
]]
local function update_location_duration()
    if win_id == nil  then return end
    -- 只有在GPS开启且未定位成功时才增加耗时
    if is_gps_enabled and not exgnss.is_fix() then
        location_duration = location_duration + 1
        if fix_time_label then
            fix_time_label:set_text(location_duration .. "s")
        end
    end
end



--[[
更新位置信息

@local
@function update_location
@param lat {number} 纬度
@param lng {number} 经度
@return nil
@usage
-- 更新位置信息标签
]]
local function update_location(lat, lng)
    if win_id == nil then return end
    
    if latitude_label then
        latitude_label:set_text(string.format("%.6f", lat))
    end
    if longitude_label then
        longitude_label:set_text(string.format("%.6f", lng))
    end
end



--[[
更新卫星状态信息

@local
@function update_satellite_status
@return nil
@usage
-- 更新可见卫星数、信号强度等信息
]]
local function update_satellite_status()
    if win_id == nil then return end
    
    -- 使用真实的 exgnss.gsv() 数据
    local gsv = exgnss.gsv()
    log.info("GPS_WIN", "exgnss.gsv() result:", gsv)
    
    -- 更新可见卫星数
    if satellite_count_label then
        if gsv and gsv.total_sats and gsv.total_sats > 0 then
            satellite_count_label:set_text(tostring(gsv.total_sats))
            log.info("GPS_WIN", "Satellite count updated to:", gsv.total_sats)
        else
            satellite_count_label:set_text("0")
            log.info("GPS_WIN", "Satellite count is 0")
        end
    end
    
    -- 获取定位状态
    local is_fix = exgnss.is_fix()
    log.info("GPS_WIN", "exgnss.is_fix() result:", is_fix)
    if fix_status_label then
        fix_status_label:set_text(is_fix and "是" or "否")
        log.info("GPS_WIN", "Fix status updated to:", is_fix and "是" or "否")
    end
    
    -- 更新速度值（使用 RMC 数据）
    if speed_label then
        if is_fix then
            local rmc = exgnss.rmc(2) -- 使用高德地图坐标系
            log.info("GPS_WIN", "exgnss.rmc(2) result:", rmc)
            if rmc and rmc.speed then
                speed_label:set_text(string.format("%.1f km/h", rmc.speed * 1.852)) -- 转换为 km/h
                log.info("GPS_WIN", "Speed updated to:", string.format("%.1f km/h", rmc.speed * 1.852))
            else
                speed_label:set_text("0 km/h")
                log.info("GPS_WIN", "Speed is 0")
            end
        else
            speed_label:set_text("0 km/h")
            log.info("GPS_WIN", "Speed is 0 (not fixed)")
        end
    end
    
    -- 更新定位时间
    if fix_time_label then
        if is_fix then
            -- 定位成功后，显示最终耗时，不再更新
            if not is_first_fix then
                is_first_fix = true
                -- 停止耗时计时器
                if duration_timer then
                    sys.timerStop(duration_timer)
                    duration_timer = nil
                end
            end
            fix_time_label:set_text(tostring(location_duration or 0) .. "s")
        else
            -- 未定位成功时，显示当前计时（由 update_location_duration 负责更新）
            -- 不要在这里重置为0，避免覆盖计时
        end
    end
end

--[[
加载地图瓦片

@local
@function load_map
@return nil
@usage
-- 加载地图瓦片
]]
local function load_map()
    if win_id == nil then return end
    
    if current_lat == 0 or current_lng == 0 then
        if address_label then
            address_label:set_text("位置:还未定位成功")
        end
        return
    end
    
    -- 检查网络连接
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    
    -- 再次检查窗口是否还存在
    if win_id == nil then return end
    
    -- 生成地图瓦片URL
    local url, x, y = mapTile.generate_gaode_url(current_lng, current_lat, 16)
    log.info("mapTile", url, x, y)
    
    -- 下载地图瓦片
    local code, headers, body_size = http.request("GET", url, nil, nil, {dst="/1.png", timeout=10000}).wait()
    log.info("http_app_get_file2", code)
    
    -- 再次检查窗口是否还存在（HTTP请求可能耗时较长）
    if win_id == nil then return end
    
    -- 加载地图瓦片
    if code == 200 then
        -- 销毁旧地图
        if map_img then
            map_img:destroy()
        end
        
        -- 显示地图
        map_img = airui.image({
            src = "/1.png",
            x = 0,
            y = 0,
            w = 250,
            h = 260,
            pivot = {x=1, y=1},
            zoom = 240,
            opacity = 255,
            parent = map_container
        })
    else
        log.warn("mapTile", "下载地图瓦片失败")
    end
end

--[[
获取地址信息

@local
@function get_address
@param lat {number} 纬度
@param lng {number} 经度
@return nil
@usage
-- 根据经纬度获取地址信息
]]
local function get_address(lat, lng)
    if win_id == nil then return end
    
    local url = string.format("http://iot.openluat.com/api/open/device_get_address?imei=%s&muid=%s&lat=%f&lon=%f", 
        mobile.imei(), mobile.muid(), lat, lng)
    
    local code, headers, body = http.request("GET", url, nil, nil, {timeout=10000}).wait()
    
    -- 再次检查窗口是否还存在（HTTP请求可能耗时较长）
    if win_id == nil then return end
    
    if code == 200 then
        local podata = json.decode(body)
        if podata.address then
            address_label:set_text(podata.address)
        else
            address_label:set_text("位置:获取地址失败")
        end
    else
        address_label:set_text("位置:网络请求失败")
    end
end

--[[
切换地图显示

@local
@function toggle_map
@return nil
@usage
-- 地图按钮点击事件
]]
local function toggle_map()
    log.info("GPS_WIN", "toggle_map called, win_id:", win_id)
    
    if win_id == nil then return end
    log.info("GPS_WIN", "toggle_map executed, is_map_visible:", is_map_visible)
    
    if is_map_visible then
        -- 点击取消：销毁地图，右侧内容保持不变
        log.info("GPS_WIN", "Destroying map")
        
        if map_img then 
            map_img:destroy() 
            map_img = nil 
        end
        if map_container then 
            map_container:destroy() 
            map_container = nil 
        end
        
        if map_toggle_label then 
            map_toggle_label:set_text("地图")
            log.info("GPS_WIN", "Map toggle label set to: 地图")
        end
        is_map_visible = false
        log.info("GPS_WIN", "is_map_visible set to: false")
    else
        -- 点击地图：创建地图覆盖在右侧内容上方
        log.info("GPS_WIN", "Creating map overlay")
        
        -- 创建地图容器
        map_container = airui.container({ parent = right_panel, x=0, y=0, w=250, h=260, color=0x1e293b, radius = 8 })
        -- 加载地图
        sys.taskInit(load_map)
        
        if map_toggle_label then 
            map_toggle_label:set_text("取消")
            log.info("GPS_WIN", "Map toggle label set to: 取消")
        end
        is_map_visible = true
        log.info("GPS_WIN", "is_map_visible set to: true")
    end
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建GPS定位页面的UI
]]
local function create_ui()
    -- 更新屏幕尺寸
    update_screen_size()
    
    -- 获取密度比例
    local density = get_density_scale()
    
    -- 主容器
    main_container = airui.container({ 
        parent = airui.screen, 
        x=0, 
        y=0, 
        w=screen_w, 
        h=screen_h, 
        color=0x0f172a 
    })

    -- 顶部返回栏
    local header_h = math.floor(40 * density)
    local header = airui.container({ 
        parent = main_container, 
        x=0, 
        y=0, 
        w=screen_w, 
        h=header_h, 
        color=0x1e293b 
    })
    
    -- 返回按钮
    local back_btn = airui.container({ 
        parent = header, 
        x = math.floor(10 * density), 
        y = math.floor((header_h - 30 * density) / 2), 
        w = math.floor(70 * density), 
        h = math.floor(30 * density), 
        color = 0x38bdf8, 
        radius = math.floor(5 * density),
        on_click = function() 
            log.info("GPS_WIN", "Return button clicked, win_id:", win_id)
            if win_id then 
                log.info("GPS_WIN", "Closing window with win_id:", win_id)
                exwin.close(win_id) 
            else
                log.info("GPS_WIN", "win_id is nil")
            end
        end
    })
    airui.label({ 
        parent = back_btn, 
        x = math.floor(10 * density), 
        y = math.floor(5 * density), 
        w = math.floor(50 * density), 
        h = math.floor(20 * density), 
        text = "返回", 
        font_size = math.floor(16 * density), 
        color = 0xfefefe, 
        align = airui.TEXT_ALIGN_CENTER 
    })

    -- 标题
    airui.label({ 
        parent = header, 
        x = math.floor(90 * density), 
        y = math.floor(4 * density), 
        w = math.floor(270 * density), 
        h = math.floor(32 * density), 
        align = airui.TEXT_ALIGN_CENTER, 
        text="GNSS定位", 
        font_size=math.floor(24 * density), 
        color=0x38bdf8 
    })

    -- 地图切换按钮
    map_toggle_btn = airui.container({ 
        parent = header, 
        x = screen_w - math.floor(110 * density), 
        y = math.floor((header_h - 30 * density) / 2), 
        w = math.floor(100 * density), 
        h = math.floor(30 * density), 
        color = 0x38bdf8, 
        radius = math.floor(5 * density),
        on_click = toggle_map
    })
    map_toggle_label = airui.label({ 
        parent = map_toggle_btn, 
        x = math.floor(10 * density), 
        y = math.floor(5 * density), 
        w = math.floor(80 * density), 
        h = math.floor(20 * density), 
        text = "地图", 
        font_size = math.floor(16 * density), 
        color = 0xfefefe, 
        align = airui.TEXT_ALIGN_CENTER 
    })

    -- 内容区域
    local content_h = screen_h - header_h
    content = airui.container({ 
        parent = main_container, 
        x=0, 
        y=header_h, 
        w=screen_w, 
        h=content_h, 
        color=0x1e293b 
    })

    -- 左侧信息面板
    local info_panel_w = math.floor(200 * density)
    local info_panel_h = content_h - math.floor(20 * density)
    local info_panel = airui.container({ 
        parent = content, 
        x=math.floor(10 * density), 
        y=math.floor(10 * density), 
        w=info_panel_w, 
        h=info_panel_h, 
        color=0x0f172a, 
        radius = math.floor(8 * density) 
    })

    -- 位置信息
    local position_section = airui.container({ 
        parent = info_panel, 
        x=math.floor(10 * density), 
        y=math.floor(10 * density), 
        w=info_panel_w - math.floor(20 * density), 
        h=math.floor(120 * density), 
        color=0x1e293b, 
        radius = math.floor(6 * density) 
    })
    
    airui.label({ 
        parent = position_section, 
        x=math.floor(10 * density), 
        y=math.floor(5 * density), 
        w=math.floor(60 * density), 
        h=math.floor(20 * density), 
        text="纬度:", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    latitude_label = airui.label({ 
        parent = position_section, 
        x=math.floor(80 * density), 
        y=math.floor(5 * density), 
        w=math.floor(100 * density), 
        h=math.floor(20 * density), 
        text="--", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0, 
        align = airui.TEXT_ALIGN_RIGHT 
    })
    
    airui.label({ 
        parent = position_section, 
        x=math.floor(10 * density), 
        y=math.floor(30 * density), 
        w=math.floor(60 * density), 
        h=math.floor(20 * density), 
        text="经度:", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    longitude_label = airui.label({ 
        parent = position_section, 
        x=math.floor(80 * density), 
        y=math.floor(30 * density), 
        w=math.floor(100 * density), 
        h=math.floor(20 * density), 
        text="--", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0, 
        align = airui.TEXT_ALIGN_RIGHT 
    })
    
    airui.label({ 
        parent = position_section, 
        x=math.floor(10 * density), 
        y=math.floor(55 * density), 
        w=math.floor(80 * density), 
        h=math.floor(20 * density), 
        text="位置:", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    address_label = airui.label({ 
        parent = position_section, 
        x=math.floor(10 * density), 
        y=math.floor(75 * density), 
        w=info_panel_w - math.floor(40 * density), 
        h=math.floor(35 * density), 
        text="点击按钮获取", 
        font_size=math.floor(12 * density), 
        color=0xe2e8f0 
    })

    -- 按钮区域
    local btn_container = airui.container({ 
        parent = info_panel, 
        x=math.floor(10 * density), 
        y=math.floor(140 * density), 
        w=info_panel_w - math.floor(20 * density), 
        h=math.floor(110 * density), 
        color=0x1e293b, 
        radius = math.floor(6 * density) 
    })
    
    -- 第一行按钮
    locate_btn = airui.button({ 
        parent = btn_container, 
        x=math.floor(10 * density), 
        y=math.floor(10 * density), 
        w=math.floor(75 * density), 
        h=math.floor(35 * density), 
        text="获取位置", 
        font_size=math.floor(14 * density), 
        color=0xfefefe, 
        background_color=0x38bdf8,
        radius = math.floor(5 * density),
        on_click = function(self)
            if not exwin.is_active(win_id) then return end
            
            sys.taskInit(get_address, current_lat, current_lng)
        end
    })
    
    -- 立即关闭按钮
    stop_btn = airui.button({ 
        parent = btn_container, 
        x=math.floor(95 * density), 
        y=math.floor(10 * density), 
        w=math.floor(75 * density), 
        h=math.floor(35 * density), 
        text=is_gps_enabled and "立即关闭" or "立即开启", 
        font_size=math.floor(14 * density), 
        color=0xfefefe, 
        background_color=0x64748b,
        radius = math.floor(5 * density),
        on_click = function()
            log.info("GPS Button", "Button clicked, is_gps_enabled:", is_gps_enabled)
            
            if is_gps_enabled then
                -- 关闭GPS应用
                log.info("GPS Button", "Closing GPS application")
                exgnss.close_all()
                is_gps_enabled = false
                log.info("GPS Button", "GPS closed, is_gps_enabled:", is_gps_enabled)
                
                -- 停止定位耗时计时器
                if duration_timer then
                    sys.timerStop(duration_timer)
                    duration_timer = nil
                end
                
                local set_text_result = pcall(function() stop_btn:set_text("立即开启") end)
                log.info("GPS Button", "set_text result:", set_text_result)
                log.info("GPS Button", "Button text set to: 立即开启")
                latitude_label:set_text("--")
                longitude_label:set_text("--")
                address_label:set_text("点击按钮获取")
                update_satellite_status()
            else
                -- 开启GPS应用
                -- 重置定位耗时计时器和标志
                location_duration = 0
                is_first_fix = false
                if fix_time_label then
                    fix_time_label:set_text("0s")
                end
                    exgnss.open(exgnss.DEFAULT, {
                        tag = "gps_start",
                        cb = location_callback
                    })
                is_gps_enabled = true
                
                -- 启动定位耗时计时器
                duration_timer = sys.timerLoopStart(update_location_duration, 1000)
                
                local set_text_result = pcall(function() stop_btn:set_text("立即关闭") end)
                log.info("GPS Button", "set_text result:", set_text_result)
                log.info("GPS Button", "Button text set to: 立即关闭")
            end
        end
    })
    
    -- 第二行按钮
    config_btn = airui.button({ 
        parent = btn_container, 
        x=math.floor(10 * density), 
        y=math.floor(55 * density), 
        w=math.floor(75 * density), 
        h=math.floor(35 * density), 
        text="配置", 
        font_size=math.floor(14 * density), 
        color=0xfefefe, 
        background_color=0x64748b,
        radius = math.floor(5 * density),
        on_click = function()
            -- 打开配置页面
            sys.publish("OPEN_CONFIG_WIN")
        end
    })
    
    satellite_btn = airui.button({ 
        parent = btn_container, 
        x=math.floor(95 * density), 
        y=math.floor(55 * density), 
        w=math.floor(75 * density), 
        h=math.floor(35 * density), 
        text="卫星信息", 
        font_size=math.floor(14 * density), 
        color=0xfefefe, 
        background_color=0x38bdf8,
        radius = math.floor(5 * density),
        on_click = function()
            -- 打开卫星信息页面
            sys.publish("OPEN_SATELLITE_WIN")
        end
    })

    -- 右侧面板
    local right_panel_x = info_panel_w + math.floor(20 * density)
    local right_panel_w = screen_w - right_panel_x - math.floor(10 * density)
    local right_panel_h = info_panel_h
    right_panel = airui.container({ 
        parent = content, 
        x=right_panel_x, 
        y=math.floor(10 * density), 
        w=right_panel_w, 
        h=right_panel_h, 
        color=0x0f172a, 
        radius = math.floor(8 * density) 
    })

    -- 创建右侧四条内容
    -- 可见卫星
    visible_satellite_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(10 * density), 
        y=math.floor(10 * density), 
        w=math.floor(120 * density), 
        h=math.floor(25 * density), 
        text="可见卫星", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    satellite_count_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(140 * density), 
        y=math.floor(10 * density), 
        w=math.floor(100 * density), 
        h=math.floor(25 * density), 
        text="0", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0 
    })
    
    -- 速度
    speed_info_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(10 * density), 
        y=math.floor(45 * density), 
        w=math.floor(120 * density), 
        h=math.floor(25 * density), 
        text="速度", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    speed_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(140 * density), 
        y=math.floor(45 * density), 
        w=math.floor(100 * density), 
        h=math.floor(25 * density), 
        text="0 km/h", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0 
    })
    
    -- 是否定位成功
    fix_status_info_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(10 * density), 
        y=math.floor(80 * density), 
        w=math.floor(120 * density), 
        h=math.floor(25 * density), 
        text="是否定位成功", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    fix_status_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(140 * density), 
        y=math.floor(80 * density), 
        w=math.floor(100 * density), 
        h=math.floor(25 * density), 
        text="否", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0 
    })
    
    -- 本次定位成功耗时
    fix_time_info_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(10 * density), 
        y=math.floor(115 * density), 
        w=math.floor(140 * density), 
        h=math.floor(25 * density), 
        text="本次定位成功耗时", 
        font_size=math.floor(14 * density), 
        color=0x94a3b8 
    })
    fix_time_label = airui.label({ 
        parent = right_panel, 
        x=math.floor(150 * density), 
        y=math.floor(115 * density), 
        w=math.floor(90 * density), 
        h=math.floor(25 * density), 
        text="0s", 
        font_size=math.floor(14 * density), 
        color=0xe2e8f0 
    })
    
    -- 更新卫星状态
    -- update_satellite_status()
    
    -- 调试信息
    log.info("GPS_WIN", "右侧内容已创建")
end

--[[
GNSS定位成功回调函数

@local
@function location_callback
@param tag string 应用标签
@return nil
@usage
-- 定位成功时调用，更新定位信息
]]
local function location_callback(tag)
    log.info("GPS_WIN", "定位成功回调：" .. tag)
    
    -- 停止定位耗时计时器
    if duration_timer then
        sys.timerStop(duration_timer)
        duration_timer = nil
    end
    if win_id == nil then return end
    -- 获取定位数据
    if exgnss.is_fix() then
        local rmc = exgnss.rmc(2) -- 使用高德地图坐标系
        current_lat = rmc.lat
        current_lng = rmc.lng
        update_location(current_lat, current_lng)
        sys.taskInit(get_address, current_lat, current_lng)
        update_satellite_status()
        
        -- 更新是否定位成功
        if fix_status_label then
            fix_status_label:set_text("是")
        end
        
        log.info("GPS_WIN", "定位成功，耗时：" .. location_duration .. "秒")
    else
        log.info("GPS_WIN", "定位失败")
        -- 更新是否定位成功
        if fix_status_label then
            fix_status_label:set_text("否")
        end
    end
    
    -- 定位任务完成
    -- is_gps_enabled = false
end

--[[
定时定位任务

@local
@function timed_location_task
@return nil
@usage
-- 每5分钟执行一次定位任务
]]
local function timed_location_task()
    if exwin.is_active(win_id) and not is_gps_enabled then
        -- 重置定位耗时计时器和标志
        location_duration = 0
        is_first_fix = false
        if fix_time_label then
            fix_time_label:set_text("0s")
        end
        
        -- 开启定位
        exgnss.open(exgnss.TIMERORSUC, {
            tag = "gps_app",
            val = 30,
            cb = location_callback
        })
        
        is_gps_enabled = true
        
        -- 启动定位耗时计时器
        duration_timer = sys.timerStart(update_location_duration, 1000)
    end
end

--有效震动判断
local function ind()
    log.info("int", gpio.get(intPin))
    --接收数据如果大于5就删掉第一个
    if #ticktable>=5 then
        log.info("table.remove",table.remove(ticktable,1))
    end
    --存入新的tick值
    if not ipready then
        log.info("ipready",ipready)
        table.insert(ticktable,num)
    else
        log.info("ipready2",ipready)
        table.insert(ticktable,os.time())
    end
    log.info("tick",os.time(),(ticktable[5]-ticktable[1]<10),ticktable[5]>0)
    log.info("tick2",ticktable[1],ticktable[2],ticktable[3],ticktable[4],ticktable[5])
    --表长度为5且，第5次中断时间间隔减去第一次间隔小于10s，且第5次值为有效值
    if #ticktable>=5 and (ticktable[5]-ticktable[1]<10 and ticktable[1]>0) then
        log.info("vib", "xxx")
        --是否要去触发有效震动逻辑
        if eff==false then
            sys.publish("EFFECTIVE_VIBRATION")
        end
    end

end

-- 设置30s分钟之后再判断是否有效震动函数
local function num_cb()
    eff=false
end

local function eff_vib()
    sys.publish("SEND_DATA_REQ", "gnssnormal", "触发震动，开启GNSS") --发送数据到服务器
    --触发之后eff设置为true，30分钟之后再触发有效震动
    eff=true
    --30分钟之后再触发有效震动
    sys.timerStart(num_cb,config.nextTriggerTime*1000)
    --判断gnss是否处于打开状态
    if config.autoClose then
            -- 自动开启GNSS
            exgnss.open(exgnss.TIMERORSUC, {
            tag = "gps_app",
            val = config.gnssOnTime, -- 定时时间（秒）
            cb = location_callback
        })
    else
        exgnss.open(exgnss.TIMER, {
            tag = "gps_app",
            val = config.gnssOnTime, -- 定时时间（秒）
            cb = location_callback
        })
    end
    if exgnss.is_fix() then
        log.info("已经定位成功")
        location_callback()
    else
        duration_timer = sys.timerLoopStart(update_location_duration, 1000)
    end
end

sys.subscribe("EFFECTIVE_VIBRATION",eff_vib)


local function exvib_fnc()
    -- 初始化外设分组开关状态
    exmux.setup(HARDWARE_ENV)
    -- 打开外设分组
    exmux.open("i2c0")
    -- 1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
    -- 2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
    -- 3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；
    --打开震动检测功能
    exvib.open(1)
    --设置gpio防抖100ms
    gpio.debounce(intPin, 100)
    --设置gpio中断触发方式wakeup2唤醒脚默认为下降沿触发
    gpio.setup(intPin, ind,nil,gpio.FALLING)
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    sys.timerStop(tickid)
    sys.wait(1000)
    ipready=true
    if ticktable[1]~=0 then
        log.info("os.time()-((num+1)-ticktable[1])",os.time()-((num+1)-ticktable[1]))
        ticktable[1]=os.time()-((num+1)-ticktable[1])
    end
    if ticktable[2]~=0 then
        log.info("os.time()-((num+1)-ticktable[2])",os.time()-((num+1)-ticktable[2]))
        ticktable[2]=os.time()-((num+1)-ticktable[2])
    end
    if ticktable[3]~=0 then
        log.info("os.time()-((num+1)-ticktable[3])",os.time()-((num+1)-ticktable[3]))
        ticktable[3]=os.time()-((num+1)-ticktable[3])
    end
    if ticktable[4]~=0 then
        log.info("os.time()-((num+1)-ticktable[4])",os.time()-((num+1)-ticktable[4]))
        ticktable[4]=os.time()-((num+1)-ticktable[4])
    end
    if ticktable[5]~=0 then
        log.info("os.time()-((num+1)-ticktable[5])",os.time()-((num+1)-ticktable[5]))
        ticktable[5]=os.time()-((num+1)-ticktable[5])
    end
end

--[[
初始化GNSS模块

@local
@function init_gnss
@return nil
@usage
-- 初始化GNSS，根据配置启动相应的定位模式
]]
local function init_gnss()
    config = config_win.get_config()
    log.info("CONFIGNEW", config)
    
    -- 根据配置页面的设置初始化exgnss
    if config.mode == 'always' then
        log.info("gps_win", "always mode")
        -- 常开启模式：直接开启GNSS
        exgnss.open(exgnss.DEFAULT, {
            tag = "gps_app",
            cb = location_callback
        })
        is_gps_enabled = true
        -- 设置按钮文本
        if stop_btn then
            stop_btn:set_text("立即关闭")
        end
        if exgnss.is_fix() then
            log.info("已经定位成功")
            location_callback()
        else
            duration_timer = sys.timerLoopStart(update_location_duration, 1000)
        end
    elseif config.mode == 'timer' then
        log.info("gps_win", "timer mode")
        -- 定时开启模式：设置定时定位
        if config.autoClose then
            -- 自动开启GNSS
                exgnss.open(exgnss.TIMERORSUC, {
                tag = "gps_app",
                val = config.gnssDuration, -- 定时时间（秒）
                cb = location_callback
            })
            if not sys.timerIsActive(gnss_timer) then
                gnss_timer =  sys.timerLoopStart(function()
                    -- 重置定位耗时计时器和标志
                    location_duration = 0
                    is_first_fix = false
                    exgnss.open(exgnss.TIMERORSUC, {
                    tag = "gps_app",
                    val = config.gnssDuration, -- 定时时间（秒）
                    cb = location_callback
                })
                 duration_timer = sys.timerLoopStart(update_location_duration, 1000)
                end,(tonumber(config.timerStart)*1000))
            end
        else
            exgnss.open(exgnss.TIMER, {
                tag = "gps_app",
                val = config.gnssDuration, -- 定时时间（秒）
                cb = location_callback
            })
            if not sys.timerIsActive(gnss_timer) then
                gnss_timer =  sys.timerLoopStart(function()
                    -- 重置定位耗时计时器和标志
                    location_duration = 0
                    is_first_fix = false
                    exgnss.open(exgnss.TIMER, {
                    tag = "gps_app",
                    val = config.gnssDuration, -- 定时时间（秒）
                    cb = location_callback
                    })
                    duration_timer = sys.timerLoopStart(update_location_duration, 1000)
                end,(tonumber(config.timerStart)*1000))
            end
        end
        is_gps_enabled = true
        -- 设置按钮文本
        if stop_btn then
            stop_btn:set_text("立即关闭")
        end
        if exgnss.is_fix() then
            log.info("已经定位成功")
            location_callback()
        else
            duration_timer = sys.timerLoopStart(update_location_duration, 1000)
        end
    elseif config.mode == 'shake' then
        log.info("gps_win", "shake mode")
        -- 震动触发开启模式：设置震动触发
        sys.taskInit(exvib_fnc)
        is_gps_enabled = true
        -- 设置按钮文本
        if stop_btn then
            stop_btn:set_text("立即关闭")
        end
    else
        -- 其他模式：默认关闭GNSS
        is_gps_enabled = false
        -- 设置按钮文本
        if stop_btn then
            stop_btn:set_text("立即开启")
        end
    end
    
    -- 订阅GNSS状态变化消息
    sys.subscribe("GNSS_STATE", function(event, ticks)
        -- 定位成功后更新经纬度显示
        log.info("exgnss", "state", event)
        if event=="FIXED" then
            if win_id == nil then return end
            -- 停止定位耗时计时器
            if duration_timer then
                sys.timerStop(duration_timer)
                duration_timer = nil
            end
            local rmc = exgnss.rmc(2) -- 使用高德地图坐标系
            current_lat = rmc.lat
            current_lng = rmc.lng
            update_location(current_lat, current_lng)
            sys.taskInit(get_address, current_lat, current_lng)
            update_satellite_status()
        end
        
    end)
    
    -- 定期更新卫星状态
    if not sys.timerIsActive(gps_timer) then
        gps_timer = sys.timerLoopStart(function()
            if win_id == nil then return end
            if exwin.is_active(win_id) then
                update_satellite_status()
                -- 定期检查定位状态，防止消息遗漏
                if exgnss.is_fix() then
                    local rmc = exgnss.rmc(2) -- 使用高德地图坐标系
                    if rmc and rmc.lat and rmc.lng then
                        current_lat = rmc.lat
                        current_lng = rmc.lng
                        update_location(current_lat, current_lng)
                    end
                end
            end
        end, 5000)
    end
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI
]]
local function on_create()
    create_ui()
    init_gnss()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器
]]
local function on_destroy()    
    log.info("GPS_WIN", "Window destroy callback")
    
    -- 停止所有定时器
    if duration_timer then
        sys.timerStop(duration_timer)
        duration_timer = nil
    end
    if gps_timer then
        sys.timerStop(gps_timer)
        gps_timer = nil
    end
    if gnss_timer then
        sys.timerStop(gnss_timer)
        gnss_timer = nil
    end
    
    -- 关闭GNSS
    exgnss.close_all()
    
    -- 停止震动检测定时器
    if tickid and sys.timerIsActive(tickid) then
        sys.timerStop(tickid)
        tickid = nil
    end
    
    -- 销毁主容器
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 获得焦点时的处理
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 失去焦点时的处理
end

-- 订阅打开GPS页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_GPS_WIN", open_handler)
