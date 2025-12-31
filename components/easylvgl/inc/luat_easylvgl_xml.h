#ifndef LUAT_EASYLVGL_XML_H
#define LUAT_EASYLVGL_XML_H

#include "lvgl9/src/core/lv_obj.h"

#ifdef __cplusplus
extern "C" {
#endif

bool easylvgl_xml_init(void);
bool easylvgl_xml_deinit(void);
bool easylvgl_xml_register_from_file(const char *path);
bool easylvgl_xml_register_from_data(const char *name, const char *xml_def);
lv_obj_t *easylvgl_xml_create_screen(const char *name);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_EASYLVGL_XML_H */

