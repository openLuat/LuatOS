local btn_demo = {}

--demo1
local function event_handler(obj, event)
        if(event == lvgl.EVENT_CLICKED) then
                print("Clicked\n")
        elseif(event == lvgl.EVENT_VALUE_CHANGED) then
                print("Toggled\n")
        end
end

function btn_demo.demo1()
    local label
    local btn1 = lvgl.btn_create(lvgl.scr_act(), nil)
    lvgl.obj_set_event_cb(btn1, event_handler)
    lvgl.obj_align(btn1, nil, lvgl.ALIGN_CENTER, 0, -40)

    label = lvgl.label_create(btn1, nil)
    lvgl.label_set_text(label, "Button")

    local btn2 = lvgl.btn_create(lvgl.scr_act(), nil)
    lvgl.obj_set_event_cb(btn2, event_handler)
    lvgl.obj_align(btn2, nil, lvgl.ALIGN_CENTER, 0, 40)
    lvgl.btn_set_checkable(btn2, true)
    lvgl.btn_toggle(btn2)
    lvgl.btn_set_fit2(btn2, lvgl.FIT_NONE, lvgl.FIT_TIGHT)

    label = lvgl.label_create(btn2, nil)
    lvgl.label_set_text(label, "Toggled")
end

--demo2
function btn_demo.demo2()
	local path_overshoot = lvgl.anim_path_t()
	lvgl.anim_path_init(path_overshoot);
	lvgl.anim_path_set_cb(path_overshoot, "overshoot");

	local path_ease_out = lvgl.anim_path_t()
	lvgl.anim_path_init(path_ease_out);
	lvgl.anim_path_set_cb(path_ease_out, "ease_out");

	local path_ease_in_out = lvgl.anim_path_t()
	lvgl.anim_path_init(path_ease_in_out);
	lvgl.anim_path_set_cb(path_ease_in_out, "ease_in_out");

	--Gum-like button
	local style_gum = lvgl.style_t()
	lvgl.style_init(style_gum);
	lvgl.style_set_transform_width(style_gum, lvgl.STATE_PRESSED, 10);
	lvgl.style_set_transform_height(style_gum, lvgl.STATE_PRESSED, -10);
	lvgl.style_set_value_letter_space(style_gum, lvgl.STATE_PRESSED, 5);
	lvgl.style_set_transition_path(style_gum, lvgl.STATE_DEFAULT, path_overshoot);
	lvgl.style_set_transition_path(style_gum, lvgl.STATE_PRESSED, path_ease_in_out);
	lvgl.style_set_transition_time(style_gum, lvgl.STATE_DEFAULT, 250);
	lvgl.style_set_transition_delay(style_gum, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_transition_prop_1(style_gum, lvgl.STATE_DEFAULT, lvgl.STYLE_TRANSFORM_WIDTH);
	lvgl.style_set_transition_prop_2(style_gum, lvgl.STATE_DEFAULT, lvgl.STYLE_TRANSFORM_HEIGHT);
	lvgl.style_set_transition_prop_3(style_gum, lvgl.STATE_DEFAULT, lvgl.STYLE_VALUE_LETTER_SPACE);

	local btn1 = lvgl.btn_create(lvgl.scr_act(), nil);
	lvgl.obj_align(btn1, nil, lvgl.ALIGN_CENTER, 0, -80);
	lvgl.obj_add_style(btn1, lvgl.BTN_PART_MAIN, style_gum);

	--Instead of creating a label add a values string
	lvgl.obj_set_style_local_value_str(btn1, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, "Gum");

	--Halo on press
	local style_halo = lvgl.style_t()
	lvgl.style_init(style_halo);
	lvgl.style_set_transition_time(style_halo, lvgl.STATE_PRESSED, 400);
	lvgl.style_set_transition_time(style_halo, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_transition_delay(style_halo, lvgl.STATE_DEFAULT, 200);
	lvgl.style_set_outline_width(style_halo, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_outline_width(style_halo, lvgl.STATE_PRESSED, 20);
	lvgl.style_set_outline_opa(style_halo, lvgl.STATE_DEFAULT, lvgl.OPA_COVER);
	lvgl.style_set_outline_opa(style_halo, lvgl.STATE_FOCUSED, lvgl.OPA_COVER);   --Just to be sure, the theme might use it*/
	lvgl.style_set_outline_opa(style_halo, lvgl.STATE_PRESSED, lvgl.OPA_TRANSP);
	lvgl.style_set_transition_prop_1(style_halo, lvgl.STATE_DEFAULT, lvgl.STYLE_OUTLINE_OPA);
	lvgl.style_set_transition_prop_2(style_halo, lvgl.STATE_DEFAULT, lvgl.STYLE_OUTLINE_WIDTH);

	local btn2 = lvgl.btn_create(lvgl.scr_act(), nil);
	lvgl.obj_align(btn2, nil, lvgl.ALIGN_CENTER, 0, 0);
	lvgl.obj_add_style(btn2, lvgl.BTN_PART_MAIN, style_halo);
	lvgl.obj_set_style_local_value_str(btn2, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, "Halo");

	--Ripple on press
	local style_ripple = lvgl.style_t()
	lvgl.style_init(style_ripple);
	lvgl.style_set_transition_time(style_ripple, lvgl.STATE_PRESSED, 300);
	lvgl.style_set_transition_time(style_ripple, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_transition_delay(style_ripple, lvgl.STATE_DEFAULT, 300);
	lvgl.style_set_bg_opa(style_ripple, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_opa(style_ripple, lvgl.STATE_PRESSED, lvgl.OPA_80);
	lvgl.style_set_border_width(style_ripple, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_outline_width(style_ripple, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_transform_width(style_ripple, lvgl.STATE_DEFAULT, -20);
	lvgl.style_set_transform_height(style_ripple, lvgl.STATE_DEFAULT, -20);
	lvgl.style_set_transform_width(style_ripple, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_transform_height(style_ripple, lvgl.STATE_PRESSED, 0);

	lvgl.style_set_transition_path(style_ripple, lvgl.STATE_DEFAULT, path_ease_out);
	lvgl.style_set_transition_prop_1(style_ripple, lvgl.STATE_DEFAULT, lvgl.STYLE_BG_OPA);
	lvgl.style_set_transition_prop_2(style_ripple, lvgl.STATE_DEFAULT, lvgl.STYLE_TRANSFORM_WIDTH);
	lvgl.style_set_transition_prop_3(style_ripple, lvgl.STATE_DEFAULT, lvgl.STYLE_TRANSFORM_HEIGHT);

	local btn3 = lvgl.btn_create(lvgl.scr_act(), nil);
	lvgl.obj_align(btn3, nil, lvgl.ALIGN_CENTER, 0, 80);
	lvgl.obj_add_style(btn3, lvgl.BTN_PART_MAIN, style_ripple);
	lvgl.obj_set_style_local_value_str(btn3, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, "Ripple");
end

return btn_demo

