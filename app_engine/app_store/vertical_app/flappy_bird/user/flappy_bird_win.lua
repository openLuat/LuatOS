local Config = require("fb_config")
local Resources = require("fb_resources")

local win_id = nil
local main_container = nil
local game_timer_id = nil
local game = nil
local logical_width
local logical_height

local Game = {}
Game.__index = Game

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function rectangles_overlap(left, right)
    return left.x < right.x + right.w and left.x + left.w > right.x and left.y < right.y + right.h and left.y + left.h > right.y
end

local function rotation_to_airui(degrees)
    local normalized = degrees % 360
    if normalized < 0 then
        normalized = normalized + 360
    end
    return round(normalized * 10)
end

local function set_container_visible(container, visible)
    if visible then
        container:open()
    else
        container:hide()
    end
end

local function set_image_visible(image, visible)
    image:set_opacity(visible and 255 or 0)
end

local function is_pipe_in_safe_horizontal_range(x)
    return x >= 0 and x <= Config.SCREEN_W - Config.PIPE_W
end

local function get_parked_pipe_x()
    return Config.SCREEN_W - Config.PIPE_W
end

local function close_window()
    if win_id then
        exwin.close(win_id)
    end
end

local function create_pipe_image(parent, src, height)
    return airui.image({
        parent = parent,
        src = src,
        x = get_parked_pipe_x(),
        y = 0,
        w = Config.PIPE_W,
        h = height,
        opacity = 0
    })
end

local function hide_active_pipe_images(pipe)
    if pipe.top_image then
        set_image_visible(pipe.top_image, false)
    end
    if pipe.bottom_image then
        set_image_visible(pipe.bottom_image, false)
    end
end

local function set_pipe_visible(pipe, visible)
    if pipe.render_visible == visible then
        return false
    end

    pipe.render_visible = visible
    if not visible then
        hide_active_pipe_images(pipe)
    end
    return true
end

local function destroy_pipe_image(image)
    if image then
        image:destroy()
    end
end

local function destroy_ui_node(node)
    if node then
        node:destroy()
    end
end

local function create_digit_strip(parent, options)
    local container = airui.container({
        parent = parent,
        x = options.x,
        y = options.y,
        w = options.w,
        h = options.h
    })

    local slots = {}
    local default_digit = options.digit_set[0]
    for index = 1, options.max_digits do
        slots[index] = airui.image({
            parent = container,
            src = default_digit.path,
            x = 0,
            y = 0,
            w = default_digit.w,
            h = default_digit.h,
            opacity = 0
        })
    end

    return {
        container = container,
        slots = slots,
        digit_set = options.digit_set,
        spacing = options.spacing or 0,
        align = options.align or "left",
        width = options.w,
        y = options.offset_y or 0,
        last_value = nil
    }
end

