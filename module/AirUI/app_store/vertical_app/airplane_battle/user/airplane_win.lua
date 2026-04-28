--[[
飞机大战应用市场页面模块。

这个文件不再承担 LCD、TP、AirUI 的宿主初始化职责，而是把自己实现成一个可被应用市场打开和关闭的窗口：
1. 根入口 main.lua 只负责 require 本模块并发布打开消息；
2. 本模块通过 exwin.open 管理 on_create / on_destroy 生命周期；
3. 游戏主循环和触摸订阅只在窗口存活时存在，窗口关闭后会一并清理。
]]

--[[
推荐阅读顺序：
1. 先看全局状态区，理解 runtime_display、layout、game、touch 分别缓存什么；
2. 再看缩放、边界、对象池与坐标映射这几组基础函数；
3. 然后看 set_state、reset_round、move_player_to、spawn_enemy、check_collisions 等核心玩法逻辑；
4. 最后看 build_ui、register_touch_handler 和 on_create / on_destroy，串起窗口生命周期。
]]

-- 这一组句柄对应窗口级资源。
-- win_id 用于主动关闭窗口，main_container 是挂在 airui.screen 下的根容器，game_timer_id 保存主循环定时器句柄。
local win_id = nil
local main_container = nil
local game_timer_id = nil

-- 这批 base_* 常量是设计稿级别的基准尺寸。
-- 后续 rebuild_layout 会根据当前逻辑分辨率和横竖屏状态，把这些值映射成运行时布局参数。
local base_width = 480
local base_height = 800
local base_hud_padding = 16
local base_overlay_width = 360
local base_primary_button_width = 220
local base_player_width = 48
local base_player_height = 56
local base_player_bottom_margin = 24

-- runtime_display 保存“显示驱动真实参数”和“窗口逻辑视图参数”的映射结果。
-- raw_* 来自 lcd.getSize，logical_* 会结合 airui rotation 做宽高互换，供布局与触摸映射统一使用。
local runtime_display = {
    rotation = 0,
    raw_width = base_width,
    raw_height = base_height,
    logical_width = base_width,
    logical_height = base_height,
    is_landscape = false
}

-- 这一组参数控制战斗节奏、对象池规模和资源路径。
-- 其中 tick_ms 是主循环步进粒度，bullet_interval 和 enemy_interval_* 共同决定自动开火与刷怪节奏。
local tick_ms = 33
local bullet_interval = 250
local enemy_interval_min = 200
local enemy_interval_max = 1000
local max_bullets = 8
local max_enemies = 8
local diagonal_enemy_chance = 35
local base_enemy_side_speed_min = 2
local base_enemy_side_speed_max = 4
local player_sprite_path = "/luadb/player.png"
local enemy_sprite_path = "/luadb/enemy.png"
local bullet_sprite_path = "/luadb/bullet.png"
local theme_page_bg = 0xf6f8fc
local theme_surface = 0xffffff
local theme_surface_alt = 0xeaf2ff
local theme_playfield_bg = 0xf1f7ff
local theme_playfield_border = 0xcad8ea
local theme_text_primary = 0x25364d
local theme_text_secondary = 0x667a96
local theme_text_muted = 0x91a4bc
local theme_accent = 0x3b82f6
local theme_accent_soft = 0xdcebff
local theme_success = 0x0f766e
local theme_warning = 0xd95b72
local theme_warning_soft = 0xffe6eb
local theme_border = 0xd9e3ef
local theme_border_strong = 0xb8cadf
local theme_bullet = 0xffa23a
local theme_bullet_border = 0xe0861f
local theme_player_fallback = 0x4a90ff
local theme_player_fallback_border = 0xbdd7ff
local theme_enemy_fallback = 0xff7f8e
local theme_enemy_fallback_border = 0xffc4cf

-- ui 统一缓存跨函数访问的 AirUI 对象引用。
-- HUD 文本、按钮、开始页/暂停页/结束页、无敌开关等组件都会挂在这里，方便逻辑层直接刷新界面。
local ui = {}

-- layout 是当前屏幕条件下的布局推导结果缓存。
-- 它既保存根页面尺寸，也保存 HUD、覆盖层、按钮、玩家活动区和对象尺寸等运行时几何信息。
local layout = {
    width = base_width,
    height = base_height,
    hud_height = 88,
    playfield_height = base_height - 88,
    hud_padding = base_hud_padding,
    overlay_width = base_overlay_width,
    overlay_x = math.floor((base_width - base_overlay_width) / 2),
    primary_button_width = base_primary_button_width,
    primary_button_x = math.floor((base_width - base_primary_button_width) / 2),
    player_min_y = math.floor((base_height - 88) * 0.42),
    player_bottom_margin = base_player_bottom_margin
}

-- game 是整局游戏的运行时数据中心。
-- 真正的字段会在 reset_runtime_state 中统一重建，这里先保留一个占位表，便于后续所有函数共享引用名。
local game = {}

-- touch 保存一次拖拽会话的上下文。
-- track_id 用于在支持多点触控的环境里锁定当前这次拖拽，offset_* 用于消除“按住飞机边缘时突然跳中心”的问题。
local touch = {}

-- 切换无敌 UI 时，需要防止程序性更新反向触发 on_change 回调。
-- 这个标记只在同步 switch 状态的短暂窗口内置为 true。
local invincible_ui_syncing = false

-- 对象池实体在隐藏时不会停到负坐标，而是停放在父容器内部的安全角落。
-- 这样可以尽量避免底层容器把越界对象算入内容范围，影响触摸和滚动判断。
local entity_park_margin = 2

-- 从驱动、布局或外部状态读取尺寸时统一做兜底。
-- 只要值不存在或非正数，就回退到调用方提供的默认值。
local function display_value(value, fallback)
    if value and value > 0 then
        return value
    end
    return fallback
end

-- 用设计稿默认值初始化 layout 的基础字段。
-- 这个阶段只建立“最小可用布局”，更细的横竖屏差异和缩放参数会在 rebuild_layout 里补齐。
local function init_layout_state(view_width, view_height)
    layout.width = display_value(view_width, base_width)
    layout.height = display_value(view_height, base_height)
    layout.hud_height = 88
    layout.playfield_height = layout.height - layout.hud_height
    layout.hud_padding = base_hud_padding
    layout.overlay_width = base_overlay_width
    layout.overlay_x = math.floor((layout.width - layout.overlay_width) / 2)
    layout.primary_button_width = base_primary_button_width
    layout.primary_button_x = math.floor((layout.width - layout.primary_button_width) / 2)
    layout.player_min_y = math.floor(layout.playfield_height * 0.42)
    layout.player_bottom_margin = base_player_bottom_margin
end

-- 读取当前显示设备的原始尺寸和 AirUI 旋转角度，并换算出窗口真正使用的逻辑宽高。
-- 后续布局推导和触摸坐标补偿都依赖这里输出的 logical_* 与 rotation。
local function refresh_runtime_display()
    local raw_width = base_width
    local raw_height = base_height
    local rotation = 0

    if lcd and lcd.getSize then
        local w, h = lcd.getSize()
        if w and h and w > 0 and h > 0 then
            raw_width = w
            raw_height = h
        end
    end

    if airui and airui.get_rotation then
        local current_rotation = airui.get_rotation()
        if type(current_rotation) == "number" then
            rotation = current_rotation % 360
            if rotation < 0 then
                rotation = rotation + 360
            end
        end
    end

    local logical_width = raw_width
    local logical_height = raw_height
    if rotation == 90 or rotation == 270 then
        logical_width = raw_height
        logical_height = raw_width
    end

    runtime_display.rotation = rotation
    runtime_display.raw_width = raw_width
    runtime_display.raw_height = raw_height
    runtime_display.logical_width = logical_width
    runtime_display.logical_height = logical_height
    runtime_display.is_landscape = logical_width > logical_height
end

