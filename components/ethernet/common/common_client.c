#include "luat_base.h"
#if defined(LUAT_USE_DHCP) || defined(LUAT_USE_DNS)
#include "dhcp_def.h"
#include "dns_def.h"
#include "bsp_common.h"

typedef struct
{
	dhcp_client_info_t dhcp_client[2];
}common_client_struct;
#endif