local function update_digit_strip(strip, value)
    local normalized_value = math.max(0, math.floor(value))
    if strip.last_value == normalized_value then
        return
    end

    local text = tostring(normalized_value)
    if #text > #strip.slots then
        text = text:sub(#text - #strip.slots + 1)
    end

    local total_width = 0
    for index = 1, #text do
        local digit = tonumber(text:sub(index, index))
        total_width = total_width + strip.digit_set[digit].w
        if index < #text then
            total_width = total_width + strip.spacing
        end
    end

    local start_x = 0
    if strip.align == "center" then
        start_x = round((strip.width - total_width) / 2)
    elseif strip.align == "right" then
        start_x = strip.width - total_width
    end

    local cursor_x = start_x
    for index, slot in ipairs(strip.slots) do
        if index <= #text then
            local digit = tonumber(text:sub(index, index))
            local spec = strip.digit_set[digit]
            slot:set_src(spec.path)
            slot:set_pos(cursor_x, strip.y)
            slot:set_opacity(255)
            cursor_x = cursor_x + spec.w + strip.spacing
        else
            slot:set_opacity(0)
        end
    end

    strip.last_value = normalized_value
end

function Game.new(parent)
    return setmetatable({
        parent = parent,
        best_score = 0,
        previous_best = 0,
        score = 0,
        state = "boot",
        theme = nil,
        ui = {},
        pipes = {},
        bird = {
            x = Config.BIRD_START_X,
            y = Config.BIRD_START_Y,
            velocity = 0,
            frame_index = 1,
            frame_timer = 0,
            ready_timer = 0,
            rotation = 0,
            render_frame_index = nil,
            render_x = nil,
            render_y = nil,
            render_rotation = nil
        },
        ground = {
            x1 = 0,
            x2 = Config.LAND_W
        }
    }, Game)
end

function Game:build_ui()
    self.ui.root = airui.container({
        parent = self.parent,

        x = (logical_width - Config.SCREEN_W) / 2,
        y = (logical_height - Config.SCREEN_H) / 2,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H
    })

    self.ui.background = airui.image({
        parent = self.ui.root,
        src = Resources.background.day,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H
    })

    self.ui.pipe_layer = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H
    })

    for index = 1, Config.PIPE_COUNT do
        self.pipes[index] = {
            top_image = nil,
            bottom_image = nil,
            x = Config.PIPE_START_X,
            gap_y = Config.PIPE_PRESET_GAP_Y[1],
            preset_index = 1,
            scored = false,
            render_visible = false,
            last_render_x = nil,
            last_bottom_y = nil
        }
    end

    self.ui.bird = airui.image({
        parent = self.ui.root,
        src = Resources.bird_frame(0, 1),
        x = Config.BIRD_START_X,
        y = Config.BIRD_START_Y,
        w = Config.BIRD_W,
        h = Config.BIRD_H,
        pivot = {
            x = 24,
            y = 24
        }
    })

    self.ui.land_left = airui.image({
        parent = self.ui.root,
        src = Resources.land,
        x = 0,
        y = Config.LAND_Y,
        w = Config.SCREEN_W,
        h = Config.LAND_H
    })

    self.ui.land_right = airui.image({
        parent = self.ui.root,
        src = Resources.land,
        x = 0,
        y = Config.LAND_Y,
        w = Config.SCREEN_W,
        h = Config.LAND_H,
        opacity = 0
    })

    self.ui.top_score = create_digit_strip(self.ui.root, {
        x = 0,
        y = Config.SCORE_TOP_Y,
        w = Config.SCREEN_W,
        h = 44,
        max_digits = Config.TOP_SCORE_DIGITS,
        digit_set = Resources.font_digits,
        align = "center",
        spacing = 0
    })

    self.ui.ready_layer = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H
    })

    self.ui.ready_title = airui.image({
        parent = self.ui.ready_layer,
        src = Resources.title,
        x = Config.READY_TITLE_X,
        y = Config.READY_TITLE_Y,
        w = 178,
        h = 48
    })

    self.ui.ready_text = airui.image({
        parent = self.ui.ready_layer,
        src = Resources.ready,
        x = Config.READY_TEXT_X,
        y = Config.READY_TEXT_Y,
        w = 196,
        h = 62
    })

    self.ui.tutorial = airui.image({
        parent = self.ui.ready_layer,
        src = Resources.tutorial,
        x = Config.READY_TUTORIAL_X,
        y = Config.READY_TUTORIAL_Y,
        w = 114,
        h = 98
    })

    self.ui.input_layer = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H,
        on_click = function(a, b, c, d)
            self:on_primary_action()
        end
    })

    self.ui.ready_exit_button = airui.container({
        parent = self.ui.input_layer,
        x = Config.EXIT_BUTTON_X,
        y = Config.EXIT_BUTTON_Y,
        w = 116,
        h = 70,
        on_click = function()
            close_window()
        end
    })
    self.ui.ready_exit_button_image = airui.image({
        parent = self.ui.ready_exit_button,
        src = Resources.exit_button,
        x = 0,
        y = 0,
        w = 116,
        h = 70
    })

    set_container_visible(self.ui.top_score.container, false)
end