-- 每次窗口创建时重建所有运行时状态。
-- 这里会清空旧 UI 引用、重置布局缓存、重新初始化战局表和触摸表，确保窗口重复打开时不残留上一局的数据。
local function reset_runtime_state()
    ui = {}
    layout = {}
    game = {
        state = "boot",
        invincible = false,
        score = 0,
        best_score = 0,
        elapsed = 0,
        fire_cd = 0,
        spawn_cd = 0,
        enemy_interval = enemy_interval_max,
        player = {
            x = 0,
            y = 0,
            w = base_player_width,
            h = base_player_height,
            ref = nil
        },
        bullets = {},
        enemies = {}
    }
    touch = {
        dragging = false,
        track_id = nil,
        offset_x = 0,
        offset_y = 0
    }

    init_layout_state(runtime_display.logical_width, runtime_display.logical_height)
end

-- 把一个数限制在给定区间内。
-- 布局缩放、实体移动和难度控制都会使用这个基础函数。
local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

-- 把比例计算后的浮点值稳定地落到整数像素。
-- 统一从这里四舍五入，可以减少布局推导时各处出现不同的取整方式。
local function round(value)
    return math.floor(value + 0.5)
end

-- 把设计稿里的横向尺寸映射到当前运行时宽度。
-- design_width 会随横竖屏切换，因此横屏下并不是简单地对 base_width 做缩放。
local function scale_w(value)
    local design_width = layout.design_width or base_width
    return round(value * (layout.width or base_width) / design_width)
end

-- 把设计稿里的纵向尺寸映射到当前运行时高度。
-- 和 scale_w 一样，它遵循 rebuild_layout 计算后的设计坐标系。
local function scale_h(value)
    local design_height = layout.design_height or base_height
    return round(value * (layout.height or base_height) / design_height)
end

-- 字号采用横纵缩放里更保守的一侧，并再做上下限约束。
-- 这样可以避免横屏大拉伸时字体过大，也避免极小分辨率下文本不可读。
local function scale_font(value)
    local design_width = layout.design_width or base_width
    local design_height = layout.design_height or base_height
    local view_width = layout.width or base_width
    local view_height = layout.height or base_height
    return clamp(round(value * math.min(view_width / design_width, view_height / design_height)), 14, 48)
end

-- 根据当前 logical size 与 rotation 重建整套布局参数。
-- 这里既负责 HUD、战场、覆盖层、按钮的几何推导，也负责把玩家、子弹、敌机的尺寸与速度换算到当前视图。
-- 它是整个脚本里最重要的预处理步骤之一，后续所有 UI 构建与碰撞边界都默认它已经执行过。
local function rebuild_layout()
    init_layout_state(runtime_display.logical_width, runtime_display.logical_height)

    local width = layout.width
    local height = layout.height

    layout.rotation = runtime_display.rotation or 0
    layout.is_landscape = runtime_display.is_landscape == true
    layout.design_width = layout.is_landscape and base_height or base_width
    layout.design_height = layout.is_landscape and base_width or base_height
    layout.scale_x = width / layout.design_width
    layout.scale_y = height / layout.design_height
    layout.font_scale = math.min(layout.scale_x, layout.scale_y)
    layout.page_padding = clamp(round(math.min(width, height) * 0.05), 16, 40)
    layout.section_gap = clamp(round(math.min(width, height) * 0.03), 10, 24)
    layout.overlay_padding = clamp(round(math.min(width, height) * 0.04), 16, 28)
    layout.decor_height = clamp(round(math.min(width, height) * 0.018), 10, 18)
    layout.playfield_top = 0

    if layout.is_landscape then
        layout.hud_padding = clamp(round(width * 0.022), 12, 22)
        layout.hud_height = clamp(round(height * 0.18), 64, 92)
        layout.playfield_height = height - layout.hud_height
        layout.playfield_top = layout.hud_height
        layout.hud_band_y = layout.hud_height - layout.decor_height
        layout.hud_band_h = layout.decor_height
        layout.hud_accent_x = layout.hud_padding
        layout.hud_accent_y = clamp(round(layout.hud_height * 0.16), 10, 16)
        layout.hud_accent_w = clamp(round(width * 0.006), 4, 8)
        layout.hud_accent_h = clamp(layout.hud_height - layout.hud_accent_y * 2, 34, 52)
        layout.hud_left_width = clamp(round(width * 0.24), 170, 240)
        layout.pause_button_width = clamp(round(width * 0.16), 104, 140)
        layout.pause_button_height = clamp(round(layout.hud_height * 0.58), 42, 56)
        layout.hud_title_y = clamp(round(layout.hud_height * 0.16), 10, 18)
        layout.hud_subtitle_y = clamp(round(layout.hud_height * 0.52), 38, 52)
        layout.hud_title_height = clamp(round(layout.hud_height * 0.26), 20, 30)
        layout.hud_subtitle_height = clamp(round(layout.hud_height * 0.22), 18, 26)

        layout.overlay_width = math.min(width - layout.page_padding * 2, clamp(round(width * 0.66), 420, 560))
        layout.overlay_x = math.floor((width - layout.overlay_width) / 2)
        layout.primary_button_width = math.min(layout.overlay_width - layout.overlay_padding * 2, clamp(round(width * 0.30), 200, 260))
        layout.primary_button_x = math.floor((width - layout.primary_button_width) / 2)

        layout.start_card_w = layout.overlay_width
        layout.start_card_x = math.floor((width - layout.start_card_w) / 2)
        layout.start_card_y = clamp(round(height * 0.08), 36, 56)
        layout.start_card_h = clamp(round(height * 0.46), 196, 244)
        layout.start_decor_x = layout.start_card_x + layout.overlay_padding
        layout.start_decor_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.12), 18, 28)
        layout.start_decor_w = clamp(round(layout.start_card_w * 0.18), 72, 128)
        layout.start_decor_h = clamp(round(height * 0.02), 8, 14)
        layout.start_title_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.18), 32, 48)
        layout.start_subtitle_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.42), 82, 110)
        layout.start_caption_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.68), 136, 166)
        layout.start_button_y = layout.start_card_y + layout.start_card_h + layout.section_gap
        layout.start_button_h = clamp(round(height * 0.11), 48, 60)
        layout.start_secondary_button_y = layout.start_button_y + layout.start_button_h + layout.section_gap
        layout.start_hint_y = math.min(height - scale_h(24) - 12, layout.start_secondary_button_y + layout.start_button_h + layout.section_gap)

        layout.pause_page_h = clamp(round(height * 0.82), 360, 420)
        layout.pause_page_y = math.max(18, math.floor((height - layout.pause_page_h) / 2))
        layout.gameover_page_h = clamp(round(height * 0.82), 360, 420)
        layout.gameover_page_y = math.max(12, math.floor((height - layout.gameover_page_h) / 2))
        layout.overlay_header_h = clamp(round(height * 0.03), 14, 22)
        layout.overlay_button_h = clamp(round(height * 0.11), 44, 56)
        layout.playfield_guard_left = clamp(round(width * 0.02), 10, 18)
        layout.playfield_guard_right = layout.playfield_guard_left
        layout.playfield_guard_top = clamp(round(layout.playfield_height * 0.03), 10, 18)
        layout.playfield_guard_bottom = layout.playfield_guard_top
        layout.player_active_min_y = math.floor(layout.playfield_height * 0.28)
    else
        layout.hud_padding = clamp(round(width * 0.035), 12, 28)
        layout.hud_height = clamp(round(height * 0.11), 72, 118)
        layout.playfield_height = height - layout.hud_height
        layout.playfield_top = layout.hud_height
        layout.hud_band_y = layout.hud_height - layout.decor_height
        layout.hud_band_h = layout.decor_height
        layout.hud_accent_x = layout.hud_padding
        layout.hud_accent_y = clamp(round(layout.hud_height * 0.16), 10, 18)
        layout.hud_accent_w = clamp(round(width * 0.008), 4, 8)
        layout.hud_accent_h = clamp(layout.hud_height - layout.hud_accent_y * 2, 36, 56)
        layout.hud_left_width = math.max(140, math.floor(width * 0.33))
        layout.pause_button_width = clamp(round(width * 0.19), 84, 132)
        layout.pause_button_height = clamp(round(layout.hud_height * 0.55), 42, 58)
        layout.hud_title_y = clamp(round(layout.hud_height * 0.14), 10, 18)
        layout.hud_subtitle_y = clamp(round(layout.hud_height * 0.48), 40, 52)
        layout.hud_title_height = clamp(round(layout.hud_height * 0.28), 20, 30)
        layout.hud_subtitle_height = clamp(round(layout.hud_height * 0.24), 18, 26)

        layout.overlay_width = math.min(width - layout.page_padding * 2, clamp(round(width * 0.76), 300, 440))
        layout.overlay_x = math.floor((width - layout.overlay_width) / 2)
        layout.primary_button_width = math.min(layout.overlay_width - layout.overlay_padding * 2, clamp(round(width * 0.46), 190, 300))
        layout.primary_button_x = math.floor((width - layout.primary_button_width) / 2)

        layout.start_card_x = layout.page_padding
        layout.start_card_y = clamp(round(height * 0.15), 108, 180)
        layout.start_card_w = width - layout.page_padding * 2
        layout.start_card_h = clamp(round(height * 0.36), 286, 380)
        layout.start_decor_x = layout.start_card_x + layout.page_padding
        layout.start_decor_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.09), 20, 36)
        layout.start_decor_w = clamp(round(layout.start_card_w * 0.24), 72, 128)
        layout.start_decor_h = clamp(round(height * 0.012), 8, 14)
        layout.start_title_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.16), 44, 72)
        layout.start_subtitle_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.42), 118, 160)
        layout.start_caption_y = layout.start_card_y + clamp(round(layout.start_card_h * 0.72), 202, 268)
        layout.start_button_y = layout.start_card_y + layout.start_card_h + layout.section_gap + 12
        layout.start_button_h = clamp(round(height * 0.08), 56, 72)
        layout.start_secondary_button_y = layout.start_button_y + layout.start_button_h + layout.section_gap
        layout.start_hint_y = math.min(height - 48, layout.start_secondary_button_y + layout.start_button_h + layout.section_gap + 8)

        layout.pause_page_y = clamp(round(height * 0.23), 160, 244)
        layout.pause_page_h = clamp(round(height * 0.48), 380, 500)
        layout.gameover_page_y = clamp(round(height * 0.22), 156, 244)
        layout.gameover_page_h = clamp(round(height * 0.5), 380, 500)
        layout.overlay_header_h = clamp(round(height * 0.02), 14, 20)
        layout.overlay_button_h = clamp(round(height * 0.068), 50, 60)
        layout.playfield_guard_left = clamp(round(width * 0.03), 12, 24)
        layout.playfield_guard_right = layout.playfield_guard_left
        layout.playfield_guard_top = clamp(round(height * 0.02), 12, 24)
        layout.playfield_guard_bottom = layout.playfield_guard_top
        layout.player_active_min_y = math.floor(layout.playfield_height * 0.42)
    end

    game.player.w = clamp(round(base_player_width * layout.scale_x), 40, 84)
    game.player.h = clamp(round(base_player_height * layout.scale_y), 44, 96)
    layout.player_bottom_margin = clamp(round(layout.playfield_height * 0.03), 18, 32)
    layout.player_min_y = layout.player_active_min_y

    layout.bullet_w = clamp(round(5 * layout.scale_x), 4, 10)
    layout.bullet_h = clamp(round(16 * layout.scale_y), 12, 28)
    layout.bullet_speed = clamp(round(24 * layout.font_scale), 18, 32)
    layout.enemy_width_base = clamp(round(34 * layout.scale_x), 30, 64)
    layout.enemy_width_step = clamp(round(8 * layout.scale_x), 6, 14)
    layout.enemy_height_base = clamp(round(28 * layout.scale_y), 24, 52)
    layout.enemy_height_step = clamp(round(10 * layout.scale_y), 8, 18)
    layout.enemy_speed_base = clamp(round(6 * layout.font_scale), 5, 10)
    layout.enemy_speed_step = 1
    layout.enemy_side_speed_min = clamp(round(base_enemy_side_speed_min * layout.scale_x), 1, 5)
    layout.enemy_side_speed_max = math.max(layout.enemy_side_speed_min, clamp(round(base_enemy_side_speed_max * layout.scale_x), 2, 7))
