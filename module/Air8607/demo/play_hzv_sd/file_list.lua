--[[
@module  file_list
@summary HZV 素材选择列表页应用功能模块（airui 列表 + 触摸点选）
@version 1.0
@date    2026.10.30
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的素材选择列表页应用功能模块，核心业务逻辑为：
1、建一个全屏容器做列表页，容器里放标题、提示文字、"顺序播放全部"按钮和素材列表；
2、素材列表是一列 airui.button，每行一个文件，文字为"序号 + 文件名"，行高固定；
3、行数超出列表容器高度时靠上下滑动翻看，列表容器自带滚动条；
4、点素材行发出 HZV_PLAY_REQ 消息，消息参数是素材序号，由 main.lua 接消息起播；
5、点"顺序播放全部"按钮发出 HZV_PLAY_REQ 消息，序号固定为 0，表示按顺序轮播整张表；
6、show 和 hide 用 set_hidden 切换列表页的显隐，播放时收起，返回时展开。

点击回调是所有素材行共用的一个具名函数，回调里用按钮文字反查素材序号，
所以不需要给每一行单独造回调函数。

本文件的对外接口有3个：
1、file_list.init(files)：按素材列表建出整个选择页，files 每项为 {path=, name=, size=}
2、file_list.show：显示素材选择页
3、file_list.hide：隐藏素材选择页，给视频让出画面
]]

local M = {}

-- 列表页尺寸，铺满 1024x600 的屏幕
local PAGE_W = 1024
local PAGE_H = 600

-- 页面四边留白
local PAD = 24

-- 标题区高度
local TITLE_H = 44

-- 提示文字高度
local TIP_H = 28

-- 素材行的行距与按钮高度
local ITEM_H = 60
local BTN_H  = 52

-- "顺序播放全部"按钮尺寸
local PLAY_ALL_W = 248
local PLAY_ALL_H = 44

-- 配色
local COL_BG       = 0x101418
local COL_PANEL    = 0x1B2430
local COL_ITEM     = 0x2B3646
local COL_ITEM_ALL = 0x1D6B4F
local COL_TEXT     = 0xFFFFFF
local COL_SUB      = 0x9AA7B8

-- 标题字号与正文字号
local FONT_TITLE = 26
local FONT_ITEM  = 20
local FONT_TIP   = 16

-- 列表页根容器，show 和 hide 都作用在它身上
local list_page = nil

-- 素材列表容器
local list_box = nil

-- 素材行按钮文字到素材序号的对照表，点击回调按文字查序号
local row_index = {}

--[[
素材行的点击回调；

@summary 所有素材行共用，按按钮文字查出素材序号后发出选片消息

@param userdata sender 被点中的素材行按钮

@return nil
]]
local function on_item_click(sender)
    local text  = sender:get_text()
    local index = row_index[text]
    if not index then
        log.warn("file_list", "点中的行不在素材列表里", text)
        return
    end
    log.info("file_list", "选中素材", index, text)
    sys.publish("HZV_PLAY_REQ", index)
end

--[[
"顺序播放全部"按钮的点击回调；

@summary 发出序号为 0 的选片消息，表示按顺序轮播整张表

@param userdata sender 被点中的按钮

@return nil
]]
local function on_play_all_click(sender)
    log.info("file_list", "选中顺序播放全部")
    sys.publish("HZV_PLAY_REQ", 0)
end

--[[
建立素材选择列表页；

@api file_list.init(files)

@summary 按素材列表建出全屏选择页，每条素材一行按钮，一行"顺序播放全部"按钮放在标题右侧

@param table files 素材列表，每项为 {path=, name=, size=}，由 sd_app.list_hzv 提供

@return boolean 建页成功返回 true，files 不是表或列表页已经建过返回 false

@usage
local files = sd_app.list_hzv()
file_list.init(files)
file_list.show()
]]
function M.init(files)
    if type(files) ~= "table" then
        log.error("file_list", "素材列表不是表，无法建立选择页")
        return false
    end
    if list_page then
        log.warn("file_list", "素材选择页已经建立过，不重复建立")
        return false
    end

    row_index = {}

    -- 列表页根容器，铺满整个屏幕，播放时用 set_hidden 收起
    list_page = airui.container({
        x     = 0,
        y     = 0,
        w     = PAGE_W,
        h     = PAGE_H,
        color = COL_BG,
    })

    -- 标题
    airui.label({
        parent     = list_page,
        x          = PAD,
        y          = 16,
        w          = PAGE_W - PAD * 3 - PLAY_ALL_W,
        h          = TITLE_H,
        text       = "TF 卡 HZV 素材列表",
        font_size  = FONT_TITLE,
        color      = COL_TEXT,
    })

    -- "顺序播放全部"按钮，放在标题右侧
    airui.button({
        parent    = list_page,
        x         = PAGE_W - PAD - PLAY_ALL_W,
        y         = 16,
        w         = PLAY_ALL_W,
        h         = PLAY_ALL_H,
        text      = "顺序播放全部",
        font_size = FONT_ITEM,
        style     = {
            bg_color   = COL_ITEM_ALL,
            text_color = COL_TEXT,
            radius     = 8,
        },
        on_click  = on_play_all_click,
    })

    -- 素材列表区域的高度，行数超出时靠上下滑动翻看
    local list_h = PAGE_H - (16 + TITLE_H + 10 + TIP_H + 10) - PAD

    -- 提示文字，没素材时提示拷贝素材，条数多时提示可以滑动
    local tip = "点文件名开始播放，点右上角“顺序播放全部”可轮播整张表"
    if #files == 0 then
        tip = "TF 卡里没有 .hzv 素材，请把素材拷贝到卡根目录后重新上电"
    elseif #files * ITEM_H > list_h then
        tip = tip .. "，上下滑动查看更多"
    end
    airui.label({
        parent    = list_page,
        x         = PAD,
        y         = 16 + TITLE_H + 10,
        w         = PAGE_W - PAD * 2,
        h         = TIP_H,
        text      = tip,
        font_size = FONT_TIP,
        color     = COL_SUB,
    })

    -- 素材列表容器，行数超出高度时上下滑动
    list_box = airui.container({
        parent = list_page,
        x      = PAD,
        y      = 16 + TITLE_H + 10 + TIP_H + 10,
        w      = PAGE_W - PAD * 2,
        h      = list_h,
        color  = COL_PANEL,
    })

    for i = 1, #files do
        local text = string.format("%02d  %s", i, files[i].name)
        airui.button({
            parent    = list_box,
            x         = 0,
            y         = (i - 1) * ITEM_H,
            w         = PAGE_W - PAD * 2,
            h         = BTN_H,
            text      = text,
            font_size = FONT_ITEM,
            style     = {
                bg_color   = COL_ITEM,
                text_color = COL_TEXT,
                radius     = 8,
            },
            on_click  = on_item_click,
        })
        row_index[text] = i
    end

    log.info("file_list", "素材选择页建立完成", "素材数量" .. #files)
    return true
end

--[[
显示素材选择页；

@api file_list.show()

@summary 把列表页容器设为可见，返回列表时调用

@return nil

@usage
file_list.show()
]]
function M.show()
    if not list_page then
        return
    end
    list_page:set_hidden(false)
    log.info("file_list", "素材选择页已显示")
end

--[[
隐藏素材选择页；

@api file_list.hide()

@summary 把列表页容器设为隐藏，起播之前调用，给视频让出画面

@return nil

@usage
file_list.hide()
]]
function M.hide()
    if not list_page then
        return
    end
    list_page:set_hidden(true)
    log.info("file_list", "素材选择页已隐藏")
end

return M