function Game:create_gameover_ui()
    if self.ui.gameover_layer then
        return
    end

    self.ui.gameover_layer = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H
    })

    self.ui.game_over_text = airui.image({
        parent = self.ui.gameover_layer,
        src = Resources.game_over,
        x = Config.GAMEOVER_TEXT_X,
        y = Config.GAMEOVER_TEXT_Y,
        w = 204,
        h = 54
    })

    self.ui.score_panel = airui.image({
        parent = self.ui.gameover_layer,
        src = Resources.score_panel,
        x = Config.SCORE_PANEL_X,
        y = Config.SCORE_PANEL_Y,
        w = 238,
        h = 126
    })

    self.ui.medal_layer = airui.container({
        parent = self.ui.gameover_layer,
        x = Config.MEDAL_X,
        y = Config.MEDAL_Y,
        w = 44,
        h = 44
    })
    self.ui.medal_image = airui.image({
        parent = self.ui.medal_layer,
        src = Resources.medals[1],
        x = 0,
        y = 0,
        w = 44,
        h = 44
    })

    self.ui.panel_score = create_digit_strip(self.ui.gameover_layer, {
        x = Config.PANEL_SCORE_X,
        y = Config.PANEL_SCORE_Y,
        w = 76,
        h = 20,
        max_digits = Config.PANEL_SCORE_DIGITS,
        digit_set = Resources.panel_digits,
        align = "right",
        spacing = 0
    })

    self.ui.panel_best = create_digit_strip(self.ui.gameover_layer, {
        x = Config.PANEL_BEST_X,
        y = Config.PANEL_BEST_Y,
        w = 76,
        h = 20,
        max_digits = Config.PANEL_SCORE_DIGITS,
        digit_set = Resources.panel_digits,
        align = "right",
        spacing = 0
    })

    self.ui.new_badge_layer = airui.container({
        parent = self.ui.gameover_layer,
        x = Config.NEW_BADGE_X,
        y = Config.NEW_BADGE_Y,
        w = 32,
        h = 14
    })
    self.ui.new_badge = airui.image({
        parent = self.ui.new_badge_layer,
        src = Resources.new_badge,
        x = 0,
        y = 0,
        w = 32,
        h = 14
    })

    self.ui.play_button = airui.container({
        parent = self.ui.gameover_layer,
        x = Config.PLAY_BUTTON_X,
        y = Config.PLAY_BUTTON_Y,
        w = 116,
        h = 70,
        on_click = function()
            self:reset_round(true)
        end
    })
    self.ui.play_button_image = airui.image({
        parent = self.ui.play_button,
        src = Resources.play_button,
        x = 0,
        y = 0,
        w = 116,
        h = 70
    })

    self.ui.exit_button = airui.container({
        parent = self.ui.gameover_layer,
        x = Config.EXIT_BUTTON_X,
        y = Config.EXIT_BUTTON_Y,
        w = 116,
        h = 70,
        on_click = function()
            close_window()
        end
    })

    self.ui.exit_button_image = airui.image({
        parent = self.ui.exit_button,
        src = Resources.exit_button,
        x = 0,
        y = 0,
        w = 116,
        h = 70
    })

    set_container_visible(self.ui.medal_layer, false)
    set_container_visible(self.ui.new_badge_layer, false)
end

function Game:destroy_gameover_ui()
    destroy_ui_node(self.ui.gameover_layer)
    self.ui.gameover_layer = nil
    self.ui.game_over_text = nil
    self.ui.score_panel = nil
    self.ui.medal_layer = nil
    self.ui.medal_image = nil
    self.ui.panel_score = nil
    self.ui.panel_best = nil
    self.ui.new_badge_layer = nil
    self.ui.new_badge = nil
    self.ui.play_button = nil
    self.ui.play_button_image = nil
    self.ui.exit_button = nil
    self.ui.exit_button_image = nil
end

function Game:destroy()
    self.ui = {}
    self.pipes = {}
    self.theme = nil
end

