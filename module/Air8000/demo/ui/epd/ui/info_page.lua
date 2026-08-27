--[[
@module  info_page
@summary 动态信息演示模块（电池/温度/时间）
@version 1.0
@date    2026.08.19
@author  江访
@usage
本模块为动态信息演示功能模块，主要功能包括：
1、使用epd库局部刷新(PARTIAL)演示动态内容更新；
2、显示电池图标和电量百分比；
3、读取并显示CPU温度；
4、显示实时时间；

按键功能：
- PWR键：返回主页
- BOOT键：手动触发一次刷新

对外接口：
1、info_page.draw()：绘制动态信息页面
2、info_page.handle_key()：处理信息页面按键事件
3、info_page.need_update()：检查是否需要自动刷新
4、info_page.on_enter()：页面进入时重置状态
5、info_page.on_leave()：页面离开时执行清理操作
]]

local info_page = {}

-- 信息显示状态
local info_state = {
    bat = 80,             -- 当前电量百分比
    last_update = 0,      -- 最后更新时间
    update_interval = 5000, -- 自动刷新间隔（5秒）
}

-- 动态信息区布局（右半屏，250x122横屏）
local INFO_X1, INFO_Y1, INFO_X2, INFO_Y2 = 126, 34, 244, 118

--[[
读取电池电量百分比
@local
@return number 电量百分比 0~100
]]
local function get_battery()
    local bat = info_state.bat
    if adc and adc.CH_VBAT then
        adc.open(adc.CH_VBAT)
        local vv = adc.get(adc.CH_VBAT)
        if vv and vv > 0 then
            -- 按 3.0~4.2V 估算百分比
            bat = math.floor((vv - 3000) / (4200 - 3000) * 100)
            if bat < 0 then bat = 0 end
            if bat > 100 then bat = 100 end
        end
        adc.close(adc.CH_VBAT)
    end
    return bat
end

--[[
读取CPU温度
@local
@return number 温度（摄氏度）
]]
local function get_temp()
    local temp_c = 50   -- 默认50度
    if adc and adc.CH_CPU then
        adc.open(adc.CH_CPU)
        local tv = adc.get(adc.CH_CPU)
        if tv and tv > 0 then
            temp_c = math.floor(tv / 1000)   -- 毫摄氏度转摄氏度
        end
        adc.close(adc.CH_CPU)
    end
    return temp_c
end

-- 数值右对齐边界
local val_right = INFO_X2 - 4

