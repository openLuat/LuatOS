--[[
@module  dash_widget_calendar
@summary 86盒深色部件仪表盘的月历部件，当月日期网格与今天高亮
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的月历部件，核心业务逻辑为：
1、卡片顶上一行左边写月份、右边写年份；
2、下面一行是星期简称表头，日一二三四五六各占一格；
3、再下面是6行7列的日期网格，一个月最多6行，格子统一铺满，没到1号和过了月末的格子留空；
4、今天那格底下垫一个品红实心圆，数字用白色压在上面；

本文件的对外接口有1个：
1、dash_widget_calendar.create()：创建月历部件

更多说明参考本目录下的readme.md文件
]]

local dash_theme = require "dash_theme"
local dash_data = require "dash_data"

local dash_widget_calendar = {}

-- ==================== 部件内部布局 ====================

-- 卡片头部
local HEAD_X = 14         -- 月份横坐标
local HEAD_Y = 10         -- 月份纵坐标
local HEAD_W = 120        -- 月份宽度
local HEAD_H = 26         -- 月份高度
local YEAR_X = 150        -- 年份横坐标
local YEAR_Y = 12         -- 年份纵坐标
local YEAR_W = 88         -- 年份宽度
local YEAR_H = 22         -- 年份高度

-- 星期表头与日期网格
local CELL_X0 = 14        -- 第一列的横坐标
local CELL_W = 32         -- 一格宽度
local WEEK_Y = 40         -- 星期表头纵坐标
local WEEK_H = 21         -- 星期表头高度
local GRID_Y = 62         -- 日期网格第一行的纵坐标
local CELL_H = 21         -- 一格高度
local COL_COUNT = 7       -- 列数，一周7天
local ROW_COUNT = 6       -- 行数，一个月最多跨6周

-- 今天高亮圆
local TODAY_DOT_R = 10    -- 高亮圆半径，直径20压在一格21的高度里，不出格

-- ==================== 内部函数 ====================

--[[
生成今天高亮圆的图元；
一个品红实心圆，垫在今天的数字下面；
图元画在2倍半径的方框里，圆心取方框正中；

@function (内部函数) build_today_dot_items

@return table
shape图元数组
]]
local function build_today_dot_items()
    return {
        { type = "circle", cx = TODAY_DOT_R, cy = TODAY_DOT_R, r = TODAY_DOT_R,
            color = dash_theme.COLOR.ACCENT, width = 1,
            fill = true, fill_color = dash_theme.COLOR.ACCENT },
    }
end

--[[
算某个日期在网格里的行列；
日期下标从1号所在列往后数，1号所在列由当月月历数据给出；

@function (内部函数) calc_cell_pos

@table month_grid
当月月历数据，由dash_data.get_month_grid返回；

@number day
几号，从1开始；

@return number, number
列号与行号，都从1开始
]]
local function calc_cell_pos(month_grid, day)
    local cell_index = month_grid.first_wday - 1 + day
    local col_index = (cell_index - 1) % COL_COUNT + 1
    local row_index = math.floor((cell_index - 1) / COL_COUNT) + 1
    return col_index, row_index
end

--[[
取某个格子的横坐标与纵坐标；

@function (内部函数) calc_cell_xy

@number col_index
列号，从1开始；

@number row_index
行号，从1开始；

@return number, number
格子的横坐标与纵坐标
]]
local function calc_cell_xy(col_index, row_index)
    local cell_x = CELL_X0 + (col_index - 1) * CELL_W
    local cell_y = GRID_Y + (row_index - 1) * CELL_H
    return cell_x, cell_y
end

--[[
搭建星期表头；
日一二三四五六各占一格，居中显示；

@function (内部函数) create_week_header

@userdata card_obj
月历卡片对象；

@usage
create_week_header(card_obj)
]]
local function create_week_header(card_obj)
    for i = 1, COL_COUNT do
        local week_x, _ = calc_cell_xy(i, 1)
        dash_theme.label(card_obj, week_x, WEEK_Y, CELL_W, WEEK_H,
            dash_data.WEEK_SHORT_NAME[i], dash_theme.FONT_SIZE.MINI,
            dash_theme.COLOR.TEXT_SUB, airui.TEXT_ALIGN_CENTER)
    end
