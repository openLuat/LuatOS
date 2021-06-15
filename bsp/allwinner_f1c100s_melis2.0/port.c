#include "port.h"
#include "stdint.h"
static void port_thread(void *arg)
{
    uint32_t      width;
    uint32_t       height;
    ES_FILE     *disp;
	
	disp    = eLIBs_fopen("b:\\DISP\\DISPLAY", "r+");
	
	width   = eLIBs_fioctrl(disp,DISP_CMD_SCN_GET_WIDTH, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
	height  = eLIBs_fioctrl(disp,DISP_CMD_SCN_GET_HEIGHT, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
	
    DBG("entry luatos thread! %u, %u", width, height);
    eLIBs_fclose(disp);
    while(1)
    {
        esKRNL_TimeDly(1000/SYS_TICK);
        // DBG("hello world1");
    }
}

int port_entry(void)
{
    u8 id;
    DBG("entry luatos app!");
    id = esKRNL_TCreate(port_thread, NULL, 0x10000, KRNL_priolevel1);
    DBG("thread id %d!", id);
}