end

-- 生成闭区间随机整数。
-- 敌机出生位置和斜飞横向速度都会复用这个工具函数。
local function random_between(minimum, maximum)
    if maximum <= minimum then
        return minimum
    end
    return minimum + math.random(maximum - minimum)
end

-- 随机返回 -1 或 1，给斜飞敌机决定左右方向。
local function random_sign()
    if math.random(0, 1) == 0 then
        return -1
    end
    return 1
end

-- 安全更新 label 文本，避免 UI 还未创建时直接调用导致报错。
local function set_label_text(label, text)
    if label then
        label:set_text(text)
    end
end

-- 统一切换覆盖层容器的显隐状态。
-- 开始页、暂停页、结束页都走这一层，而实体对象则使用单独的显隐逻辑。
local function set_hidden(component, hidden)
    if component then
        component:set_hidden(hidden)
    end
end

-- 对支持 set_text 的组件做统一安全赋值。
-- 无敌开关在 switch 不可用时会退回 button，因此这里不能假设所有控件类型都一致。
local function set_component_text(component, text)
    if component and component.set_text then
        component:set_text(text)
    end
end

-- 程序性同步 switch 状态时，先比较当前值并短暂开启保护标记。
-- 这样 refresh_invincible_ui 在更新 UI 时不会再次触发用户交互回调，形成递归刷新。
local function set_switch_state(component, checked)
    if not component or not component.set_state then
        return
    end

    local current_state = nil
    if component.get_state then
        current_state = component:get_state()
    end

    if current_state == checked then
        return
    end

    invincible_ui_syncing = true
    component:set_state(checked)
    invincible_ui_syncing = false
end

-- 把“无敌模式”同步到 HUD 与两个覆盖层入口。
-- 这个函数把逻辑状态翻译成文本、按钮文案和 switch 状态，是无敌模式的统一 UI 刷新入口。
local function refresh_invincible_ui()
    local enabled = game.invincible == true
    local hud_status_suffix = enabled and " INV" or ""

    set_component_text(ui.start_invincible_button, enabled and "已开" or "已关")
    set_component_text(ui.pause_invincible_button, enabled and "已开" or "已关")

    set_switch_state(ui.start_invincible_switch, enabled)
    set_switch_state(ui.pause_invincible_switch, enabled)

    if game.state == "running" then
        set_label_text(ui.status_label, "RUN" .. hud_status_suffix)
        set_label_text(ui.tip_label, enabled and "碰撞免疫" or "拖拽移动")
    elseif game.state == "paused" then
        set_label_text(ui.status_label, "PAUSE" .. hud_status_suffix)
        set_label_text(ui.tip_label, enabled and "无敌模式已开" or "拖拽移动")
    elseif game.state == "gameover" then
        set_label_text(ui.tip_label, "拖拽移动")
    else
        set_label_text(ui.status_label, "READY" .. hud_status_suffix)
        set_label_text(ui.tip_label, enabled and "无敌模式已开" or "拖拽移动")
    end
end

-- 创建带可选边框的纯色矩形容器。
-- 它既用于页面装饰，也作为图片资源不存在时的实体占位外观。
local function create_block(parent, x, y, w, h, color, border_color)
    local block = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = w,
        h = h,
        color = color
    })
    if border_color then
        block:set_border_color(border_color, 2)
    end
    return block
end

-- 解析实体图片路径。
-- 当前窗口版逻辑只接受显式传入的资源路径，不再像调试脚本那样额外尝试同目录文件名回退。
local function resolve_sprite_path(sprite_path)
    if not sprite_path then
        return nil
    end
    if io.exists(sprite_path) then
        return sprite_path
    end
    return nil
end

