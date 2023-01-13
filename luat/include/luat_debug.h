#ifndef LUAT_DEBUG_H
#define LUAT_DEBUG_H


typedef enum LUAT_DEBUG_FAULT_MODE
{	
	LUAT_DEBUG_FAULT_RESET,
	LUAT_DEBUG_FAULT_HANG
}LUAT_DEBUG_FAULT_MODE_E;


void luat_debug_print(const char *fmt, ...);
#define LUAT_DEBUG_PRINT(fmt, argv...) luat_debug_print("%s %d:"fmt, __FUNCTION__,__LINE__, ##argv)

void luat_debug_assert(const char *fun_name, unsigned int line_no, const char *fmt, ...);
#define LUAT_DEBUG_ASSERT(condition, fmt, argv...)  do {  \
														{ \
															if((condition) == 0) \
															{ \
																luat_debug_assert(__FUNCTION__, __LINE__, fmt, ##argv); \
															}\
														} \
													} while(0)

void luat_debug_set_fault_mode(LUAT_DEBUG_FAULT_MODE_E mode);


#endif
