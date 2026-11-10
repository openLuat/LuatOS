/** @file luat_plcui_binding.h Shared Lua handle and component binding interfaces. */
#ifndef LUAT_PLCUI_BINDING_H
#define LUAT_PLCUI_BINDING_H

#include "luat_plcui_component.h"

#define PLCUI_IMAGE_MT "plcui.image"
#define PLCUI_LABEL_MT "plcui.label"
#define PLCUI_TEXTAREA_MT "plcui.textarea"
#define PLCUI_KEYBOARD_MT "plcui.keyboard"
#define PLCUI_CONTAINER_MT "plcui.container"
#define PLCUI_TABLE_MT "plcui.table"
#define PLCUI_CHART_MT "plcui.chart"

int luat_plcui_push_error(lua_State *L, const plcui_error_t *error);
int luat_plcui_binding_error(lua_State *L, const char *code, const char *message);
int luat_plcui_binding_success(lua_State *L);
plcui_widget_t *luat_plcui_binding_check_object(lua_State *L, plcui_error_t *error);
plcui_widget_t *luat_plcui_binding_check_type(lua_State *L, plcui_widget_type_t type, plcui_error_t *error);
void luat_plcui_binding_push_object(lua_State *L, int xml_handle_stack_index, unsigned page_index, unsigned widget_index);
void luat_plcui_binding_register_common(lua_State *L);

int luat_plcui_xml_load(lua_State *L);
void luat_plcui_register_xml_meta(lua_State *L);
void luat_plcui_register_image_meta(lua_State *L);
void luat_plcui_register_label_meta(lua_State *L);
void luat_plcui_register_textarea_meta(lua_State *L);
void luat_plcui_register_keyboard_meta(lua_State *L);
void luat_plcui_register_container_meta(lua_State *L);
void luat_plcui_register_table_meta(lua_State *L);
void luat_plcui_register_chart_meta(lua_State *L);

#endif
