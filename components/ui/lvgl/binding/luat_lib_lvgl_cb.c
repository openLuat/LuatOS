/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/


#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"

//#define LUAT_LOG_TAG "lvgl.cb"
//#include "luat_log.h"

static int l_obj_es_cb(lua_State *L, void*ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
    if (lua_isfunction(L, -1)) {
        lua_pushlightuserdata(L, msg->ptr);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 2, 0);
    }
    return 0;
}

static void luat_lv_obj_event_cb(struct _lv_obj_t * obj, lv_event_t event) {
    if (obj->user_data.event_cb_ref == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = l_obj_es_cb;
    msg.ptr = obj;
    msg.arg1 = obj->user_data.event_cb_ref;
    msg.arg2 = event;
    luat_msgbus_put(&msg, 0);
}

static lv_res_t luat_lv_obj_signal_cb(struct _lv_obj_t * obj, lv_signal_t sign, void * param) {
    if (obj->user_data.signal_cb_ref == 0)
        return LV_RES_OK;
    rtos_msg_t msg = {0};
    msg.handler = l_obj_es_cb;
    msg.ptr = obj;
    msg.arg1 = obj->user_data.signal_cb_ref;
    msg.arg2 = sign;
    luat_msgbus_put(&msg, 0);
    return LV_RES_OK;
}

/*
设置组件的事件回调
@api lvgl.obj_set_event_cb(obj, func)
@userdata lvgl组件指针
@func lua函数, 参数有2个 (obj, event), 其中obj是当前对象, event是事件类型, 为整型
@return nil 无返回值
*/
int luat_lv_obj_set_event_cb(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL) {
        LLOGW("obj is NULL when set event cb");
        return 0;
    }
    if (obj->user_data.event_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, obj->user_data.event_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        obj->user_data.event_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_obj_set_event_cb(obj, luat_lv_obj_event_cb);
    }
    else {
        obj->user_data.event_cb_ref = 0;
        lv_obj_set_event_cb(obj, NULL);
    }
    return 0;
}

int luat_lv_keyboard_def_event_cb(lua_State *L) {
    lv_obj_t* kb = lua_touserdata(L, 1);
    lv_event_t event = (lv_event_t)luaL_checkinteger(L, 2);
    lv_keyboard_def_event_cb(kb, event);
    return 0;
}

/*
设置组件的信号回调
@api lvgl.obj_set_signal_cb(obj, func)
@userdata lvgl组件指针
@func lua函数, 参数有2个 (obj, signal), 其中obj是当前对象, signal是信号类型, 为整型
@return nil 无返回值
*/
int luat_lv_obj_set_signal_cb(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL) {
        LLOGW("obj is NULL when set event cb");
        return 0;
    }
    if (obj->user_data.signal_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, obj->user_data.signal_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        obj->user_data.signal_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_obj_set_signal_cb(obj, luat_lv_obj_signal_cb);
    }
    else {
        obj->user_data.signal_cb_ref = 0;
        lv_obj_set_signal_cb(obj, NULL);
    }
    return 0;
}

//========================================================================
#if LV_USE_ANIMATION
static int l_obj_anim_cb(lua_State *L, void*ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
    if (lua_isfunction(L, -1)) {
        lua_pushlightuserdata(L, ptr);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 2, 0);
    }
    return 0;
}

// static void luat_lv_anim_exec_cb(struct _lv_anim_t * anim, lv_coord_t value) {
//     if (anim->user_data.exec_cb_ref == 0)
//         return;
//     rtos_msg_t msg = {0};
//     msg.handler = l_obj_anim_cb;
//     msg.ptr = anim;
//     msg.arg1 = anim->user_data.exec_cb_ref;
//     msg.arg2 = value;
//     luat_msgbus_put(&msg, 0);
// }

