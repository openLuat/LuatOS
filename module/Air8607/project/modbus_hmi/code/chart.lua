--[[
@module  chart
@summary 曲线辅助：迷你趋势线 + 纵轴可视范围计算
@version 3.0.0
@date    2026.10.25

曲线本体已全部交给 airui 原生 chart（airui.chart，LVGL lv_chart），
由 C 层绘制网格、坐标轴刻度与标签、渐变填充。
本模块只保留原生没有的部分：
  · spark     仪表盘 KPI 卡里的迷你趋势线（216x22，太小，用原生 chart 反而累赘）
  · vis_range 纵轴可视范围（原生 chart 的 y_min/y_max 是固定的整数，
               自适应量程要在 Lua 侧算好再喂回去）
]]
local theme = require "theme"

local M = {}
local C = theme.C

-- ==================== 迷你趋势线 ====================
-- 迷你趋势线：宽度有限，把历史点全画上去会糊成一片（216px 里塞 80 个点，
-- 间距不到 3px，比 2px 的线宽还窄），看起来像"每个时刻有一堆点"。
-- 按宽度抽稀，保证每个点至少占 4px；只取最近的一段，越旧的点越不重要。
function M.spark(hist, w, h, color)
    local n = #hist
    if n < 2 then return {} end
    local max_pts = math.max(8, math.floor(w / 4))
    local s = (n > max_pts) and (n - max_pts + 1) or 1
    local cnt = n - s + 1
    if cnt < 2 then return {} end

    local mn, mx = hist[s], hist[s]
    for i = s + 1, n do
        if hist[i] < mn then mn = hist[i] end
        if hist[i] > mx then mx = hist[i] end
    end
    if mx - mn < 0.0001 then mx = mn + 1 end
    local pad = 2
    local xspan, yspan = w - 2 * pad, h - 2 * pad
    local function px(i) return pad + xspan * (i - 1) / (cnt - 1) end
    local function py(v) return pad + yspan * (1 - (v - mn) / (mx - mn)) end
    local items = {}
    for i = 0, cnt - 2 do
        items[#items + 1] = {
            type = "line", x1 = px(i), y1 = py(hist[s + i]),
            x2 = px(i + 1), y2 = py(hist[s + i + 1]),
            color = color, width = 2,
        }
    end
    return items
end

--[[
纵轴可视范围：以数据自身的 min/max 为主，告警阈值只用来兜底"最小跨度"。

注意：不能把 lo/hi 直接当显示边界 —— 那样环境温度 24.0~25.6 的波动
会被撑到 10~32 的量程里，214px 高的图上只占 16px，看起来就是一条直线。
参考量程（hi-lo）在这里只用于推导最小跨度，保证数据恒定时窗口不会退化为 0。

@param hist 历史数组
@param pt   点位表（用 hi/lo，其次 dhi/dlo）
@return mn, mx
]]
function M.vis_range(hist, pt)
    local nn = #hist
    if nn < 1 then return 0, 1 end
    local mn, mx = hist[1], hist[1]
    for i = 2, nn do
        if hist[i] < mn then mn = hist[i] end
        if hist[i] > mx then mx = hist[i] end
    end
    local ref = 0
    if pt.hi and pt.lo then
        ref = pt.hi - pt.lo
    elseif pt.dhi and pt.dlo then
        ref = pt.dhi - pt.dlo
    end
    local min_span
    if ref > 0 then
        min_span = ref * 0.06
    else
        min_span = math.max(math.abs(mn + mx) * 0.01, 0.5)
    end
    local span = mx - mn
    if span < min_span then
        local c = (mn + mx) / 2
        mn, mx = c - min_span / 2, c + min_span / 2
    else
        local p = span * 0.15
        mn, mx = mn - p, mx + p
    end
    if mx - mn < 0.0001 then mx = mn + 1 end
    return mn, mx
end

return M
