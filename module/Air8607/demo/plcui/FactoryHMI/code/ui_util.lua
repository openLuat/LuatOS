--[[
@module  ui_util
@summary 组件安全访问封装
@version 1.0
@date    2026.11.10
@usage
plcui 的页面组件是按需创建的：切页请求会延后到下一轮 UI 才生效，
切页失败（例如图片解码失败）时 find 会拿到 nil，直接调用组件方法
会让整个 Lua VM 退出（日志表现为 alarm_win.lua:83: attempt to index a nil value）。

本模块把"find + 调用"合成一步，组件不存在就静默跳过，保证界面异常时
脚本还能继续跑，不会把整机拖进重启。

对外接口：
1、ui_util.set     改文字
2、ui_util.src     换图
3、ui_util.chk     改选中态
4、ui_util.hide    显隐
5、ui_util.disable 禁用/启用
6、ui_util.cell    表格写单元格
7、ui_util.values  图表整组赋值
8、ui_util.point   图表追加点
9、ui_util.alive   判断组件是否存在
]]

local M = {}

local function find(xml, page, id)
    if not xml then return nil end
    local ok, widget = pcall(xml.find, xml, page, id)
    if ok then return widget end
    return nil
end

--[[
组件是否存在；
]]
function M.alive(xml, page, id)
    return find(xml, page, id) ~= nil
end

--[[
设置文字；
]]
function M.set(xml, page, id, text)
    local w = find(xml, page, id)
    if w then w:set_text(text) end
end

--[[
切换图片；
]]
function M.src(xml, page, id, source)
    local w = find(xml, page, id)
    if w then w:set_src(source) end
end

--[[
切换选中态；
]]
function M.chk(xml, page, id, on)
    local w = find(xml, page, id)
    if w then w:set_checked(on) end
end

--[[
显示 / 隐藏；
]]
function M.hide(xml, page, id, hidden)
    local w = find(xml, page, id)
    if w then w:set_hidden(hidden) end
end

--[[
禁用 / 启用；
]]
function M.disable(xml, page, id, disabled)
    local w = find(xml, page, id)
    if w then w:set_disabled(disabled) end
end

--[[
表格写单元格；
]]
function M.cell(xml, page, id, row, column, text)
    local w = find(xml, page, id)
    if w then w:set_cell(row, column, text) end
end

--[[
图表整组赋值；
]]
function M.values(xml, page, id, series, data)
    local w = find(xml, page, id)
    if w then w:set_values(series, data) end
end

--[[
图表追加一个点；
]]
function M.point(xml, page, id, series, value)
    local w = find(xml, page, id)
    if w then w:add_point(series, value) end
end

return M
