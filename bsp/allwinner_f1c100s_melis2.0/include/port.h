#include  "epdk.h"
#include "mod_orange.h"
#include "gui_core.h"
#include "bsp_display.h"
#define DBG(X,Y...) __log("%s %d:"X"\r\n", __FUNCTION__, __LINE__, ##Y)
#define SYS_TICK    (10)
extern int port_entry(void);