--[[
@module image_page
@summary 图片组件演示
@version 1.0
@date 2026.01.27
@author 李源龙
@usage
本文件演示airui.image组件的用法，展示图片显示功能。
]]
-- 加载显示驱动
lcd_drv = require("lcd_drv")
-- 加载触摸驱动
tp_drv = require("tp_drv")
local exgnss=require "exgnss"

local map_img
local map_btn
local position_label
local mapTile=require("mapTile")
local lng,lat=0,0
local latlabel,lnglabel
local sta_label
local function latlngfun()
    while true do
        sys.wait(5000)
        if exgnss.is_fix() then
            local rmc=exgnss.rmc(2)
            lng=rmc.lng
            lat=rmc.lat
            lnglabel:set_text("经度:"..lng)
            latlabel:set_text("纬度:"..lat)
        end
    end
end
sys.taskInit(latlngfun)
local function connect_fnc(status)
    if status then
        sta_label:set_text("服务器连接状态：已连接")
    else
        sta_label:set_text("服务器连接状态：未连接")
    end
end
sys.subscribe("CONNECT_SUCCESS",connect_fnc)
local function position()
     while not socket.adapter(socket.dft()) do
            log.warn("http_app_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
    end
    if lng==0 or lat==0 then
        position_label:set_text("位置:还未定位成功")
        return
    end
    local url= string.format("http://iot.openluat.com/api/open/device_get_address?imei=%s&muid=%s&lat=%f&lon=%f", 
    mobile.imei(), mobile.muid(), lat, lng)
    local code, headers, body = http.request("GET", url, nil, nil, {timeout=10000}).wait()
    log.info("http_app_get_file2",code, headers, body)
    local podata=json.decode(body)
    log.info("http_app_get_file2",podata.address)
    position_label:set_text("位置:"..podata.address)
end
local function map()

    while not socket.adapter(socket.dft()) do
        log.warn("http_app_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    if lng==0 or lat==0 then
        log.info("没有定位成功，获取地图失败")
        return
    end
    log.info("mapTile1", lat,lng)
    local url, x, y = mapTile.generate_gaode_url(lng, lat,16)
    log.info("mapTile", url,x,y)
    local code, headers, body_size = http.request("GET", url, nil, nil, {dst="/1.png", timeout=10000}).wait()
    log.info("http_app_get_file2",code)
    -- sys.wait(5000)
    -- 创建可点击图片
    map_img = airui.image({
        src = "/1.png",
        x = 0,
        y = 0,
        w = 256,
        h = 256,
        pivot = {x=1, y=1},
        zoom = 240,
        opacity = 255, -- 透明度
        -- on_click = function(self)
        --     log.info("image", "图片被点击了")
        -- end
    })
end

local function ui_main()
    log.info("IMAGE")
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()
    
    sys.wait(1000)
    local img = airui.image({
            src = "/luadb/cc.jpg",
            x = 0,
            y = 0,
            w = 320,
            h = 480,
            -- opacity =255 , -- 透明度
        })
    lnglabel = airui.label({
        text = "经度：",
        x = 20,
        y = 300,
        w = 200,
        h = 40,
    })
    latlabel = airui.label({
        text = "纬度：",
        x = 20,
        y = 350,
        w = 200,
        h = 40,
    })

    position_label = airui.label({
        text = "位置：",
        x = 20,
        y = 400,
        w = 280,
        h = 40,
    })
    local is_play = false
    map_btn = airui.button({ 
    text = "地图", 
    x = 20, 
    y = 250, 
    w = 50,
    h = 40,
    on_click = function() 
        if is_play then
            -- 当前是“取消”，点击后切换为“地图”
            map_btn:set_text("地图")
            if map_img then
                map_img:destroy()
            end
            is_play = false
        else
            -- 当前是“地图”，点击后切换为“取消”
            map_btn:set_text("取消")
            sys.taskInit(map)
            is_play = true
        end
    end 
    })
    local btn2 = airui.button({ 
    text = "获取位置", 
    x = 200, 
    y = 250, 
    w = 100,
    h = 40,
    on_click = function() 
        sys.taskInit(position)
    end 
    })
    sta_label = airui.label({ 
    text = "服务器连接状态：未连接", 
    x = 20, 
    y = 450, 
    w = 200,
    h = 40, 
    })

end

sys.taskInit(ui_main)