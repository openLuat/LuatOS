local arc_demo1 = {}

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

function arc_demo1.demo()
    --Create an Arc*/
    local arc = lvgl.arc_create(lvgl.scr_act(), nil)
    lvgl.arc_set_bg_angles(arc, 0, 360);
    lvgl.arc_set_angles(arc, 270, 270);
    lvgl.obj_align(arc, nil, lvgl.ALIGN_CENTER, 0, 0)

    id = sys.timerLoopStart(arc_loader, 20, arc)
end

return arc_demo1
