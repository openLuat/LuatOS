
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_fs_drv_init(lv_fs_drv_t* drv)
int luat_lv_fs_drv_init(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_drv_init);
    lv_fs_drv_t* drv = (lv_fs_drv_t*)lua_touserdata(L, 1);
    lv_fs_drv_init(drv);
    return 0;
}

//  void lv_fs_drv_register(lv_fs_drv_t* drv_p)
int luat_lv_fs_drv_register(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_drv_register);
    lv_fs_drv_t* drv_p = (lv_fs_drv_t*)lua_touserdata(L, 1);
    lv_fs_drv_register(drv_p);
    return 0;
}

//  lv_fs_drv_t* lv_fs_get_drv(char letter)
int luat_lv_fs_get_drv(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_get_drv);
    char letter = (char)luaL_checkinteger(L, 1);
    lv_fs_drv_t* ret = NULL;
    ret = lv_fs_get_drv(letter);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  bool lv_fs_is_ready(char letter)
int luat_lv_fs_is_ready(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_is_ready);
    char letter = (char)luaL_checkinteger(L, 1);
    bool ret;
    ret = lv_fs_is_ready(letter);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_fs_res_t lv_fs_open(lv_fs_file_t* file_p, char* path, lv_fs_mode_t mode)
int luat_lv_fs_open(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_open);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    char* path = (char*)luaL_checkstring(L, 2);
    lv_fs_mode_t mode;
    // miss arg convert
    lv_fs_res_t ret;
    ret = lv_fs_open(file_p ,path ,mode);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_close(lv_fs_file_t* file_p)
int luat_lv_fs_close(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_close);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    lv_fs_res_t ret;
    ret = lv_fs_close(file_p);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_remove(char* path)
int luat_lv_fs_remove(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_remove);
    char* path = (char*)luaL_checkstring(L, 1);
    lv_fs_res_t ret;
    ret = lv_fs_remove(path);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_read(lv_fs_file_t* file_p, void* buf, uint32_t btr, uint32_t* br)
int luat_lv_fs_read(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_read);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    void* buf = (void*)lua_touserdata(L, 2);
    uint32_t btr = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t* br = (uint32_t*)lua_touserdata(L, 4);
    lv_fs_res_t ret;
    ret = lv_fs_read(file_p ,buf ,btr ,br);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_write(lv_fs_file_t* file_p, void* buf, uint32_t btw, uint32_t* bw)
int luat_lv_fs_write(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_write);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    void* buf = (void*)lua_touserdata(L, 2);
    uint32_t btw = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t* bw = (uint32_t*)lua_touserdata(L, 4);
    lv_fs_res_t ret;
    ret = lv_fs_write(file_p ,buf ,btw ,bw);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_seek(lv_fs_file_t* file_p, uint32_t pos)
int luat_lv_fs_seek(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_seek);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_seek(file_p ,pos);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_tell(lv_fs_file_t* file_p, uint32_t* pos)
int luat_lv_fs_tell(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_tell);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    uint32_t* pos = (uint32_t*)lua_touserdata(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_tell(file_p ,pos);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_trunc(lv_fs_file_t* file_p)
int luat_lv_fs_trunc(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_trunc);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    lv_fs_res_t ret;
    ret = lv_fs_trunc(file_p);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_size(lv_fs_file_t* file_p, uint32_t* size)
int luat_lv_fs_size(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_size);
    lv_fs_file_t* file_p = (lv_fs_file_t*)lua_touserdata(L, 1);
    uint32_t* size = (uint32_t*)lua_touserdata(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_size(file_p ,size);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_rename(char* oldname, char* newname)
int luat_lv_fs_rename(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_rename);
    char* oldname = (char*)luaL_checkstring(L, 1);
    char* newname = (char*)luaL_checkstring(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_rename(oldname ,newname);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_dir_open(lv_fs_dir_t* rddir_p, char* path)
int luat_lv_fs_dir_open(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_dir_open);
    lv_fs_dir_t* rddir_p = (lv_fs_dir_t*)lua_touserdata(L, 1);
    char* path = (char*)luaL_checkstring(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_dir_open(rddir_p ,path);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_dir_read(lv_fs_dir_t* rddir_p, char* fn)
int luat_lv_fs_dir_read(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_dir_read);
    lv_fs_dir_t* rddir_p = (lv_fs_dir_t*)lua_touserdata(L, 1);
    char* fn = (char*)luaL_checkstring(L, 2);
    lv_fs_res_t ret;
    ret = lv_fs_dir_read(rddir_p ,fn);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_dir_close(lv_fs_dir_t* rddir_p)
int luat_lv_fs_dir_close(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_dir_close);
    lv_fs_dir_t* rddir_p = (lv_fs_dir_t*)lua_touserdata(L, 1);
    lv_fs_res_t ret;
    ret = lv_fs_dir_close(rddir_p);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_fs_res_t lv_fs_free_space(char letter, uint32_t* total_p, uint32_t* free_p)
int luat_lv_fs_free_space(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_free_space);
    char letter = (char)luaL_checkinteger(L, 1);
    uint32_t* total_p = (uint32_t*)lua_touserdata(L, 2);
    uint32_t* free_p = (uint32_t*)lua_touserdata(L, 3);
    lv_fs_res_t ret;
    ret = lv_fs_free_space(letter ,total_p ,free_p);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  char* lv_fs_get_letters(char* buf)
int luat_lv_fs_get_letters(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_get_letters);
    char* buf = (char*)luaL_checkstring(L, 1);
    char* ret = NULL;
    ret = lv_fs_get_letters(buf);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_fs_get_ext(char* fn)
int luat_lv_fs_get_ext(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_get_ext);
    char* fn = (char*)luaL_checkstring(L, 1);
    char* ret = NULL;
    ret = lv_fs_get_ext(fn);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_fs_up(char* path)
int luat_lv_fs_up(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_up);
    char* path = (char*)luaL_checkstring(L, 1);
    char* ret = NULL;
    ret = lv_fs_up(path);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_fs_get_last(char* path)
int luat_lv_fs_get_last(lua_State *L) {
    LV_DEBUG("CALL %s", lv_fs_get_last);
    char* path = (char*)luaL_checkstring(L, 1);
    char* ret = NULL;
    ret = lv_fs_get_last(path);
    lua_pushstring(L, ret);
    return 1;
}

