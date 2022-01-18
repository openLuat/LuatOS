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

typedef struct
{
    lv_event_code_t filter;
    int event_cb_ref;
    int user_data_ref;
} luat_event_dsc_t;

typedef struct
{
    int dsc_cnt;
    luat_event_dsc_t *dsc;
} luat_obj_event_user_data_t;

static void luat_lv_obj_event_cb(lv_event_t *event) {
    luat_obj_event_user_data_t *user_data = event->current_target->luat_user_data;

    if (user_data == NULL)
        return;

    lua_State *L = event->user_data;
    for (int i = 0; i < user_data->dsc_cnt; i++) {
        if(user_data->dsc[i].filter == LV_EVENT_ALL || user_data->dsc[i].filter == event->code) {
            printf("%s call lua\n", __FUNCTION__);
            lua_geti(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
            lua_pushlightuserdata(L, event);
            lua_call(L, 1, 0);
        }
    }

    if (event->code == LV_EVENT_DELETE)
    {
        for (int i = 0; i < user_data->dsc_cnt; i++) {
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].user_data_ref);
        }
        if (user_data->dsc != NULL)
            lv_mem_free(user_data->dsc);
        lv_mem_free(user_data);
    }
}

/*
设置组件的事件回调
@api lvgl.obj_add_event_cb(obj, func)
@userdata lvgl组件指针
@func lua函数, 参数有2个 (obj, event), 其中obj是当前对象, event是事件类型, 为整型
@return nil 无返回值
*/
int luat_lv_obj_add_event_cb(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL) {
        LLOGW("obj is NULL when set event cb");
        return 0;
    }

    if (!lua_isfunction(L, 2)) {
        LLOGW("cb isn't function");
        return 0;
    }

    lv_event_code_t filter = luaL_checkinteger(L, 3);

    lua_pushvalue(L, 2);
    int event_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    lua_pushvalue(L, 4);
    int user_data_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    luat_obj_event_user_data_t *user_data = obj->luat_user_data;
    if (user_data == NULL)
    {
        user_data = lv_mem_alloc(sizeof(luat_obj_event_user_data_t));
        user_data->dsc_cnt = 0;
        user_data->dsc = NULL;
        obj->luat_user_data = user_data;

        lv_obj_add_event_cb(obj, luat_lv_obj_event_cb, LV_EVENT_ALL, G(L)->mainthread);
    }

    user_data->dsc_cnt++;
    user_data->dsc = lv_mem_realloc(user_data->dsc, user_data->dsc_cnt * sizeof(luat_event_dsc_t));

    user_data->dsc[user_data->dsc_cnt - 1].filter = filter;
    user_data->dsc[user_data->dsc_cnt - 1].event_cb_ref = event_cb_ref;
    user_data->dsc[user_data->dsc_cnt - 1].user_data_ref = user_data_ref;

    lua_pushlightuserdata(L, &user_data->dsc[user_data->dsc_cnt - 1]);
    return 1;
}

int luat_lv_obj_remove_event_cb(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL || lua_gettop(L) != 2) {
        return 0;
    }

    luat_obj_event_user_data_t *user_data = obj->luat_user_data;
    if (user_data == NULL) {
        return 0;
    }

    if (lua_isnil(L, 2))
    {
        for (int i = 0; i < user_data->dsc_cnt; i++) {
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].user_data_ref);
        }
        user_data->dsc_cnt = 0;
        lv_mem_free(user_data->dsc);
        return 0;
    }

    for (int i = 0; i < user_data->dsc_cnt; i++) {
        lua_geti(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
        if (lua_rawequal(L, -1, -2))
        {
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
            luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].user_data_ref);
            for (; i < user_data->dsc_cnt - 1; i++)
            {
                user_data->dsc[i] = user_data->dsc[i + 1];
            }
            user_data->dsc_cnt--;
            user_data->dsc = lv_mem_realloc(user_data->dsc, user_data->dsc_cnt * sizeof(luat_event_dsc_t));
            return 0;
        }
    }

    return 0;
}

int luat_lv_obj_remove_event_cb_with_user_data(lua_State *L) {
    lv_obj_t* obj = lua_touserdata(L, 1);
    if (obj == NULL || lua_gettop(L) != 3) {
        return 0;
    }

    luat_obj_event_user_data_t *user_data = obj->luat_user_data;
    if (user_data == NULL) {
        return 0;
    }

    for (int i = 0; i < user_data->dsc_cnt; i++) {
        lua_geti(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
        if (lua_isnil(L, 2) || lua_rawequal(L, -1, 2))
        {
            lua_geti(L, LUA_REGISTRYINDEX, user_data->dsc[i].user_data_ref);
            if (lua_rawequal(L, -1, 3))
            {
                luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].event_cb_ref);
                luaL_unref(L, LUA_REGISTRYINDEX, user_data->dsc[i].user_data_ref);
                for (; i < user_data->dsc_cnt - 1; i++)
                {
                    user_data->dsc[i] = user_data->dsc[i + 1];
                }
                user_data->dsc_cnt--;
                user_data->dsc = lv_mem_realloc(user_data->dsc, user_data->dsc_cnt * sizeof(luat_event_dsc_t));
                return 0;
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }

    return 0;
}

int luat_lv_keyboard_def_event_cb(lua_State *L) {
    lv_event_t *event = lua_touserdata(L, 1);
    lv_keyboard_def_event_cb(event);
    return 0;
}

//========================================================================

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
//     if (anim->luat_user_data.exec_cb_ref == 0)
//         return;
//     rtos_msg_t msg = {0};
//     msg.handler = l_obj_anim_cb;
//     msg.ptr = anim;
//     msg.arg1 = anim->luat_user_data.exec_cb_ref;
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
    if (anim->luat_user_data.exec_cb_ref == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = l_obj_anim_cb;
    msg.ptr = var;
    msg.arg1 = anim->luat_user_data.exec_cb_ref;
    msg.arg2 = value;
    luat_msgbus_put(&msg, 0);
    // lua_geti(_L, LUA_REGISTRYINDEX, anim->luat_user_data.exec_cb_ref);
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
    // anim->luat_user_data.obj = obj;

    if (anim->luat_user_data.exec_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, anim->luat_user_data.exec_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        anim->luat_user_data.exec_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_anim_set_exec_cb(anim, luat_lv_anim_exec_cb);
    }
    else {
        anim->luat_user_data.exec_cb_ref = 0;
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
    if (anim->luat_user_data.ready_cb_ref == 0)
        return;
    rtos_msg_t msg = {0};
    msg.handler = l_anim_ready_cb;
    msg.ptr = anim;
    msg.arg1 = anim->luat_user_data.ready_cb_ref;
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
    if (anim->luat_user_data.ready_cb_ref != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, anim->luat_user_data.ready_cb_ref);
    }
    if (lua_isfunction(L, 2)) {
        lua_settop(L, 2);
        anim->luat_user_data.ready_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lv_anim_set_ready_cb(anim, luat_lv_anim_ready_cb);
    }
    else {
        anim->luat_user_data.ready_cb_ref = 0;
        lv_anim_set_ready_cb(anim, NULL);
    }
    return 0;
}
