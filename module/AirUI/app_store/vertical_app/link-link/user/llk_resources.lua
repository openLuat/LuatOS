local Config = require("llk_config")

local function detect_resource_root()
    local nested_root = "/luadb/res/"
    if io and io.exists and io.exists(nested_root .. "bg_main.png") then
        return nested_root
    end

    local flat_root = "/luadb/"
    if io and io.exists and io.exists(flat_root .. "bg_main.png") then
        return flat_root
    end

    return nested_root
end

local RESOURCE_ROOT = detect_resource_root()

local function resolve_resource_path(name)
    return RESOURCE_ROOT .. name
end

local Resources = {
    background = resolve_resource_path("bg_main.png"),
    tiles = {},
    tiles_selected = {},
}

for _, tile_id in ipairs(Config.TILE_IDS) do
    Resources.tiles[tile_id] = resolve_resource_path(tile_id .. ".png")
    Resources.tiles_selected[tile_id] = resolve_resource_path(tile_id .. "_selected.png")
end

function Resources.tile(tile_id, selected)
    if selected then
        return Resources.tiles_selected[tile_id] or Resources.tiles[tile_id]
    end
    return Resources.tiles[tile_id]
end

return Resources