-- 创建一个“优先图片、失败退回色块”的实体外壳。
-- 后续玩家、子弹、敌机都只依赖 set_pos 与显隐接口，因此这里需要确保返回对象满足最基本的移动能力。
local function create_sprite_shell(parent, x, y, w, h, color, border_color, sprite_path, use_img)
    local resolved_path = resolve_sprite_path(sprite_path)
    if resolved_path and use_img then
        -- 这里需要确保img的set_pos存在，如果不存在，就退回到普通的块组件
        local img_obj = airui.image({
            parent = parent,
            src = resolved_path,
            x = x,
            y = y,
            w = w,
            h = h,
            opacity = 255
        })
        return img_obj
    end
    return create_block(parent, x, y, w, h, color, border_color)
end

-- 返回对象池实体的安全停放坐标。
-- 这里忽略实体本身尺寸，统一停在容器左上方的保护带里即可。
local function get_entity_parking_pos(_)
    return entity_park_margin, entity_park_margin
end

-- 统一实体显示状态。
-- 优先走 set_hidden，其次退回 opacity，以兼容不同类型的 AirUI 组件。
local function set_entity_ref_visible(entity, visible)
    if not entity.ref then
        return
    end
    if entity.render_visible == visible then
        return
    end
    if entity.ref.set_hidden then
        entity.ref:set_hidden(not visible)
    elseif entity.ref.set_opacity then
        entity.ref:set_opacity(visible and 255 or 0)
    end
    entity.render_visible = visible
end

-- 把实体的显示对象挪回停放点，但不直接修改它的逻辑 alive 状态。
local function park_entity_ref(entity)
    if entity.ref then
        local park_x, park_y = get_entity_parking_pos(entity)
        entity.ref:set_pos(park_x, park_y)
    end
end

-- 统一获取战场左边界。
-- 这个边界不只是“屏幕最左侧”，还承担给战场留出一点安全区的职责。
local function get_playfield_min_x()
    return layout.playfield_guard_left or 0
end

-- 根据实体宽度推导左上角可到达的最右位置。
local function get_playfield_max_x(entity_width)
    return math.max(get_playfield_min_x(), (layout.width or base_width) - entity_width - (layout.playfield_guard_right or 0))
end

-- 在统一横向边界内约束实体位置。
local function clamp_entity_x(value, entity_width)
    return clamp(value, get_playfield_min_x(), get_playfield_max_x(entity_width))
end

-- 统一获取战场顶部边界。
local function get_playfield_min_y()
    return layout.playfield_guard_top or 0
end

-- 根据实体高度推导纵向可放置的最大值。
local function get_playfield_max_y(entity_height)
    return math.max(get_playfield_min_y(), (layout.playfield_height or (layout.height or base_height)) - entity_height - (layout.playfield_guard_bottom or 0))
end

-- 在统一纵向边界内约束实体位置。
local function clamp_entity_y(value, entity_height)
    return clamp(value, get_playfield_min_y(), get_playfield_max_y(entity_height))
end

-- 玩家除了遵守统一战场边界，还会被限制在玩法定义的活动下半区。
local function get_player_min_y()
    return math.max(layout.player_active_min_y or layout.player_min_y or 0, get_playfield_min_y())
end

-- 玩家底部同样要同时满足玩法留白和统一战场 guard。
local function get_player_max_y()
    local player_bottom_limit = (layout.playfield_height or base_height) - game.player.h - (layout.player_bottom_margin or base_player_bottom_margin)
    return math.min(player_bottom_limit, get_playfield_max_y(game.player.h))
end

-- 当玩家已经顶到活动区上边界后，继续上推手指时只冻结 y 方向。
-- 这样既保留左右拖拽手感，也减少纵向手势继续向父容器传递的机会。
local function clamp_player_drag_screen_y(screen_y, anchor_y)
    local drag_anchor_y = anchor_y or math.floor(game.player.h / 2)
    local current_player_min_y = get_player_min_y()
    local player_top_screen_y = (layout.hud_height or 0) + current_player_min_y + drag_anchor_y

    if game.player.y <= current_player_min_y and screen_y < player_top_screen_y then
        return player_top_screen_y
    end

    return screen_y
end

-- 判定一个实体是否仍位于当前战场的可渲染逻辑区间内。
-- 对象池实体一旦离开这个区间，就会被停放并隐藏，而不是继续留在越界位置。
local function can_render_entity(entity)
    return entity.x >= get_playfield_min_x() and entity.x <= get_playfield_max_x(entity.w) and entity.y >= get_playfield_min_y() and entity.y <= get_playfield_max_y(entity.h)
end

-- 把实体逻辑状态同步到它对应的 UI 对象。
-- 对永久存在的玩家对象，alive 为 nil 时只更新位置；对子弹和敌机，则根据 alive 与可渲染性决定显示或停放。
local function sync_entity(entity)
    if not entity.ref then
        return
    end

    if entity.alive == nil then
        entity.ref:set_pos(entity.x, entity.y)
        return
    end

    if entity.alive and can_render_entity(entity) then
        entity.ref:set_pos(entity.x, entity.y)
        set_entity_ref_visible(entity, true)
    else
        park_entity_ref(entity)
        set_entity_ref_visible(entity, false)
    end
end

-- 让对象池实体失活并回收到安全停放区。
-- 这里不会销毁 UI 对象，只是重置逻辑坐标并隐藏，等待下次复用。
local function deactivate_entity(entity)
    entity.alive = false
    local park_x, park_y = get_entity_parking_pos(entity)
    entity.x = park_x
    entity.y = park_y
    park_entity_ref(entity)
    set_entity_ref_visible(entity, false)
end

-- 从对象池中重新激活一个实体，并写入它的主要运行参数。
local function activate_entity(entity, x, y, w, h, speed)
    entity.alive = true
    entity.x = x
    entity.y = y
    entity.w = w or entity.w
    entity.h = h or entity.h
    entity.speed = speed or entity.speed
    sync_entity(entity)
end

-- 基础矩形命中测试。
-- 触摸命中玩家、以及某些局部区域判定都依赖这个函数。
local function point_in_rect(point_x, point_y, rect_x, rect_y, rect_w, rect_h)
    return point_x >= rect_x and point_x < rect_x + rect_w and point_y >= rect_y and point_y < rect_y + rect_h
end

-- 把触摸驱动上报的原始坐标映射到当前窗口逻辑坐标系。
-- 由于 rotation 可能是 0/90/180/270，这里统一做旋转补偿，让后续拖拽逻辑只面对一套坐标。
local function remap_touch_point(raw_x, raw_y)
    local mapped_x = raw_x
    local mapped_y = raw_y
    local raw_w = display_value(runtime_display.raw_width, layout.width or base_width)
    local raw_h = display_value(runtime_display.raw_height, layout.height or base_height)

    if runtime_display.rotation == 90 then
        mapped_x = raw_h - raw_y - 1
        mapped_y = raw_x
    elseif runtime_display.rotation == 180 then
        mapped_x = raw_w - raw_x - 1
        mapped_y = raw_h - raw_y - 1
    elseif runtime_display.rotation == 270 then
        mapped_x = raw_y
        mapped_y = raw_w - raw_x - 1
    end

    mapped_x = clamp(mapped_x, 0, (layout.width or base_width) - 1)
    mapped_y = clamp(mapped_y, 0, (layout.height or base_height) - 1)
    return mapped_x, mapped_y
end

-- 触摸点使用整屏坐标，而玩家实体使用 playfield 局部坐标。
-- 这里要把 HUD 的顶部偏移补回来，才能正确判断手指是否命中飞机本体。
local function touch_hits_player(screen_x, screen_y)
    return point_in_rect(screen_x, screen_y, game.player.x, (layout.hud_height or 0) + game.player.y, game.player.w, game.player.h)
end

-- 结束本次拖拽会话并清理上下文。
local function reset_drag_state()
    touch.dragging = false
    touch.track_id = nil
    touch.offset_x = 0
    touch.offset_y = 0
end

