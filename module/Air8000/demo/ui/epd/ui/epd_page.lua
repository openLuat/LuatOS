--[[
@module  epd_page
@summary epd核心库演示模块
@version 1.0
@date    2026.08.19
@author  江访
@usage
本模块为epd核心库演示功能模块，主要功能包括：
1、展示epd核心库的基本图形绘制功能；
2、演示线、矩形、圆形等基本图形绘制；
3、显示文本和二维码生成功能；
4、展示hzfont矢量字体渲染；

按键功能：
- PWR键：返回主页
- BOOT键：无功能

对外接口：
1、epd_page.draw()：绘制epd演示页面
2、epd_page.handle_key()：处理epd页面按键事件
3、epd_page.on_enter()：页面进入时重置状态
4、epd_page.on_leave()：页面离开时执行清理操作
]]

local epd_page = {}

--[[
绘制epd演示页面；
绘制epd演示页面的所有图形和UI元素（250x122横屏）；

@api epd_page.draw()
@summary 绘制epd演示页面的所有图形和UI元素
@return nil

@usage
-- 在UI主循环中调用
epd_page.draw()
]]
function epd_page.draw()
    -- 清空画布为白色
    panel:clear(epd.WHITE)
    panel:setColor(epd.BLACK, epd.WHITE)

    -- 标题（hzfont矢量字体，基线20）
    panel:drawHzfont(10, 20, "epd核心库演示", 16)

    -- 标题分隔线
    panel:line(4, 26, 246, 26, epd.BLACK)

    -- 左侧区域（图形演示，y=34..118 不超界）
    -- 圆形一组
    panel:circle(20, 48, 8, epd.BLACK, 0)   -- 空心圆
    panel:circle(44, 48, 8, epd.BLACK, 1)   -- 实心圆

    -- 矩形一组
    panel:rect(12, 62, 28, 78, epd.BLACK, 0)  -- 空心矩形
    panel:rect(36, 62, 52, 78, epd.BLACK, 1)  -- 实心矩形

    -- 线条一组
    panel:line(12, 90, 24, 90, epd.BLACK)    -- 横线
    panel:line(32, 84, 32, 96, epd.BLACK)   -- 竖线
    panel:line(40, 84, 52, 96, epd.BLACK)   -- 斜线

    -- 中间区域（文本演示）
    panel:drawHzfont(70, 48, "矢量字体", 14)
    panel:drawHzfont(70, 68, "HzFont ABC", 12)
    panel:drawHzfont(70, 88, "中文 123", 12)

    -- 右侧区域（二维码，y=34..86 不超界）
    panel:drawHzfont(150, 48, "二维码", 12)
    panel:qrcode(150, 52, "https://docs.openluat.com/osapi/core/epd/", 36, epd.BLACK)

    -- 底部提示（基线112，12号字顶100，距屏底10px）
    panel:drawHzfont(10, 112, "PWR键:返回主页", 12)

    -- 刷新屏幕（全刷）
    local ok, rerr = panel:refresh(epd.FULL).wait()
    if not ok then
        log.error("epd_page", "refresh failed", rerr)
    end
end

--[[
处理按键事件；
根据按键类型执行相应的操作；

@api epd_page.handle_key(key_type, switch_page)
@summary 处理epd页面按键事件
@string key_type 按键类型
@valid_values "pwr_up"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = epd_page.handle_key("pwr_up", switch_page)
]]
function epd_page.handle_key(key_type, switch_page)
    log.info("epd_page.handle_key", "key_type:", key_type)

    if key_type == "pwr_up" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    return false
end

--[[
页面进入时重置状态；

@api epd_page.on_enter()
@summary 页面进入时重置状态
@return nil

@usage
-- 在页面切换时调用
epd_page.on_enter()
]]
function epd_page.on_enter()
    log.info("epd_page", "进入epd演示页面")
end

--[[
页面离开时执行清理操作；

@api epd_page.on_leave()
@summary 页面离开时执行清理操作
@return nil

@usage
-- 在页面切换时调用
epd_page.on_leave()
]]
function epd_page.on_leave()
    log.info("epd_page", "离开epd演示页面")
end

return epd_page