--[[
绘制动态信息页面；
绘制电池/温度/时间三项动态信息（局部刷新，只更新右半屏）；

@api info_page.draw()
@summary 绘制电池/温度/时间动态信息
@return nil

@usage
-- 在UI主循环中调用
info_page.draw()
]]
function info_page.draw()
    -- 首次绘制时全刷整屏，后续用局部刷新更新信息区
    local is_first = (info_state.last_update == 0)

    if is_first then
        -- 整屏清空并绘制静态部分（左半屏）
        panel:clear(epd.WHITE)
        panel:setColor(epd.BLACK, epd.WHITE)

        -- 标题
        panel:drawHzfont(10, 22, "动态信息演示", 16)
        panel:line(4, 28, 246, 28, epd.BLACK)

        -- 左侧说明文字
        panel:drawHzfont(10, 50, "局部刷新演示", 14)
        panel:drawHzfont(10, 72, "只更新右侧信息区", 12)
        panel:drawHzfont(10, 94, "其余画面保持不变", 12)
        panel:drawHzfont(10, 118, "PWR键:返回", 12)

        -- 右侧信息区边框
        panel:rect(INFO_X1, INFO_Y1, INFO_X2, INFO_Y2, epd.BLACK, 0)
    end

    -- 读取电池电量
    local bat = get_battery()

    -- 读取CPU温度
    local temp_c = get_temp()

    -- 读取时间
    local t = os.date("*t")

    -- 清空信息区内部（保留边框）
    panel:rect(INFO_X1 + 2, INFO_Y1 + 2, INFO_X2 - 2, INFO_Y2 - 2, epd.WHITE, 1)

    -- ===== 电池行 =====
    -- 电池图标（外框 + 正极头）
    panel:rect(130, 40, 168, 56, epd.BLACK, 0)
    panel:rect(169, 44, 172, 52, epd.BLACK, 1)
    -- 电池填充（按电量比例）
    local fill_w = math.floor((bat / 100) * 36)
    if fill_w > 0 then
        panel:rect(132, 42, 131 + fill_w, 54, epd.BLACK, 1)
    end
    -- 电量百分比（右对齐）
    local bat_str = string.format("%d%%", bat)
    local bw = panel:getHzfontWidth(bat_str, 16)
    local bx = val_right - bw
    if bx < 176 then bx = 176 end
    panel:drawHzfont(bx, 54, bat_str, 16)

    -- ===== 温度行（℃）=====
    local temp_str = string.format("%d ℃", temp_c)
    panel:drawHzfont(130, 80, "温度", 14)
    local tw = panel:getHzfontWidth(temp_str, 14)
    panel:drawHzfont(val_right - tw, 80, temp_str, 14)

    -- ===== 时间行 =====
    local hh = string.format("%02d", t.hour)
    local mm = string.format("%02d", t.min)
    local ss = string.format("%02d", t.sec)
    local time_str = hh .. ":" .. mm .. ":" .. ss
    panel:drawHzfont(130, 104, "时间", 14)
    local tw2 = panel:getHzfontWidth(time_str, 14)
    panel:drawHzfont(val_right - tw2, 104, time_str, 14)

    -- 局部刷新信息区（仅更新右半屏）
    local ok, rerr = panel:refresh(epd.PARTIAL).wait()
    if not ok then
        log.error("info_page", "refresh failed", rerr)
    end

    -- 更新最后刷新时间
    info_state.last_update = mcu.ticks()
end

--[[
处理按键事件；
根据按键类型执行相应的操作；

@api info_page.handle_key(key_type, switch_page)
@summary 处理信息页面按键事件
@string key_type 按键类型
@valid_values "boot_up", "pwr_up"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = info_page.handle_key("boot_up", switch_page)
]]
function info_page.handle_key(key_type, switch_page)
    log.info("info_page.handle_key", "key_type:", key_type)

    if key_type == "boot_up" then
        -- BOOT键：手动刷新一次
        info_page.draw()
        return true
    elseif key_type == "pwr_up" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    return false
end

--[[
检查是否需要更新；
基于时间间隔判断是否需要刷新显示；

@api info_page.need_update()
@summary 检查是否需要更新时间显示
@return bool 需要更新返回true，否则返回false

@usage
-- 在UI主循环中调用
if info_page.need_update() then
    info_page.draw()
end
]]
function info_page.need_update()
    local current_time = mcu.ticks()
    return (current_time - info_state.last_update) >= info_state.update_interval
end

--[[
自动更新；
局部刷新动态信息（电池/温度/时间）；
配合need_update()在UI主循环中周期调用，实现信息自动刷新；

@api info_page.auto_update()
@summary 局部刷新动态信息
@return nil

@usage
-- 在UI主循环超时分支中调用
if info_page.need_update() then
    info_page.auto_update()
end
]]
function info_page.auto_update()
    -- 读取数据并局部刷新信息区
    local bat = get_battery()
    local temp_c = get_temp()
    local t = os.date("*t")
    info_page.draw()   -- draw内部会用局部刷新
end

--[[
页面进入时重置状态；

@api info_page.on_enter()
@summary 页面进入时重置状态
@return nil

@usage
-- 在页面切换时调用
info_page.on_enter()
]]
function info_page.on_enter()
    info_state.last_update = 0
    log.info("info_page", "进入动态信息页面")
end

--[[
页面离开时执行清理操作；

@api info_page.on_leave()
@summary 页面离开时执行清理操作
@return nil

@usage
-- 在页面切换时调用
info_page.on_leave()
]]
function info_page.on_leave()
    log.info("info_page", "离开动态信息页面")
end

return info_page
