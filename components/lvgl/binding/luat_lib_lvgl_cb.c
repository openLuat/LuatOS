
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
