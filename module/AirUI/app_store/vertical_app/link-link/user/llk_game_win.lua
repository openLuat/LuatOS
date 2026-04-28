local Config = require("llk_config")
local Resources = require("llk_resources")

local win_id = nil
local main_container = nil
local game_timer_id = nil
local game = nil
local raw_screen_width = Config.SCREEN_W
local raw_screen_height = Config.SCREEN_H
local screen_rotation = 0
local logical_width = Config.SCREEN_W
local logical_height = Config.SCREEN_H
local border_inset = 2
local tile_layer_inset = 4

local THEME = {
    page_bg = 0xf7ecd6,
    panel = 0xf9f2df,
    panel_alt = 0xf1e1c4,
    panel_strong = 0xe8d1ab,
    border = 0x9d7247,
    border_soft = 0xc59d72,
    text = 0x5c391c,
    text_muted = 0x8c6c47,
    accent = 0xb94a3f,
    accent_soft = 0xf6ddd2,
    success = 0x577d48,
    warning = 0xb07b28,
    line = 0xd27c24,
    board = 0xefe1c5,
}

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

local function remap_touch_point(raw_x, raw_y)
    local mapped_x = raw_x
    local mapped_y = raw_y

    if screen_rotation == 90 then
        mapped_x = raw_screen_height - raw_y - 1
        mapped_y = raw_x
    elseif screen_rotation == 180 then
        mapped_x = raw_screen_width - raw_x - 1
        mapped_y = raw_screen_height - raw_y - 1
    elseif screen_rotation == 270 then
        mapped_x = raw_y
        mapped_y = raw_screen_width - raw_x - 1
    end

    mapped_x = clamp(mapped_x, 0, logical_width - 1)
    mapped_y = clamp(mapped_y, 0, logical_height - 1)
    return mapped_x, mapped_y
end

local function shuffle_in_place(list)
    for index = #list, 2, -1 do
        local swap_index = math.random(1, index)
        list[index], list[swap_index] = list[swap_index], list[index]
    end
end

local function set_widget_visible(widget, visible)
    if not widget then
        return
    end
    if visible then
        widget:open()
    else
        widget:hide()
    end
end

local function set_image_visible(image, visible)
    if not image then
        return
    end
    image:set_opacity(visible and 255 or 0)
end

local function destroy_node(node)
    if node then
        node:destroy()
    end
end

local function close_window()
    if win_id then
        exwin.close(win_id)
    end
end

local function copy_point(row, col)
    return {
        row = row,
        col = col,
    }
end

local function get_max_level_board_size()
    local max_rows = Config.BOARD_ROWS
    local max_cols = Config.BOARD_COLS

    for _, spec in ipairs(Config.LEVELS) do
        local rows = spec.rows or Config.BOARD_ROWS
        local cols = spec.cols or Config.BOARD_COLS
        if rows > max_rows then
            max_rows = rows
        end
        if cols > max_cols then
            max_cols = cols
        end
    end

    return max_rows, max_cols
end

local MAX_BOARD_ROWS, MAX_BOARD_COLS = get_max_level_board_size()

local function format_time_ms(value)
    local seconds = math.max(0, math.ceil(value / 1000))
    return string.format("%03d", seconds)
end

local function tile_key(row, col)
    return string.format("%d:%d", row, col)
end

