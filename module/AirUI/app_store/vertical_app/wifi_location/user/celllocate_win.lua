--[[
@module  celllocate_win
@summary 基站定位页面
@version 1.0
@date    2026.03.27
@author  您的名字
@usage
本模块为基站定位页面，提供基站定位功能和地图显示。
点击主菜单的相应按钮打开此页面。
]]

local win_id = nil
local main_container, content
local map_toggle_btn, map_toggle_label
local longitude_label, latitude_label, address_label
local locate_btn
local map_placeholder, map_container, map_img
local is_map_showing = false
local right_panel
local current_lat = 0
local current_lng = 0

-- 引入配置模块
local cell_config = require "cell_config_win"
local airlbs = require "airlbs"
local mapTile = require "mapTile"

local function destroy_map()
    if map_img then map_img:destroy(); map_img = nil end
    if map_container then map_container:destroy(); map_container = nil end
end

--[[
加载地图

@local
@function load_map
@return nil
@usage
-- 内部调用，加载地图瓦片
]]
local function get_address(lat, lng)
    if win_id == nil then return end
    local mac1 = netdrv.mac(socket.LWIP_STA)
    local mac = "M01" .. mac1 
    local url = string.format("http://iot.openluat.com/api/open/device_get_address?imei=%s&muid=%s&lat=%f&lon=%f", 
        mac, mcu.muid(), lat, lng)
    
    local code, headers, body = http.request("GET", url, nil, nil, {timeout=10000}).wait()
    
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

local function load_map()
    if win_id == nil then return end
    
    if current_lat == 0 or current_lng == 0 then
        address_label:set_text("位置:还未定位成功")
        return
    end
    
    -- 检查网络连接
    if not socket.adapter(socket.dft()) then
        log.warn("http_app_task_func", "wait IP_READY", socket.dft())
        -- 不使用 while 循环，避免 UI 卡顿
        sys.waitUntil("IP_READY", 5000)
        -- 再次检查网络连接
        if not socket.adapter(socket.dft()) then
            log.warn("mapTile", "网络连接失败")
            return
        end
    end
    
    -- 生成地图瓦片URL
    local url, x, y = mapTile.generate_gaode_url(current_lng, current_lat, 16)
    log.info("mapTile", url, x, y)
    
    -- 下载地图瓦片
    local code, headers, body_size = http.request("GET", url, nil, nil, {dst="/1.png", timeout=10000}).wait()
    log.info("http_app_get_file2", code)
    
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
            w = 440,
            h = 300,
            pivot = {x=1, y=1},
            zoom = 256,
            opacity = 255,
            parent = right_panel
        })
    else
        log.warn("mapTile", "下载地图瓦片失败")
    end
end

--[[
创建地图

@local
@function create_map
@return nil
@usage
-- 内部调用，创建地图视图
]]
local function create_map()
    -- 直接在 right_panel 上显示地图，不创建额外容器
    sys.taskInit(load_map)
end

--[[
创建右侧内容

@local
@function create_right_content
@return nil
@usage
-- 内部调用，创建右侧面板内容
]]
local location_type_info_label, location_type_label

local function create_right_content()
    -- 地图显示区域
    map_placeholder = airui.label({ parent = right_panel, x=0, y=320, w=440, h=40, text = "地图显示区域", font_size = 18, color = 0x94a3b8, align = airui.TEXT_ALIGN_CENTER })
end

