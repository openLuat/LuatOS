#include  "epdk.h"
#define DBG(X,Y...) __log("%s %d:"X"\r\n", __FUNCTION__, __LINE__, ##Y)
#define SYS_TICK    (10)
extern int port_entry(void);