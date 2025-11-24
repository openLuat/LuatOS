--加载sys库
_G.sys = require("sys")


local num = 10
local username = "张三"
local appdata = {
    -- age = num,
    person = {
        name = username,
        age = num
    }
}

local function event_handler(obj, event)
    if (event == lvgl.EVENT_CLICKED) then
        appdata.person.age = appdata.person.age + 1
        airui.refresh_text("text_area_2", appdata)
        log.info("button clicked age=", appdata.person.age)
    end
end

local appfuncs = {
    update_age = event_handler
}


sys.taskInit(function()
    -- local uiJson = io.open("/luadb/ui.json")
    -- local ui_path = "/luadb/ui.json"
    local ui_path = "/luadb/demo_2.json"
    local uiJson = io.open(ui_path)
    local ui = json.decode(uiJson:read("*a"))
    log.info("ui", ui, ui.pages[1].children[1].name)
    log.info("初始化lvgl", lvgl.init(ui.project_settings.resolution.width, ui.project_settings.resolution.height))
    
    airui.init(ui_path, {data = appdata, funcs = appfuncs})

    local button = airui.get_widget("button_2")
    sys.wait(5000)
    -- airui.del_widget(button)
end)


sys.run()