local function destroy_right_content()
    if location_type_info_label then location_type_info_label:destroy(); location_type_info_label = nil end
    if location_type_label then location_type_label:destroy(); location_type_label = nil end
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、信息面板和地图视图
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0x1e293b })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=60, color=0x1e293b })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = header, x = 20, y = 10, w = 100, h = 40, color = 0x38bdf8, radius = 8,
        on_click = function() 
            log.info("CELLLOCATE_WIN", "Return button clicked")
            if win_id then 
                exwin.close(win_id) 
            end 
        end
    })
    airui.label({ parent = back_btn, x = 20, y = 10, w = 60, h = 20, text = "返回", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 标题
    airui.label({ parent = header, x = 140, y = 10, w = 200, h = 40, align = airui.TEXT_ALIGN_CENTER, text="WIFI定位", font_size=28, color=0x38bdf8 })

    -- 地图切换按钮
    map_toggle_btn = airui.container({ parent = header, x = 360, y = 10, w = 100, h = 40, color = 0x38bdf8, radius = 8,
        on_click = function()
            -- 延迟执行，确保所有对象都已初始化
            sys.timerStart(function()
                if win_id == nil then return end
                log.info("CELLLOCATE_WIN", "Map toggle clicked, is showing:", is_map_showing)
                if is_map_showing then
                    -- 隐藏地图，显示右侧面板
                    log.info("CELLLOCATE_WIN", "Hiding map, showing right content")
                    destroy_map()
                    create_right_content()
                    if map_toggle_label then 
                        map_toggle_label:set_text("地图")
                        log.info("CELLLOCATE_WIN", "Map toggle label set to: 地图")
                    end
                    is_map_showing = false
                    log.info("CELLLOCATE_WIN", "is_map_showing set to: false")
                else
                    -- 显示地图，隐藏右侧面板
                    log.info("CELLLOCATE_WIN", "Showing map, hiding right content")
                    destroy_right_content()
                    create_map()
                    if map_toggle_label then 
                        map_toggle_label:set_text("取消")
                        log.info("CELLLOCATE_WIN", "Map toggle label set to: 取消")
                    end
                    is_map_showing = true
                    log.info("CELLLOCATE_WIN", "is_map_showing set to: true")
                end
            end, 100)
        end
    })
    map_toggle_label = airui.label({ parent = map_toggle_btn, x = 10, y = 10, w = 80, h = 20, text = "地图", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x=0, y=60, w=480, h=740, color=0x1e293b })

    -- 上方信息面板 - 增大尺寸
    local info_panel = airui.container({ parent = content, x=20, y=20, w=440, h=200, color=0x0f172a, radius = 8 })

    -- 位置信息 - 三行显示
    local position_section = airui.container({ parent = info_panel, x=20, y=20, w=400, h=150, color=0x1e293b, radius = 6 })
    
    -- 经度
    airui.label({ parent = position_section, x=20, y=5, w=60, h=30, text="经度:", font_size=18, color=0x94a3b8 })
    longitude_label = airui.label({ parent = position_section, x=80, y=5, w=300, h=30, text="--", font_size=18, color=0xe2e8f0, align = airui.TEXT_ALIGN_RIGHT })
    
    -- 纬度
    airui.label({ parent = position_section, x=20, y=45, w=60, h=30, text="纬度:", font_size=18, color=0x94a3b8 })
    latitude_label = airui.label({ parent = position_section, x=80, y=45, w=300, h=30, text="--", font_size=18, color=0xe2e8f0, align = airui.TEXT_ALIGN_RIGHT })
    
    -- 位置
    airui.label({ parent = position_section, x=20, y=85, w=60, h=30, text="位置:", font_size=18, color=0x94a3b8 })
    address_label = airui.label({ parent = position_section, x=80, y=85, w=300, h=60, text="点击按钮获取", font_size=16, color=0xe2e8f0 })

    -- 下方地图面板 - 下移位置
    right_panel = airui.container({ parent = content, x=20, y=240, w=440, h=360, color=0x0f172a, radius = 8 })

    -- 创建右侧内容
    create_right_content()
    
    -- 按钮区域 - 放到地图下面，下移位置
    local btn_container = airui.container({ parent = content, x=20, y=630, w=440, h=60, color=0x0f172a, radius = 8 })
    
    -- 基站定位按钮
    locate_btn = airui.button({ 
        parent = btn_container, 
        x=10, 
        y=10, 
        w=200, 
        h=40, 
        text="WIFI定位", 
        font_size=18, 
        color=0xfefefe, 
        background_color=0x38bdf8,
        radius = 8,
        on_click = function()
            log.info("CELLLOCATE_WIN", "Locate button clicked")
            
            -- 设置按钮状态
            locate_btn:set_text("定位中...")
            
            -- 启动基站定位任务
            sys.taskInit(function()
                log.info("CELLLOCATE_WIN", "Starting location task")
                
                -- 获取配置
                local config = cell_config.get_config()
                local has_config = config and config.key_id and config.key and config.key_id ~= "" and config.key ~= ""
                
                local lat, lng, address
                
                if has_config then
                    -- 使用 airlbs 定位（高精度，收费）
                    log.info("CELLLOCATE_WIN", "Using airlbs for location")
                    
                    -- 确保网络就绪
                    while not socket.adapter(socket.dft()) do
                        sys.waitUntil("IP_READY", 1000)
                    end

                    socket.sntp() --进行NTP授时
                    sys.waitUntil("NTP_UPDATE", 1000)

                     -- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
                    local wifi_info = nil
                    if wlan then
                        -- wlan.init()--初始化wlan
                        wlan.scan()--扫描wifi
                        local res,data=sys.waitUntil("WIFI_DONE", 10000)--等待扫描完成
                        wifi_info = data
                        -- wifi_info = wlan.scanResult()--获取扫描结果
                        log.info("scan", "wifi_info", #wifi_info)--打印扫描结果
                    end
                    log.info("CONFIG",config.key_id,config.key)
                    -- 调用 airlbs 定位
                        local result, data = airlbs.request({
                            project_id = config.key_id,-- 项目ID
                            project_key = config.key,-- 项目密钥
                            wifi_info = wifi_info,-- wifi信息
                            timeout = 10000,-- 实际的超时时间(单位：ms)
                        })
                    
                    if result  then
                        log.info("CELLLOCATE_WIN", "Airlbs location successful", data.lat, data.lng)
                        -- 确保lat和lng是数字类型
                        lat = tonumber(data.lat) or 0
                        lng = tonumber(data.lng) or 0
                        address = "基站定位"
                    else
                        log.error("CELLLOCATE_WIN", "Airlbs location failed", json.encode(data or {}))
                        address_label:set_text("定位失败，请检查配置")
                        locate_btn:set_text("基站定位")
                        return
                    end
                else
                    -- 未配置定位参数
                    log.error("CELLLOCATE_WIN", "No location configuration")
                    address_label:set_text("未配置定位参数")
                    locate_btn:set_text("基站定位")
                    return
                end
                
                -- 更新位置信息
                longitude_label:set_text(string.format("%.6f", lng))
                latitude_label:set_text(string.format("%.6f", lat))
                -- 调用获取地址信息的函数
                sys.taskInit(get_address, lat, lng)
                
                -- 更新定位类型标签
                if location_type_label then
                    location_type_label:set_text("基站定位")
                end
                
                -- 更新当前经纬度
                current_lng = lng
                current_lat = lat
                
                -- 恢复按钮状态
                locate_btn:set_text("重新定位")
            end)
        end
    })
    
    -- 配置按钮
    local config_btn = airui.button({ 
        parent = btn_container, 
        x=220, 
        y=10, 
        w=210, 
        h=40, 
        text="配置", 
        font_size=18, 
        color=0xfefefe, 
        background_color=0x64748b,
        radius = 8,
        on_click = function()
            -- 打开配置页面
            sys.publish("OPEN_CELL_CONFIG_WIN")
        end
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并初始化变量
]]
local function on_create()
    log.info("CELLLOCATE_WIN", "on_create function called")
    create_ui()
    log.info("CELLLOCATE_WIN", "UI created successfully")
    
    -- 初始化变量
    is_map_showing = false
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器并释放资源
]]
local function on_destroy()
    log.info("CELLLOCATE_WIN", "on_destroy function called")
    
    -- 销毁地图相关资源
    if map_img then 
        map_img:destroy() 
        map_img = nil 
    end
    if map_container then 
        map_container:destroy() 
        map_container = nil 
    end
    
    -- 销毁主容器
    if main_container then 
        main_container:destroy() 
        main_container = nil 
    end
    
    -- 重置状态变量
    win_id = nil
    is_map_showing = false
    current_lat = 0
    current_lng = 0
    
    log.info("CELLLOCATE_WIN", "on_destroy completed")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("CELLLOCATE_WIN", "on_get_focus function called")
    -- 获得焦点时的处理
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("CELLLOCATE_WIN", "on_lose_focus function called")
    -- 失去焦点时的处理
end

-- 订阅打开基站定位页面的消息
local function open_handler()
    log.info("CELLLOCATE_WIN", "OPEN_CELLLOCATE_WIN event received")
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    log.info("CELLLOCATE_WIN", "Window created with id:", win_id)
end
sys.subscribe("OPEN_CELLLOCATE_WIN", open_handler)


