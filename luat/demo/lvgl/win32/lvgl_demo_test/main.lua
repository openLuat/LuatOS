_G.sys = require "sys"

local arc = require "arc_demo"
local bar = require "bar_demo"
local btn = require "btn_demo"
local btnmatrix = require "btnmatrix_demo"
local calendar = require "calendar_demo"
local canvas = require "canvas_demo"
local checkbox = require "checkbox_demo"
local chart = require "chart_demo"
local cont = require "cont_demo"
local cpicker = require "cpicker_demo"
local dropdown = require "dropdown_demo"
local gauge = require "gauge_demo"
local img = require "img_demo"
local imgbtn = require "imgbtn_demo"
local keyboard = require "keyboard"
local label = require "label_demo"
local led = require "led_demo"
local line = require "line_demo"
local list = require "list_demo"
local lmeter = require "lmeter_demo"
local msdbox = require "msdbox_demo"
local objmask = require "objmask_demo"
local page = require "page_demo"
local roller = require "roller_demo"
local slider = require "slider_demo"
local spinbox = require "spinbox_demo"
local spinner = require "spinner_demo"
local switch = require "switch_demo"
local table = require "table_demo"
local tabview = require "tabview_demo"
local textarea = require "textarea"
local tileview = require "tileview_demo"
local win = require "win_demo"

_G.symbol = require "symbol"

sys.taskInit(function ()
    log.info("lvgl", lvgl.init(480,320))

    -- arc.demo1()
    -- arc.demo2()
    -- bar.demo()
    -- btn.demo1()
    -- btn.demo2()
    -- btnmatrix.demo()
    -- calendar.demo()
    -- canvas.demo()
    -- checkbox.demo()
    -- chart.demo1()
    -- chart.demo2()
    -- cont.demo()
    -- cpicker.demo()
    -- dropdown.demo1()
    -- dropdown.demo2()
    -- gauge.demo1()
    -- img.demo()
    -- imgbtn.demo()
    -- keyboard.demo()
    -- label.demo()
    -- led.demo()
    -- line.demo()
    -- list.demo()
    -- lmeter.demo()
    -- msdbox.demo()
    -- objmask.demo()
    -- page.demo()
    -- roller.demo()
    -- slider.demo()
    -- spinbox.demo()
    -- spinner.demo()
    -- switch.demo()
    -- table.demo()
    -- tabview.demo()
    -- textarea.demo()
    -- tileview.demo()
    win.demo()

    while true do
        sys.wait(1000)
    end
end)

sys.run()
