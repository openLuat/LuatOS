local animation = {}

--新建一个动画
function animation.create(obj,obj_fn,from,to,cb,duration,path)
    local anim = lvgl.anim_create()
    lvgl.anim_set_var(anim,obj)
    lvgl.anim_set_exec_cb(anim, obj_fn)
    lvgl.anim_set_values(anim, from, to)
    lvgl.anim_set_time(anim, duration or 1000)
    lvgl.anim_set_path_str(anim, path or "ease_in")
    if cb then
        lvgl.anim_set_ready_cb(anim, cb)
    end
    return anim
end

function animation.free(anim)
    lvgl.anim_del(anim)
end

--新建一个动画并立即运行，最后删除
function animation.once(obj,obj_fn,from,to,cb,duration,path)
    local anim = animation.create(obj,obj_fn,from,to,nil,duration,path)
    lvgl.anim_set_ready_cb(anim, function()
        animation.free(anim)
        if cb then
            cb()
        end
    end)
    lvgl.anim_start(anim)
end

return animation