static void luat_lv_anim_exec_cb(void* var, lv_coord_t value) {
    lv_anim_t* anim = lv_anim_get(var, luat_lv_anim_exec_cb);
    if (anim == NULL) {
        LLOGW("lv_anim_get return NULL!!!");
        return;
    }
    //LLOGD(">>>>>>>>>>>>>>>>>>>");
    if (anim->user_data.exec_cb_ref == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = l_obj_anim_cb;
    msg.ptr = var;
    msg.arg1 = anim->user_data.exec_cb_ref;
    msg.arg2 = value;
    luat_msgbus_put(&msg, 0);
    // lua_geti(_L, LUA_REGISTRYINDEX, anim->user_data.exec_cb_ref);
    // if (lua_isfunction(_L, -1)) {
    //     lua_pushlightuserdata(_L, var);
    //     lua_pushinteger(_L, value);
    //     lua_call(_L, 2, 0);
    // }
}


/*
设置动画回调
@api lvgl.anim_set_exec_cb(anim, func)
@userdata 动画指针
@userdata lvgl组件指针
@func lua函数, 参数有2个 (obj, value), 其中obj是当前对象, signal是信号类型, 为整型
@return nil 无返回值
*/
int luat_lv_anim_set_exec_cb(lua_State *L) {
    lv_anim_t* anim = lua_touserdata(L, 1);
    if (anim == NULL) {
        LLOGW("obj is NULL when set event cb");
        return 0;
    }
    // lv_obj_t* obj = lua_touserdata(L, 2);
    // anim->user_data.obj = obj;

    if (anim->user_data.exec_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, anim->user_data.exec_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        anim->user_data.exec_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_anim_set_exec_cb(anim, luat_lv_anim_exec_cb);
    }
    else {
        anim->user_data.exec_cb_ref = 0;
        lv_anim_set_exec_cb(anim, NULL);
    }
    return 0;
}

static int l_anim_ready_cb(lua_State *L, void*ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
    if (lua_isfunction(L, -1)) {
        lua_pushlightuserdata(L, msg->ptr);
        lua_call(L, 1, 0);
    }
    return 0;
}

static void luat_lv_anim_ready_cb(lv_anim_t* anim) {
    if (anim->user_data.ready_cb_ref == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = l_anim_ready_cb;
    msg.ptr = anim;
    msg.arg1 = anim->user_data.ready_cb_ref;
    luat_msgbus_put(&msg, 0);
}
/*
设置动画回调
@api lvgl.anim_set_ready_cb(anim, func)
@userdata 动画指针
@userdata lvgl组件指针
@func lua函数, 参数有1个 (anim), 其中anim是当前对象
@return nil 无返回值
*/
int luat_lv_anim_set_ready_cb(lua_State *L) {
    lv_anim_t* anim = lua_touserdata(L, 1);
    if (anim == NULL) {
        LLOGW("anim is NULL when set event cb");
        return 0;
    }
    if (anim->user_data.ready_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, anim->user_data.ready_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        anim->user_data.ready_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_anim_set_ready_cb(anim, luat_lv_anim_ready_cb);
    }
    else {
        anim->user_data.ready_cb_ref = 0;
        lv_anim_set_ready_cb(anim, NULL);
    }
    return 0;
}

/*
设置动画回调
@api lvgl.anim_path_set_cb(path, func)
@userdata 动画指针
@userdata lvgl组件指针
@func lua函数, 参数有1个 (path), 其中path是当前对象
@return nil 无返回值
*/
int luat_lv_anim_path_set_cb(lua_State *L) {
    lv_anim_path_t* path = lua_touserdata(L, 1);
    if (path == NULL) {
        LLOGW("path is NULL when set event cb");
        return 0;
    }
    const char* tp = luaL_checkstring(L, 2);
    if (!strcmp("linear", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_linear);
    }
    else if (!strcmp("ease_in", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_ease_in);
    }
    else if (!strcmp("ease_out", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_ease_out);
    }
    else if (!strcmp("ease_in_out", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_ease_in_out);
    }
    else if (!strcmp("overshoot", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_overshoot);
    }
    else if (!strcmp("bounce", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_bounce);
    }
    else if (!strcmp("step", tp)) {
        lv_anim_path_set_cb(path, lv_anim_path_step);
    }
    else {
        //lv_anim_path_set_cb(&path, NULL);
        return 0;
    }
    return 0;
}
#endif

/*
发送事件给组件
@api lvgl.event_send(obj, ent)
@userdata 组件指针
@int      事件id, 例如 lvgl.EVENT_PRESSED
@return bool 成功返回true, 对象已被删除的话返回false或者nil
@return int 底层返回值,如果obj为nil就返回nil
*/
int luat_lv_event_send(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL) {
        LLOGW("obj is NULL when event_send");
        return 0;
    }
    lv_event_t event = luaL_checkinteger(L, 2);
    lv_res_t ret = lv_event_send(obj, event, NULL);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}