function Game:random_pipe_preset()
    local preset_index = math.random(1, #Config.PIPE_PRESET_GAP_Y)
    return preset_index, Config.PIPE_PRESET_GAP_Y[preset_index]
end

function Game:reset_round(select_new_theme)
    if select_new_theme or not self.theme then
        self.theme = Resources.pick_theme()
    end

    self.state = "ready"
    self.score = 0
    self.previous_best = self.best_score
    self.bird.x = Config.BIRD_START_X
    self.bird.y = Config.BIRD_START_Y
    self.bird.velocity = 0
    self.bird.frame_index = 2
    self.bird.frame_timer = 0
    self.bird.ready_timer = 0
    self.bird.rotation = 0

    self:apply_theme()
    self:reset_ground()
    self:reset_pipes()
    self:update_bird_visual()
    self:update_top_score()
    self:show_ready_ui()
end

function Game:apply_theme()
    self.ui.background:set_src(self.theme.background)
    -- 随机切换小鸟皮肤
    self.ui.bird:set_src(self.theme.bird_frames[self.bird.frame_index])

    self.bird.render_frame_index = nil
    self:update_bird_visual()
end

function Game:rebuild_pipe_images(pipe)
    local preset = self.theme.pipe_presets[pipe.preset_index]

    destroy_pipe_image(pipe.top_image)
    destroy_pipe_image(pipe.bottom_image)

    pipe.top_image = create_pipe_image(self.ui.pipe_layer, preset.top.path, preset.top.h)
    pipe.bottom_image = create_pipe_image(self.ui.pipe_layer, preset.bottom.path, preset.bottom.h)
    pipe.render_visible = false
    pipe.last_render_x = nil
    pipe.last_bottom_y = nil
end

function Game:reset_ground()
    self.ground.x1 = 0
    self.ground.x2 = 0
    self.ui.land_left:set_pos(round(self.ground.x1), Config.LAND_Y)
    self.ui.land_right:set_pos(round(self.ground.x2), Config.LAND_Y)
    self.ui.land_right:set_opacity(0)
end

function Game:reset_pipes()
    for index, pipe in ipairs(self.pipes) do
        pipe.x = Config.PIPE_START_X + (index - 1) * Config.PIPE_SPACING
        pipe.preset_index, pipe.gap_y = self:random_pipe_preset()
        pipe.scored = false
        self:rebuild_pipe_images(pipe)
        self:update_pipe_visual(pipe)
    end
end

function Game:update_pipe_visual(pipe)
    local render_x = round(pipe.x)
    if not is_pipe_in_safe_horizontal_range(render_x) then
        set_pipe_visible(pipe, false)
        pipe.last_render_x = nil
        pipe.last_bottom_y = nil
        return
    end

    local bottom_y = pipe.gap_y + Config.PIPE_GAP
    local visibility_changed = set_pipe_visible(pipe, true)

    if visibility_changed then
        set_image_visible(pipe.top_image, true)
        set_image_visible(pipe.bottom_image, true)
    end

    if visibility_changed or pipe.last_render_x ~= render_x or pipe.last_bottom_y ~= bottom_y then
        pipe.top_image:set_pos(render_x, 0)
        pipe.bottom_image:set_pos(render_x, bottom_y)
        pipe.last_render_x = render_x
        pipe.last_bottom_y = bottom_y
    end
end

function Game:update_top_score()
    update_digit_strip(self.ui.top_score, self.score)
end

function Game:update_gameover_panel()
    if not self.ui.gameover_layer then
        return
    end

    update_digit_strip(self.ui.panel_score, self.score)
    update_digit_strip(self.ui.panel_best, self.best_score)

    local medal_path = Resources.medal_for_score(self.score, Config.MEDAL_THRESHOLDS)
    if medal_path then
        self.ui.medal_image:set_src(medal_path)
        set_container_visible(self.ui.medal_layer, true)
    else
        set_container_visible(self.ui.medal_layer, false)
    end

    set_container_visible(self.ui.new_badge_layer, self.score > self.previous_best and self.score > 0)
end

function Game:show_ready_ui()
    set_container_visible(self.ui.ready_layer, true)
    self:destroy_gameover_ui()
    set_container_visible(self.ui.top_score.container, false)
    set_container_visible(self.ui.input_layer, true)
    set_container_visible(self.ui.ready_exit_button, true)
    self:update_top_score()
end

function Game:show_playing_ui()
    set_container_visible(self.ui.ready_layer, false)
    self:destroy_gameover_ui()
    set_container_visible(self.ui.top_score.container, true)
    set_container_visible(self.ui.input_layer, true)
    set_container_visible(self.ui.ready_exit_button, false)
    self:update_top_score()
end

function Game:show_gameover_ui()
    self:create_gameover_ui()
    set_container_visible(self.ui.ready_layer, false)
    set_container_visible(self.ui.gameover_layer, true)
    set_container_visible(self.ui.top_score.container, false)
    set_container_visible(self.ui.input_layer, false)
    self:update_gameover_panel()
end

function Game:on_primary_action()
    if self.state == "ready" then
        self.state = "playing"
        self.bird.velocity = Config.BIRD_FLAP_VELOCITY
        self.bird.ready_timer = 0
        self:show_playing_ui()
        return
    end

    if self.state == "playing" then
        self.bird.velocity = Config.BIRD_FLAP_VELOCITY
    end
end

function Game:update(frame_dt)
    if self.state == "ready" then
        self:update_ready_bird(frame_dt)
        self:update_bird_frame(frame_dt)
        return
    end

    if self.state == "playing" then
        self:update_bird_physics(frame_dt)
        self:update_bird_frame(frame_dt)
        self:update_pipes(frame_dt)
        self:check_score()
        if self:check_pipe_collision() then
            self:enter_gameover()
        end
        return
    end

    if self.state == "gameover" then
        self:update_bird_fall(frame_dt)
    end
end

function Game:update_ready_bird(frame_dt)
    self.bird.ready_timer = self.bird.ready_timer + frame_dt
    self.bird.rotation = 0
    self.bird.y = Config.BIRD_START_Y + math.sin(self.bird.ready_timer * Config.BIRD_READY_BOB_SPEED) * Config.BIRD_READY_BOB_AMPLITUDE
    self:update_bird_transform()
end

function Game:update_bird_frame(frame_dt_or_force)
    self.bird.frame_timer = self.bird.frame_timer + frame_dt_or_force * 1000
    if self.bird.frame_timer < Config.BIRD_FRAME_MS then
        return
    end

    self.bird.frame_timer = self.bird.frame_timer - Config.BIRD_FRAME_MS
    -- self.bird.frame_index = self.bird.frame_index + 1
    -- if self.bird.frame_index > #self.theme.bird_frames then
    --     self.bird.frame_index = 1
    -- end
    self:update_bird_visual()
end

function Game:update_bird_visual()

    -- 这里是控制小鸟动画帧的逻辑，原本是每隔一定时间切换一次小鸟的图片来实现扇动翅膀的效果。但是在这个版本中，我们暂时不切换小鸟的图片，而是保持在一个固定的帧上。不然太卡了
    -- if self.bird.render_frame_index ~= self.bird.frame_index then
    --     self.ui.bird:set_src(self.theme.bird_frames[self.bird.frame_index])
    --     self.bird.render_frame_index = self.bird.frame_index
    -- end
    self:update_bird_transform()
end

function Game:update_bird_physics(frame_dt)
    self.bird.velocity = clamp(self.bird.velocity + Config.BIRD_GRAVITY * frame_dt, Config.BIRD_FLAP_VELOCITY, Config.BIRD_MAX_FALL_SPEED)
    self.bird.y = self.bird.y + self.bird.velocity * frame_dt

    if self.bird.y < Config.BIRD_MIN_Y then
        self.bird.y = Config.BIRD_MIN_Y
        self.bird.velocity = 0
    end

    if self.bird.y >= Config.FLOOR_Y then
        self.bird.y = Config.FLOOR_Y
        self.bird.rotation = Config.BIRD_ROTATION_DOWN_MAX
        self:update_bird_transform()
        self:enter_gameover()
        return
    end

    if self.bird.velocity < 0 then
        self.bird.rotation = Config.BIRD_ROTATION_UP
    else
        local ratio = clamp(self.bird.velocity / Config.BIRD_MAX_FALL_SPEED, 0, 1)
        self.bird.rotation = ratio * Config.BIRD_ROTATION_DOWN_MAX
    end

    self:update_bird_transform()
end

function Game:update_bird_fall(frame_dt)
    if self.bird.y >= Config.FLOOR_Y then
        self.bird.y = Config.FLOOR_Y
        self.bird.rotation = Config.BIRD_ROTATION_DOWN_MAX
        self:update_bird_transform()
        self.state = "wait_restart"
        return
    end

    self.bird.velocity = clamp(self.bird.velocity + Config.BIRD_GRAVITY * frame_dt, 0, Config.BIRD_MAX_FALL_SPEED)
    self.bird.y = math.min(self.bird.y + self.bird.velocity * frame_dt, Config.FLOOR_Y)
    self.bird.rotation = Config.BIRD_ROTATION_DOWN_MAX
    self:update_bird_transform()
end

function Game:update_bird_transform()
    local render_x = round(self.bird.x)
    local render_y = round(self.bird.y)
    local render_rotation = rotation_to_airui(self.bird.rotation)

    if self.bird.render_x ~= render_x or self.bird.render_y ~= render_y then
        self.ui.bird:set_pos(render_x, render_y)
        self.bird.render_x = render_x
        self.bird.render_y = render_y
    end

    -- if self.bird.render_rotation ~= render_rotation then
    --     self.ui.bird:set_rotation(render_rotation)
    --     self.bird.render_rotation = render_rotation
    -- end
end

function Game:update_pipes(frame_dt)
    local move_distance = Config.PIPE_SPEED * frame_dt
    local rightmost_x = 0

    for _, pipe in ipairs(self.pipes) do
        pipe.x = pipe.x - move_distance
        if pipe.x > rightmost_x then
            rightmost_x = pipe.x
        end
        self:update_pipe_visual(pipe)
    end

    for _, pipe in ipairs(self.pipes) do
        if pipe.x + Config.PIPE_W < 0 then
            pipe.x = rightmost_x + Config.PIPE_SPACING
            pipe.preset_index, pipe.gap_y = self:random_pipe_preset()
            pipe.scored = false
            rightmost_x = pipe.x
            self:rebuild_pipe_images(pipe)
            self:update_pipe_visual(pipe)
        end
    end
end

function Game:check_score()
    local bird_x = self.bird.x + Config.BIRD_HITBOX.x
    for _, pipe in ipairs(self.pipes) do
        if not pipe.scored and pipe.x + Config.PIPE_W < bird_x then
            pipe.scored = true
            self.score = self.score + 1
            self:update_top_score()
        end
    end
end

function Game:get_bird_hitbox()
    return {
        x = self.bird.x + Config.BIRD_HITBOX.x,
        y = self.bird.y + Config.BIRD_HITBOX.y,
        w = Config.BIRD_HITBOX.w,
        h = Config.BIRD_HITBOX.h
    }
end

function Game:check_pipe_collision()
    local bird_box = self:get_bird_hitbox()
    for _, pipe in ipairs(self.pipes) do
        local top_box = {
            x = pipe.x,
            y = pipe.gap_y - Config.PIPE_H,
            w = Config.PIPE_W,
            h = Config.PIPE_H
        }
        local bottom_box = {
            x = pipe.x,
            y = pipe.gap_y + Config.PIPE_GAP,
            w = Config.PIPE_W,
            h = Config.PIPE_H
        }
        if rectangles_overlap(bird_box, top_box) or rectangles_overlap(bird_box, bottom_box) then
            return true
        end
    end
    return false
end

function Game:enter_gameover()
    if self.state == "gameover" then
        return
    end

    self.state = "gameover"
    if self.score > self.best_score then
        self.best_score = self.score
    end
    if self.bird.velocity < 0 then
        self.bird.velocity = 0
    end
    self.bird.frame_index = 2
    self.bird.render_frame_index = nil
    self:update_bird_visual()
    self:show_gameover_ui()
end

local function stop_game_loop()
    if game_timer_id then
        sys.timerStop(game_timer_id)
        game_timer_id = nil
    end
end

local function game_tick()
    if game then
        game:update(Config.FRAME_MS / 1000)
    end
end

local function on_create()
    if os and os.time then
        math.randomseed(os.time())
    else
        math.randomseed(1)
    end
    math.random()
    math.random()
    math.random()
    local raw_width, raw_height = Config.SCREEN_W, Config.SCREEN_H
    local rotation = 0;
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
    logical_width = raw_width
    logical_height = raw_height
    if rotation == 90 or rotation == 270 then
        logical_width = raw_height
        logical_height = raw_width
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = logical_width,
        h = logical_height,
        color = 0xffffff
    })

    game = Game.new(main_container)
    game:build_ui()
    game:reset_round(true)
    game_timer_id = sys.timerLoopStart(game_tick, Config.FRAME_MS)
end

local function on_destroy()
    stop_game_loop()
    if game then
        game:destroy()
        game = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_FLAPPY_BIRD_WIN", open_handler)
