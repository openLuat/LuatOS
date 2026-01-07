--[[
@module  eink_page
@summary eink核心库演示模块
@version 1.0
@date    2026.01.06
@author  江访  
@usage
本模块为eink核心库演示功能模块，主要功能包括：
1、展示eink核心库的基本图形绘制功能；
2、演示线、矩形、圆形等基本图形绘制；
3、显示文本和二维码生成功能；
4、提供电池图标显示功能；

按键功能：
- GPIO9：返回主页

对外接口：
1、eink_page.draw()：绘制eink演示页面
2、eink_page.handle_key()：处理eink页面按键事件
3、eink_page.on_enter()：页面进入时重置状态
4、eink_page.on_leave()：页面离开时执行清理操作
]] 

local eink_page = {}

--[[
绘制eink演示页面；
绘制eink演示页面的所有图形和UI元素；

@api eink_page.draw()
@summary 绘制eink演示页面的所有图形和UI元素
@return nil

@usage
-- 在UI主循环中调用
eink_page.draw()
]] 
function eink_page.draw()
    -- 清除绘图缓冲区（使用白色背景）
    eink.clear(1, true)
    
    -- 绘制外边框（水平+垂直线组合）
    eink.line(5, 5, 195, 5, 0)     -- 上边框水平线
    eink.line(5, 195, 195, 195, 0) -- 下边框水平线
    eink.line(5, 5, 5, 195, 0)     -- 左边框垂直线
    eink.line(195, 5, 195, 195, 0) -- 右边框垂直线

    -- 标题区域（22号英文字体）
    eink.setFont(eink.font_opposansm22)
    eink.rect(10, 10, 190, 40, 0, 0)     -- 标题背景（无斜线）
    eink.print(35, 34, "LuatOS-eink", 0) -- 黑色文字

    -- 区域分隔线（水平）
    eink.line(10, 50, 190, 50, 0)   -- 标题与内容分隔线
    eink.line(100, 55, 100, 190, 0) -- 左右区域分隔线（垂直）

    -- 左侧区域（左半屏）
    -- 1. 文本演示，中文目前仅支持12号中文字体
    eink.setFont(eink.font_opposansm12_chinese)
    eink.print(15, 65, "1. 12中文字体", 0)
    eink.print(20, 85, "GPIO9返回", 0)

    -- 2. 矩形与线条演示
    eink.print(15, 110, "2. 图形演示", 0)
    eink.circle(33, 135, 15, 0, 0)    -- 空心圆形
    eink.circle(73, 135, 15, 0, 1)    -- 实心圆形
    eink.rect(20, 160, 60, 185, 0, 0) -- 空心矩形
    eink.rect(70, 160, 90, 185, 0, 1) -- 实心矩形

    -- 右侧区域（右半屏）
    -- 3. 二维码演示
    eink.print(110, 65, "3. 二维码", 0)
    eink.qrcode(115, 70, "https://docs.openluat.com/osapi/core/eink/", 69)

    -- 4. 电池与位图演示
    eink.print(110, 160, "4. 状态图标", 0)
    eink.bat(120, 170, 3750) -- 电池图标
    eink.print(150, 180, "电量", 0)

    -- 刷新屏幕（不清屏）
    eink.show(0, 0, true)
end

--[[
处理按键事件；
根据按键类型执行相应的操作；

@api eink_page.handle_key(key_type, switch_page)
@summary 处理eink页面按键事件
@string key_type 按键类型
@valid_values "confirm_down"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = eink_page.handle_key("confirm_down", switch_page)
]] 
function eink_page.handle_key(key_type, switch_page)
    log.info("eink_page.handle_key", "key_type:", key_type)
    
    if key_type == "confirm_down" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    -- BOOT键无功能
    return false
end

--[[
页面进入时重置状态；

@api eink_page.on_enter()
@summary 页面进入时重置状态
@return nil

@usage
-- 在页面切换时调用
eink_page.on_enter()
]] 
function eink_page.on_enter()
    log.info("eink_page", "进入eink演示页面")
end

--[[
页面离开时执行清理操作；

@api eink_page.on_leave()
@summary 页面离开时执行清理操作
@return nil

@usage
-- 在页面切换时调用
eink_page.on_leave()
]] 
function eink_page.on_leave()
    log.info("eink_page", "离开eink演示页面")
end

return eink_page