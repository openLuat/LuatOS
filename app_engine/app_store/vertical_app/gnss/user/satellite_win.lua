--[[
@module  satellite_win
@summary 卫星信息页面模块
@version 1.0
@date    2026.05.21
@author  合宙技术
@usage
本模块为卫星信息页面，显示卫星的详细信息。
订阅"OPEN_SATELLITE_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local satellite_table
local exgnss = require("exgnss")

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

--[[
加载卫星数据
@local
@function load_satellite_data
@return nil
@usage
-- 加载并显示卫星数据
]]
local function load_satellite_data()
    if not exwin.is_active(win_id) then return end
    
    log.info("Satellite Win", "Loading satellite data...")
    
    local gsv = exgnss.gsv()
    log.info("Satellite Win", "exgnss.gsv() result:", json.encode(gsv))
    
    satellite_table:set_cell_text(0, 0, "编号")
    satellite_table:set_cell_text(0, 1, "类型")
    satellite_table:set_cell_text(0, 2, "信噪比")
    satellite_table:set_cell_text(0, 3, "方位角")
    satellite_table:set_cell_text(0, 4, "仰角")
    
    local function get_satellite_type(tp)
        local type_map = {[0] = "GPS", [1] = "BD", [2] = "GLON", [3] = "GAL", [4] = "QZSS"}
        return type_map[tp] or "Unknown"
    end
    
    if gsv and gsv.total_sats and gsv.total_sats > 0 and gsv.sats then
        log.info("Satellite Win", "Found " .. gsv.total_sats .. " satellites")
        for i, sat in ipairs(gsv.sats) do
            local row_index = i
            if row_index < satellite_table.rows then
                satellite_table:set_cell_text(row_index, 0, tostring(sat.nr))
                satellite_table:set_cell_text(row_index, 1, get_satellite_type(sat.tp))
                satellite_table:set_cell_text(row_index, 2, tostring(sat.snr) .. "dBm")
                satellite_table:set_cell_text(row_index, 3, tostring(sat.azimuth) .. "°")
                satellite_table:set_cell_text(row_index, 4, tostring(sat.elevation) .. "°")
                log.info("Satellite Win", "Added satellite to row " .. row_index)
            else
                log.warn("Satellite Win", "Not enough rows to display satellite " .. i)
            end
        end
    else
        log.warn("Satellite Win", "No satellite data found: " .. json.encode(gsv))
    end
end

--[[
创建窗口UI
@local
@function create_ui
@return nil
@usage
-- 内部调用，创建卫星信息页面的UI
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
        on_click = function() if win_id then exwin.close(win_id) end end
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
        w = math.floor(280 * density), 
        h = math.floor(32 * density), 
        align = airui.TEXT_ALIGN_CENTER, 
        text="卫星信息", 
        font_size=math.floor(24 * density), 
        color=0x38bdf8 
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

    -- 卫星表格
    satellite_table = airui.table({ 
        parent = content, 
        x=math.floor(10 * density), 
        y=math.floor(10 * density), 
        w=screen_w - math.floor(20 * density), 
        h=content_h - math.floor(20 * density), 
        rows = 9, 
        cols = 5, 
        col_width = {math.floor(80 * density), math.floor(100 * density), math.floor(100 * density), math.floor(80 * density), math.floor(70 * density)}, 
        font_size = math.floor(12 * density),
        border_color = 0x38bdf8,
    })
end

--[[
窗口创建回调
@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并加载卫星数据
]]
local function on_create()
    create_ui()
    
    local gsv = exgnss.gsv()
    
    satellite_table:set_cell_text(0, 0, "编号")
    satellite_table:set_cell_text(0, 1, "卫星类型")
    satellite_table:set_cell_text(0, 2, "信噪比")
    satellite_table:set_cell_text(0, 3, "方位角")
    satellite_table:set_cell_text(0, 4, "仰角")
    
    local function get_satellite_type(tp)
        local type_map = {[0] = "GPS", [1] = "BD", [2] = "GLON", [3] = "GAL", [4] = "QZSS"}
        return type_map[tp] or "Unknown"
    end
    
    if gsv and gsv.sats and #gsv.sats > 0 then
        for i = 1, math.min(#gsv.sats, 8) do
            local sat = gsv.sats[i]
            satellite_table:set_cell_text(i, 0, tostring(sat.nr))
            satellite_table:set_cell_text(i, 1, get_satellite_type(sat.tp))
            satellite_table:set_cell_text(i, 2, tostring(sat.snr) .. "dBm")
            satellite_table:set_cell_text(i, 3, tostring(sat.azimuth) .. "°")
            satellite_table:set_cell_text(i, 4, tostring(sat.elevation) .. "°")
        end
    else
        log.warn("Satellite Win", "No satellite data found")
    end
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
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
end

-- 窗口失去焦点回调
local function on_lose_focus()
end

-- 订阅打开卫星信息页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_SATELLITE_WIN", open_handler)

return {}
