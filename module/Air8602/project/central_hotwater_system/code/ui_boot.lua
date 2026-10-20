--[[
@module  ui_boot
@summary 开机动画覆盖层（logo + 标题 + 副标题 + 进度条）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在主窗口创建后调用：
  ui_boot.create(sw, sh, T)   -- 建覆盖层（位于最上层）
  ui_boot.set_progress(p)     -- 更新进度 0..100
  ui_boot.destroy()           -- 销毁覆盖层
AirUI 无 CSS 过渡动画，这里用「进度条步进 + 延时销毁」近似设计稿的开机动画。
]]

local W = require "ui_widgets"

local M = {}
local handles = nil

local function sun_items(c)
    return {
        { type = "circle", cx = 21, cy = 21, r = 8, color = c, width = 3 },
        { type = "line", x1 = 21, y1 = 3,  x2 = 21, y2 = 10, color = c, width = 3 },
        { type = "line", x1 = 21, y1 = 32, x2 = 21, y2 = 39, color = c, width = 3 },
        { type = "line", x1 = 3,  y1 = 21, x2 = 10, y2 = 21, color = c, width = 3 },
        { type = "line", x1 = 32, y1 = 21, x2 = 39, y2 = 21, color = c, width = 3 },
        { type = "line", x1 = 9,  y1 = 9,  x2 = 14, y2 = 14, color = c, width = 3 },
        { type = "line", x1 = 33, y1 = 33, x2 = 28, y2 = 28, color = c, width = 3 },
        { type = "line", x1 = 33, y1 = 9,  x2 = 28, y2 = 14, color = c, width = 3 },
        { type = "line", x1 = 9,  y1 = 33, x2 = 14, y2 = 28, color = c, width = 3 },
    }
end

function M.create(sw, sh, T)
    local root = airui.container({
        parent = airui.screen, x = 0, y = 0, w = sw, h = sh,
        color = 0x05080F, radius = 0,
    })
    local cx = math.floor(sw / 2)

    -- logo 方块 + 太阳图形
    local box = airui.container({
        parent = root, x = W.d(cx - 37), y = W.d(206), w = W.d(74), h = W.d(74),
        radius = W.d(22), color = T.accent_soft, border_color = T.cyan, border_width = 1,
    })
    airui.shape({
        parent = box, x = W.d(16), y = W.d(16), w = W.d(42), h = W.d(42),
        items = sun_items(T.cyan),
    })

    W.label(root, 0, 300, sw, 30, "太阳能热水工程控制系统", 17, T.text_bright, airui.TEXT_ALIGN_CENTER)
    W.label(root, 0, 336, sw, 18, "SOLAR HOT WATER CONTROLLER", 10.5, T.text_dim, airui.TEXT_ALIGN_CENTER)

    handles = {
        root = root,
        prog = airui.bar({
            parent = root, x = W.d(cx - 95), y = W.d(392), w = W.d(190), h = W.d(3),
            min = 0, max = 100, value = 0,
            radius = W.d(2), border_width = 0,
            bg_color = 0x1A2130, indicator_color = T.cyan,
        }),
    }
    return root
end

function M.set_progress(p)
    if handles and handles.prog then
        handles.prog:set_value(math.floor(p + 0.5))
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
