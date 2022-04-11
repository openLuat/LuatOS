#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
extern void DBG_Printf(const char* format, ...);
#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

typedef struct
{
	void *task_handle;
	uint8_t spi_id;
	uint8_t cs_pin;
	uint8_t rst_pin;
	uint8_t irq_pin;
	uint8_t link_pin;
}w5500_ctrl_t;

static w5500_ctrl_t prvW5500;


static void w5500_task(void *param)
{

}

void w5500_init(luat_spi_t* spi, uint8_t irq_pin, uint8_t rst_pin, uint8_t link_pin)
{
	if (!prvW5500.task_handle)
	{
		luat_thread_t thread;
		thread.task_fun = w5500_task;
		thread.name = "w5500";
		thread.stack_size = 1024;
		thread.priority = 3;
		luat_thread_start(&thread);
		prvW5500.task_handle = thread.handle;
	}
}
