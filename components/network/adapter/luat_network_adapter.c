
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_network_adapter.h"

static network_adapter_info *prv_adapter_table[NW_ADAPTER_QTY];
static void* prv_adapter_param_table[NW_ADAPTER_QTY];

int network_register_adapter(uint8_t adapter_index, network_adapter_info *info, void *user_data)
{
	prv_adapter_table[adapter_index] = info;
	prv_adapter_param_table[adapter_index] = user_data;
}

#endif
