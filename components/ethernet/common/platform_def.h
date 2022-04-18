

#ifndef ETHERNET_COMMON_PLATFORM_DEF_H_
#define ETHERNET_COMMON_PLATFORM_DEF_H_

#define platform_random	luat_crypto_trng
#define platform_send_event luat_send_event_to_task
#define platform_wait_event luat_wait_event_from_task
#define platform_create_task	luat_thread_start
#define malloc 	luat_heap_malloc
#define free 	luat_heap_free
#define msleep	luat_timer_mdelay
#endif /* ETHERNET_COMMON_PLATFORM_DEF_H_ */
