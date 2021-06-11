#include "port.h"

static void port_thread(void *arg)
{
    DBG("entry luatos thread!");
    while(1)
    {
        esKRNL_TimeDly(1000/SYS_TICK);
        DBG("hello world1");
    }
}

int port_entry(void)
{
    u8 id;
    DBG("entry luatos app!");
    id = esKRNL_TCreate(port_thread, NULL, 0x10000, KRNL_priolevel1);
    DBG("thread id %d!", id);
}