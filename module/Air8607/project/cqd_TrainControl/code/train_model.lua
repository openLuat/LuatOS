-- 广东铁路运行模拟：列车沿线路往返运行，实时统计占用、准点率和线路负载。
local M = {}
M.__index = M

local function distance(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

local function clock_text(seconds)
    local h = math.floor(seconds / 3600) % 24
    local m = math.floor(seconds / 60) % 60
    local s = math.floor(seconds) % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

function M.new(data, config)
    local self = setmetatable({
        data = data,
        config = config,
        station_by_id = {},
        edge_by_id = {},
        edge_by_pair = {},
        edges = {},
        routes = {},
        trains = {},
        line_loads = {},
        alerts = {},
        time = 0
    }, M)

    for _, station in ipairs(data.stations) do
        self.station_by_id[station.id] = station
    end

    for _, edge in ipairs(data.edges) do
        local a = self.station_by_id[edge.from]
        local b = self.station_by_id[edge.to]
        edge.ax, edge.ay = a.x, a.y
        edge.bx, edge.by = b.x, b.y
        edge.from_name, edge.to_name = a.name, b.name
        edge.length = distance(edge.ax, edge.ay, edge.bx, edge.by)
        edge.count = 0
        edge.occupied = false
        edge.busy = false
        table.insert(self.edges, edge)
        self.edge_by_id[edge.id] = edge
        self.edge_by_pair[edge.from .. "|" .. edge.to] = edge
        self.edge_by_pair[edge.to .. "|" .. edge.from] = edge
    end

    for _, route in ipairs(data.routes) do
        local segments = {}
        local cursor = 0
        for i = 1, #route.path - 1 do
            local from_id = route.path[i]
            local to_id = route.path[i + 1]
            local edge = self.edge_by_pair[from_id .. "|" .. to_id]
            assert(edge, "missing edge " .. from_id .. " -> " .. to_id)
            local dir = edge.from == from_id and 1 or -1
            local length = edge.length
            segments[#segments + 1] = {
                edge = edge,
                dir = dir,
                start = cursor,
                finish = cursor + length,
                length = length
            }
            cursor = cursor + length
        end
        route.segments = segments
        route.total = cursor
        route.train = {
            id = route.id,
            route = route,
            pos = cursor * (route.start or 0),
            dir = 1,
            dwell = 0,
            delay = route.delay or 0,
            speed_kmh = route.speed,
            world_speed = 16 + route.speed / 20,
            speed_display = route.speed,
            status = (route.delay or 0) > 0 and ("晚点 " .. route.delay .. " 分") or "正点",
            x = 0, y = 0, angle = 0
        }
        table.insert(self.trains, route.train)
    end

    self:update_train_positions()
    self:recompute_network()
    return self
end

function M:update_train_positions()
    for _, train in ipairs(self.trains) do
        local route = train.route
        local pos = train.pos
        local segment = route.segments[#route.segments]
        for _, seg in ipairs(route.segments) do
            if pos <= seg.finish or seg == route.segments[#route.segments] then
                segment = seg
                break
            end
        end
        local t = (pos - segment.start) / segment.length
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local edge_t = segment.dir == 1 and t or (1 - t)
        local edge = segment.edge
        train.edge = edge
        train.edge_id = edge.id
        train.t = edge_t
        train.x = edge.ax + (edge.bx - edge.ax) * edge_t
        train.y = edge.ay + (edge.by - edge.ay) * edge_t
        local angle = math.atan(edge.by - edge.ay, edge.bx - edge.ax)
        if segment.dir == -1 then angle = angle + math.pi end
        train.angle = angle
        if segment.dir == 1 then
            train.from_name, train.to_name = edge.from_name, edge.to_name
        else
            train.from_name, train.to_name = edge.to_name, edge.from_name
        end
        train.line = edge.line
    end
end

function M:recompute_network()
    for _, edge in ipairs(self.edges) do
        edge.count = 0
    end
    for _, train in ipairs(self.trains) do
        if train.edge then train.edge.count = train.edge.count + 1 end
    end
    local occupied_edges = 0
    local busy_edges = 0
    for _, edge in ipairs(self.edges) do
        edge.occupied = edge.count > 0
        edge.busy = edge.count >= 2
        if edge.occupied then occupied_edges = occupied_edges + 1 end
        if edge.busy then busy_edges = busy_edges + 1 end
    end
    self.occupied_edges = occupied_edges
    self.busy_edges = busy_edges

    local load_by_line = {}
    for _, edge in ipairs(self.edges) do
        local load = load_by_line[edge.line]
        if not load then
            load = { name = edge.line, total = 0, occupied = 0, trains = 0 }
            load_by_line[edge.line] = load
        end
        load.total = load.total + 1
        if edge.occupied then
            load.occupied = load.occupied + 1
            load.trains = load.trains + edge.count
        end
    end
    self.line_loads = {}
    for _, name in ipairs(self.data.line_order) do
        local load = load_by_line[name]
        if load then
            load.percent = load.total > 0 and math.floor(load.occupied * 100 / load.total + 0.5) or 0
            if load.percent >= 70 then
                load.level = "high"
            elseif load.percent >= 40 then
                load.level = "mid"
            else
                load.level = "low"
            end
            table.insert(self.line_loads, load)
        end
    end

    local delayed_count = 0
    local avg_speed = 0
    for i, train in ipairs(self.trains) do
        if train.delay > 0 then delayed_count = delayed_count + 1 end
        train.speed_display = math.floor(train.speed_kmh + math.sin(self.time / 7 + i) * 3 + 0.5)
        avg_speed = avg_speed + train.speed_display
    end
    self.delayed_count = delayed_count
    self.online = #self.trains
    self.on_time = self.online > 0 and (self.online - delayed_count) * 100 / self.online or 100
    self.avg_speed = self.online > 0 and avg_speed / self.online or 0
    self.occupancy = #self.edges > 0 and occupied_edges * 100 / #self.edges or 0
    self.passenger = 12.6 + math.sin(self.time / 17) * 0.9 + math.sin(self.time / 6) * 0.3
    self.alerts_count = delayed_count + busy_edges

    self.alerts = {}
    for _, train in ipairs(self.trains) do
        if train.delay > 0 then
            table.insert(self.alerts, train.id .. " 晚点 " .. train.delay .. " 分 · " .. train.line)
            if #self.alerts >= 2 then break end
        end
    end
    for _, edge in ipairs(self.edges) do
        if edge.busy then
            table.insert(self.alerts, edge.line .. " " .. edge.from_name .. "—" .. edge.to_name ..
                " 占用 " .. edge.count .. " 列")
            if #self.alerts >= 3 then break end
        end
    end
    if #self.alerts == 0 then
        table.insert(self.alerts, "全网运行平稳，暂无新增告警")
    end
end

function M:step(dt)
    self.time = self.time + dt
    for _, train in ipairs(self.trains) do
        if train.dwell > 0 then
            train.dwell = train.dwell - dt
            if train.dwell < 0 then train.dwell = 0 end
        else
            local route = train.route
            train.pos = train.pos + train.dir * train.world_speed * dt
            if train.pos >= route.total then
                train.pos = route.total
                train.dir = -1
                train.dwell = 2.2
            elseif train.pos <= 0 then
                train.pos = 0
                train.dir = 1
                train.dwell = 2.2
            end
        end
    end
    self:update_train_positions()
    self:recompute_network()
end

function M:snapshot()
    local total_seconds = self.config.start_seconds + math.floor(self.time)
    local trains = {}
    for _, train in ipairs(self.trains) do
        trains[#trains + 1] = {
            id = train.id,
            x = train.x,
            y = train.y,
            angle = train.angle,
            edge_id = train.edge_id,
            from_name = train.from_name,
            to_name = train.to_name,
            status = train.status,
            delay = train.delay,
            speed_display = train.speed_display,
            line = train.line
        }
    end
    local loads = {}
    for _, load in ipairs(self.line_loads) do
        loads[#loads + 1] = {
            name = load.name,
            percent = load.percent,
            occupied = load.occupied,
            total = load.total,
            trains = load.trains,
            level = load.level
        }
    end
    local edge_states = {}
    for _, edge in ipairs(self.edges) do
        edge_states[#edge_states + 1] = {
            id = edge.id,
            line = edge.line,
            occupied = edge.occupied,
            busy = edge.busy,
            count = edge.count
        }
    end
    return {
        clock = clock_text(total_seconds),
        date = self.config.simulated_date,
        online = self.online,
        delayed = self.delayed_count,
        on_time = self.on_time,
        avg_speed = self.avg_speed,
        occupancy = self.occupancy,
        passenger = self.passenger,
        alerts_count = self.alerts_count,
        trains = trains,
        line_loads = loads,
        edge_states = edge_states,
        alerts = self.alerts,
        busy_edges = self.busy_edges
    }
end

return M
