--[[
@module  hzv_ui
@summary HZV 视频选片界面模块（AirUI 触摸界面：目录切换 + 文件列表 + 播放控制 + 全屏 + 音量 + 状态显示）
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本文件为 HZV 播放 demo 的图形界面模块，核心业务逻辑为：
1、初始化触摸屏（GT911，参数全部来自 hzv_hw 的 tp 段）并绑定到 AirUI 输入设备；
2、顶部标题栏显示"HZV 视频库"和当前列表里的文件数量；
3、左侧顶部是"内置存储 / TF 卡"两个目录切换按钮，选中哪个就只列该目录下的 *.hzv；
   左侧下方是文件列表，点一下换片，正在播放的那一项高亮；
4、右侧是播放区，视频按区域内居中显示（不缩放）；
5、底部工具栏：播放 / 暂停 / 停止 / 音量- / 音量+ / 刷新 / 全屏 七个按钮，
   右侧实时显示实际帧率 fps 与当前音量；
6、点"全屏"后隐藏标题栏/目录栏/列表/工具栏，视频在整屏范围内居中播放，
   底部浮出一条控制栏（播放 / 暂停 / 退出全屏 + 状态文字），点"退出全屏"还原界面；
7、界面每 1 秒刷新一次状态文字，统计来自 hzv_player.stats()。

关于全屏：
airui.video 不支持缩放，控件尺寸与素材帧尺寸不一致时会被组件强制改回素材尺寸，
所以全屏不是"把画面放大"，而是把可用播放区域从右侧一小块换成整屏，画面仍按素材
原始分辨率居中显示。底部浮动控制栏必须在视频之后创建：同一父对象里 LVGL 按创建
顺序绘制，后建的控件才压得住画面。

关于中文显示：
界面上所有文字都是中文，必须先在 lcd_app.init() 里调用 airui.font_load 加载固件内置的
中文矢量字库（hzfont），否则中文会全部渲染成方块"豆腐块"，按钮就看不出是什么功能。
本文件只负责用中文写文字，字体加载统一放在 lcd_app.lua 里做。

对外接口：
1、hzv_ui.start()：初始化触摸并创建界面，成功返回 true；
                  没有触摸配置或 tp.init 失败时返回 false，由 main.lua 回退到自动演示模式

界面布局按屏幕分辨率自适应计算，1024x600 上为：顶部 56px 标题栏 + 左侧 30% 宽目录栏与
文件列表 + 右侧播放区 + 底部 64px 工具栏（7 个按钮 + 状态栏）。
]]

local hzv_hw = require "hzv_hw"
local lcd_app = require "lcd_app"
local hzv_player = require "hzv_player"

local M = {}

-- 界面配色（深色底，和视频画面更协调）
local COL_BG       = 0x121212   -- 整体背景
local COL_PANEL    = 0x1F1F1F   -- 标题栏/工具栏
local COL_TEXT     = 0xE6E6E6   -- 主要文字
local COL_SUB      = 0x8A8A8A   -- 次要文字
local COL_ITEM     = 0x2A2A2A   -- 列表项/按钮背景
local COL_ITEM_SEL = 0x1F4E79   -- 正在播放的列表项背景

-- 布局参数（像素），实际尺寸由屏幕分辨率换算
local PAD        = 8    -- 通用内边距
local HEADER_H   = 56   -- 顶部标题栏高度
local FOOTER_H   = 64   -- 底部工具栏高度
local ITEM_H     = 46   -- 每个文件列表项的高度
local BTN_W      = 96   -- 工具栏按钮宽度（6 个按钮，1024 屏上刚好放得下）
local BTN_H      = 40   -- 工具栏按钮高度
local DIR_BAR_H  = 46   -- 左侧目录切换栏高度（"内置存储 / TF 卡"两个按钮）
local FS_BAR_H   = 56   -- 全屏模式下浮动控制栏高度
local FS_LABEL_W = 230  -- 全屏控制栏右侧状态文字的宽度

-- 音量按钮每次加减的步进（音量刻度 0~100，100 为原始音量，0 为静音）
local VOL_STEP   = 5

-- 界面对象，nil 表示未创建
local ui = {}