-- 轴对齐矩形碰撞检测。
-- 玩家、敌机、子弹都是近似矩形，因此这里用 AABB 足够直接且高效。
local function aabb_hit(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- 根据当前战局状态刷新 HUD 文本与暂停按钮文案。
-- 状态文本和无敌模式提示最终都会统一收敛到这里与 refresh_invincible_ui。
local function update_hud()
    set_label_text(ui.score_label, string.format("SCORE %04d", game.score))
    set_label_text(ui.best_label, string.format("BEST %04d", game.best_score))
    if game.state == "running" then
        if ui.pause_btn then
            ui.pause_btn:set_text("暂停")
        end
    elseif game.state == "paused" then
        if ui.pause_btn then
            ui.pause_btn:set_text("继续")
        end
    elseif game.state == "gameover" then
        set_label_text(ui.status_label, "OVER")
        if ui.pause_btn then
            ui.pause_btn:set_text("暂停")
        end
    else
        if ui.pause_btn then
            ui.pause_btn:set_text("暂停")
        end
    end
    refresh_invincible_ui()
end

-- 把玩家放回默认出生位置。
-- 玩家始终水平居中，并停在战场下方预留出的安全底边之上。
local function center_player()
    game.player.x = math.floor(((layout.width or base_width) - game.player.w) / 2)
    game.player.y = (layout.playfield_height or base_height) - game.player.h - (layout.player_bottom_margin or base_player_bottom_margin)
    sync_entity(game.player)
end

-- 重置一局游戏的临时数据并清空对象池中的活动实体。
-- 这一步只重置战局，不会重建整棵 UI 树。
local function reset_round()
    game.score = 0
    game.elapsed = 0
    game.fire_cd = 0
    game.spawn_cd = 0
    game.enemy_interval = enemy_interval_max
    center_player()
    for _, bullet in ipairs(game.bullets) do
        deactivate_entity(bullet)
    end
    for _, enemy in ipairs(game.enemies) do
        deactivate_entity(enemy)
    end
    update_hud()
end

-- 控制三个覆盖层页面的显示关系。
-- 页面都采用预创建后切 hidden 的方式，而不是切状态时临时新建销毁。
local function show_page(page_name)
    set_hidden(ui.start_page, page_name ~= "start")
    set_hidden(ui.pause_page, page_name ~= "paused")
    set_hidden(ui.gameover_page, page_name ~= "gameover")
end

-- 统一状态机入口。
-- 这里负责切换页面、结束拖拽会话，并把 HUD 文本刷新到与当前状态一致。
local function set_state(next_state)
    game.state = next_state
    if next_state ~= "running" then
        reset_drag_state()
    end
    if next_state == "start" then
        show_page("start")
    elseif next_state == "paused" then
        show_page("paused")
    elseif next_state == "gameover" then
        show_page("gameover")
    else
        show_page(nil)
    end
    update_hud()
end

-- 从头开始一局新战斗。
local function start_game()
    reset_round()
    set_state("running")
end

-- 只允许 running -> paused 的单向切换。
local function pause_game()
    if game.state == "running" then
        set_state("paused")
    end
end

-- 从暂停恢复到运行，但不重置任何场上数据。
local function resume_game()
    if game.state == "paused" then
        set_state("running")
    end
end

-- 结算当前战局，更新最高分并切到结束页。
local function end_game()
    if game.score > game.best_score then
        game.best_score = game.score
    end
    set_label_text(ui.gameover_score, string.format("本局得分 %d", game.score))
    set_label_text(ui.gameover_best, string.format("最高分 %d", game.best_score))
    set_state("gameover")
end

-- HUD 顶部按钮统一通过这里在暂停和继续之间切换。
local function toggle_pause()
    if game.state == "running" then
        pause_game()
    elseif game.state == "paused" then
        resume_game()
    end
end

-- 主动关闭当前 exwin 窗口。
-- 关闭动作最终会触发 on_destroy，在那里统一回收资源。
local function close_window()
    if win_id then
        exwin.close(win_id)
    end
end

-- 修改无敌模式总开关，并立即同步全部相关 UI。
local function set_invincible_enabled(enabled)
    game.invincible = enabled == true
    update_hud()
end

-- 创建一个“无敌模式”开关区。
-- 如果当前 AirUI 提供 switch，就使用原生开关；否则退回按钮，保持功能可用但交互形式更简单。
local function create_invincible_toggle(parent, title_x, title_y, title_w, control_y, value_y, compact_layout, hide_value)
    airui.label({
        parent = parent,
        x = title_x,
        y = title_y,
        w = title_w,
        h = scale_h(hide_value and 30 or 24),
        text = "无敌模式",
        font_size = scale_font(18),
        color = theme_text_primary,
        align = compact_layout and airui.TEXT_ALIGN_LEFT or airui.TEXT_ALIGN_CENTER
    })

    local value_label = nil
    if not hide_value then
        value_label = airui.label({
            parent = parent,
            x = title_x,
            y = value_y,
            w = title_w,
            h = scale_h(24),
            text = "",
            font_size = scale_font(15),
            color = theme_text_secondary,
            align = compact_layout and airui.TEXT_ALIGN_LEFT or airui.TEXT_ALIGN_CENTER
        })
    end

    if airui and airui.switch then
        local switch_obj = nil
        switch_obj = airui.switch({
            parent = parent,
            x = compact_layout and (title_x + title_w - scale_w(70)) or (title_x + math.floor((title_w - scale_w(70)) / 2)),
            y = control_y,
            checked = game.invincible,
            on_change = function()
                if invincible_ui_syncing then
                    return
                end
                set_invincible_enabled(switch_obj:get_state())
            end
        })
        return value_label, switch_obj, nil
    end

    local button_w = compact_layout and clamp(round(title_w * 0.34), 112, 156) or clamp(round(title_w * 0.58), 132, 190)
    local button_h = clamp(round((layout.height or base_height) * 0.058), 42, 54)
    local toggle_button = nil
    toggle_button = airui.button({
        parent = parent,
        x = compact_layout and (title_x + title_w - button_w) or (title_x + math.floor((title_w - button_w) / 2)),
        y = control_y,
        w = button_w,
        h = button_h,
        color = theme_accent_soft,
        text = "",
        font_size = scale_font(18),
        text_color = theme_accent,
        on_click = function()
            set_invincible_enabled(not game.invincible)
        end
    })
    return value_label, nil, toggle_button
end

-- 根据触摸点更新玩家位置。
-- 这里会把整屏触摸坐标换算到战场内部坐标，并叠加玩家自身活动区限制，避免飞机被拖出合法区域。
local function move_player_to(screen_x, screen_y, anchor_x, anchor_y)
    if game.state ~= "running" then
        return
    end

    local drag_anchor_x = anchor_x or math.floor(game.player.w / 2)
    local drag_anchor_y = anchor_y or math.floor(game.player.h / 2)
    local local_x = clamp_entity_x(math.floor(screen_x - drag_anchor_x), game.player.w)
    local local_y = clamp_entity_y(math.floor(screen_y - (layout.hud_height or 0) - drag_anchor_y), game.player.h)
    local_y = clamp(local_y, get_player_min_y(), get_player_max_y())

    game.player.x = local_x
    game.player.y = local_y
    sync_entity(game.player)
end

-- 从子弹对象池里取出一个空闲子弹发射出去。
-- 发射点默认在玩家机身上沿附近，形成自动连发的视觉效果。
local function spawn_bullet()
    for _, bullet in ipairs(game.bullets) do
        if not bullet.alive then
            local bullet_x = game.player.x + math.floor(game.player.w / 2) - math.floor(bullet.w / 2)
            local bullet_y = game.player.y - bullet.h + 4
            activate_entity(bullet, bullet_x, bullet_y)
            return
        end
    end
end

-- 从敌机对象池里生成一架新敌机。
-- 敌机会依据当前分数获得速度加成，并按概率切换为直飞或斜飞模式。
local function spawn_enemy()
    for _, enemy in ipairs(game.enemies) do
        if not enemy.alive then
            local enemy_w = enemy.w
            local enemy_x = random_between(get_playfield_min_x(), get_playfield_max_x(enemy_w))
            local enemy_y = -enemy.h
            local difficulty_boost = math.floor(game.score / 80)
            local is_diagonal = math.random(100) <= diagonal_enemy_chance
            activate_entity(enemy, enemy_x, enemy_y, enemy.w, enemy.h, enemy.base_speed + difficulty_boost)
            enemy.flight_mode = is_diagonal and "diagonal" or "straight"
            if is_diagonal then
                enemy.vx = random_sign() * random_between(layout.enemy_side_speed_min, layout.enemy_side_speed_max)
            else
                enemy.vx = 0
            end
            return
        end
    end
end

-- 推进所有存活子弹的位置。
-- 子弹越过战场顶部后会直接回收到对象池。
local function update_bullets()
    for _, bullet in ipairs(game.bullets) do
        if bullet.alive then
            bullet.y = bullet.y - bullet.speed
            if bullet.y < get_playfield_min_y() - bullet.h then
                deactivate_entity(bullet)
            else
                sync_entity(bullet)
            end
        end
    end
end

-- 推进敌机位置，并处理斜飞模式的左右反弹。
-- 敌机越过战场底部后不再参与碰撞，而是直接失活回池。
local function update_enemies()
    for _, enemy in ipairs(game.enemies) do
        if enemy.alive then
            local min_x = get_playfield_min_x()
            local max_x = get_playfield_max_x(enemy.w)
            enemy.x = enemy.x + (enemy.vx or 0)
            enemy.y = enemy.y + enemy.speed

            if enemy.x <= min_x then
                enemy.x = min_x
                if enemy.flight_mode == "diagonal" then
                    enemy.vx = math.abs(enemy.vx or 0)
                end
            elseif enemy.x >= max_x then
                enemy.x = max_x
                if enemy.flight_mode == "diagonal" then
                    enemy.vx = -math.abs(enemy.vx or 0)
                end
            end

            if enemy.y > (layout.playfield_height or base_height) then
                deactivate_entity(enemy)
            else
                sync_entity(enemy)
            end
        end
    end
end

-- 根据分数逐步缩短刷怪间隔，让游戏节奏持续加快。
local function update_difficulty()
    local accelerated = enemy_interval_max - math.floor(game.score * 3)
    game.enemy_interval = clamp(accelerated, enemy_interval_min, enemy_interval_max)
end

-- 处理玩家与敌机、子弹与敌机两类碰撞。
-- 先检查玩家碰撞是因为它会直接结束战局；无敌模式开启时则只消灭敌机，不触发失败。
local function check_collisions()
    for _, enemy in ipairs(game.enemies) do
        if enemy.alive and can_render_entity(enemy) and aabb_hit(game.player, enemy) then
            deactivate_entity(enemy)
            if not game.invincible then
                end_game()
                return
            end
        end
    end

    for _, bullet in ipairs(game.bullets) do
        if bullet.alive and can_render_entity(bullet) then
            for _, enemy in ipairs(game.enemies) do
                if enemy.alive and can_render_entity(enemy) and aabb_hit(bullet, enemy) then
                    deactivate_entity(bullet)
                    deactivate_entity(enemy)
                    game.score = game.score + 10
                    if game.score > game.best_score then
                        game.best_score = game.score
                    end
                    update_difficulty()
                    update_hud()
                    break
                end
            end
        end
    end
end

-- 构建窗口内的整套 UI 结构与对象池。
-- 这里会按“根容器 -> 战场/HUD -> 玩家与对象池 -> 三个覆盖层页面”的顺序把所有组件一次性创建出来。
local function build_ui()
    -- 先根据 layout 计算本轮构建需要用到的局部坐标与尺寸。
    -- 这些值只服务当前 build_ui 执行，不需要长期写回 layout。
    local hud_left_x = layout.hud_padding + layout.hud_accent_w + scale_w(8)
    local hud_left_w = layout.hud_left_width
    local pause_button_x = layout.width - layout.hud_padding - layout.pause_button_width
    local status_x = hud_left_x + hud_left_w + scale_w(8)
    local status_w = pause_button_x - status_x - scale_w(8)
    local start_text_x = layout.start_card_x + layout.page_padding
    local start_text_w = layout.start_card_w - layout.page_padding * 2
    local start_toggle_x = start_text_x + scale_w(12)
    local start_toggle_w = start_text_w - scale_w(24)
    local start_toggle_title_y = layout.start_caption_y + scale_h(34)
    local start_toggle_control_y = start_toggle_title_y - scale_h(4)
    local pause_toggle_x = layout.overlay_padding
    local pause_toggle_w = layout.overlay_width - layout.overlay_padding * 2
    local pause_title_y = clamp(round(layout.pause_page_h * 0.14), 30, 44)
    local pause_subtitle_y = pause_title_y + clamp(round(layout.pause_page_h * 0.16), 34, 48)
    local pause_primary_button_y = pause_subtitle_y + scale_h(42)
    local pause_secondary_button_y = pause_primary_button_y + layout.overlay_button_h + layout.section_gap
    local pause_exit_button_y = pause_secondary_button_y + layout.overlay_button_h + layout.section_gap
    local pause_toggle_title_y = pause_exit_button_y + layout.overlay_button_h + clamp(round(layout.section_gap * 0.8), 10, 18)
    local pause_toggle_control_y = pause_toggle_title_y - scale_h(4)
    local gameover_title_h = clamp(round(layout.gameover_page_h * 0.15), 40, 54)
    local gameover_subtitle_h = clamp(round(layout.gameover_page_h * 0.08), 20, 28)
    local gameover_score_h = clamp(round(layout.gameover_page_h * 0.11), 32, 42)
    local gameover_best_h = clamp(round(layout.gameover_page_h * 0.1), 30, 40)
    local gameover_title_y = clamp(round(layout.gameover_page_h * 0.11), 28, 42)
    local gameover_subtitle_y = gameover_title_y + gameover_title_h + clamp(round(layout.section_gap * 0.35), 8, 14)
    local gameover_score_y = gameover_subtitle_y + gameover_subtitle_h + clamp(round(layout.section_gap * 1.25), 16, 24)
    local gameover_best_y = gameover_score_y + gameover_score_h + clamp(round(layout.section_gap * 0.45), 10, 16)
    local gameover_primary_button_y = gameover_best_y + gameover_best_h + clamp(round(layout.section_gap * 1.4), 20, 30)
    local gameover_exit_button_y = gameover_primary_button_y + layout.overlay_button_h + layout.section_gap

    -- 根容器是真正属于本窗口的 UI 根节点。
    -- 它挂在 main_container 之下，窗口销毁时会整棵树一起释放。
    ui.root = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = layout.width,
        h = layout.height,
        color = theme_page_bg
    })

    -- playfield 是实际战斗区域，玩家、子弹、敌机都使用这套局部坐标系。
    ui.playfield = airui.container({
        parent = ui.root,
        x = 0,
        y = layout.hud_height,
        w = layout.width,
        h = layout.playfield_height,
        color = theme_playfield_bg
    })
    ui.playfield:set_border_color(theme_playfield_border, 1)

    -- HUD 独立放在顶部，负责显示分数、状态和暂停入口。
    ui.hud = airui.container({
        parent = ui.root,
        x = 0,
        y = 0,
        w = layout.width,
        h = layout.hud_height,
        color = theme_surface
    })
    ui.hud:set_border_color(theme_border, 1)

    -- 先创建 HUD 背景装饰，再叠加文本和按钮控件。
    create_block(ui.hud, 0, layout.hud_band_y, layout.width, layout.hud_band_h, theme_surface_alt)
    create_block(ui.hud, layout.hud_accent_x, layout.hud_accent_y, layout.hud_accent_w, layout.hud_accent_h, theme_accent)

    ui.score_label = airui.label({
        parent = ui.hud,
        x = hud_left_x,
        y = layout.hud_title_y,
        w = hud_left_w,
        h = layout.hud_title_height,
        text = "SCORE 0000",
        font_size = scale_font(18),
        color = theme_text_primary
    })

    ui.best_label = airui.label({
        parent = ui.hud,
        x = hud_left_x,
        y = layout.hud_subtitle_y,
        w = hud_left_w,
        h = layout.hud_subtitle_height,
        text = "BEST 0000",
        font_size = scale_font(16),
        color = theme_text_secondary
    })

    ui.status_label = airui.label({
        parent = ui.hud,
        x = status_x,
        y = layout.hud_title_y,
        w = status_w,
        h = layout.hud_title_height,
        text = "READY",
        font_size = scale_font(18),
        color = theme_success,
        align = airui.TEXT_ALIGN_CENTER
    })

    ui.tip_label = airui.label({
        parent = ui.hud,
        x = status_x,
        y = layout.hud_subtitle_y,
        w = status_w,
        h = layout.hud_subtitle_height,
        text = "拖拽移动",
        font_size = scale_font(16),
        color = theme_text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    ui.pause_btn = airui.button({
        parent = ui.hud,
        x = pause_button_x,
        y = math.floor((layout.hud_height - layout.pause_button_height) / 2),
        w = layout.pause_button_width,
        h = layout.pause_button_height,
        color = theme_accent_soft,
        text = "暂停",
        font_size = scale_font(20),
        text_color = theme_accent,
        on_click = function()
            toggle_pause()
        end
    })
    local use_image = false

    if airui.image then
        local img_obj = airui.image({
            parent = ui.playfield,
            src = player_sprite_path,
            x = 0,
            y = 0,
            w = game.player.w,
            h = game.player.h,
            opacity = 0
        })
        
        if img_obj.set_pos then
            use_image = true
        end
        img_obj:destroy()
    end
    
    -- 玩家本体不走对象池，它在窗口存活期间始终存在，只根据状态更新位置。
    game.player.ref = create_sprite_shell(ui.playfield, 0, 0, game.player.w, game.player.h, theme_player_fallback, theme_player_fallback_border, player_sprite_path, use_image)

    -- 预先创建整组子弹对象池，战斗中只做激活与回收。
    for _ = 1, max_bullets do
        local bullet = {
            alive = false,
            x = 0,
            y = entity_park_margin,
            w = layout.bullet_w,
            h = layout.bullet_h,
            speed = layout.bullet_speed,
            render_visible = true,
            ref = create_sprite_shell(ui.playfield, entity_park_margin, entity_park_margin, layout.bullet_w, layout.bullet_h, theme_bullet, theme_bullet_border, bullet_sprite_path, use_image)
        }
        deactivate_entity(bullet)
        game.bullets[#game.bullets + 1] = bullet
    end

    -- 预先创建整组敌机对象池，并故意做出一些尺寸与基础速度差异，让节奏更有层次。
    for index = 1, max_enemies do
        local enemy_w = layout.enemy_width_base + (index % 3) * layout.enemy_width_step
        local enemy_h = layout.enemy_height_base + (index % 2) * layout.enemy_height_step
        local enemy = {
            alive = false,
            x = 0,
            y = entity_park_margin,
            w = enemy_w,
            h = enemy_h,
            speed = layout.enemy_speed_base + 1,
            base_speed = layout.enemy_speed_base + (index % 4) * layout.enemy_speed_step,
            vx = 0,
            flight_mode = "straight",
            render_visible = true,
            ref = create_sprite_shell(ui.playfield, entity_park_margin, entity_park_margin, enemy_w, enemy_h, theme_enemy_fallback, theme_enemy_fallback_border, enemy_sprite_path, use_image)
        }
        deactivate_entity(enemy)
        game.enemies[#game.enemies + 1] = enemy
    end

    -- 开始页覆盖层负责展示标题、规则提示、无敌模式入口与开始/退出按钮。
    ui.start_page = airui.container({
        parent = ui.root,
        x = 0,
        y = 0,
        w = layout.width,
        h = layout.height,
        color = theme_page_bg
    })
    create_block(ui.start_page, layout.start_card_x, layout.start_card_y, layout.start_card_w, layout.start_card_h, theme_surface, theme_border)
    create_block(ui.start_page, layout.start_decor_x, layout.start_decor_y, layout.start_decor_w, layout.start_decor_h, theme_accent_soft)

    airui.label({
        parent = ui.start_page,
        x = start_text_x,
        y = layout.start_title_y,
        w = start_text_w,
        h = scale_h(56),
        text = "AIRPLANE RAID",
        font_size = scale_font(34),
        color = theme_text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = ui.start_page,
        x = start_text_x,
        y = layout.start_subtitle_y,
        w = start_text_w,
        h = scale_h(80),
        text = "拖拽飞机躲避敌机\n火力自动发射",
        font_size = scale_font(22),
        color = theme_text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = ui.start_page,
        x = start_text_x,
        y = layout.start_caption_y,
        w = start_text_w,
        h = scale_h(24),
        text = "应用市场版",
        font_size = scale_font(18),
        color = theme_text_muted,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 开始页的无敌模式入口与游戏内暂停页共用同一套逻辑开关。
    ui.start_invincible_value, ui.start_invincible_switch, ui.start_invincible_button = create_invincible_toggle(ui.start_page, start_toggle_x, start_toggle_title_y, start_toggle_w, start_toggle_control_y, nil, true, true)

    airui.button({
        parent = ui.start_page,
        x = layout.primary_button_x,
        y = layout.start_button_y,
        w = layout.primary_button_width,
        h = layout.start_button_h,
        color = theme_accent,
        text = "开始作战",
        font_size = scale_font(26),
        text_color = theme_surface,
        on_click = function()
            start_game()
        end
    })

    airui.button({
        parent = ui.start_page,
        x = layout.primary_button_x,
        y = layout.start_secondary_button_y,
        w = layout.primary_button_width,
        h = layout.start_button_h,
        color = theme_warning_soft,
        text = "退出游戏",
        font_size = scale_font(24),
        text_color = theme_warning,
        on_click = function()
            close_window()
        end
    })

    ui.start_hint_label = airui.label({
        parent = ui.start_page,
        x = 0,
        y = layout.start_hint_y,
        w = layout.width,
        h = scale_h(30),
        text = "轻点开始，进入战斗",
        font_size = scale_font(18),
        color = theme_text_muted,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 暂停页覆盖层承接继续、重开、退出以及无敌模式切换。
    ui.pause_page = airui.container({
        parent = ui.root,
        x = layout.overlay_x,
        y = layout.pause_page_y,
        w = layout.overlay_width,
        h = layout.pause_page_h,
        color = theme_surface
    })
    ui.pause_page:set_border_color(theme_border_strong, 2)
    create_block(ui.pause_page, 0, 0, layout.overlay_width, layout.overlay_header_h, theme_accent_soft)

    airui.label({
        parent = ui.pause_page,
        x = 0,
        y = pause_title_y,
        w = layout.overlay_width,
        h = clamp(round(layout.pause_page_h * 0.18), 40, 52),
        text = "游戏已暂停",
        font_size = scale_font(30),
        color = theme_text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = ui.pause_page,
        x = 0,
        y = pause_subtitle_y,
        w = layout.overlay_width,
        h = clamp(round(layout.pause_page_h * 0.1), 20, 28),
        text = "休息一下，再继续推进分数",
        font_size = scale_font(16),
        color = theme_text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 暂停页内的无敌开关与开始页保持同步，避免出现两个入口显示不一致。
    ui.pause_invincible_value, ui.pause_invincible_switch, ui.pause_invincible_button = create_invincible_toggle(ui.pause_page, pause_toggle_x, pause_toggle_title_y, pause_toggle_w, pause_toggle_control_y, nil, true, true)

    airui.button({
        parent = ui.pause_page,
        x = math.floor((layout.overlay_width - layout.primary_button_width) / 2),
        y = pause_primary_button_y,
        w = layout.primary_button_width,
        h = layout.overlay_button_h,
        color = theme_accent,
        text = "继续",
        font_size = scale_font(24),
        text_color = theme_surface,
        on_click = function()
            resume_game()
        end
    })

    airui.button({
        parent = ui.pause_page,
        x = math.floor((layout.overlay_width - layout.primary_button_width) / 2),
        y = pause_secondary_button_y,
        w = layout.primary_button_width,
        h = layout.overlay_button_h,
        color = theme_warning_soft,
        text = "重新开始",
        font_size = scale_font(24),
        text_color = theme_warning,
        on_click = function()
            start_game()
        end
    })

    airui.button({
        parent = ui.pause_page,
        x = math.floor((layout.overlay_width - layout.primary_button_width) / 2),
        y = pause_exit_button_y,
        w = layout.primary_button_width,
        h = layout.overlay_button_h,
        color = theme_warning_soft,
        text = "退出游戏",
        font_size = scale_font(24),
        text_color = theme_warning,
        on_click = function()
            close_window()
        end
    })

    -- 结束页负责展示本局成绩、历史最高分以及再次开始或退出窗口的入口。
    ui.gameover_page = airui.container({
        parent = ui.root,
        x = layout.overlay_x,
        y = layout.gameover_page_y,
        w = layout.overlay_width,
        h = layout.gameover_page_h,
        color = theme_surface
    })
    ui.gameover_page:set_border_color(theme_border_strong, 2)
    create_block(ui.gameover_page, 0, 0, layout.overlay_width, layout.overlay_header_h, theme_warning_soft)

    airui.label({
        parent = ui.gameover_page,
        x = 0,
        y = gameover_title_y,
        w = layout.overlay_width,
        h = gameover_title_h,
        text = "任务失败",
        font_size = scale_font(32),
        color = theme_text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = ui.gameover_page,
        x = 0,
        y = gameover_subtitle_y,
        w = layout.overlay_width,
        h = gameover_subtitle_h,
        text = "整理一下节奏，再来一轮",
        font_size = scale_font(16),
        color = theme_text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    ui.gameover_score = airui.label({
        parent = ui.gameover_page,
        x = 0,
        y = gameover_score_y,
        w = layout.overlay_width,
        h = gameover_score_h,
        text = "本局得分 0",
        font_size = scale_font(24),
        color = theme_warning,
        align = airui.TEXT_ALIGN_CENTER
    })

    ui.gameover_best = airui.label({
        parent = ui.gameover_page,
        x = 0,
        y = gameover_best_y,
        w = layout.overlay_width,
        h = gameover_best_h,
        text = "最高分 0",
        font_size = scale_font(22),
        color = theme_text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = ui.gameover_page,
        x = math.floor((layout.overlay_width - layout.primary_button_width) / 2),
        y = gameover_primary_button_y,
        w = layout.primary_button_width,
        h = layout.overlay_button_h,
        color = theme_accent,
        text = "再次出击",
        font_size = scale_font(24),
        text_color = theme_surface,
        on_click = function()
            start_game()
        end
    })

    airui.button({
        parent = ui.gameover_page,
        x = math.floor((layout.overlay_width - layout.primary_button_width) / 2),
        y = gameover_exit_button_y,
        w = layout.primary_button_width,
        h = layout.overlay_button_h,
        color = theme_warning_soft,
        text = "退出游戏",
        font_size = scale_font(24),
        text_color = theme_warning,
        on_click = function()
            close_window()
        end
    })

    -- 初始时暂停页和结束页都隐藏，只保留开始页可见。
    -- 最后再做一次无敌模式 UI 同步，确保开关文案与状态一致。
    set_hidden(ui.pause_page, true)
    set_hidden(ui.gameover_page, true)
    refresh_invincible_ui()
end

-- 固定步进的战斗主循环。
-- 它只在 running 状态下推进计时器，并依次处理开火、刷怪、实体更新和碰撞结算。
local function game_tick()
    if game.state ~= "running" then
        return
    end

    game.elapsed = game.elapsed + tick_ms
    game.fire_cd = game.fire_cd + tick_ms
    game.spawn_cd = game.spawn_cd + tick_ms

    if game.fire_cd >= bullet_interval then
        game.fire_cd = game.fire_cd - bullet_interval
        spawn_bullet()
    end

    if game.spawn_cd >= game.enemy_interval then
        game.spawn_cd = 0
        spawn_enemy()
    end

    update_bullets()
    update_enemies()
    check_collisions()
end

-- 注册窗口级触摸订阅。
-- 触摸回调只在本窗口存活期间存在，并且只有命中玩家后才进入拖拽，避免空白区域误触影响页面交互。
local function register_touch_handler()
    airui.touch_subscribe(function(state, x, y, track_id)
        if not main_container or not (state and x and y) then
            return
        end

        -- 进入拖拽判断前，先把原始坐标补偿到当前逻辑坐标系。
        local logical_x, logical_y = remap_touch_point(x, y)

        if state == airui.TP_DOWN then
            -- 只有在战斗进行中、手指落在战场区域且当前没有已有拖拽时，才允许开始新的拖拽会话。
            if touch.dragging or game.state ~= "running" or logical_y < layout.playfield_top then
                return
            end
            if touch_hits_player(logical_x, logical_y) then
                touch.dragging = true
                touch.track_id = track_id
                touch.offset_x = clamp(logical_x - game.player.x, 0, game.player.w)
                touch.offset_y = clamp(logical_y - (layout.hud_height or 0) - game.player.y, 0, game.player.h)
                move_player_to(logical_x, logical_y, touch.offset_x, touch.offset_y)
            end
        elseif state == airui.TP_HOLD then
            -- 拖拽进行中只跟踪当前这根手指，并在靠近上边界时做“只冻结 y”的止推处理。
            if touch.dragging and (track_id == nil or touch.track_id == nil or track_id == touch.track_id) then
                local drag_y = clamp_player_drag_screen_y(logical_y, touch.offset_y)
                move_player_to(logical_x, drag_y, touch.offset_x, touch.offset_y)
            end
        elseif state == airui.TP_UP then
            -- 只有结束当前这次拖拽的手指抬起时，才清空拖拽上下文。
            if touch.dragging and (track_id == nil or touch.track_id == nil or track_id == touch.track_id) then
                reset_drag_state()
            end
        end
    end)
end

-- 停止窗口内的战斗主循环定时器。
-- 单独抽成函数后，on_destroy 可以更清晰地表达清理顺序。
local function stop_game_loop()
    if game_timer_id then
        sys.timerStop(game_timer_id)
        game_timer_id = nil
    end
end

-- exwin 的创建回调。
-- 这里会按“随机种子 -> 读取显示状态 -> 重建运行时状态 -> 推导布局 -> 创建根容器与 UI -> 启动触摸与主循环”的顺序初始化窗口。
local function on_create()
    if os and os.time then
        math.randomseed(os.time())
    else
        math.randomseed(1)
    end

    refresh_runtime_display()
    reset_runtime_state()
    rebuild_layout()

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = layout.width,
        h = layout.height,
        color = theme_page_bg
    })

    build_ui()
    reset_round()
    set_state("start")
    register_touch_handler()
    game_timer_id = sys.timerLoopStart(game_tick, tick_ms)
end

-- exwin 的销毁回调。
-- 这里统一回收主循环、触摸订阅和根容器，并把窗口句柄与拖拽状态重置干净。
local function on_destroy()
    stop_game_loop()
    if airui and airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    reset_drag_state()
    win_id = nil
end

-- 当前窗口重新获得焦点时没有额外副作用。
-- 保留空钩子是为了和 exwin 生命周期接口保持完整一致。
local function on_get_focus()
end

-- 窗口失焦时主动暂停，防止用户切走后战局仍在后台继续推进。
local function on_lose_focus()
    pause_game()
end

-- 把窗口生命周期回调注册给 exwin，并保存返回的窗口句柄。
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

-- 根入口只需要发布这个消息，本模块就会负责打开窗口并接管后续生命周期。
sys.subscribe("OPEN_AIRPLANE_BATTLE_WIN", open_handler)
