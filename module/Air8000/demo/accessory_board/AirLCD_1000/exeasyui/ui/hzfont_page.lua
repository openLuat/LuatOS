--[[
@module  hzfont_page
@summary HZFont矢量字体演示页面模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本文件为HZFont矢量字体演示页面模块，核心业务逻辑为：
1、创建HZFont矢量字体演示页面，展示矢量字体的动态调整能力；
2、演示多种字体大小和颜色的文本显示效果；
3、提供字体大小动态切换功能，展示矢量字体的缩放优势；
4、展示HZFont矢量字体的特性和应用场景；

本文件的对外接口有1个：
1、hzfont_page.create(ui)：创建并返回HZFont演示窗口；
]]

local hzfont_page = {}

--[[
页面演示状态记录表

@table demo_state
@field current_size number 当前演示字体大小，初始值为16号
]]
local demo_state = {
    current_size = 16  -- 当前字体大小，从16号开始
}

--[[
创建HZFont矢量字体演示页面窗口；

@api hzfont_page.create(ui)

@summary 创建HZFont矢量字体演示页面

@param ui table exEasyUI库对象，用于创建UI组件

@return table 返回创建的窗口对象

@usage
-- 在页面切换逻辑中调用
local hzfont_win = hzfont_page.create(ui)
return hzfont_win
]]
function hzfont_page.create(ui)
    --[[
    创建主窗口
    @param background_color number 窗口背景颜色，白色
    @param x number 窗口左上角X坐标，0
    @param y number 窗口左上角Y坐标，0
    @param w number 窗口宽度，320像素
    @param h number 窗口高度，480像素
    ]]
    local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 320,
        h = 480
    })

    --[[
    页面标题标签
    @param x number 标签左上角X坐标，85像素
    @param y number 标签左上角Y坐标，25像素
    @param text string 标签文本内容
    @param color number 文本颜色，黑色
    @param size number 字体大小，16号
    ]]
    local title = ui.label({
        x = 85,
        y = 25,
        text = "HZFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 16
    })

    --[[
    返回按钮
    @param x number 按钮左上角X坐标，20像素
    @param y number 按钮左上角Y坐标，20像素
    @param w number 按钮宽度，60像素
    @param h number 按钮高度，30像素
    @param text string 按钮文本
    @param on_click function 按钮点击回调函数，调用窗口的back方法返回上一页
    ]]
    local btn_back = ui.button({
        x = 20,
        y = 20,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            win:back()
        end
    })

    --[[
    动态字体大小调整标题
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，70像素
    @param text string 标签文本内容
    @param color number 文本颜色，黑色
    @param size number 字体大小，16号
    ]]
    local dynamic_title = ui.label({
        x = 20,
        y = 70,
        text = "动态字体大小调整:",
        color = ui.COLOR_BLACK,
        size = 16
    })

    --[[
    字体大小信息显示标签
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，100像素
    @param text string 标签文本内容，显示当前字体大小
    @param color number 文本颜色，蓝色
    @param size number 字体大小，16号
    ]]
    local size_info = ui.label({
        x = 20,
        y = 100,
        text = "当前大小: 16号 (可调整)",
        color = ui.COLOR_BLUE,
        size = 16
    })

    --[[
    字体大小切换按钮
    @param x number 按钮左上角X坐标，20像素
    @param y number 按钮左上角Y坐标，140像素
    @param w number 按钮宽度，120像素
    @param h number 按钮高度，30像素
    @param text string 按钮文本
    @param on_click function 按钮点击回调函数，切换字体大小
    ]]
    local btn_change_size = ui.button({
        x = 20,
        y = 140,
        w = 120,
        h = 30,
        text = "切换字体大小",
        on_click = function()
            -- 每次点击增加4号字体大小
            demo_state.current_size = demo_state.current_size + 4
            
            -- 当字体大小超过32号时，重置为12号
            if demo_state.current_size > 32 then
                demo_state.current_size = 12
            end
            
            -- 更新标签文本和字体大小
            size_info:set_text("当前字体大小: " .. demo_state.current_size .. "号")
            size_info:set_size(demo_state.current_size)
        end
    })

    --[[
    字体演示区域标题
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，180像素
    @param text string 标签文本内容
    @param color number 文本颜色，黑色
    @param size number 字体大小，16号
    ]]
    local demo_title = ui.label({
        x = 20,
        y = 180,
        text = "字体演示:",
        color = ui.COLOR_BLACK,
        size = 16
    })

    --[[
    数字演示标签
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，210像素
    @param text string 标签文本内容，显示数字
    @param color number 文本颜色，蓝色
    @param size number 字体大小，14号
    ]]
    local number_demo = ui.label({
        x = 20,
        y = 210,
        text = "数字: 0123456789",
        color = ui.COLOR_BLUE,
        size = 14
    })

    --[[
    符号演示标签
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，250像素
    @param text string 标签文本内容，显示特殊符号
    @param color number 文本颜色，橙色
    @param size number 字体大小，20号
    ]]
    local symbol_demo = ui.label({
        x = 20,
        y = 250,
        text = "符号: !@#$%^&*()_+-=[]",
        color = ui.COLOR_ORANGE,
        size = 20
    })

    --[[
    中英文演示标签
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，300像素
    @param text string 标签文本内容，显示中英文混合文本
    @param color number 文本颜色，红色
    @param size number 字体大小，28号
    ]]
    local text_demo = ui.label({
        x = 20,
        y = 300,
        text = "中英文: LuatOS",
        color = ui.COLOR_RED,
        size = 28
    })

    --[[
    HZFont特性说明标题
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，350像素
    @param text string 标签文本内容
    @param color number 文本颜色，黑色
    @param size number 字体大小，14号
    ]]
    local feature_title = ui.label({
        x = 20,
        y = 350,
        text = "HZFont特性:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    --[[
    HZFont特性说明第一条
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，380像素
    @param text string 标签文本内容，说明HZFont的内置特性
    @param color number 文本颜色，灰色
    @param size number 字体大小，12号
    ]]
    local feature1 = ui.label({
        x = 20,
        y = 380,
        text = "- 内置矢量字体，无需外部硬件",
        color = ui.COLOR_GRAY,
        size = 12
    })

    --[[
    HZFont特性说明第二条
    @param x number 标签左上角X坐标，20像素
    @param y number 标签左上角Y坐标，410像素
    @param text string 标签文本内容，说明HZFont的动态调整能力
    @param color number 文本颜色，灰色
    @param size number 字体大小，12号
    ]]
    local feature2 = ui.label({
        x = 20,
        y = 410,
        text = "- 支持10-100号字体动态调整",
        color = ui.COLOR_GRAY,
        size = 12
    })

    --[[
    将创建的UI组件添加到窗口
    按照从背景到前景的顺序添加，确保显示层次正确
    ]]
    win:add(title)
    win:add(btn_back)
    win:add(dynamic_title)
    win:add(size_info)
    win:add(btn_change_size)
    win:add(demo_title)
    win:add(number_demo)
    win:add(symbol_demo)
    win:add(text_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)

    return win
end

return hzfont_page