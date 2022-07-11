#include "platform_def.h"
#include "luat_base.h"

#include "luat_network_adapter.h"

uint32_t sys_arch_protect(void)
{
	luat_os_entry_cri();
	return 0;
}

void sys_arch_unprotect(uint32_t lev)
{
	luat_os_exit_cri();
}
