--[[
@module  map_demo
@summary 1024x600 上的 airui.map 交互界面（含比例尺/测距、收藏点、轨迹、引导、离线路线）
@version 2.0
@date    2026.10.28
@usage
底图仍由同事做好的 airui.map 组件负责（拖动/缩放/定位箭头）。
业务功能全部在 Lua 层通过 airui.shape 覆盖层实现，无需改 C：
  工具栏两行：缩放、回家、跟随、定位；测距、收藏、轨迹、引导、路线。
覆盖层在 on_change（拖动缩放）和 500ms 定时帧（GPS 移动）时重绘。
]]

local common = require "map_common"
local geo = require "geo"
local overlay = require "overlay"
local poi_mod = require "poi"
local track_mod = require "track"
local guide_mod = require "guide"
local route_mod = require "route"
local roadnav = require "roadnav"
local voice = require "voice"
local store_mod = require "store"
local M = {}

-- 模拟行驶速度（米/秒），同时用于出发播报的预计用时与每帧位移
local SIM_SPEED = 10

function M.run()
    local layout = common.layout()
    local rect = layout.map

    -- 背景 + 右侧工具栏底色（与地图浅底区分，形成竖向分区）
    airui.shape({
        x = 0, y = 0,
        w = layout.w, h = layout.h,
        items = {
            { type = "rect", x = 0, y = 0, w = layout.w, h = layout.h,
              fill = true, fill_color = 0xF4F7FB, color = 0xF4F7FB },
            { type = "rect", x = layout.sidebar.x, y = 0,
              w = layout.sidebar.w, h = layout.sidebar.h,
              fill = true, fill_color = 0xE7EDF5, color = 0xE7EDF5 },
            -- 分隔线
            { type = "line", x1 = layout.sidebar.x, y1 = 0,
              x2 = layout.sidebar.x, y2 = layout.sidebar.h,
              color = 0xCFD9E6 },
        },
    })

    local status = airui.label({
        x = 12, y = layout.status_y, w = layout.w - 24, h = 24,
        text = "正在加载离线瓦片",
        font_size = 18, color = 0x24344B,
    })
    local note = airui.label({
        x = 12, y = layout.note_y, w = layout.w - 24, h = 24,
        text = "开封 /sd/tiles 高德矢量 JPEG  |  输入 WGS84，瓦片 GCJ02",
        font_size = 16, color = 0x526277,
    })

    local state = {
        busy = false,
        gps = false,
        tick = 0,
        ready = 0,
        started = false,
        -- 业务模式：nil 普通；"measure" 测距；"poi" 点图选点；
        -- "guide" 点图选目的地；"marker" 下一次点击存为收藏点
        mode = nil,
    }

    -- 各业务模块实例
    local pois = poi_mod.create()
    local track = track_mod.create()
    local guide = guide_mod.create()
    local route = route_mod.create()
    -- 开机自动加载“皇宋大观->鼎立国际城E区”真实道路折线
    route:set_points(roadnav.points, roadnav.name)
    -- 模拟行驶的道路里程（沿路线累计，米）
    local road_dist = 0
    -- 路线起点/终点（道路折线首末点，自定义规划后会更新）
    local road_origin = roadnav.points[1]
    local road_dest = roadnav.points[#roadnav.points]
    -- 开机即进入引导：目的地为鼎立国际城E区
    guide:set_destination({ name = "鼎立国际城E区",
        lon = road_dest.lon, lat = road_dest.lat })

    -- 转弯播报：指向下一条未播转弯。默认内置路线，自定义规划后整体替换。
    local turns_list = roadnav.turns or {}
    local turn_i = 1
    local depart_said = false

    -- 离线点选规划：正在编辑的途经点
    local plan_pts = {}

    -- 角度差归一化到 -180~180（左转为正、右转为负）
    local function angle_diff(a, b)
        local d = (b - a + 540) % 360 - 180
        return d
    end

    --[[由一组折线点推断转弯播报点（纯本地，无需道路网）
    对每个中间点比较前后两段方位角，偏转超过阈值即记一个转弯。
    @return table { {at=距起点米, verb=中文动作}, ... }
    ]]
    local function build_turns(points, seg_len)
        local turns = {}
        local acc = 0 -- 当前点距起点里程
        for i = 2, #points - 1 do
            acc = acc + seg_len[i - 1]
            local b1 = geo.bearing(points[i - 1].lon, points[i - 1].lat,
                points[i].lon, points[i].lat)
            local b2 = geo.bearing(points[i].lon, points[i].lat,
                points[i + 1].lon, points[i + 1].lat)
            local d = angle_diff(b1, b2) -- >0 左转，<0 右转
            local ad = math.abs(d)
            local verb
            if ad >= 160 then
                verb = "掉头"
            elseif ad >= 35 then
                verb = d > 0 and "左转" or "右转"
            end
            if verb then
                turns[#turns + 1] = { at = acc, verb = verb }
            end
        end
        return turns
    end

    -- 开机即初始化 TTS 音频通路（独立协程，失败不影响地图）
    sys.taskInit(function()
        voice.init({ volume = 35 })
    end)

    -- 测距临时点
    local measure_pts = {}

    -- 最近一帧 GPS，初始在路线起点皇宋大观南门
    local cur = { lon = road_origin.lon, lat = road_origin.lat,
        heading = 30, speed = 0, valid = false }

    local map, ovl
    local scale_label -- 必须在 map 之后创建，否则会被地图控件盖住

    -- 沿路线走 dist 米，返回该处坐标与航向；到终点则停在终点
    local function road_position(dist)
        local pts = route.points
        local remain = dist
        for i = 1, #pts - 1 do
            local seg = route.seg_len[i]
            if remain <= seg then
                local t = seg > 0 and (remain / seg) or 0
                local p1, p2 = pts[i], pts[i + 1]
                local lon = p1.lon + (p2.lon - p1.lon) * t
                local lat = p1.lat + (p2.lat - p1.lat) * t
                return lon, lat, geo.bearing(p1.lon, p1.lat, p2.lon, p2.lat)
            end
            remain = remain - seg
        end
        local pe = pts[#pts]
        local pb = pts[#pts - 1]
        return pe.lon, pe.lat, geo.bearing(pb.lon, pb.lat, pe.lon, pe.lat)
    end

    local function set_note(text)
        note:set_text(text)
    end

    -- 重绘整个覆盖层
    local function redraw()
        if not ovl or map:is_destroyed() then
            return
        end
        ovl:begin()

        route:draw(ovl)
        track:draw(ovl)
        pois:draw(ovl)

        if state.mode == "measure" then
            -- 测距折线（灰紫色）+ 端点
            if #measure_pts >= 2 then
                ovl:add_polyline(measure_pts, 0x7C5CD6, 4)
            end
            for _, p in ipairs(measure_pts) do
                local x, y = ovl:to_screen(p.lon, p.lat)
                ovl:add_dot(x, y, 5, 0x7C5CD6, 0xFFFFFF)
            end
        end

        if state.mode == "plan" then
            -- 规划折线（绿色，与正式路线一致）+ 起点/途经点/终点
            if #plan_pts >= 2 then
                ovl:add_polyline(plan_pts, 0x22B573, 4)
            end
            for i, p in ipairs(plan_pts) do
                local x, y = ovl:to_screen(p.lon, p.lat)
                local color = (i == 1) and 0x22B573 or (i == #plan_pts and 0xEF4444 or 0xF59E0B)
                ovl:add_dot(x, y, 7, color, 0xFFFFFF)
            end
        end

        -- 轻量引导（画在收藏点之上，便于看边缘箭头）
        if guide:active() then
            guide:draw(ovl, cur.valid and cur.lon or nil, cur.valid and cur.lat or nil)
        end

        -- 比例尺（左下角，相对覆盖层局部坐标）
        do
            local clon, clat = common.center(map)
            local mpp = geo.meters_per_pixel(clat, map:get_zoom())
            local bar_m, bar_px, bar_label = geo.nice_scale(mpp)
            local py = rect.h - 24
            ovl:add_scale_bar(16, py, math.floor(bar_px + 0.5), 0x24344B)
            scale_label:set_text(bar_label)
        end

        -- 当前位置车标：最后画，压在路线/收藏点之上（航向由地图自带箭头体现）
        if cur.valid then
            local px, py = ovl:to_screen(cur.lon, cur.lat)
            ovl:add_dot(px, py, 9, 0x1E6FFF, 0xFFFFFF)
        end

        ovl:commit()
    end

    -- 测距总长度
    local function measure_length()
        local total = 0
        for i = 2, #measure_pts do
            total = total + geo.distance(
                measure_pts[i - 1].lon, measure_pts[i - 1].lat,
                measure_pts[i].lon, measure_pts[i].lat)
        end
        return total
    end

    -- 规划折线总长度
    local function plan_length()
        local total = 0
        for i = 2, #plan_pts do
            total = total + geo.distance(
                plan_pts[i - 1].lon, plan_pts[i - 1].lat,
                plan_pts[i].lon, plan_pts[i].lat)
        end
        return total
    end

    -- 应用一条自定义路线：装载折线、本地推断转弯、设目的地、重置引导、移动车标到起点
    local function apply_route(points, name)
        if not route:set_points(points, name) then
            return false
        end
        turns_list = build_turns(route.points, route.seg_len)
        road_origin = route.points[1]
        road_dest = route.points[#route.points]
        road_dist = 0
        turn_i = 1
        depart_said = false
        guide:set_destination({
            name = name .. " 终点",
            lon = road_dest.lon, lat = road_dest.lat,
        })
        cur.lon, cur.lat = road_origin.lon, road_origin.lat
        cur.valid = false
        if map then
            map:set_position({
                lon = road_origin.lon, lat = road_origin.lat,
                heading = 0, valid = true,
            })
            map:set_center(road_origin.lon, road_origin.lat)
        end
        return true
    end

    -- 完成规划：生成路线、保存到 SD 卡、开始引导
    local function finish_plan(plan_btn, guide_btn)
        if #plan_pts < 2 then
            set_note("至少要点 2 个点（起点和终点）才能生成路线")
            return
        end
        local name = string.format("自定义路线_%02d%02d%02d",
            os.date and tonumber(os.date("%H")) or 0,
            os.date and tonumber(os.date("%M")) or 0,
            os.date and tonumber(os.date("%S")) or 0)
        -- 深拷贝一份交给 route，避免后续清空 plan_pts 影响路线
        local points = {}
        for i, p in ipairs(plan_pts) do
            points[i] = { lon = p.lon, lat = p.lat }
        end
        if not apply_route(points, name) then
            set_note("路线生成失败")
            return
        end
        -- 持久化到 SD 卡（只存折线，转弯由设备本地推断）
        local dir = "/sd/map/routes"
        store_mod.mkdir(dir)
        local path = dir .. "/" .. name .. ".json"
        local saved = store_mod.save(path, { name = name, points = points }, true)
        plan_pts = {}
        state.mode = nil
        if plan_btn then plan_btn:set_text("规划路线") end
        redraw()
        local mins = math.floor(route.total / SIM_SPEED / 60 + 0.5)
        set_note(string.format(
            "路线已生成：全程%s、%d 个转弯，预计%d分钟，点“定位开”开始导航（%s）",
            geo.fmt_distance(route.total), #turns_list, mins,
            saved and "已存SD卡" or "未存盘"))
        log.info("plan", name, "点", #points, "转弯", #turns_list,
            "总长", string.format("%.0f", route.total), "存盘", tostring(saved))
    end

    local function show_stats()
        if not map or map:is_destroyed() then
            return
        end
        local s = map:get_stats()
        local lon, lat = common.center(map)
        status:set_text(string.format(
            "z%d  %.5f, %.5f  |  就绪 %d/%d  等待 %d  缺失 %d  |  %.2f MiB",
            map:get_zoom(), lon, lat,
            s.visible_ready, s.visible, s.pending, s.missing,
            s.bytes_used / 1048576))
    end

    -- 地图点击/触摸：先处理业务模式，再做 POI 命中
    local function handle_click(info)
        local lx, ly = info.x, info.y
        -- measure 模式：追加测距点
        if state.mode == "measure" then
            measure_pts[#measure_pts + 1] = { lon = info.lon, lat = info.lat }
            local n = #measure_pts
            if n >= 2 then
                set_note(string.format("测距：%d 点  总长 %s（再点地图继续，点“测距”退出）",
                    n, geo.fmt_distance(measure_length())))
            else
                set_note("测距：已放第一个点，再点地图放下一点")
            end
            redraw()
            return
        end

        -- plan 模式：追加途经点
        if state.mode == "plan" then
            plan_pts[#plan_pts + 1] = { lon = info.lon, lat = info.lat }
            local n = #plan_pts
            if n >= 2 then
                set_note(string.format(
                    "规划中：%d 点  总长 %s（点“完成规划”生成路线，点“撤销”可删末点）",
                    n, geo.fmt_distance(plan_length())))
            else
                set_note("已放起点，再点地图放转弯点 / 终点")
            end
            redraw()
            return
        end

        -- marker 模式：下一次点击直接存为收藏点
        if state.mode == "marker" then
            local name = "标记点" .. tostring(pois:count() + 1)
            pois:add(name, info.lon, info.lat, 0)
            state.mode = nil
            set_note("已收藏：" .. name)
            redraw()
            return
        end

        -- poi / guide 模式：先尝试命中收藏点
        if state.mode == "poi" or state.mode == "guide" then
            local hit = pois:hit_test(ovl, lx, ly)
            if hit then
                if state.mode == "poi" then
                    pois:set_active(hit)
                    set_note(pois:describe(hit, map))
                else
                    guide:set_destination({
                        name = hit.name, lon = hit.lon, lat = hit.lat,
                    })
                    road_dist = 0
                    depart_said, turn_i = false, 1
                    state.mode = nil
                    set_note("引导中：" .. hit.name)
                end
                redraw()
                return
            end
            -- guide 模式点空地：直接把该处作为目的地
            if state.mode == "guide" then
                guide:set_destination({
                    name = string.format("目的地 %.5f,%.5f", info.lon, info.lat),
                    lon = info.lon, lat = info.lat,
                })
                road_dist = 0
                depart_said, turn_i = false, 1
                state.mode = nil
                set_note("引导中：" .. guide.dest.name)
                redraw()
                return
            end
        end

        log.info("map.click", info.lon, info.lat, lx, ly)
        set_note(string.format("点击 %.6f, %.6f", info.lon, info.lat))
    end

    map = airui.map(common.config({
        center = { lon = road_origin.lon, lat = road_origin.lat },
        zoom = 15,
        on_change = function(self, info)
            show_stats()
            log.info("map.view", string.format("z%d %.6f %.6f follow=%s",
                info.zoom, info.lon, info.lat, tostring(info.follow)))
            redraw()
        end,
        on_ready = function()
            state.ready = state.ready + 1
            show_stats()
            redraw()
        end,
        on_click = function(self, info)
            handle_click(info)
        end,
        on_tile_error = function(self, info)
            log.warn("map.tile", info.zoom, info.x, info.y, info.reason or info.error)
        end,
    }))
    assert(map, "地图创建失败")
    map:set_position({
        lon = common.home.lon, lat = common.home.lat,
        heading = 30, valid = true,
    })

    -- 覆盖层（在 map 创建之后）
    ovl = overlay.create(map, rect)

    -- 比例尺文字（必须在 map 之后创建，否则会被地图控件盖住）
    scale_label = airui.label({
        x = 16, y = layout.map.y + layout.map.h - 72, w = 220, h = 22,
        text = "", font_size = 16, color = 0x24344B,
    })

    -- 引导事件回调：更新提示行并语音播报（合并，避免覆盖前面的 TTS 回调）
    guide.on_near = function(g)
        set_note("即将到达：" .. g.dest.name)
        voice.say("前方即将到达目的地", true)
    end
    guide.on_arrive = function(g)
        set_note("已到达目的地：" .. g.dest.name)
        voice.say("已到达目的地，本次导航结束", true)
    end

    -- 路线事件回调
    route.on_waypoint = function(r, wp)
        set_note("已到达途经点：" .. wp.name .. "，继续沿路线前进")
    end
    route.on_finish = function(r)
        set_note("路线已走完全程：" .. r.name)
    end

    -- 右侧竖排工具栏：vbtn 自动向下堆叠，gap() 留分组间隔
    -- 右侧两列网格工具栏
    local sb = layout.sidebar
    local PAD, GAP = 8, 8          -- 栏内边距、按键间距
    local COLW = (sb.w - PAD * 2 - GAP) / 2
    local cur_x, cur_y = PAD, PAD  -- 下一个格子位置
    local row_h = 0

    local colors = {
        normal = { bg = 0xE5EDF9, press = 0xD3E0F2, fg = 0x143E78 },
        primary = { bg = 0x1E6FFF, press = 0x1659CC, fg = 0xFFFFFF },
        ok = { bg = 0x22B573, press = 0x1B945C, fg = 0xFFFFFF },
        warn = { bg = 0xF59E0B, press = 0xD08307, fg = 0xFFFFFF },
    }

    -- 先换行（用于 span=2 按键前留齐整）
    local function newline()
        if cur_x ~= PAD then
            cur_x = PAD
            cur_y = cur_y + row_h + GAP
            row_h = 0
        end
    end

    -- 放一个格子：span=2 横跨整行；fsize 控制字号（普通格用小字防溢出）
    local function cell(text, kind, span, h, fsize, callback)
        if span == 2 then newline() end
        local w = (span == 2) and (COLW * 2 + GAP) or COLW
        local c = colors[kind or "normal"] or colors.normal
        local b = airui.button({
            x = sb.x + cur_x, y = cur_y, w = w, h = h, text = text,
            style = {
                radius = 8,
                bg_color = c.bg,
                pressed_bg_color = c.press,
                text_color = c.fg,
                font_size = fsize,
                border_width = 0,
            },
            on_click = function()
                if state.busy or map:is_destroyed() then
                    return
                end
                callback()
            end,
        })
        row_h = math.max(row_h, h)
        if span == 2 then
            cur_x = PAD
            cur_y = cur_y + h + GAP
            row_h = 0
        else
            cur_x = cur_x + w + GAP
            if cur_x >= sb.w - PAD - 2 then
                cur_x = PAD
                cur_y = cur_y + row_h + GAP
                row_h = 0
            end
        end
        return b
    end
    local function btn(text, kind, callback)
        return cell(text, kind, 1, 44, 18, callback)
    end
    local function widebtn(text, kind, callback)
        return cell(text, kind, 2, 48, 20, callback)
    end
    local function rowgap(px)
        newline()
        cur_y = cur_y + (px or 4)
    end

    -- ── 视图组 ──
    btn("放大 +", nil, function()
        map:set_zoom(math.min(17, map:get_zoom() + 1))
    end)
    btn("缩小 -", nil, function()
        map:set_zoom(math.max(14, map:get_zoom() - 1))
    end)
    btn("回到车位", nil, function()
        state.gps = false
        cur.valid = false
        map:set_follow(false)
        map:set_center(common.home.lon, common.home.lat)
        map:set_zoom(15)
        map:set_position({
            lon = common.home.lon, lat = common.home.lat,
            heading = 30, valid = true,
        })
    end)

    local follow_btn
    follow_btn = btn("跟随关", nil, function()
        local enabled = not map:get_follow()
        map:set_follow(enabled)
        follow_btn:set_text(enabled and "跟随开" or "跟随关")
    end)
    rowgap(6)

    -- ── 导航组 ──
    local gps_btn
    gps_btn = widebtn("开始模拟定位", "primary", function()
        state.gps = not state.gps
        gps_btn:set_text(state.gps and "停止模拟定位" or "开始模拟定位")
        set_note(state.gps and "模拟定位运行中：轨迹/引导/路线均会随位置更新" or
            "已关闭模拟定位")
    end)

    local guide_btn
    guide_btn = btn(guide:active() and "取消引导" or "设目的地", "ok", function()
        if guide:active() then
            guide:cancel()
            voice.stop()
            road_dist = 0
            depart_said, turn_i = false, 1
            guide_btn:set_text("设目的地")
            set_note("已取消目的地引导")
        else
            state.mode = "guide"
            guide_btn:set_text("取消引导")
            set_note("点一个收藏图钉，或直接点地图上的空地作为目的地")
        end
        redraw()
    end)

    local route_btn
    route_btn = btn("SD路线", nil, function()
        if route:loaded() then
            route:clear()
            turns_list = {}
            guide:cancel()
            voice.stop()
            road_dist = 0
            depart_said, turn_i = false, 1
            guide_btn:set_text("设目的地")
            route_btn:set_text("SD路线")
            set_note("已清除当前路线")
            redraw()
            return
        end
        -- 读取固定示例路线文件，走与点选规划相同的应用逻辑（含本地转弯推断）
        local data = store_mod.load("/sd/map/routes/demo_route.json")
        if data and type(data.points) == "table" and #data.points >= 2
            and apply_route(data.points, data.name or "SD路线") then
            route_btn:set_text("清除路线")
            guide_btn:set_text("取消引导")
            set_note("SD路线已加载：" .. route.name ..
                string.format("，全程%s、%d个转弯，点“开始模拟定位”出发",
                    geo.fmt_distance(route.total), #turns_list))
        else
            set_note("路线文件不存在：/sd/map/routes/demo_route.json，可用“规划路线”现场生成")
        end
        redraw()
    end)
    rowgap(6)

    -- ── 路线规划组 ──
    local plan_btn
    plan_btn = btn("规划路线", "warn", function()
        if state.mode == "plan" then
            state.mode = nil
            plan_pts = {}
            plan_btn:set_text("规划路线")
            set_note("已退出规划，草稿已丢弃")
        else
            state.mode = "plan"
            plan_pts = {}
            plan_btn:set_text("放弃规划")
            set_note("规划模式：依次点地图放 起点→转弯点→终点，绿色起点、红色终点")
        end
        redraw()
    end)

    btn("撤销末点", nil, function()
        if state.mode ~= "plan" then
            set_note("请先点“规划路线”进入规划模式")
            return
        end
        if #plan_pts == 0 then
            set_note("还没有可撤销的点")
            return
        end
        plan_pts[#plan_pts] = nil
        set_note(#plan_pts >= 2 and
            string.format("已撤销末点，剩 %d 点，总长 %s", #plan_pts, geo.fmt_distance(plan_length()))
            or "已撤销，可重新从起点开始点")
        redraw()
    end)

    widebtn("完成规划", "ok", function()
        if state.mode ~= "plan" then
            set_note("请先点“规划路线”，在地图上点选起点、转弯点、终点")
            return
        end
        finish_plan(plan_btn, guide_btn)
    end)
    rowgap(6)

    -- ── 工具组 ──
    local measure_btn
    measure_btn = btn("测距", nil, function()
        if state.mode == "measure" then
            state.mode = nil
            measure_pts = {}
            measure_btn:set_text("测距")
            set_note("已退出测距")
        else
            state.mode = "measure"
            measure_pts = {}
            measure_btn:set_text("结束测距")
            set_note("测距模式：依次点地图取点，多点累计总距离")
        end
        redraw()
    end)

    btn("标记此处", nil, function()
        state.mode = "marker"
        set_note("请在地图上点一下要收藏的位置")
    end)

    btn("选收藏点", nil, function()
        state.mode = (state.mode == "poi") and nil or "poi"
        set_note(state.mode and "点一个地图上的图钉查看收藏点详情" or "已退出选点")
        redraw()
    end)

    local track_btn
    track_btn = btn("开始记录", nil, function()
        if track:is_recording() then
            local path = track:stop(os.time and os.time())
            track_btn:set_text("开始记录")
            set_note("轨迹已保存：" .. tostring(path))
        else
            track:start(os.time and os.time())
            track_btn:set_text("停止记录")
            set_note("开始记录轨迹，移动后自动采样")
        end
        redraw()
    end)

    btn("刷新瓦片", nil, function()
        map:refresh()
        redraw()
    end)

    local ui = {
        map = map,
        rect = rect,
        state = state,
        set_note = set_note,
        set_busy = function(busy)
            state.busy = busy and true or false
        end,
        start = function()
            if state.started then
                return
            end
            state.started = true
            sys.taskInit(function()
                while not map:is_destroyed() do
                    if state.gps and not state.busy then
                        state.tick = state.tick + 1
                        local angle = state.tick * 0.12
                        local now = os.time and os.time() or state.tick
                        local lon, lat, heading
                        if guide:active() then
                            -- 模拟 GPS：沿真实道路折线行驶（SIM_SPEED × 0.5s）
                            road_dist = math.min(road_dist + SIM_SPEED * 0.5, route.total)
                            lon, lat, heading = road_position(road_dist)

                            -- 出发播报（进入引导后第一帧，只播一次）
                            if not depart_said then
                                depart_said = true
                                turn_i = 1
                                local km = route.total / 1000
                                local mins = math.floor(route.total / SIM_SPEED / 60 + 0.5)
                                voice.say(string.format(
                                    "已为您规划路线，全程%.1f公里，预计%d分钟，开始导航",
                                    km, mins), true)
                            end

                            -- 转弯播报：距下一条转弯进入 120 米时播报
                            local tn = turns_list[turn_i]
                            if tn and (tn.at - road_dist) <= 120 and road_dist < tn.at then
                                voice.say(string.format("前方%d米，%s",
                                    math.max(0, math.floor(tn.at - road_dist + 0.5)), tn.verb))
                                turn_i = turn_i + 1
                            end
                        else
                            -- 无目的地：绕 home 走椭圆，带航向
                            road_dist = 0
                            heading = (state.tick * 7) % 360
                            lon = common.home.lon + math.sin(angle) * 0.001
                            lat = common.home.lon + math.cos(angle) * 0.0007
                        end
                        map:set_position({
                            lon = lon, lat = lat,
                            heading = heading, valid = true,
                        })
                        -- 模拟地速：相邻帧位移 / 0.5 秒（沿路 5m/帧 = 10 m/s）
                        local speed = cur.valid
                            and geo.distance(cur.lon, cur.lat, lon, lat) / 0.5 or 0
                        cur.lon, cur.lat = lon, lat
                        cur.heading, cur.speed, cur.valid = heading, speed, true

                        track:update(lon, lat, true, now)
                        guide:update(lon, lat, heading, speed, true)
                        route:update(lon, lat, true, speed)
                        redraw()

                        -- 提示行：沿路线行驶时用「沿路剩余里程」，与播报口径一致
                        if guide:active() and route:loaded() and not route.finished then
                            local tn = turns_list[turn_i]
                            local seg = tn and string.format("  下一路口%.0f米后%s",
                                math.max(0, tn.at - road_dist), tn.verb) or ""
                            set_note(string.format(
                                "沿%s  剩余%s / 全程%s  预计%s到达%s",
                                route.name,
                                geo.fmt_distance(route.remaining),
                                geo.fmt_distance(route.total),
                                geo.fmt_duration(route.remaining / SIM_SPEED),
                                seg))
                        else
                            local gtext = guide:status_text()
                            if gtext then
                                set_note(gtext)
                            elseif track:is_recording() then
                                set_note(track:summary())
                            end
                        end
                    end
                    if not map:is_destroyed() then
                        follow_btn:set_text(map:get_follow() and "跟随开" or "跟随关")
                        gps_btn:set_text(state.gps and "停止模拟定位" or "开始模拟定位")
                        show_stats()
                    end
                    sys.wait(500)
                end
            end)
        end,
    }
    log.info("airui.map", "界面已创建", rect.w, rect.h)
    redraw()
    return ui
end

return M
