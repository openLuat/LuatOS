#ifndef LUAT_TYPES_H
#define LUAT_TYPES_H

#ifndef LUAT_RET
#define LUAT_RET int
#endif

#ifndef LUAT_RT_RET_TYPE
#define LUAT_RT_RET_TYPE	void
#endif

#ifndef LUAT_RT_CB_PARAM
#define LUAT_RT_CB_PARAM void *param
#endif

enum {
    LUAT_ERR_OK   = (0) ,
    LUAT_ERR_FAIL = (-1),
    LUAT_TRUE     = (1) ,
    LUAT_FALSE    = (0) ,
    LUAT_NULL     = (0)
};

#endif

