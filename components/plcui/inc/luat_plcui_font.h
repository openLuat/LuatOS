/** @file luat_plcui_font.h Text font resolution and XML-owned HZFont faces. */
#ifndef LUAT_PLCUI_FONT_H
#define LUAT_PLCUI_FONT_H

#include "luat_plcui.h"

bool luat_plcui_resolve_widget_font(plcui_widget_t *widget, plcui_error_t *error);
bool luat_plcui_set_font_size(plcui_widget_t *widget, uint16_t size, plcui_error_t *error);
void luat_plcui_free_fonts(plcui_document_t *xml);

#endif
