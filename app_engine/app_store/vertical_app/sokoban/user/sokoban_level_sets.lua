local xsokoban_pack = require "sokoban_levels_xsokoban"

local M = {
    sets = {
        {
            id = "xsokoban",
            name = "XSokoban90图",
            levels = (xsokoban_pack and xsokoban_pack.levels) or {},
        },
    },
}

return M
