#include "luat_base.h"
#include "cJSON.h"



typedef void (*luat_remotem_uplink_cb)(char* buff, size_t len);
typedef void (*luat_remotem_typeopt)(cJSON* top, cJSON* data);


typedef struct luat_remotem_ctx
{
    char bsp[32];
    char self_id[64];
    char session_id[64];
    int wait;
    struct
    {
        char host[64];
        int  port;
        char user[128];
        char password[128];
        char protocol[8];
        char topic_uplink[192];
        char topic_downlink[192];
    } mqtt;
    
}luat_remotem_ctx_t;

void luat_remotem_init(int argc, char** argv);


void luat_remotem_putbuff(char* buff, size_t len);
void luat_remotem_set_uplink(luat_remotem_uplink_cb uplink);
cJSON* luat_remotem_json_init(cJSON* top);
int luat_remotem_ready(void);
int luat_remotem_up(cJSON* top);
// from string ext
void luat_str_tohex(char* str, size_t len, char* buff);
void luat_str_tohexwithsep(char* str, size_t len, char* separator, size_t len_j, char* buff);


void luat_remotem_typeopt_init(cJSON* top, cJSON* data);
void luat_remotem_typeopt_log(cJSON* top, cJSON* data);
void luat_remotem_typeopt_gpio(cJSON* top, cJSON* data);
void luat_remotem_typeopt_uart(cJSON* top, cJSON* data);
void luat_remotem_typeopt_indev(cJSON* top, cJSON* data);
void luat_remotem_typeopt_ping(cJSON* top, cJSON* data);

typedef struct type_opt
{
    const char* name;
    luat_remotem_typeopt typeopt;
}type_opt_t;
