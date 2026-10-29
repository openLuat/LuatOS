--[[
@module  map_check
@summary 真机上对已经显示的 airui.map 做一轮功能自检
@version 1.0
@date    2026.10.28
@usage
对应 PC auto_test 里不拆控件、也不依赖截图和坏图夹具的部分：
视口加载、中心点、投影往返、缩放边界、平移、跟随、无效定位、快速切换后收敛。
多实例、父容器销毁、缺图、坏图、JPEG 夹具仍由 PC 套件覆盖。
自检结束会把地图收回开封市区回家点，方便接着用手操作。
]]

local common = require "map_common"
local M = {}

function M.run(ui)
    local map = ui.map
    local rect = ui.rect
    local passed = 0

    local function check(value, message)
        assert(value, message)
        passed = passed + 1
        log.info("map.test", "PASS", passed, message)
    end

    local function near(a, b, epsilon, message)
        check(type(a) == "number" and math.abs(a - b) <= epsilon, message)
    end

    local function budget(target)
        local stats = target:get_stats()
        check(stats.bytes_used <= stats.cache_bytes, "解码字节没有超过预算")
        check(stats.visible <= stats.capacity, "可见瓦片没有超过槽位")
        return stats
    end

    local function restore()
        if map:is_destroyed() then
            return
        end
        map:set_follow(false)
        map:set_draggable(true)
        map:set_center(common.home.lon, common.home.lat)
        map:set_zoom(15)
        map:set_position({
            lon = common.home.lon, lat = common.home.lat,
            heading = 30, valid = true,
        })
    end

    ui.set_busy(true)
    ui.set_note("自检中，地图会短暂移动")
    log.info("map.test", "开始", common.probe)

    local ok, err = xpcall(function()
        map:set_draggable(false)
        map:set_follow(false)

        check(io.exists(common.probe), "SD 卡上有中心瓦片 " .. common.probe)

        local s = common.wait_idle(map)
        check(s.visible_ready == s.visible and s.visible > 0, "初始视口瓦片已铺满")
        check(ui.state.ready > 0, "on_ready 已回调")
        check(s.missing == 0 and s.failed == 0, "初始视口没有缺失或失败瓦片")
        budget(map)

        local initially_loaded, initial_visible = s.loaded_total, s.visible
        map:pan(1, 0)
        s = common.wait_idle(map)
        local loaded_delta = s.loaded_total - initially_loaded
        check(s.visible_ready == s.visible, "平移 1 像素后可见瓦片仍然就绪")
        check(loaded_delta >= 0
            and loaded_delta <= math.ceil(rect.h / 256) + 1
            and loaded_delta < initial_visible,
            "平移 1 像素会复用已解码瓦片")
        map:set_center(common.home.lon, common.home.lat)
        common.wait_idle(map)

        local lon, lat = common.center(map)
        near(lon, common.home.lon, 0.000002, "中心经度保持 WGS84 输入")
        near(lat, common.home.lat, 0.000002, "中心纬度保持 WGS84 输入")
        local x, y = common.screen(map, common.home.lon, common.home.lat)
        near(x, rect.w / 2, 1, "中心投影到控件水平中点")
        near(y, rect.h / 2, 1, "中心投影到控件垂直中点")
        local samples = {
            { 40, 40 },
            { rect.w / 2, rect.h / 2 },
            { rect.w - 40, rect.h - 40 },
        }
        for _, pixel in ipairs(samples) do
            local glon, glat = common.geo(map, pixel[1], pixel[2])
            local sx, sy = common.screen(map, glon, glat)
            near(sx, pixel[1], 0.1, "投影往返 x")
            near(sy, pixel[2], 0.1, "投影往返 y")
        end

        map:set_zoom(16)
        local zlon, zlat = common.center(map)
        near(zlon, lon, 0.000002, "缩放后经度不变")
        near(zlat, lat, 0.000002, "缩放后纬度不变")
        common.wait_idle(map)
        check(not pcall(function() map:set_zoom(99) end), "拒绝超过全局上限的缩放")
        check(not pcall(function() map:set_zoom(-1) end), "拒绝负缩放")
        check(not pcall(function() map:set_zoom(13) end), "拒绝低于配置下限的缩放")
        check(not pcall(function() map:set_zoom(18) end), "拒绝高于配置上限的缩放")
        check(map:get_zoom() == 16, "被拒绝的缩放不会改掉当前级别")

        map:set_center(190, 100)
        local blon, blat = common.center(map)
        check(blon >= -180 and blon <= 180, "经度在世界边界被折回")
        check(blat >= -85.051129 and blat <= 85.051129, "纬度被限制在墨卡托范围")
        map:set_center(common.home.lon, common.home.lat)
        map:set_zoom(15)
        common.wait_idle(map)

        map:set_follow(false)
        local bx, by = common.screen(map, common.home.lon, common.home.lat)
        map:pan(96, -48)
        local ax, ay = common.screen(map, common.home.lon, common.home.lat)
        near(ax - bx, 96, 0.1, "水平平移量与请求一致")
        near(ay - by, -48, 0.1, "垂直平移量与请求一致")
        common.wait_idle(map)

        map:set_position({
            lon = common.home.lon + 0.001,
            lat = common.home.lat + 0.001,
            heading = 90, valid = true,
        })
        map:set_follow(true)
        lon, lat = common.center(map)
        near(lon, common.home.lon + 0.001, 0.000002, "跟随定位到最新经度")
        near(lat, common.home.lat + 0.001, 0.000002, "跟随定位到最新纬度")
        map:set_position({
            lon = common.home.lon + 0.002,
            lat = common.home.lat,
            heading = 180, valid = true,
        })
        lon, lat = common.center(map)
        near(lon, common.home.lon + 0.002, 0.000002, "跟随会跟上新的定位")
        map:set_position({ lon = 0, lat = 0, valid = false })
        local invalid_lon = common.center(map)
        near(invalid_lon, lon, 0.000002, "无效定位不会移动中心")
        map:set_follow(false)

        for i = 1, 8 do
            map:set_zoom(14 + i % 4)
            map:set_center(common.home.lon + (i % 3 - 1) * 0.0005, common.home.lat)
            if i % 4 == 0 then
                sys.wait(10)
            end
        end
        map:set_center(common.home.lon, common.home.lat)
        map:set_zoom(15)
        s = common.wait_idle(map)
        check(s.visible_ready == s.visible, "快速缩放和平移后停在最后的视口")
        budget(map)
    end, debug.traceback)

    pcall(restore)
    ui.set_busy(false)
    if not ok then
        error(err, 0)
    end
    log.info("map.test", "MAP_TEST_PASS", passed)
    return passed
end

return M
