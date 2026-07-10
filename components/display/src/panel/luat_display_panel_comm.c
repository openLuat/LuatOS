#include "luat_base.h"
#include "luat_display_panel_comm.h"

#define LUAT_LOG_TAG "panel_comm"
#include "luat_log.h"

/*支持的显示面板列表*/
static struct luat_display_panel *panels[] = {
    &spi_panel_st7789,
    &spi_panel_ili9341,
};

/*查找显示面板*/
struct luat_display_panel *luat_display_find_panel(unsigned int connector_type)
{
    int i;

    for (i = 0; i < ARRAY_SIZE(panels); i++) {
        if (panels[i]->connector_type == connector_type) {
            break;
        }
    }

    if (i >= ARRAY_SIZE(panels))
        return NULL;

    LLOGI("find panel driver : %s\n", panels[i]->name);
    
    return panels[i];
}


