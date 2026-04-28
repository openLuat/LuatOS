--[[
  用 airui.container 几何块拼棋子（无 Canvas 时可用）
  白子偏亮、黑子偏暗，风格偏简约示意

  注意：airui.container 是 userdata，不能把 _gx 等字段挂在上面；
  使用「格子表」cell（Lua table）保存 gfx_parts，cell.piece_root 为父容器。
]]

local M = {}

local function add_part(list, o)
    list[#list + 1] = o
end

local function rect(parent, x, y, w, h, color, radius)
    return airui.container({
        parent = parent,
        x = x,
        y = y,
        w = w,
        h = h,
        color = color,
        radius = radius or 0,
    })
end

--- @param cell table 须含 piece_root（父容器）；本模块在 cell.gfx_parts 中保存子块引用
function M.clear(cell)
    if not cell or not cell.gfx_parts then
        return
    end
    for i = #cell.gfx_parts, 1, -1 do
        local o = cell.gfx_parts[i]
        if o and o.destroy then
            pcall(function()
                o:destroy()
            end)
        end
        cell.gfx_parts[i] = nil
    end
    cell.gfx_parts = nil
end

--- @param cell table { piece_root = airui.container, ... }
--- @param ch string 棋子字符 KkQq...
function M.draw(cell, ch)
    M.clear(cell)
    local pr = cell and cell.piece_root
    if not pr or not ch or ch == "." then
        return
    end
    cell.gfx_parts = {}
    local parts = cell.gfx_parts

    local is_w = ch >= "A" and ch <= "Z"
    local fill = is_w and 0xFFF6EA or 0x1E1E1E
    local shade = is_w and 0xD7C4B2 or 0x0A0A0A
    local hi = is_w and 0xFFFFFF or 0x3A3A3A

    local uw = ch:upper()

    if uw == "P" then
        add_part(parts, rect(pr, 20, 10, 16, 14, hi, 8))
        add_part(parts, rect(pr, 16, 24, 24, 18, fill, 4))
        add_part(parts, rect(pr, 14, 38, 28, 10, shade, 2))
    elseif uw == "R" then
        add_part(parts, rect(pr, 12, 36, 32, 12, shade, 2))
        add_part(parts, rect(pr, 16, 22, 24, 18, fill, 3))
        add_part(parts, rect(pr, 14, 16, 28, 8, fill, 2))
        add_part(parts, rect(pr, 14, 12, 6, 6, fill, 1))
        add_part(parts, rect(pr, 25, 12, 6, 6, fill, 1))
        add_part(parts, rect(pr, 36, 12, 6, 6, fill, 1))
    elseif uw == "N" then
        -- 马：明显**不对称**，马头向右侧伸出（与居中对称的象区分）
        add_part(parts, rect(pr, 12, 38, 32, 8, shade, 2))
        add_part(parts, rect(pr, 14, 26, 18, 14, fill, 3))
        add_part(parts, rect(pr, 20, 20, 10, 12, fill, 2))
        add_part(parts, rect(pr, 26, 14, 22, 14, fill, 4))
        add_part(parts, rect(pr, 34, 8, 14, 12, hi, 5))
        add_part(parts, rect(pr, 40, 4, 8, 10, fill, 3))
    elseif uw == "B" then
        -- 象：**左右对称**、**细长**主教冠 + 顶球 + 双尖（像主教帽开口）
        add_part(parts, rect(pr, 13, 36, 30, 9, shade, 2))
        add_part(parts, rect(pr, 25, 18, 5, 20, fill, 2))
        add_part(parts, rect(pr, 20, 8, 16, 14, hi, 7))
        add_part(parts, rect(pr, 17, 3, 9, 7, fill, 2))
        add_part(parts, rect(pr, 30, 3, 9, 7, fill, 2))
        add_part(parts, rect(pr, 26, 5, 4, 4, shade, 1))
    elseif uw == "Q" then
        add_part(parts, rect(pr, 12, 34, 32, 12, shade, 2))
        add_part(parts, rect(pr, 16, 22, 24, 16, fill, 4))
        add_part(parts, rect(pr, 10, 14, 8, 8, hi, 3))
        add_part(parts, rect(pr, 24, 10, 8, 8, hi, 3))
        add_part(parts, rect(pr, 38, 14, 8, 8, hi, 3))
        add_part(parts, rect(pr, 22, 6, 12, 10, fill, 5))
    elseif uw == "K" then
        add_part(parts, rect(pr, 14, 34, 28, 12, shade, 2))
        add_part(parts, rect(pr, 18, 22, 20, 16, fill, 3))
        add_part(parts, rect(pr, 24, 14, 8, 12, fill, 2))
        add_part(parts, rect(pr, 22, 8, 12, 4, hi, 1))
        add_part(parts, rect(pr, 26, 4, 4, 12, hi, 1))
    end
end

return M