end

--[[
搭建日期网格；
先垫今天的高亮圆，再压上6行7列的日期数字，创建顺序决定绘制层级；
本月1号之前的格子和月末之后的格子留空；

@function (内部函数) create_day_grid

@userdata card_obj
月历卡片对象；

@table month_grid
当月月历数据，由dash_data.get_month_grid返回；

@usage
create_day_grid(card_obj, dash_data.get_month_grid())
]]
local function create_day_grid(card_obj, month_grid)
    local today_col, today_row = calc_cell_pos(month_grid, month_grid.today_day)
    local today_x, today_y = calc_cell_xy(today_col, today_row)
    -- 高亮圆方框给足2倍半径，圆心落在格子正中
    -- 先建高亮圆再建数字，创建顺序决定绘制层级，数字压在圆上
    local dot_x = today_x + math.floor((CELL_W - TODAY_DOT_R * 2) / 2)
    local dot_y = today_y + math.floor((CELL_H - TODAY_DOT_R * 2) / 2)
    airui.shape({
        parent = card_obj,
        x = dot_x, y = dot_y, w = TODAY_DOT_R * 2, h = TODAY_DOT_R * 2,
        items = build_today_dot_items(),
    })

    for row_index = 1, ROW_COUNT do
        for col_index = 1, COL_COUNT do
            local cell_index = (row_index - 1) * COL_COUNT + col_index
            local day = cell_index - (month_grid.first_wday - 1)
            local cell_x, cell_y = calc_cell_xy(col_index, row_index)
            local day_text = ""
            if day >= 1 and day <= month_grid.day_count then
                day_text = tostring(day)
            end
            local day_color = dash_theme.COLOR.TEXT
            if day ~= month_grid.today_day then
                day_color = dash_theme.COLOR.TEXT_SUB
            end
            dash_theme.label(card_obj, cell_x, cell_y, CELL_W, CELL_H,
                day_text, dash_theme.FONT_SIZE.MINI,
                day_color, airui.TEXT_ALIGN_CENTER)
        end
    end
end

-- ==================== 对外接口 ====================

--[[
创建月历部件；
部件自己建一块卡片，头部、星期表头、日期网格依次挂在卡片下面，
内部布局按252x194的部件尺寸排的，改尺寸要同步改上面的布局常量；

@api dash_widget_calendar.create(parent, x, y, w, h)

@userdata or nil
parent
父对象，传nil则挂在当前屏幕上；

@number x
部件左上角的横坐标，单位像素；

@number y
部件左上角的纵坐标，单位像素；

@number w
部件宽度，单位像素；

@number h
部件高度，单位像素；

@usage
dash_widget_calendar.create(page_root, 20, 268, 252, 194)
]]
function dash_widget_calendar.create(parent, x, y, w, h)
    local card_obj = dash_theme.card(parent, x, y, w, h)
    local month_grid = dash_data.get_month_grid()

    dash_theme.label(card_obj, HEAD_X, HEAD_Y, HEAD_W, HEAD_H,
        dash_data.MONTH_NAME[month_grid.month], dash_theme.FONT_SIZE.TITLE,
        dash_theme.COLOR.ACCENT, airui.TEXT_ALIGN_LEFT)

    dash_theme.label(card_obj, YEAR_X, YEAR_Y, YEAR_W, YEAR_H,
        tostring(month_grid.year), dash_theme.FONT_SIZE.BODY,
        dash_theme.COLOR.TEXT_SUB, airui.TEXT_ALIGN_RIGHT)

    create_week_header(card_obj)
    create_day_grid(card_obj, month_grid)

    log.info("dash_widget_calendar", "月历部件创建完成",
        month_grid.year, month_grid.month, month_grid.first_wday, month_grid.day_count)
end

return dash_widget_calendar
