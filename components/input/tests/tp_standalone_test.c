/* Link/run TP with no input, AirUI, Lua, or heap implementation. */
#include "luat_tp.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned locked, received, reads, done, closes;
static int fail_sink;
void test_log(const char *s, ...) {(void)s;}
int luat_rtos_mutex_create(luat_rtos_mutex_t *m) {*m=(void*)1;return 0;}
int luat_rtos_mutex_lock(luat_rtos_mutex_t m,uint32_t t) {(void)m;(void)t;assert(!locked);locked=1;return 0;}
int luat_rtos_mutex_unlock(luat_rtos_mutex_t m) {(void)m;assert(locked);locked=0;return 0;}
int luat_rtos_task_create(luat_rtos_task_handle *t,uint32_t s,uint32_t p,const char*n,void(*f)(void*),void*d,uint32_t q)
{(void)s;(void)p;(void)n;(void)f;(void)d;(void)q;*t=(void*)2;return 0;}
void luat_rtos_task_sleep(uint32_t t) {(void)t;}
int luat_rtos_message_recv(luat_rtos_task_handle t,uint32_t*i,void*p,uint32_t w) {(void)t;(void)i;(void)p;(void)w;return -1;}
int luat_gpio_irq_enable(int p,uint8_t e,int t,void*d) {(void)p;(void)e;(void)t;(void)d;return 0;}
static int control(luat_tp_config_t *c) {(void)c;assert(locked);return 0;}
static int read_tp(luat_tp_config_t *c,luat_tp_data_t *data)
{(void)c;assert(locked);reads++;memset(data,0,sizeof(*data)*LUAT_TP_TOUCH_MAX);data[0]=(luat_tp_data_t){.event=TP_EVENT_TYPE_DOWN,.x_coordinate=10,.y_coordinate=20};return 1;}
static void read_done(luat_tp_config_t *c) {(void)c;assert(locked);done++;}
static int callback(luat_tp_config_t *c,luat_tp_data_t *d)
{(void)c;assert(!locked && d[0].x_coordinate==20 && d[0].y_coordinate==89);received++;return 0;}
static int sink_open(luat_tp_config_t *c) {assert(locked);if(fail_sink)return -1;c->sink_context=(void*)3;return 0;}
static void sink_close(luat_tp_config_t *c) {assert(locked);closes++;c->sink_context=NULL;}
static int sink_process(luat_tp_config_t *c,luat_tp_data_t *d)
{assert(c->sink_context==(void*)3 && locked);memcpy(d,c->tp_data,sizeof(*d)*LUAT_TP_TOUCH_MAX);d[0].x_coordinate=20;d[0].y_coordinate=89;return 1;}
int main(void)
{
    luat_tp_opts_t driver={.init=control,.read=read_tp,.read_done=read_done,.deinit=control,.sleep=control,.wakeup=control};
    luat_tp_config_t c={.opts=&driver,.w=100,.h=80,.direction=LUAT_TP_ROTATE_90,.callback=callback};
    assert(!luat_tp_init(&c));assert(luat_tp_process(&c)==1 && received==1 && done==1);
    assert(!luat_tp_sleep(&c));assert(!luat_tp_process(&c) && reads==1);
    assert(!luat_tp_wakeup(&c));assert(luat_tp_process(&c)==1 && received==2);
    assert(!luat_tp_deinit(&c));assert(!luat_tp_process(&c));
    const luat_tp_sink_ops_t sink={.open=sink_open,.close=sink_close,.process=sink_process};c.sink_ops=&sink;
    fail_sink=1;assert(luat_tp_init(&c)<0 && !c.running && !c.sink_context);
    fail_sink=0;assert(!luat_tp_init(&c));assert(luat_tp_process(&c)==1 && received==3);
    assert(!luat_tp_deinit(&c) && closes==1 && !c.sink_context);
    puts("TP standalone PASS: legacy callback, transforms, lifecycle and custom sink without input/AirUI");
    return 0;
}
