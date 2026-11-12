--[[
@module  ui_curve
@summary 历史趋势曲线封装（airui.chart，shift 模式滚动，值域放大 100 倍保留 0.01℃ 精度）
@version 1.0.0
@date    2026.11.09

为什么放大 100 倍：
airui.chart 的 set_values/push 在 C 层按 lua_tointeger 取整，直接喂 0~100℃ 会丢到 1℃ 精度；
统一乘 100 后 y 轴范围 0~10000，既有 0.01℃ 分辨率，也能直接映射到 0~100.00℃ 刻度。

为什么用 push 而不是 set_values：
shift 模式下 push 一次 O(1)，2s 一个点不需要每次重建 300 元素数组；
断线时不 push，曲线自然停住，不会画出误导的平直线。
]]
local M = {}

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C

--[[
创建一张趋势卡
@param parent userdata 父容器
@param x number
@param y number
@param w number
@param h number
@param title string 卡片标题
@param opts table 可选：series=序列条数（默认 1），axis_ticks=刻度数（默认 5）
@return table {card=, chart=, legend=, push=function(idx,val), set_level=function(lv)}
]]
function M.build(parent, x, y, w, h, title, opts)
    opts = opts or {}
    local card = theme.card(parent, x, y, w, h, C.panel, 12, C.line, 1)

    -- 标题宽度要避让右上角图例：图例每通道 126px，通道越多标题可用宽度越小
    local legend_w = (opts.series or 2) * 126 + 8
    theme.label(card, 14, 8, w - legend_w, 22, title or "历史趋势", 16, C.ink2)

    -- 左侧 Y 轴刻度（chart 自带轴标签是整数，不直观，这里自绘 0~100.0℃）
    local axis_w = 48
    local plot_x = axis_w
    local plot_y = 34
    -- 底部留 24px 给 X 轴刻度：airui 的 x 轴标签画在 chart 对象下方 4px 处，
    -- 不是画在 chart 内部，留 12px 会被卡片下边缘压掉
    local plot_h = h - plot_y - 24
    local plot_w = w - plot_x - 14

    local ticks = opts.axis_ticks or 5
    for i = 0, ticks do
        local v = conf.scale.val_max * i / ticks
        local yy = plot_y + plot_h - math.floor(plot_h * i / ticks) - 8
        theme.label(card, 2, yy, axis_w - 6, 16, string.format("%.1f", v), 12, C.ink3,
            airui.TEXT_ALIGN_RIGHT)
    end
    theme.label(card, 2, plot_y - 14, axis_w - 6, 14, conf.scale.unit, 11, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    -- 两个轴都关掉内置刻度标签，刻度统一自绘，保证字号/颜色完全一致：
    --   Y 轴：内置按原始码整数印 0/2000/…/10000，不直观，改 0.0~100.0℃；
    --   X 轴：内置标签用 LVGL 默认字体（约 14px）+ 固定色 0x6b7280，跟自绘 Y 轴的
    --        12px + C.ink3 对不上，一张图里会出现两截不同风格的刻度文字。
    -- X 轴语义是静态的（窗口内分钟 0→span），不随时间变化，自绘一次没有刷新成本。
    local span_min = math.floor(conf.trend.cap * conf.trend.sample_ms / 60000 + 0.5)
    if span_min < 1 then
        span_min = 1
    end
    local x_ticks = opts.x_ticks or 6
    if x_ticks < 2 then
        x_ticks = 2
    end

    local chart = airui.chart({
        parent = card,
        x = plot_x, y = plot_y, w = plot_w, h = plot_h,
        type = "line",
        update_mode = "shift",
        point_count = conf.trend.cap,
        y_min = conf.trend.y_min,
        y_max = conf.trend.y_max,
        y_axis = { min = conf.trend.y_min, max = conf.trend.y_max, enable = false },
        x_axis = { enable = false },
        line_width = 2,
        point_radius = 0,
        bg_opa = 0,
        border_width = 0,
        hdiv = 4,
        vdiv = 6,
        grid_color = C.line2,
        grid_opa = 55,
    })
    if not chart then
        log.error("ui_curve", "chart 创建失败")
        return nil
    end

    -- X 轴数字：0 = 最左（最旧），span_min = 右端最新
    -- 垂直位置与内置实现一致（chart 下方 4px：C 层 label_y = chart_y + chart_h + 4）
    local x_lw = 40
    for i = 0, x_ticks - 1 do
        local v = math.floor(span_min * i / (x_ticks - 1) + 0.5)
        local lx = math.floor(plot_x + plot_w * i / (x_ticks - 1) - x_lw / 2)
        -- 首尾标签夹在卡片内沿，避免被卡片边界裁剪（内置实现同样会 clamp）
        if lx < 0 then
            lx = 0
        elseif lx + x_lw > w - 2 then
            lx = w - 2 - x_lw
        end
        theme.label(card, lx, plot_y + plot_h + 4, x_lw, 16, tostring(v), 12, C.ink3,
            airui.TEXT_ALIGN_CENTER)
    end

    chart:set_line_color(1, conf.chs[1].color)
    local series_count = 1
    for i = 2, (opts.series or 2) do
        local id = chart:add_series({ color = conf.chs[i].color, name = conf.chs[i].name })
        series_count = id or series_count
    end

    -- 图例：右上角色块 + 通道名 + 当前值
    -- 每通道 126px 预算：色块 10 + 间距 + 名称 60 + 当前值 44（右对齐）
    -- 名称列原来只有 50px，装不下 13 号字的"温度 1"（约 53px），
    -- LVGL 会在空格处折行，第二行的数字被 20px 行高裁掉，看起来像少了字
    local legend = {}
    local lx = w - series_count * 126
    for i = 1, series_count do
        theme.box(card, lx, 13, 10, 10, conf.chs[i].color, 2)
        theme.label(card, lx + 15, 8, 60, 20, conf.chs[i].name, 13, C.ink3)
        legend[i] = theme.label(card, lx + 78, 8, 44, 20, "--", 14, conf.chs[i].color,
            airui.TEXT_ALIGN_RIGHT)
        lx = lx + 126
    end

    local api = {
        card = card,
        chart = chart,
        legend = legend,
        series_count = series_count,
    }

    --[[
    推入一个新采样点
    @param idx number 通道序号（1 起）
    @param val number 工程量（℃）
    ]]
    function api.push(idx, val)
        if idx < 1 or idx > series_count then
            return
        end
        -- 曲线点阵单位 0.01℃：0~100.00℃ 对应 0~10000 = conf.trend.y_max
        pcall(chart.push, chart, idx, math.floor(val * 100 + 0.5))
        if legend[idx] then
            theme.set_text(legend[idx], string.format("%.1f", val))
        end
    end

    --[[
    把 app_data 里保留的历史重新灌回新建的 chart

    页面切换时 ui_main.show() 会销毁整棵 LVGL 树（释放显存），chart 里的点随之消失，
    但 app_data.hist/stamps 一直活着。重建页面后用 set_values 一次性右对齐回填，
    曲线就和切换前接得上，不会"从零开始"。

    为什么前面补 false：set_values 是 i<count 时取 values[i]、超出的位置补空点，
    也就是**左对齐**；而滚动图最新点在右侧，历史应靠右。C 层
    airui_chart_lua_value_to_point 对非数字返回 LV_CHART_POINT_NONE，
    所以用 false 占位最合适（用 nil 会破坏 lua_rawlen 的长度计算，用 0 会画出假 0℃ 直线）。

    为什么 n == 0 也要写满 N 个 false：主页开机第一屏建图时 hist 还是空的，
    传空表会让 airui_chart_set_series_values 因 values == NULL 直接返回，
    N 个位置一个都不写，保持 lv_chart_add_series 的初始状态；之后每 2s push
    只写一格，最左那段"从未被写过"的位置就会参与连线，视觉上是从底部拉起
    一根斜线到第一个实测点，要等整个窗口灌满才消失。统一成"无论 n 是多少
    都写满 N 个位置"，两个页面对同一份 hist 得到的就是同一幅图。

    @param hist table 各通道温度历史（℃）
    @param stamps table 各通道时间戳
    @return table 各通道最后一个时间戳，用于给页面的 last_t 去重
    ]]
    function api.restore(hist, stamps)
        local N = conf.trend.cap
        local last = {}
        for i = 1, series_count do
            local h = hist and hist[i]
            local n = h and #h or 0
            -- n 可能大于 N（改了 cap 但历史没重新裁），只取最新的 m 个
            local m = n
            if m > N then
                m = N
            end
            local base = n - m
            local arr = {}
            local pad = N - m
            for k = 1, pad do
                arr[k] = false
            end
            if m > 0 then
                for k = 1, m do
                    arr[pad + k] = math.floor(h[base + k] * 100 + 0.5)
                end
                if legend[i] then
                    theme.set_text(legend[i], string.format("%.1f", h[n]))
                end
            end
            -- 回填失败必须看得见：pcall 静默吞错会让"整幅点阵没写进去"
            -- 表现为曲线从底部拉出一条斜线，却查不到原因
            local ok, err = pcall(chart.set_values, chart, i, arr)
            if not ok then
                log.warn("ui_curve", "历史回填失败", i, tostring(err))
            end
            if i == 1 then
                log.info("ui_curve", "重建曲线", "cap=" .. N,
                    "历史点数=" .. n, "写入=" .. (ok and "ok" or "fail"))
            end
            last[i] = (stamps and stamps[i]) and stamps[i][n] or nil
        end
        return last
    end

    -- 建完立刻回填；opts.restore = false 可关掉（调试用）
    if opts.restore ~= false then
        local ok, err = pcall(function()
            local data = require "app_data"
            api.last_stamp = api.restore(data.hist, data.stamps)
        end)
        if not ok then
            log.warn("ui_curve", "历史回填失败", tostring(err))
        end
    end

    return api
end

return M
