--[[
@module  dash_widget_music
@summary 86盒深色部件仪表盘的音乐部件，唱片封面、歌名歌手与播放暂停按钮
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的音乐部件，核心业务逻辑为：
1、左边一张唱片封面，用airui.shape的图元画出来，不带图片资源；
2、封面右边两行字，上面歌名下面歌手；
3、最右一个胶囊按钮，播放中写「暂停」、暂停中写「播放」，点一下翻转状态；
4、播放状态存在dash_data.MUSIC里，接真机时从这里换成设备侧的播放状态；

本文件的对外接口有1个：
1、dash_widget_music.create()：创建音乐部件

更多说明参考本目录下的readme.md文件
]]

local dash_theme = require "dash_theme"
local dash_data = require "dash_data"

local dash_widget_music = {}

-- ==================== 部件内部布局 ====================

-- 唱片封面
local ART_X = 16          -- 封面横坐标
local ART_Y = 14          -- 封面纵坐标
local ART_SIZE = 64       -- 封面边长

-- 歌名与歌手
local TITLE_X = 96        -- 歌名横坐标
local TITLE_Y = 16        -- 歌名纵坐标
local TITLE_W = 224       -- 歌名宽度
local TITLE_H = 26        -- 歌名高度
local ARTIST_X = 96       -- 歌手横坐标
local ARTIST_Y = 48       -- 歌手纵坐标
local ARTIST_W = 224      -- 歌手宽度
local ARTIST_H = 22       -- 歌手高度

-- 播放暂停按钮
local PLAY_X = 352        -- 按钮横坐标
local PLAY_Y = 29         -- 按钮纵坐标
local PLAY_W = 72         -- 按钮宽度
local PLAY_H = 34         -- 按钮高度

-- ==================== 运行状态 ====================

-- 播放暂停按钮的底板和文字对象
local play_bg = nil
local play_text = nil

-- ==================== 内部函数 ====================

--[[
生成唱片封面的图元；
一张深色圆角方块上画一圈品红圆环和一个品红圆心，读作黑胶唱片；

@function (内部函数) build_art_items

@return table
shape图元数组
]]
local function build_art_items()
    return {
        { type = "rect", x = 0, y = 0, w = ART_SIZE, h = ART_SIZE, radius = 14,
            color = dash_theme.COLOR.CARD_HI, fill = true, fill_color = dash_theme.COLOR.CARD_HI },
        { type = "circle", cx = 32, cy = 32, r = 20,
            color = dash_theme.COLOR.ACCENT, width = 3, round_start = true },
        { type = "circle", cx = 32, cy = 32, r = 6,
            color = dash_theme.COLOR.ACCENT, width = 1, fill = true, fill_color = dash_theme.COLOR.ACCENT },
    }
end

--[[
按播放状态刷新播放暂停按钮；
播放中按钮写「暂停」并上强调色，暂停中按钮写「播放」用卡片凸起色；

@function (内部函数) refresh_play_button

@usage
refresh_play_button()
]]
local function refresh_play_button()
    if dash_data.MUSIC.playing then
        play_text:set_text("暂停")
        play_bg:set_color(dash_theme.COLOR.ACCENT)
        play_text:set_color(dash_theme.COLOR.BLACK)
    else
        play_text:set_text("播放")
        play_bg:set_color(dash_theme.COLOR.CARD_HI)
        play_text:set_color(dash_theme.COLOR.TEXT)
    end
end

-- ==================== 回调函数 ====================

--[[
播放暂停按钮的点击回调；
翻转播放状态并刷新按钮；

@function (内部函数) on_play_click

@userdata sender
被点的按钮文字对象；

@usage
on_play_click(sender)
]]
local function on_play_click(sender)
    dash_data.MUSIC.playing = not dash_data.MUSIC.playing
    refresh_play_button()
    log.info("dash_widget_music", "播放状态", tostring(dash_data.MUSIC.playing))
end

-- ==================== 对外接口 ====================

--[[
创建音乐部件；
部件自己建一块卡片，唱片封面、歌名歌手、播放暂停按钮都挂在卡片下面，
内部布局按440x92的部件尺寸排的，改尺寸要同步改上面的布局常量；

@api dash_widget_music.create(parent, x, y, w, h)

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
dash_widget_music.create(page_root, 20, 164, 440, 92)
]]
function dash_widget_music.create(parent, x, y, w, h)
    local card_obj = dash_theme.card(parent, x, y, w, h)

    airui.shape({
        parent = card_obj,
        x = ART_X, y = ART_Y, w = ART_SIZE, h = ART_SIZE,
        items = build_art_items(),
    })

    dash_theme.label(card_obj, TITLE_X, TITLE_Y, TITLE_W, TITLE_H,
        dash_data.MUSIC.title, dash_theme.FONT_SIZE.TITLE,
        dash_theme.COLOR.TEXT, airui.TEXT_ALIGN_LEFT)

    dash_theme.label(card_obj, ARTIST_X, ARTIST_Y, ARTIST_W, ARTIST_H,
        dash_data.MUSIC.artist, dash_theme.FONT_SIZE.BODY,
        dash_theme.COLOR.TEXT_SUB, airui.TEXT_ALIGN_LEFT)

    play_bg, play_text = dash_theme.pill(card_obj, PLAY_X, PLAY_Y, PLAY_W, PLAY_H,
        "暂停", dash_theme.COLOR.ACCENT, dash_theme.COLOR.BLACK)
    play_text:set_on_click(on_play_click)

    refresh_play_button()
    log.info("dash_widget_music", "音乐部件创建完成")
end

return dash_widget_music
