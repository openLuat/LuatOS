local Config = require("fb_config")

local function detect_resource_root()
    local nested_root = "/luadb/res/"
    if io and io.exists and io.exists(nested_root .. "bg_day.png") then
        return nested_root
    end

    local flat_root = "/luadb/"
    if io and io.exists and io.exists(flat_root .. "bg_day.png") then
        return flat_root
    end

    return nested_root
end

local RESOURCE_ROOT = detect_resource_root()

local function resolve_resource_path(name)
    return RESOURCE_ROOT .. name
end

local function build_pipe_presets(top_prefix, bottom_prefix)
    local presets = {}
    for _, gap_y in ipairs(Config.PIPE_PRESET_GAP_Y) do
        presets[#presets + 1] = {
            gap_y = gap_y,
            top = {
                path = resolve_resource_path(string.format("%s_pre_%d.png", top_prefix, gap_y)),
                h = gap_y,
            },
            bottom = {
                path = resolve_resource_path(string.format("%s_pre_%d.png", bottom_prefix, gap_y)),
                h = Config.LAND_Y - (gap_y + Config.PIPE_GAP),
            },
        }
    end
    return presets
end

local Resources = {
    background = {
        day = resolve_resource_path("bg_day.png"),
        night = resolve_resource_path("bg_night.png"),
    },
    land = resolve_resource_path("land.png"),
    title = resolve_resource_path("title.png"),
    ready = resolve_resource_path("text_ready.png"),
    tutorial = resolve_resource_path("tutorial.png"),
    game_over = resolve_resource_path("text_game_over.png"),
    score_panel = resolve_resource_path("score_panel.png"),
    play_button = resolve_resource_path("button_play.png"),
    exit_button = resolve_resource_path("exit_button.png"),
    new_badge = resolve_resource_path("new.png"),
    pipes = {
        green = build_pipe_presets("pipe_down", "pipe_up"),
    },
    medals = {
        [1] = resolve_resource_path("medals_0.png"),
        [2] = resolve_resource_path("medals_1.png"),
        [3] = resolve_resource_path("medals_2.png"),
        [4] = resolve_resource_path("medals_3.png"),
    },
    dimensions = {
        font = {
            [0] = { w = 24, h = 44 },
            [1] = { w = 16, h = 44 },
            [2] = { w = 24, h = 44 },
            [3] = { w = 24, h = 44 },
            [4] = { w = 24, h = 44 },
            [5] = { w = 24, h = 44 },
            [6] = { w = 24, h = 44 },
            [7] = { w = 24, h = 44 },
            [8] = { w = 24, h = 44 },
            [9] = { w = 24, h = 44 },
        },
        panel = {
            [0] = { w = 16, h = 20 },
            [1] = { w = 16, h = 20 },
            [2] = { w = 16, h = 20 },
            [3] = { w = 16, h = 20 },
            [4] = { w = 16, h = 20 },
            [5] = { w = 16, h = 20 },
            [6] = { w = 16, h = 20 },
            [7] = { w = 16, h = 20 },
            [8] = { w = 16, h = 20 },
            [9] = { w = 16, h = 20 },
        },
    },
}

Resources.font_digits = {}
Resources.panel_digits = {}

function Resources.bird_frame(palette, frame_index)
    return resolve_resource_path(string.format("bird%d_%d.png", palette, frame_index))
end

for digit = 0, 9 do
    Resources.font_digits[digit] = {
        path = resolve_resource_path(string.format("font_%03d.png", digit + 48)),
        w = Resources.dimensions.font[digit].w,
        h = Resources.dimensions.font[digit].h,
    }
    Resources.panel_digits[digit] = {
        path = resolve_resource_path(string.format("number_score_%02d.png", digit)),
        w = Resources.dimensions.panel[digit].w,
        h = Resources.dimensions.panel[digit].h,
    }
end

function Resources.pick_theme()
    local pipe_set = Resources.pipes.green
    local background = math.random(0, 1) == 0 and Resources.background.day or Resources.background.night
    local bird_palette = math.random(0, 2)
    local bird_frames = {
        Resources.bird_frame(bird_palette, 0),
        Resources.bird_frame(bird_palette, 1),
        Resources.bird_frame(bird_palette, 2),
    }
    return {
        background = background,
        pipe_presets = pipe_set,
        bird_frames = bird_frames,
    }
end

function Resources.medal_for_score(score, thresholds)
    if score >= thresholds[4] then
        return Resources.medals[4]
    end
    if score >= thresholds[3] then
        return Resources.medals[3]
    end
    if score >= thresholds[2] then
        return Resources.medals[2]
    end
    if score >= thresholds[1] then
        return Resources.medals[1]
    end
    return nil
end

return Resources