-- 文件列表与对应按钮（用于高亮正在播放的项）
local files       = {}
local item_btns   = {}
local cur_index   = 0

-- 当前浏览的素材目录：nil = 全部目录，"/luadb" = 内置存储，"/sd" = TF 卡
local cur_dir     = nil
-- 目录切换按钮，key 为目录路径，用于切换后刷新选中态
local dir_btns    = {}

-- 全屏状态：true 时隐藏界面各栏，视频占满整屏
local fullscreen  = false

--[[
截断过长的文件名；

@api hzv_ui.short_name(name)
@summary 列表宽度有限，文件名超过 16 个字符时截断并加省略号
@param string name 原始文件名
@return string 用于显示的短名
]]
local function short_name(name)
    if #name > 16 then
        return name:sub(1, 15) .. "..."
    end
    return name
end

--[[
初始化触摸屏并绑定到 AirUI；

@api hzv_ui.init_touch()
@summary 按 hzv_hw 的 tp 段做 I2C 复用、i2c.setup、tp.init，并绑定到 AirUI
@return boolean 初始化成功返回 true
]]
local function init_touch()
    local cfg = hzv_hw.get()
    local tp_cfg = cfg.tp
    if not tp_cfg then
        log.warn("hzv_ui", "当前板型没有配置触摸屏", cfg.name)
        return false
    end
    if not rawget(_G, "tp") or not tp.init then
        log.error("hzv_ui", "固件不支持 tp 库，请烧录带 LUAT_USE_TP 的固件")
        return false
    end

    -- I2C 功能复用：出厂固件里写在 pins 表，由 platform_loader 调 pins.setup
    if tp_cfg.pins and rawget(_G, "pins") and pins.setup then
        for _, p in ipairs(tp_cfg.pins) do
            pcall(pins.setup, p.pin, p.func)
        end
        log.info("hzv_ui", "触摸 I2C 引脚复用完成，数量", #tp_cfg.pins)
    end

    -- 硬件 I2C 初始化（软件 I2C 的板型只要把 port 换成 i2c.createSoft 的对象即可）
    i2c.setup(tp_cfg.port, i2c.SLOW)

    -- 触摸屏复位：air780 系列的 GT911 有的板和 LCD 共用一个复位脚
    if tp_cfg.pin_rst then
        gpio.setup(tp_cfg.pin_rst, 0)
        gpio.close(tp_cfg.pin_rst)   -- 关掉输出恢复高阻态，把复位交给 tp.init 内部时序
        i2c.setup(tp_cfg.port, i2c.SLOW)
    end

    local param = {
        port     = tp_cfg.port,
        pin_int  = tp_cfg.pin_int,
        int_type = tp.FALLING,
        w        = cfg.lcd.w,
        h        = cfg.lcd.h,
    }
    -- pin_rst 为 nil 时不要传这个字段（Air8605 出厂固件明确要求不传，传了会锁死 INT）
    if tp_cfg.pin_rst then
        param.pin_rst = tp_cfg.pin_rst
    end

    -- 使用 AirUI 时不需要传触摸回调，第三个参数传 nil 由 LVGL 自己处理触摸事件
    local tp_device = tp.init(tp_cfg.model or "gt911", param, nil)
    if not tp_device then
        log.error("hzv_ui", "触摸初始化失败，请检查 I2C/复位/中断脚与屏是否匹配")
        return false
    end

    -- 把触摸设备绑定到 AirUI 输入，绑定后按钮的 on_click 才会被触发
    local bind_ok = airui.device_bind_touch(tp_device)
    if not bind_ok then
        log.error("hzv_ui", "触摸绑定 AirUI 失败")
        return false
    end

    log.info("hzv_ui", "触摸初始化成功并已绑定 AirUI")
    return true
end

--[[
统一写状态文字（窗口态写工具栏右侧，全屏态写浮动控制栏）；
@param string text 要显示的文字
@return nil
]]
local function set_status_text(text)
    if ui.status then
        ui.status:set_text(text)
    end
    -- 全屏时工具栏被隐藏，状态文字改到浮动控制栏里显示
    if ui.fs_status then
        ui.fs_status:set_text(text)
    end
end

--[[
用帧计数自算帧率（只在引擎给的 fps 不可信时兜底）；

@summary mcu.ticks() 返回的是 tick 数、不是毫秒，必须按 mcu.hz() 换算成毫秒；
          同时要校验采样窗口：窗口太短（两次调用挨得太近）会把 15fps 算成几百，
          帧数回退（组件重建过）也要丢掉这一次采样
@param number frames 引擎累计帧数
@return number 帧率，采样数据不足时返回 nil
]]
local function calc_fps_by_frames(frames)
    frames = tonumber(frames)
    if not frames or not rawget(_G, "mcu") or not mcu.ticks then
        return nil
    end

    local tick = mcu.ticks()
    -- tick 频率不一定是 1000（有的平台是 1024、有的更高），取不到就按 1000 当毫秒
    local hz = 1000
    if mcu.hz then
        local v = tonumber(mcu.hz())
        if v and v > 0 then
            hz = v
        end
    end

    local last_tick = ui.last_tick
    local last_frames = ui.last_frames
    ui.last_tick = tick
    ui.last_frames = frames

    -- 第一次调用只记录基准，出不了值
    if not last_tick or not last_frames then
        return nil
    end

    local df = frames - last_frames
    local dt_ms = (tick - last_tick) * 1000 / hz
    -- df < 0：换片/重建后计数归零；窗口不在 0.5~5 秒之间：样本不可信
    if df < 0 or dt_ms < 500 or dt_ms > 5000 then
        return nil
    end
    return df * 1000 / dt_ms
end

--[[
刷新状态栏文字；

@api hzv_ui.update_status()
@summary 每秒钟读一次播放统计，只显示实际帧率和当前音量；
          帧率优先用引擎统计值（组件内部按 1000ms 窗口计帧，精度到 0.01），
          引擎值异常时才用 total_frames 自己算；丢帧、音画差等原始数据仍打到日志里
@return nil
]]
local function update_status()
    if not ui.status and not ui.fs_status then
        return
    end

    if not hzv_player.current() then
        set_status_text("未播放 · 点左侧文件开始播放")
        return
    end

    local vol = hzv_player.get_volume()
    local stats = hzv_player.stats()
    if not stats then
        -- 老固件没有 get_stats，只显示音量
        set_status_text("音量 " .. tostring(vol))
        return
    end

    -- 引擎的 fps 是 fps_x100 / 100，播放中才会更新；NaN、负数、明显离谱（>120）当作无效
    local fps_num = tonumber(stats.fps)
    if not fps_num or fps_num ~= fps_num or fps_num < 0 or fps_num > 120 then
        fps_num = calc_fps_by_frames(stats.total_frames)
    end

    -- 固定保留一位小数，避免浮点直接 tostring 出来一长串 "288.20000000000"
    local fps_str = "--"
    if fps_num then
        fps_str = string.format("%.1f", fps_num)
    end

    -- 状态栏只保留两项：实际帧率与当前音量（丢帧/音画差看日志即可）
    set_status_text("fps " .. fps_str .. "  音量 " .. tostring(vol))
end

--[[
状态刷新任务（具名函数，避免 sys.taskInit 里写匿名函数）；
@summary 每秒刷新一次状态栏，与界面生命周期同生共死
@return nil
]]
local function status_task()
    while true do
        sys.wait(1000)
        update_status()
    end
end

--[[
生成第 index 个列表项的点击回调；
@summary 用具名内部函数包装序号，避免在组件参数里写匿名函数
@param number index 列表序号
@return function 点击回调
]]
local function make_item_click(index)
    local function on_click()
        M.select(index)
    end
    return on_click
end

--[[
空列表时的提示文字；
@param string dir 当前目录，nil 表示全部目录
@return string 提示文字
]]
local function empty_tip(dir)
    if dir == "/luadb" then
        return "内置存储里没有 .hzv\n请把素材随脚本一起烧进 /luadb"
    elseif dir == "/sd" then
        return "TF 卡里没有 .hzv\n请把素材放到卡根目录后点刷新"
    end
    return "没有找到 .hzv 文件\n请烧进 /luadb 或放到 TF 卡"
end

--[[
重建左侧文件列表；

@api hzv_ui.rebuild_list(dir)
@summary 只扫描指定目录（nil 表示全部目录）并重建左侧列表，切换目录或点"刷新"时调用
@param string dir 目录路径，可选
@return nil
]]
local function rebuild_list(dir)
    -- 重建前先销毁旧的列表容器，避免组件叠加
    if ui.list_box then
        ui.list_box:destroy()
        ui.list_box = nil
    end
    item_btns = {}

    -- 只扫当前选中的目录，没选就扫全部（/sd + /luadb）
    files = hzv_player.scan(dir)

    -- 列表区域：左侧 30% 宽，标题栏与工具栏之间；顶部 DIR_BAR_H 让给目录切换按钮
    local list_x = PAD
    local list_y = HEADER_H + PAD + DIR_BAR_H + PAD
    local list_w = math.floor(ui.screen_w * 0.30)
    local list_h = ui.screen_h - HEADER_H - FOOTER_H - PAD * 3 - DIR_BAR_H

    ui.list_box = airui.container({
        parent = ui.bg,
        x = list_x, y = list_y, w = list_w, h = list_h,
        color = COL_PANEL,
    })

    -- 一屏最多放几项（1024x600 上是 8 项）
    local max_items = math.floor((list_h - PAD) / ITEM_H)

    if #files == 0 then
        airui.label({
            parent = ui.list_box,
            text = empty_tip(dir),
            x = PAD, y = PAD, w = list_w - PAD * 2, h = 70,
            font_size = 14, color = COL_SUB,
        })
    end

    for i = 1, math.min(#files, max_items) do
        local f = files[i]
        local btn = airui.button({
            parent = ui.list_box,
            x = PAD, y = PAD + (i - 1) * ITEM_H, w = list_w - PAD * 2, h = ITEM_H - 6,
            text = short_name(f.name),
            font_size = 16,
            style = {
                bg_color = COL_ITEM,
                text_color = COL_TEXT,
                radius = 6,
            },
            on_click = make_item_click(i),
        })
        item_btns[i] = btn
    end

    -- 标题栏右侧显示文件数量（带上当前目录，方便一眼看出看的是哪）
    if ui.count_label then
        local where = "全部目录"
        if dir == "/luadb" then
            where = "内置存储"
        elseif dir == "/sd" then
            where = "TF 卡"
        end
        ui.count_label:set_text(where .. "   " .. #files .. " 个文件")
    end

    log.info("hzv_ui", "文件列表刷新完成", #files, "个", "目录", dir or "全部")
end

--[[
给按钮换底色；
@summary 单独抽成具名函数，便于 pcall 调用（set_style 在老固件上不存在）
@param userdata btn 按钮对象
@param number color 背景色
@return nil
]]
local function set_btn_bg(btn, color)
    btn:set_style({
        bg_color = color,
    })
end

--[[
刷新列表项高亮；
@summary 正在播放的那一项换成深蓝底色，其它项恢复常规底色
@param number index 选中的序号，0 表示全部恢复
@return nil
]]
local function highlight(index)
    for i, btn in ipairs(item_btns) do
        -- set_style 是 V1.1.0 之后新增的接口，老固件没有就跳过（不影响播放）
        pcall(set_btn_bg, btn, (i == index) and COL_ITEM_SEL or COL_ITEM)
    end
end

--[[
刷新目录切换按钮的选中态；
@param string dir 当前选中的目录
@return nil
]]
local function refresh_dir_buttons(dir)
    for key, btn in pairs(dir_btns) do
        local color = (key == dir) and COL_ITEM_SEL or COL_ITEM
        -- set_style 是 AirUI V1.1.0 之后才有的接口，老固件上失败就跳过（不影响功能）
        pcall(set_btn_bg, btn, color)
    end
end

--[[
判断某个素材目录当前是否可用（TF 卡可能没插）；
@param string dir 目录路径
@return boolean 可用返回 true
]]
local function dir_ready(dir)
    for _, src in ipairs(hzv_player.sources()) do
        if src.dir == dir then
            return src.ready
        end
    end
    return true
end

--[[
挑选上电默认浏览的目录；
@summary TF 卡可用且卡里有 .hzv 就用 TF 卡（和扫描优先级一致），否则用内置存储；
          这样界面一进来目录按钮就有明确选中态，不会两个都不亮
@return string 目录路径
]]
local function pick_default_dir()
    if dir_ready("/sd") and #hzv_player.scan("/sd") > 0 then
        return "/sd"
    end
    return "/luadb"
end

--[[
切换左侧列表浏览的目录；
@param string dir 目录路径，nil 表示全部目录
@return nil
]]
local function switch_dir(dir)
    cur_dir = dir
    log.info("hzv_ui", "切换素材目录", dir or "全部")

    -- 先刷按钮选中态再重建列表，切换过程不会出现"按钮旧、列表新"
    refresh_dir_buttons(dir)
    rebuild_list(dir)

    -- 新列表里如果有正在播放的那个文件，把高亮补上（播放本身不受切换影响）
    local playing_path = hzv_player.current()
    if playing_path then
        for i, f in ipairs(files) do
            if f.path == playing_path then
                cur_index = i
                highlight(i)
                break
            end
        end
    end

    if ui.status then
        if not dir_ready(dir) then
            ui.status:set_text("TF 卡未挂载，插卡后点“刷新”")
        elseif #files == 0 then
            ui.status:set_text("该目录下没有 .hzv 文件")
        else
            ui.status:set_text("已切换目录，点左侧文件开始播放")
        end
    end
end

--[[
生成目录切换按钮的点击回调；
@summary 用具名内部函数包装目录参数，避免在组件参数里写匿名函数
@param string dir 目录路径
@return function 点击回调
]]
local function make_dir_click(dir)
    local function on_click()
        switch_dir(dir)
    end
    return on_click
end

--[[
创建左侧顶部的目录切换栏（内置存储 / TF 卡）；
@return nil
]]
local function build_dir_bar()
    local list_x = PAD
    local list_y = HEADER_H + PAD
    local list_w = math.floor(ui.screen_w * 0.30)

    ui.dir_bar = airui.container({
        parent = ui.bg,
        x = list_x, y = list_y, w = list_w, h = DIR_BAR_H,
        color = COL_PANEL,
    })

    -- 两个按钮平分宽度：左边"内置存储"（/luadb），右边"TF 卡"（/sd）
    -- sources() 的返回顺序由 SOURCE_DIRS 固定，所以按下标算 x 即可
    local btn_w = math.floor((list_w - PAD * 3) / 2)
    dir_btns = {}
    local index = 0
    for _, src in ipairs(hzv_player.sources()) do
        dir_btns[src.dir] = airui.button({
            parent = ui.dir_bar,
            x = PAD + index * (btn_w + PAD), y = PAD,
            w = btn_w, h = DIR_BAR_H - PAD * 2,
            text = src.label,
            font_size = 15,
            style = { bg_color = COL_ITEM, text_color = COL_TEXT, radius = 6 },
            on_click = make_dir_click(src.dir),
        })
        index = index + 1
    end
    refresh_dir_buttons(cur_dir)
end

--[[
选中并播放第 index 个文件；

@api hzv_ui.select(index)
@summary 打开对应素材、刷新高亮与状态栏
@param number index 文件在列表中的序号
@return nil
]]
function M.select(index)
    local f = files[index]
    if not f then
        return
    end

    log.info("hzv_ui", "选中素材", f.name, f.path)
    -- 全屏状态下换片也要用整屏区域，否则画面会突然缩回右侧小块
    local rect = fullscreen and ui.full_rect or ui.video_rect
    if not hzv_player.open(f.path, rect) then
        if ui.status then
            ui.status:set_text("打开失败：" .. f.name)
        end
        return
    end

    cur_index = index
    highlight(index)
    -- 重置 fps 采样基准，避免换片后拿旧帧数算出跳变的帧率
    ui.last_frames = nil
    ui.last_tick = nil
    ui.status:set_text(f.name .. " · 播放中")
end

--[[
创建一个工具栏按钮；

@api hzv_ui.make_button(index, text, on_click)
@summary 统一工具栏按钮的宽度、间距和配色，按钮按 index 从左往右排
@param number index 第几个按钮（从 0 开始）
@param string text 按钮文字
@param function on_click 点击回调
@return userdata 按钮对象
]]
local function make_button(index, text, on_click)
    return airui.button({
        parent = ui.footer,
        x = PAD * 2 + index * (BTN_W + PAD), y = math.floor((FOOTER_H - BTN_H) / 2),
        w = BTN_W, h = BTN_H,
        text = text, font_size = 16,
        style = { bg_color = COL_ITEM, text_color = COL_TEXT, radius = 6 },
        on_click = on_click,
    })
end

--[[
刷新音量显示（点音量按钮后立即更新状态栏，不用等下一秒的定时刷新）；

@api hzv_ui.on_volume(step)
@summary 音量加减，并把结果打到日志和状态栏
@param number step 正数加、负数减
@return nil
]]
local function on_volume(step)
    local vol = hzv_player.volume_step(step)
    log.info("hzv_ui", "音量调整", step > 0 and "+" .. step or step, "当前", vol)
    update_status()
end

--[[
底部工具栏按钮的点击回调（具名函数，避免匿名函数字面量）；
@return nil
]]
local function on_play_click()
    hzv_player.play()
end

local function on_pause_click()
    hzv_player.pause()
end

local function on_stop_click()
    hzv_player.stop()
end

local function on_vol_down_click()
    on_volume(-VOL_STEP)
end

local function on_vol_up_click()
    on_volume(VOL_STEP)
end

-- 刷新：重扫当前选中的目录，插拔卡后点一下就能看到新文件
local function on_refresh_click()
    rebuild_list(cur_dir)
    log.info("hzv_ui", "列表已刷新", "目录", cur_dir or "全部")
end

-- ########## 全屏播放 ##########

--[[
容器显隐（具名函数，供 pcall 调用）；
@param userdata obj 容器对象
@param boolean hidden 是否隐藏
@return nil
]]
local function container_set_hidden(obj, hidden)
    obj:set_hidden(hidden)
end

--[[
销毁容器（具名函数，供 pcall 调用）；
@param userdata obj 容器对象
@return nil
]]
local function container_destroy(obj)
    obj:destroy()
end

--[[
隐藏/显示界面各栏（标题栏、目录栏、文件列表、工具栏）；
@param boolean hidden 是否隐藏
@return nil
]]
local function set_ui_hidden(hidden)
    local bars = { ui.header, ui.dir_bar, ui.list_box, ui.footer }
    for _, bar in ipairs(bars) do
        if bar then
            -- 老固件没有容器 set_hidden 时只是栏位不消失，不影响播放
            pcall(container_set_hidden, bar, hidden)
        end
    end
end

--[[
创建任意父容器下的按钮（工具栏与全屏控制栏共用）；
@param userdata parent 父容器
@param number x,y,w,h 位置与尺寸
@param string text 按钮文字
@param function on_click 点击回调
@return userdata 按钮对象
]]
local function make_ctrl_button(parent, x, y, w, h, text, on_click)
    return airui.button({
        parent = parent,
        x = x, y = y, w = w, h = h,
        text = text, font_size = 16,
        style = { bg_color = COL_ITEM, text_color = COL_TEXT, radius = 6 },
        on_click = on_click,
    })
end

--[[
退出全屏：销毁浮动控制栏、恢复界面各栏、视频退回右侧播放区；
@summary 前置到控制栏之前定义，控制栏的"退出全屏"按钮要用它
@return nil
]]
local function exit_fullscreen()
    if not fullscreen then
        return
    end

    local path = hzv_player.current()
    fullscreen = false

    if ui.fs_bar then
        pcall(container_destroy, ui.fs_bar)
        ui.fs_bar = nil
    end
    ui.fs_status = nil

    set_ui_hidden(false)
    if path then
        hzv_player.open(path, ui.video_rect)
    end
    update_status()
    log.info("hzv_ui", "退出全屏播放")
end

--[[
生成"退出全屏"按钮的点击回调（具名内部函数，避免匿名函数字面量）；
@return function 点击回调
]]
local function make_exit_click()
    local function on_click()
        exit_fullscreen()
    end
    return on_click
end

--[[
全屏模式下底部的浮动控制栏（播放 / 暂停 / 退出全屏 + 状态文字）；
@summary 必须在视频创建之后调用，同父对象里后建的控件才压得住画面
@return nil
]]
local function build_fs_bar()
    local bar_w = BTN_W * 3 + FS_LABEL_W + PAD * 5
    local bar_h = FS_BAR_H
    local bx = math.floor((ui.screen_w - bar_w) / 2)
    local by = ui.screen_h - bar_h - PAD

    ui.fs_bar = airui.container({
        parent = ui.bg,
        x = bx, y = by, w = bar_w, h = bar_h,
        color = COL_PANEL,
    })

    local btn_y = math.floor((bar_h - BTN_H) / 2)
    make_ctrl_button(ui.fs_bar, PAD, btn_y, BTN_W, BTN_H, "播放", on_play_click)
    make_ctrl_button(ui.fs_bar, PAD * 2 + BTN_W, btn_y, BTN_W, BTN_H, "暂停", on_pause_click)
    make_ctrl_button(ui.fs_bar, PAD * 3 + BTN_W * 2, btn_y, BTN_W, BTN_H, "退出全屏", make_exit_click())

    ui.fs_status = airui.label({
        parent = ui.fs_bar,
        text = "全屏播放中",
        x = PAD * 4 + BTN_W * 3,
        y = math.floor((bar_h - 22) / 2),
        w = FS_LABEL_W - PAD, h = 22,
        font_size = 14, color = COL_SUB,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 建完立刻写一次统计，不用等下一秒的定时刷新
    update_status()
end

--[[
进入全屏：隐藏界面各栏，视频改到整屏区域居中播放，底部浮出控制栏；
@return nil
]]
local function enter_fullscreen()
    if fullscreen then
        return
    end

    local path = hzv_player.current()
    if not path then
        set_status_text("先点左侧文件开始播放，再进全屏")
        return
    end

    fullscreen = true
    set_ui_hidden(true)

    -- 注意：airui.video 不支持缩放，这里只是把"可用播放区域"从右侧小块换成整屏，
    -- 视频仍按素材原始分辨率在整屏内居中
    if not hzv_player.open(path, ui.full_rect) then
        -- 打开失败必须退回窗口态，否则界面全空、用户没法操作
        set_ui_hidden(false)
        fullscreen = false
        set_status_text("全屏播放失败")
        return
    end

    build_fs_bar()
    log.info("hzv_ui", "进入全屏播放", path,
        "屏幕", ui.screen_w .. "x" .. ui.screen_h)
end

--[[
切换全屏状态；
@return nil
]]
local function toggle_fullscreen()
    if fullscreen then
        exit_fullscreen()
    else
        enter_fullscreen()
    end
end

-- 底部工具栏"全屏"按钮
local function on_fullscreen_click()
    toggle_fullscreen()
end

--[[
创建界面主体；

@api hzv_ui.build()
@summary 按屏幕分辨率计算布局，创建标题栏、目录切换栏、文件列表、播放区、工具栏与状态栏
@return nil
]]
local function build()
    ui.screen_w, ui.screen_h = lcd_app.get_size()

    -- 背景（AirUI 的屏幕根对象，所有组件都挂在它下面）
    ui.bg = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = ui.screen_w, h = ui.screen_h,
        color = COL_BG,
    })

    -- ########## 顶部标题栏 ##########
    ui.header = airui.container({
        parent = ui.bg,
        x = 0, y = 0, w = ui.screen_w, h = HEADER_H,
        color = COL_PANEL,
    })

    airui.label({
        parent = ui.header,
        text = "HZV 视频库",
        x = PAD * 2, y = 14, w = 260, h = 28,
        font_size = 22, color = COL_TEXT,
    })

    ui.count_label = airui.label({
        parent = ui.header,
        text = "扫描中...",
        x = ui.screen_w - 260, y = 18, w = 240, h = 22,
        font_size = 14, color = COL_SUB,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- ########## 左侧目录切换栏（内置存储 / TF 卡）##########
    -- 上电默认落在"有素材的那个目录"上，目录按钮才有明确选中态
    if not cur_dir then
        cur_dir = pick_default_dir()
        log.info("hzv_ui", "默认浏览目录", cur_dir)
    end
    build_dir_bar()

    -- ########## 播放区（列表在 rebuild_list 里创建）##########
    local list_w = math.floor(ui.screen_w * 0.30)
    ui.video_rect = {
        -- parent 交给 hzv_player，保证视频挂在界面背景层而不是另建一个屏幕
        parent = ui.bg,
        x = list_w + PAD * 2,
        y = HEADER_H + PAD,
        w = ui.screen_w - list_w - PAD * 3,
        h = ui.screen_h - HEADER_H - FOOTER_H - PAD * 2,
    }

    -- 全屏播放区域：整屏（视频仍按素材原始分辨率在这里居中，不做缩放）
    ui.full_rect = {
        parent = ui.bg,
        x = 0, y = 0, w = ui.screen_w, h = ui.screen_h,
    }

    -- ########## 底部工具栏 ##########
    ui.footer = airui.container({
        parent = ui.bg,
        x = 0, y = ui.screen_h - FOOTER_H, w = ui.screen_w, h = FOOTER_H,
        color = COL_PANEL,
    })

    -- 七个按钮从左到右：播放 / 暂停 / 停止 / 音量- / 音量+ / 刷新 / 全屏
    make_button(0, "播放", on_play_click)
    make_button(1, "暂停", on_pause_click)
    make_button(2, "停止", on_stop_click)
    make_button(3, "音量-", on_vol_down_click)
    make_button(4, "音量+", on_vol_up_click)
    make_button(5, "刷新", on_refresh_click)
    make_button(6, "全屏", on_fullscreen_click)

    -- 状态栏放在按钮右边，右对齐显示 fps / 丢帧 / 音画差 / 音量
    local status_x = PAD * 2 + 7 * (BTN_W + PAD)
    ui.status = airui.label({
        parent = ui.footer,
        text = "就绪",
        x = status_x, y = math.floor((FOOTER_H - 22) / 2),
        w = ui.screen_w - status_x - PAD * 2, h = 22,
        font_size = 14, color = COL_SUB,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 列表放在最后创建，保证不被播放区盖住
    rebuild_list(cur_dir)
end

--[[
启动选片界面；

@api hzv_ui.start()
@summary 初始化触摸并创建界面，同时启动状态刷新任务
@return boolean 界面创建成功返回 true；无触摸配置或初始化失败返回 false

@usage
if not hzv_ui.start() then
    hzv_player.start_auto()   -- 没触摸就退回自动演示
end
]]
function M.start()
    -- 没有触摸配置的板型直接返回，交给 main.lua 走自动演示
    if not hzv_hw.has_tp() then
        return false
    end

    if not init_touch() then
        return false
    end

    -- 注意：早期 AirUI 没有导出 airui.screen（父对象传 nil 时组件默认挂到当前屏），
    -- 所以这里只检查 AirUI 库本身在不在，不要用 airui.screen 判断初始化成功与否
    if not airui or not airui.container then
        log.error("hzv_ui", "AirUI 未初始化，无法创建界面")
        return false
    end

    local ok, err = pcall(build)
    if not ok then
        log.error("hzv_ui", "创建界面失败", err)
        return false
    end
    log.info("hzv_ui", "选片界面创建完成", ui.screen_w .. "x" .. ui.screen_h)

    -- 有素材就先播第一个，省得用户还要点一下（先播再起状态任务，状态栏不会闪"未播放"）
    -- scan() 已把默认素材 dont_sick.hzv 排到第一位，所以这里选中它就是默认播放它
    if #files > 0 then
        M.select(1)
    end

    -- 状态刷新任务：每秒更新一次 fps / 丢帧 / 音画差 / 音量
    sys.taskInit(status_task)

    return true
end

--[[
销毁界面（可选接口）；

@api hzv_ui.close()
@summary 销毁所有界面组件并停止播放，需要切换到别的界面时调用
@return nil
]]
function M.close()
    hzv_player.destroy()
    if ui.bg then
        ui.bg:destroy()
    end
    ui = {}
    item_btns = {}
    dir_btns = {}
    files = {}
    cur_index = 0
    cur_dir = nil
    fullscreen = false
end

return M
