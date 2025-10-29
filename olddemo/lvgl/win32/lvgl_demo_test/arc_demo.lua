local arc_demo = {}

--demo1
function arc_demo.demo1()
    local arc = lvgl.arc_create(lvgl.scr_act(), nil)
    lvgl.arc_set_end_angle(arc, 200)
    lvgl.obj_set_size(arc, 150, 150)
    lvgl.obj_align(arc, nil, lvgl.ALIGN_CENTER, 0, 0)
end

--demo2
local id 
local a = 270;
local function arc_loader(t)
        a=a+5;
        lvgl.arc_set_end_angle(t, a);
        print(a)
        if(a >= 270 + 360) then
            sys.timerStop(id)
            return;
        end
end

function arc_demo.demo2()
    --Create an Arc*/
    local arc = lvgl.arc_create(lvgl.scr_act(), nil)
    lvgl.arc_set_bg_angles(arc, 0, 360);
    lvgl.arc_set_angles(arc, 270, 270);
    lvgl.obj_align(arc, nil, lvgl.ALIGN_CENTER, 0, 0)

    id = sys.timerLoopStart(arc_loader, 20, arc)
end

return arc_demo