local function append_unique_path_point(points, row, col)
    local count = #points
    if count > 0 then
        local last = points[count]
        if last.row == row and last.col == col then
            return
        end
    end
    points[#points + 1] = copy_point(row, col)
end

local function compress_path(points)
    local unique = {}
    for _, point in ipairs(points) do
        append_unique_path_point(unique, point.row, point.col)
    end

    local changed = true
    while changed do
        changed = false
        for index = 2, #unique - 1 do
            local prev = unique[index - 1]
            local curr = unique[index]
            local next_point = unique[index + 1]
            if (prev.row == curr.row and curr.row == next_point.row) or (prev.col == curr.col and curr.col == next_point.col) then
                table.remove(unique, index)
                changed = true
                break
            end
        end
    end

    return unique
end

function Game.new(parent)
    return setmetatable({
        parent = parent,
        state = "ready",
        current_level_index = 0,
        current_level_spec = nil,
        max_board_rows = MAX_BOARD_ROWS,
        max_board_cols = MAX_BOARD_COLS,
        board_rows = Config.BOARD_ROWS,
        board_cols = Config.BOARD_COLS,
        tile_w = Config.TILE_W,
        tile_h = Config.TILE_H,
        tile_gap = Config.TILE_GAP,
        cell_stride_x = Config.CELL_STRIDE_X,
        cell_stride_y = Config.CELL_STRIDE_Y,
        board_content_x = Config.BOARD_PADDING,
        board_content_y = Config.BOARD_PADDING,
        board_grid_w = Config.BOARD_COLS * Config.TILE_W + math.max(0, Config.BOARD_COLS - 1) * Config.TILE_GAP,
        board_grid_h = Config.BOARD_ROWS * Config.TILE_H + math.max(0, Config.BOARD_ROWS - 1) * Config.TILE_GAP,
        board_hit_origin_x = Config.BOARD_PADDING - math.floor(Config.TILE_GAP / 2),
        board_hit_origin_y = Config.BOARD_PADDING - math.floor(Config.TILE_GAP / 2),
        board_hit_w = Config.BOARD_COLS * Config.CELL_STRIDE_X,
        board_hit_h = Config.BOARD_ROWS * Config.CELL_STRIDE_Y,
        score = 0,
        best_score = 0,
        remaining_time_ms = 0,
        hints_left = 0,
        reshuffles_left = 0,
        selected = nil,
        hint_pair = nil,
        path_points = nil,
        path_timer_ms = 0,
        hint_timer_ms = 0,
        status_timer_ms = 0,
        status_override = nil,
        available_pair = nil,
        board_has_available_pair = nil,
        dirty_tiles = {},
        force_full_board_refresh = true,
        hud_cache = {},
        last_display_seconds = nil,
        board = {},
        ui = {
            tiles = {},
            path_segments = {},
        },
        dialog = {
            primary_action = nil,
            secondary_action = nil,
        },
    }, Game)
end

function Game:get_level_spec(index)
    return Config.LEVELS[index]
end

function Game:set_text_if_changed(cache_key, widget, text)
    if not widget then
        return
    end
    if self.hud_cache[cache_key] ~= text then
        self.hud_cache[cache_key] = text
        widget:set_text(text)
    end
end

function Game:set_available_pair_cache(pair)
    self.available_pair = pair
    self.board_has_available_pair = pair ~= nil
    return pair
end

function Game:invalidate_available_pair_cache()
    self.available_pair = nil
    self.board_has_available_pair = nil
end

function Game:refresh_available_pair_cache()
    return self:set_available_pair_cache(self:find_available_pair())
end

function Game:mark_all_tiles_dirty()
    self.force_full_board_refresh = true
    self.dirty_tiles = {}
end

function Game:mark_tile_dirty(row, col)
    if self:is_inside_board(row, col) then
        self.dirty_tiles[tile_key(row, col)] = {
            row = row,
            col = col,
        }
    end
end

function Game:mark_point_dirty(point)
    if point then
        self:mark_tile_dirty(point.row, point.col)
    end
end

function Game:mark_pair_dirty(pair)
    if pair then
        self:mark_point_dirty(pair.first)
        self:mark_point_dirty(pair.second)
    end
end

function Game:set_selected(point)
    local previous = self.selected
    if previous and point and previous.row == point.row and previous.col == point.col then
        return
    end
    self:mark_point_dirty(previous)
    self.selected = point and copy_point(point.row, point.col) or nil
    self:mark_point_dirty(self.selected)
end

function Game:set_hint_pair(pair)
    self:mark_pair_dirty(self.hint_pair)
    if pair then
        self.hint_pair = {
            first = copy_point(pair.first.row, pair.first.col),
            second = copy_point(pair.second.row, pair.second.col),
        }
    else
        self.hint_pair = nil
    end
    self:mark_pair_dirty(self.hint_pair)
end

function Game:get_root_offset()
    return math.floor((logical_width - Config.SCREEN_W) / 2), math.floor((logical_height - Config.SCREEN_H) / 2)
end

function Game:apply_board_layout(rows, cols)
    local tile_layer_w = Config.BOARD_W - tile_layer_inset * 2
    local tile_layer_h = Config.BOARD_H - tile_layer_inset * 2

    self.board_rows = rows or Config.BOARD_ROWS
    self.board_cols = cols or Config.BOARD_COLS
    self.tile_w = Config.TILE_W
    self.tile_h = Config.TILE_H
    self.tile_gap = Config.TILE_GAP
    self.cell_stride_x = self.tile_w + self.tile_gap
    self.cell_stride_y = self.tile_h + self.tile_gap
    self.board_grid_w = self.board_cols * self.tile_w + math.max(0, self.board_cols - 1) * self.tile_gap
    self.board_grid_h = self.board_rows * self.tile_h + math.max(0, self.board_rows - 1) * self.tile_gap

    if self.board_grid_w > tile_layer_w or self.board_grid_h > tile_layer_h then
        return false
    end

    self.board_content_x = math.max(0, math.floor((tile_layer_w - self.board_grid_w) / 2))
    self.board_content_y = math.max(0, math.floor((tile_layer_h - self.board_grid_h) / 2))
    self.board_hit_origin_x = self.board_content_x - math.floor(self.tile_gap / 2)
    self.board_hit_origin_y = self.board_content_y - math.floor(self.tile_gap / 2)
    self.board_hit_w = self.board_cols * self.cell_stride_x
    self.board_hit_h = self.board_rows * self.cell_stride_y
    return true
end

function Game:relayout_board_tiles()
    if not self.ui.tiles then
        return
    end

    for row = 1, self.max_board_rows do
        for col = 1, self.max_board_cols do
            local tile = self.ui.tiles[row] and self.ui.tiles[row][col]
            if tile then
                local active = row <= self.board_rows and col <= self.board_cols
                tile.active = active
                if active then
                    local tile_x, tile_y = self:get_board_cell_pos(row, col)
                    tile.x = tile_x
                    tile.y = tile_y
                    tile.image:set_pos(tile_x, tile_y)
                else
                    tile.x = -self.tile_w
                    tile.y = -self.tile_h
                    tile.image:set_pos(-self.tile_w, -self.tile_h)
                    tile.rendered_src = nil
                    tile.rendered_visible = false
                    tile.rendered_selected = false
                    set_image_visible(tile.image, false)
                end
            end
        end
    end

    self:mark_all_tiles_dirty()
end

function Game:screen_to_board_cell(screen_x, screen_y)
    local root_x, root_y = self:get_root_offset()
    local local_x = screen_x - root_x - Config.BOARD_X - tile_layer_inset
    local local_y = screen_y - root_y - Config.BOARD_Y - tile_layer_inset
    local hit_origin_x = self.board_hit_origin_x
    local hit_origin_y = self.board_hit_origin_y
    local hit_width = self.board_hit_w
    local hit_height = self.board_hit_h

    if local_x < hit_origin_x or local_y < hit_origin_y then
        return nil
    end
    if local_x >= hit_origin_x + hit_width or local_y >= hit_origin_y + hit_height then
        return nil
    end

    local col = math.floor((local_x - hit_origin_x) / self.cell_stride_x) + 1
    local row = math.floor((local_y - hit_origin_y) / self.cell_stride_y) + 1
    if not self:is_inside_board(row, col) then
        return nil
    end
    return row, col
end

function Game:is_inside_board(row, col)
    return row >= 1 and row <= self.board_rows and col >= 1 and col <= self.board_cols
end

function Game:get_cell(row, col)
    if row >= 0 and row <= self.board_rows + 1 and col >= 0 and col <= self.board_cols + 1 then
        if self:is_inside_board(row, col) then
            return self.board[row][col]
        end
        return 0
    end
    return nil
end

function Game:is_empty_at(row, col)
    return self:get_cell(row, col) == 0
end

function Game:is_line_clear(row1, col1, row2, col2)
    if row1 == row2 then
        local step = col2 > col1 and 1 or -1
        for col = col1 + step, col2 - step, step do
            if self:get_cell(row1, col) ~= 0 then
                return false
            end
        end
        return true
    end
    if col1 == col2 then
        local step = row2 > row1 and 1 or -1
        for row = row1 + step, row2 - step, step do
            if self:get_cell(row, col1) ~= 0 then
                return false
            end
        end
        return true
    end
    return false
end

function Game:find_direct_or_corner_path(start_row, start_col, end_row, end_col)
    if (start_row == end_row or start_col == end_col) and self:is_line_clear(start_row, start_col, end_row, end_col) then
        return {
            copy_point(start_row, start_col),
            copy_point(end_row, end_col),
        }
    end

    local corners = {
        { row = start_row, col = end_col },
        { row = end_row, col = start_col },
    }
    for _, corner in ipairs(corners) do
        if self:is_empty_at(corner.row, corner.col) and self:is_line_clear(start_row, start_col, corner.row, corner.col) and self:is_line_clear(corner.row, corner.col, end_row, end_col) then
            return {
                copy_point(start_row, start_col),
                copy_point(corner.row, corner.col),
                copy_point(end_row, end_col),
            }
        end
    end

    return nil
end

function Game:find_path(row1, col1, row2, col2)
    if row1 == row2 and col1 == col2 then
        return nil
    end

    local value = self:get_cell(row1, col1)
    if value == 0 or value ~= self:get_cell(row2, col2) then
        return nil
    end

    local direct_or_corner = self:find_direct_or_corner_path(row1, col1, row2, col2)
    if direct_or_corner then
        return compress_path(direct_or_corner)
    end

    local directions = {
        { row = -1, col = 0 },
        { row = 1, col = 0 },
        { row = 0, col = -1 },
        { row = 0, col = 1 },
    }

    for _, direction in ipairs(directions) do
        local probe_row = row1 + direction.row
        local probe_col = col1 + direction.col
        while probe_row >= 0 and probe_row <= self.board_rows + 1 and probe_col >= 0 and probe_col <= self.board_cols + 1 and self:is_empty_at(probe_row, probe_col) do
            local tail_path = self:find_direct_or_corner_path(probe_row, probe_col, row2, col2)
            if tail_path then
                local full_path = {
                    copy_point(row1, col1),
                    copy_point(probe_row, probe_col),
                }
                for _, point in ipairs(tail_path) do
                    full_path[#full_path + 1] = copy_point(point.row, point.col)
                end
                return compress_path(full_path)
            end
            probe_row = probe_row + direction.row
            probe_col = probe_col + direction.col
        end
    end

    return nil
end

function Game:remaining_tile_count()
    local count = 0
    for row = 1, self.board_rows do
        for col = 1, self.board_cols do
            if self.board[row][col] ~= 0 then
                count = count + 1
            end
        end
    end
    return count
end

function Game:find_available_pair()
    local cells = {}
    for row = 1, self.board_rows do
        for col = 1, self.board_cols do
            local value = self.board[row][col]
            if value ~= 0 then
                cells[#cells + 1] = {
                    row = row,
                    col = col,
                    value = value,
                }
            end
        end
    end

    for left_index = 1, #cells do
        local left = cells[left_index]
        for right_index = left_index + 1, #cells do
            local right = cells[right_index]
            if left.value == right.value then
                local path = self:find_path(left.row, left.col, right.row, right.col)
                if path then
                    return {
                        first = copy_point(left.row, left.col),
                        second = copy_point(right.row, right.col),
                        path = path,
                    }
                end
            end
        end
    end

    return nil
end

function Game:reset_board_matrix()
    self:invalidate_available_pair_cache()
    self:mark_all_tiles_dirty()
    self.board = {}
    for row = 1, self.board_rows do
        self.board[row] = {}
        for col = 1, self.board_cols do
            self.board[row][col] = 0
        end
    end
end

function Game:fill_board_from_values(values)
    local index = 1
    for row = 1, self.board_rows do
        for col = 1, self.board_cols do
            self.board[row][col] = values[index]
            index = index + 1
        end
    end
end

function Game:build_pair_values(kind_count)
    local values = {}
    local pair_count = (self.board_rows * self.board_cols) / 2
    local active_ids = {}
    for index = 1, kind_count do
        active_ids[index] = Config.TILE_IDS[index]
    end

    for index = 1, pair_count do
        local tile_id = active_ids[((index - 1) % #active_ids) + 1]
        values[#values + 1] = tile_id
        values[#values + 1] = tile_id
    end

    return values
end

function Game:generate_solvable_board(kind_count)
    local values = self:build_pair_values(kind_count)
    for _ = 1, Config.MAX_GENERATE_RETRY do
        shuffle_in_place(values)
        self:fill_board_from_values(values)
        local pair = self:find_available_pair()
        if pair then
            self:set_available_pair_cache(pair)
            return true
        end
    end
    self:set_available_pair_cache(nil)
    return false
end

function Game:shuffle_remaining_tiles()
    local positions = {}
    local values = {}
    for row = 1, self.board_rows do
        for col = 1, self.board_cols do
            if self.board[row][col] ~= 0 then
                positions[#positions + 1] = { row = row, col = col }
                values[#values + 1] = self.board[row][col]
            end
        end
    end

    if #values <= 2 then
        self:refresh_available_pair_cache()
        return true
    end

    for _ = 1, Config.MAX_SHUFFLE_RETRY do
        shuffle_in_place(values)
        for index, position in ipairs(positions) do
            self.board[position.row][position.col] = values[index]
        end
        local pair = self:find_available_pair()
        if pair then
            self:set_available_pair_cache(pair)
            return true
        end
    end

    self:set_available_pair_cache(nil)
    return false
end

function Game:get_board_cell_pos(row, col)
    local x = self.board_content_x + (col - 1) * self.cell_stride_x
    local y = self.board_content_y + (row - 1) * self.cell_stride_y
    return x, y
end

function Game:get_board_path_point(row, col)
    local x
    if col <= 0 then
        x = self.board_hit_origin_x
    elseif col > self.board_cols then
        x = self.board_hit_origin_x + self.board_hit_w
    else
        x = self.board_content_x + (col - 1) * self.cell_stride_x + math.floor(self.tile_w / 2)
    end

    local y
    if row <= 0 then
        y = self.board_hit_origin_y
    elseif row > self.board_rows then
        y = self.board_hit_origin_y + self.board_hit_h
    else
        y = self.board_content_y + (row - 1) * self.cell_stride_y + math.floor(self.tile_h / 2)
    end

    return x, y
end

function Game:clear_path_segments()
    for _, segment in ipairs(self.ui.path_segments) do
        destroy_node(segment)
    end
    self.ui.path_segments = {}
end

function Game:render_path_segments()
    self:clear_path_segments()
    if not self.path_points or #self.path_points < 2 then
        return
    end

    for index = 1, #self.path_points - 1 do
        local start_point = self.path_points[index]
        local end_point = self.path_points[index + 1]
        local x1, y1 = self:get_board_path_point(start_point.row, start_point.col)
        local x2, y2 = self:get_board_path_point(end_point.row, end_point.col)

        local segment_x = math.min(x1, x2)
        local segment_y = math.min(y1, y2)
        local segment_w = math.abs(x2 - x1)
        local segment_h = math.abs(y2 - y1)

        if segment_w == 0 then
            segment_x = segment_x - math.floor(Config.PATH_THICKNESS / 2)
            segment_w = Config.PATH_THICKNESS
            segment_h = math.max(segment_h, Config.PATH_THICKNESS)
        else
            segment_y = segment_y - math.floor(Config.PATH_THICKNESS / 2)
            segment_h = Config.PATH_THICKNESS
            segment_w = math.max(segment_w, Config.PATH_THICKNESS)
        end

        local segment = airui.container({
            parent = self.ui.path_layer,
            x = segment_x,
            y = segment_y,
            w = segment_w,
            h = segment_h,
            color = THEME.line,
            radius = math.floor(Config.PATH_THICKNESS / 2)
        })
        self.ui.path_segments[#self.ui.path_segments + 1] = segment
    end
end

function Game:is_cell_selected(row, col)
    return self.selected and self.selected.row == row and self.selected.col == col
end

function Game:is_cell_hinted(row, col)
    if not self.hint_pair then
        return false
    end
    local first = self.hint_pair.first
    local second = self.hint_pair.second
    return (first.row == row and first.col == col) or (second.row == row and second.col == col)
end

function Game:update_tile_widget(row, col)
    local tile = self.ui.tiles[row][col]
    if not tile or not tile.active then
        return
    end
    local value = self.board[row][col]
    local visible = value ~= 0
    local selected = visible and (self:is_cell_selected(row, col) or self:is_cell_hinted(row, col)) or false

    if visible then
        local src = Resources.tile(value, selected)
        if tile.rendered_src ~= src then
            tile.image:set_src(src)
            tile.rendered_src = src
        end
    else
        tile.rendered_src = nil
    end

    if tile.rendered_visible ~= visible then
        set_image_visible(tile.image, visible)
        tile.rendered_visible = visible
    end

    tile.rendered_selected = selected

    if value == 0 then
        return
    end
end

function Game:update_board_widgets()
    if self.force_full_board_refresh then
        for row = 1, self.board_rows do
            for col = 1, self.board_cols do
                self:update_tile_widget(row, col)
            end
        end
        self.force_full_board_refresh = false
        self.dirty_tiles = {}
        return
    end

    local dirty_tiles = self.dirty_tiles
    self.dirty_tiles = {}
    for _, tile in pairs(dirty_tiles) do
        self:update_tile_widget(tile.row, tile.col)
    end
end

function Game:update_footer_buttons()
    self:set_text_if_changed("hint_btn", self.ui.hint_btn, string.format("提示 %d", self.hints_left))
    self:set_text_if_changed("shuffle_btn", self.ui.shuffle_btn, string.format("重排 %d", self.reshuffles_left))
    self:set_text_if_changed("pause_btn", self.ui.pause_btn, self.state == "paused" and "继续" or "暂停")
end

function Game:get_status_line()
    if self.status_override then
        return self.status_override
    end

    if self.state == "ready" then
        return "点开始进入庭院"
    end
    if self.state == "paused" then
        return "游戏暂停中"
    end
    if self.state == "game_over" then
        return "本局结束"
    end
    if self.state == "level_clear" then
        return "关卡完成"
    end
    if self.state == "all_clear" then
        return "满堂圆满"
    end
    if self.selected then
        return "再选一枚相同物件"
    end

    if self.board_has_available_pair == false then
        return "当前无解，试试重排"
    end
    return "寻找一对可连通图块"
end

function Game:update_time_hud()
    local display_seconds = math.max(0, math.ceil(self.remaining_time_ms / 1000))
    if self.last_display_seconds ~= display_seconds or self.hud_cache.time_label == nil then
        self.last_display_seconds = display_seconds
        self:set_text_if_changed("time_label", self.ui.time_label, "剩余 " .. format_time_ms(self.remaining_time_ms))
    end
end

function Game:update_hud()
    local level_title = self.current_level_spec and self.current_level_spec.title or "未开始"
    local level_text = self.current_level_index > 0 and string.format("第%d关 %s %dx%d", self.current_level_index, level_title, self.board_cols, self.board_rows) or "连连看"
    self:set_text_if_changed("level_label", self.ui.level_label, level_text)
    self:set_text_if_changed("score_label", self.ui.score_label, string.format("分数 %04d", self.score))
    self:set_text_if_changed("best_label", self.ui.best_label, string.format("最佳 %04d", self.best_score))
    self:update_time_hud()
    self:set_text_if_changed("status_label", self.ui.status_label, self:get_status_line())
    self:update_footer_buttons()
end

function Game:set_status(text, duration_ms)
    self.status_override = text
    self.status_timer_ms = duration_ms or 0
    self:update_hud()
end

function Game:clear_status_override()
    self.status_override = nil
    self.status_timer_ms = 0
    self:update_hud()
end

function Game:destroy_dialog_secondary_btn()
    if self.ui.dialog_secondary_btn then
        self.ui.dialog_secondary_btn:destroy()
        self.ui.dialog_secondary_btn = nil
    end
end

function Game:hide_dialog()
    set_widget_visible(self.ui.dialog_overlay, false)
    self.dialog.primary_action = nil
    self.dialog.secondary_action = nil
end

function Game:show_dialog(title, message, primary_text, primary_action, secondary_text, secondary_action)
    self.ui.dialog_title:set_text(title or "")
    self.ui.dialog_message:set_text(message or "")
    self.ui.dialog_primary_btn:set_text(primary_text or "确定")
    self.dialog.primary_action = primary_action
    self.dialog.secondary_action = secondary_action
    self:destroy_dialog_secondary_btn()
    if secondary_text ~= nil then
        self.ui.dialog_secondary_btn = airui.button({
            parent = self.ui.dialog_panel,
            x = 72,
            y = 242,
            w = 240,
            h = 40,
            color = THEME.panel_alt,
            text = secondary_text,
            font_size = 18,
            text_color = THEME.text,
            on_click = function()
                local action = self.dialog.secondary_action
                self:hide_dialog()
                if action then
                    action()
                end
            end
        })
    end
    set_widget_visible(self.ui.dialog_overlay, true)
end

function Game:show_start_page()
    self.state = "ready"
    self.current_level_index = 0
    self.current_level_spec = nil
    self.remaining_time_ms = 0
    self.last_display_seconds = nil
    self:set_selected(nil)
    self:set_hint_pair(nil)
    self.path_points = nil
    self.path_timer_ms = 0
    self:invalidate_available_pair_cache()
    self:clear_path_segments()
    set_widget_visible(self.ui.start_page, true)
    self:hide_dialog()
    self:update_board_widgets()
    self:update_hud()
end

function Game:update_best_score()
    if self.score > self.best_score then
        self.best_score = self.score
    end
end

function Game:begin_level(index)
    local spec = self:get_level_spec(index)
    if not spec then
        self.state = "all_clear"
        self:update_best_score()
        self:update_hud()
        self:show_dialog("满堂圆满", string.format("总分 %d\n你已收齐整套庭院珍玩。", self.score), "再来一局", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    self.current_level_index = index
    self.current_level_spec = spec
    self.remaining_time_ms = spec.total_time_ms
    self.last_display_seconds = nil
    self.hints_left = spec.hints
    self.reshuffles_left = spec.reshuffles
    self:set_selected(nil)
    self:set_hint_pair(nil)
    self.path_points = nil
    self.path_timer_ms = 0
    self.hint_timer_ms = 0
    self.status_override = nil
    self.status_timer_ms = 0

    local rows = spec.rows or Config.BOARD_ROWS
    local cols = spec.cols or Config.BOARD_COLS
    if (rows * cols) % 2 ~= 0 or not self:apply_board_layout(rows, cols) then
        self.state = "game_over"
        self:update_hud()
        self:show_dialog("关卡布局异常", "当前关卡尺寸无法生成居中的可解棋盘。", "重新开始", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    self.state = "playing"
    self:hide_dialog()
    set_widget_visible(self.ui.start_page, false)
    self:relayout_board_tiles()

    self:reset_board_matrix()
    if not self:generate_solvable_board(spec.kinds) then
        self.state = "game_over"
        self:show_dialog("牌局异常", "棋盘生成失败，请重新开始。", "重试", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    self:set_status(spec.title, Config.STATUS_FLASH_MS)
    self:update_board_widgets()
    self:update_hud()
end

function Game:start_new_game()
    self.score = 0
    self:begin_level(1)
end

function Game:restart_current_level()
    local target = self.current_level_index > 0 and self.current_level_index or 1
    if self.current_level_index == 0 then
        self.score = 0
    end
    self:begin_level(target)
end

function Game:pause_or_resume()
    if self.state == "playing" then
        self.state = "paused"
        self:update_hud()
        self:show_dialog("暂停中", "庭院静了下来。\n准备好后继续配对。", "继续", function()
            self.state = "playing"
            self:hide_dialog()
            self:update_hud()
        end, "重开本关", function()
            self:restart_current_level()
        end)
        return
    end

    if self.state == "paused" then
        self.state = "playing"
        self:hide_dialog()
        self:update_hud()
    end
end

function Game:check_deadlock_after_move()
    if self:remaining_tile_count() == 0 then
        return
    end

    if self.board_has_available_pair == nil then
        self:refresh_available_pair_cache()
    end

    if self.board_has_available_pair then
        return
    end

    if self.reshuffles_left > 0 then
        self:set_status("当前无解，点重排继续", Config.STATUS_FLASH_MS)
        return
    end

    self.state = "game_over"
    self:update_best_score()
    self:update_hud()
    self:show_dialog("庭院无解", string.format("本局得分 %d\n重排次数已经用完。", self.score), "重新开始", function()
        self:start_new_game()
    end, "退出", function()
        close_window()
    end)
end

function Game:on_level_cleared()
    self.state = "level_clear"
    self:update_best_score()
    self.score = self.score + Config.LEVEL_CLEAR_BONUS * self.current_level_index
    self:update_hud()

    if self.current_level_index >= #Config.LEVELS then
        self.state = "all_clear"
        self:update_best_score()
        self:update_hud()
        self:show_dialog("满堂圆满", string.format("总分 %d\n你完成了全部五关。", self.score), "再来一局", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    local next_index = self.current_level_index + 1
    local next_spec = self:get_level_spec(next_index)
    self:show_dialog("关卡完成", string.format("当前得分 %d\n下一关: %s", self.score, next_spec.title), "下一关", function()
        self:begin_level(next_index)
    end, "退出", function()
        close_window()
    end)
end

function Game:remove_pair(first, second, path)
    self.board[first.row][first.col] = 0
    self.board[second.row][second.col] = 0
    self:mark_point_dirty(first)
    self:mark_point_dirty(second)
    self:set_selected(nil)
    self:set_hint_pair(nil)
    self.hint_timer_ms = 0
    self.path_points = nil
    self.path_timer_ms = 0
    self.score = self.score + Config.MATCH_SCORE + self.current_level_index * 5
    self.remaining_time_ms = self.remaining_time_ms + Config.MATCH_TIME_BONUS_MS
    self:update_best_score()
    self:update_board_widgets()

    if self:remaining_tile_count() == 0 then
        self:on_level_cleared()
        return
    end

    self:refresh_available_pair_cache()
    self:update_hud()
    self:check_deadlock_after_move()
end

function Game:on_tile_click(row, col)
    if self.state ~= "playing" then
        return
    end

    local value = self.board[row][col]
    if value == 0 then
        return
    end

    if self.selected and self.selected.row == row and self.selected.col == col then
        self:set_selected(nil)
        self:update_board_widgets()
        self:update_hud()
        return
    end

    if not self.selected then
        self:set_selected(copy_point(row, col))
        self:update_board_widgets()
        self:update_hud()
        return
    end

    local previous = self.selected
    if self.board[previous.row][previous.col] == value then
        local path = self:find_path(previous.row, previous.col, row, col)
        if path then
            self:remove_pair(previous, copy_point(row, col), path)
            return
        end
    end

    self:set_selected(copy_point(row, col))
    self:set_status("这两枚暂时连不上", 900)
    self:update_board_widgets()
    self:update_hud()
end

function Game:use_hint()
    if self.state ~= "playing" then
        return
    end
    if self.hints_left <= 0 then
        self:set_status("提示次数已用完", 1000)
        return
    end

    local pair = self.available_pair or self:refresh_available_pair_cache()
    if not pair then
        self:set_status("当前无可提示组合", 1000)
        return
    end

    self.hints_left = self.hints_left - 1
    self:set_selected(nil)
    self:set_hint_pair(pair)
    self.hint_timer_ms = Config.HINT_SHOW_MS
    self:update_board_widgets()
    self:update_hud()
end

function Game:use_shuffle()
    if self.state ~= "playing" then
        return
    end
    if self.reshuffles_left <= 0 then
        self:set_status("重排次数已用完", 1000)
        return
    end
    if self:remaining_tile_count() == 0 then
        return
    end

    self.reshuffles_left = self.reshuffles_left - 1
    self:set_selected(nil)
    self:set_hint_pair(nil)
    self.hint_timer_ms = 0
    self.path_points = nil
    self.path_timer_ms = 0

    if not self:shuffle_remaining_tiles() then
        self.state = "game_over"
        self:update_best_score()
        self:update_hud()
        self:show_dialog("重排失败", string.format("本局得分 %d\n无法恢复可解棋盘。", self.score), "重新开始", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    self:mark_all_tiles_dirty()
    self:set_status("已重新整理棋盘", 900)
    self:update_board_widgets()
    self:update_hud()
end

function Game:tick_overlays(delta_ms)
    local board_refreshed = false
    local hud_refreshed = false

    if self.path_timer_ms > 0 then
        self.path_timer_ms = self.path_timer_ms - delta_ms
        if self.path_timer_ms <= 0 then
            self.path_timer_ms = 0
            self.path_points = nil
            self:clear_path_segments()
        end
    end

    if self.hint_timer_ms > 0 then
        self.hint_timer_ms = self.hint_timer_ms - delta_ms
        if self.hint_timer_ms <= 0 then
            self.hint_timer_ms = 0
            self:set_hint_pair(nil)
            board_refreshed = true
            hud_refreshed = true
        end
    end

    if self.status_timer_ms > 0 then
        self.status_timer_ms = self.status_timer_ms - delta_ms
        if self.status_timer_ms <= 0 then
            self.status_override = nil
            self.status_timer_ms = 0
            hud_refreshed = true
        end
    end

    if board_refreshed then
        self:update_board_widgets()
    end

    if hud_refreshed then
        self:update_hud()
    end
end

function Game:update(delta_seconds)
    local delta_ms = math.floor(delta_seconds * 1000)
    self:tick_overlays(delta_ms)

    if self.state ~= "playing" then
        return
    end

    self.remaining_time_ms = self.remaining_time_ms - delta_ms
    if self.remaining_time_ms <= 0 then
        self.remaining_time_ms = 0
        self.state = "game_over"
        self:update_best_score()
        self:update_hud()
        self:show_dialog("时间到了", string.format("本局得分 %d\n还差一点就能清盘。", self.score), "重新开始", function()
            self:start_new_game()
        end, "退出", function()
            close_window()
        end)
        return
    end

    self:update_time_hud()
end

function Game:build_hud()
    self.ui.hud = airui.container({
        parent = self.ui.root,
        x = Config.HUD_X,
        y = Config.HUD_Y,
        w = Config.HUD_W,
        h = Config.HUD_H,
        color = THEME.panel,
        radius = 16,
        -- on_click = function()
        --     log.info("点击了 HUD，测试事件穿透")
        -- end
    })
    self.ui.hud:set_border_color(THEME.border_soft, border_inset)

    self.ui.level_label = airui.label({
        parent = self.ui.hud,
        x = 18,
        y = 14,
        w = 250,
        h = 26,
        text = "连连看",
        font_size = 22,
        color = THEME.text
    })
    self.ui.time_label = airui.label({
        parent = self.ui.hud,
        x = 288,
        y = 14,
        w = 126,
        h = 26,
        text = "剩余 000",
        font_size = 22,
        color = THEME.accent,
        align = airui.TEXT_ALIGN_RIGHT
    })
    self.ui.score_label = airui.label({
        parent = self.ui.hud,
        x = 18,
        y = 48,
        w = 160,
        h = 22,
        text = "分数 0000",
        font_size = 18,
        color = THEME.text_muted
    })
    self.ui.best_label = airui.label({
        parent = self.ui.hud,
        x = 180,
        y = 48,
        w = 120,
        h = 22,
        text = "最佳 0000",
        font_size = 18,
        color = THEME.text_muted
    })
    self.ui.status_label = airui.label({
        parent = self.ui.hud,
        x = 18,
        y = 74,
        w = 396,
        h = 18,
        text = "点开始进入庭院",
        font_size = 16,
        color = THEME.success,
        align = airui.TEXT_ALIGN_CENTER
    })
end

function Game:build_board()
    self.ui.board_panel = airui.container({
        parent = self.ui.root,
        x = Config.BOARD_X,
        y = Config.BOARD_Y,
        w = Config.BOARD_W,
        h = Config.BOARD_H,
        color = THEME.board,
        radius = 18,
        -- on_click = function()
        --     log.info("点击了棋盘背景，测试事件穿透")
        -- end
    })
    self.ui.board_panel:set_border_color(THEME.border_soft, border_inset)

    -- self.ui.path_layer = airui.container({
    --     parent = self.ui.board_panel,
    --     x = tile_layer_inset,
    --     y = tile_layer_inset,
    --     w = Config.BOARD_W - tile_layer_inset * 2,
    --     h = Config.BOARD_H - tile_layer_inset * 2,
    --     -- on_click = function()
    --     --     log.info("点击了棋盘路径层，测试事件穿透")
    --     -- end
    -- })

    self.ui.tile_layer = airui.container({
        parent = self.ui.board_panel,
        x = tile_layer_inset,
        y = tile_layer_inset,
        w = Config.BOARD_W - tile_layer_inset * 2,
        h = Config.BOARD_H - tile_layer_inset * 2,
        -- on_click = function()
        --     log.info("点击了棋盘图块层，测试事件穿透")
        -- end
    })

    for row = 1, self.max_board_rows do
        self.ui.tiles[row] = {}
        for col = 1, self.max_board_cols do
            local tile_x, tile_y = self:get_board_cell_pos(row, col)
            local image = airui.image({
                parent = self.ui.tile_layer,
                src = Resources.tile(Config.TILE_IDS[1], false),
                x = tile_x,
                y = tile_y,
                w = self.tile_w,
                h = self.tile_h,
                opacity = 0,
            })
            self.ui.tiles[row][col] = {
                image = image,
                x = tile_x,
                y = tile_y,
                active = row <= self.board_rows and col <= self.board_cols,
                rendered_src = nil,
                rendered_visible = false,
                rendered_selected = false,
            }
        end
    end

    self:relayout_board_tiles()
end

function Game:build_footer()
    self.ui.footer = airui.container({
        parent = self.ui.root,
        x = Config.FOOTER_X,
        y = Config.FOOTER_Y,
        w = Config.FOOTER_W,
        h = Config.FOOTER_H,
        color = THEME.panel,
        radius = 18,
        -- on_click = function()
        --     log.info("点击了底栏，测试事件穿透")
        -- end
    })
    self.ui.footer:set_border_color(THEME.border_soft, 2)

    self.ui.hint_btn = airui.button({
        parent = self.ui.footer,
        x = 18,
        y = 20,
        w = 92,
        h = 48,
        color = THEME.panel_alt,
        text = "提示 0",
        font_size = 18,
        text_color = THEME.text,
        on_click = function()
            self:use_hint()
        end
    })
    self.ui.shuffle_btn = airui.button({
        parent = self.ui.footer,
        x = 120,
        y = 20,
        w = 92,
        h = 48,
        color = THEME.panel_alt,
        text = "重排 0",
        font_size = 18,
        text_color = THEME.text,
        on_click = function()
            self:use_shuffle()
        end
    })
    self.ui.pause_btn = airui.button({
        parent = self.ui.footer,
        x = 222,
        y = 20,
        w = 92,
        h = 48,
        color = THEME.accent_soft,
        text = "暂停",
        font_size = 18,
        text_color = THEME.accent,
        on_click = function()
            self:pause_or_resume()
        end
    })
    self.ui.exit_btn = airui.button({
        parent = self.ui.footer,
        x = 324,
        y = 20,
        w = 90,
        h = 48,
        color = THEME.accent_soft,
        text = "退出",
        font_size = 18,
        text_color = THEME.accent,
        on_click = function()
            close_window()
        end
    })

    airui.label({
        parent = self.ui.footer,
        x = 0,
        y = 76,
        w = Config.FOOTER_W,
        h = 16,
        text = "支持直连、一折、两折与外框绕行",
        font_size = 14,
        color = THEME.text_muted,
        align = airui.TEXT_ALIGN_CENTER
    })
end

function Game:build_start_page()
    self.ui.start_page = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H,
        color = THEME.page_bg,
        -- on_click = function()
        --     log.info("点击了开始页面，测试事件穿透")
        -- end
    })

    airui.label({
        parent = self.ui.start_page,
        x = 60,
        y = 96,
        w = 360,
        h = 120,
        text = "连连看小游戏",
        font_size = 22,
        color = THEME.text,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = self.ui.start_page,
        x = 52,
        y = 252,
        w = 376,
        h = 84,
        text = "选中两枚相同图块\n若能在两次转折内连通即可消除",
        font_size = 22,
        color = THEME.text,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = self.ui.start_page,
        x = 56,
        y = 356,
        w = 368,
        h = 78,
        text = "包含五个关卡，棋盘会逐步扩展到8列10行。\n支持提示与重排，每次成功配对都会返还一点时间。",
        font_size = 18,
        color = THEME.text_muted,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = self.ui.start_page,
        x = 120,
        y = 498,
        w = 240,
        h = 62,
        color = THEME.accent,
        text = "开始游戏",
        font_size = 28,
        text_color = THEME.panel,
        on_click = function()
            self:start_new_game()
        end
    })

    airui.button({
        parent = self.ui.start_page,
        x = 120,
        y = 578,
        w = 240,
        h = 62,
        color = THEME.panel_alt,
        text = "退出",
        font_size = 24,
        text_color = THEME.text,
        on_click = function()
            close_window()
        end
    })
end

function Game:build_dialog()
    self.ui.dialog_overlay = airui.container({
        parent = self.ui.root,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H,
        color = THEME.page_bg,
        -- on_click = function()
        --     log.info("点击了对话框遮罩，测试事件穿透")
        -- end
    })

    self.ui.dialog_panel = airui.container({
        parent = self.ui.dialog_overlay,
        x = Config.DIALOG_X,
        y = Config.DIALOG_Y,
        w = Config.DIALOG_W,
        h = Config.DIALOG_H,
        color = THEME.panel,
        radius = 18,
        -- on_click = function()
        --     log.info("点击了对话框，测试事件穿透")
        -- end
    })
    self.ui.dialog_panel:set_border_color(THEME.border, 2)

    self.ui.dialog_title = airui.label({
        parent = self.ui.dialog_panel,
        x = 0,
        y = 24,
        w = Config.DIALOG_W,
        h = 34,
        text = "",
        font_size = 30,
        color = THEME.text,
        align = airui.TEXT_ALIGN_CENTER
    })
    self.ui.dialog_message = airui.label({
        parent = self.ui.dialog_panel,
        x = 32,
        y = 82,
        w = Config.DIALOG_W - 64,
        h = 90,
        text = "",
        font_size = 20,
        color = THEME.text_muted,
        align = airui.TEXT_ALIGN_CENTER
    })
    self.ui.dialog_primary_btn = airui.button({
        parent = self.ui.dialog_panel,
        x = 72,
        y = 188,
        w = 240,
        h = 48,
        color = THEME.accent,
        text = "确定",
        font_size = 22,
        text_color = THEME.panel,
        on_click = function()
            local action = self.dialog.primary_action
            self:hide_dialog()
            if action then
                action()
            end
        end
    })
    self.ui.dialog_secondary_btn = nil
    set_widget_visible(self.ui.dialog_overlay, false)
end

function Game:build_ui()
    self.ui.root = airui.container({
        parent = self.parent,
        x = math.floor((logical_width - Config.SCREEN_W) / 2),
        y = math.floor((logical_height - Config.SCREEN_H) / 2),
        w = Config.SCREEN_W,
        h = Config.SCREEN_H,
        color = THEME.page_bg,
        -- on_click = function()
        --     log.info("点击了根容器，测试事件穿透")
        -- end
    })

    self.ui.background = airui.image({
        parent = self.ui.root,
        src = Resources.background,
        x = 0,
        y = 0,
        w = Config.SCREEN_W,
        h = Config.SCREEN_H,
    })

    self:build_hud()
    self:build_board()
    self:build_footer()
    self:build_dialog()
    self:build_start_page()

    self:reset_board_matrix()
    self:update_board_widgets()
    self:update_hud()
end

function Game:destroy()
    self:clear_path_segments()
    destroy_node(self.ui.root)
    self.ui = {
        tiles = {},
        path_segments = {},
    }
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

local function register_board_touch_handler()
    if not airui or not airui.touch_subscribe then
        return
    end

    airui.touch_subscribe(function(state, x, y, _track)
        if not game or not main_container or not (state and x and y) then
            return
        end
        if not win_id or not exwin.is_active(win_id) or state ~= airui.TP_DOWN then
            return
        end

        local logical_x, logical_y = remap_touch_point(x, y)
        local row, col = game:screen_to_board_cell(logical_x, logical_y)
        if row and col then
            game:on_tile_click(row, col)
        end
    end)
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

    local raw_width = Config.SCREEN_W
    local raw_height = Config.SCREEN_H
    local rotation = 0

    if lcd and lcd.getSize then
        local screen_w, screen_h = lcd.getSize()
        if screen_w and screen_h and screen_w > 0 and screen_h > 0 then
            raw_width = screen_w
            raw_height = screen_h
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

    raw_screen_width = raw_width
    raw_screen_height = raw_height
    screen_rotation = rotation
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
        color = 0xffffff,
        -- on_click = function()
        --     log.info("点击了主容器，测试事件穿透")
        -- end
    })

    game = Game.new(main_container)
    game:build_ui()
    game:show_start_page()
    register_board_touch_handler()
    game_timer_id = sys.timerLoopStart(game_tick, Config.FRAME_MS)
end

local function on_destroy()
    stop_game_loop()
    if airui and airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
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
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_LIANLIANKAN_WIN", open_handler)