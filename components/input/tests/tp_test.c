#include "luat_tp_input.h"
#include "luat_airui_input_touch_luatos.h"
#include "luat_malloc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#define CHECK(x) do {if (!(x)) {fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);exit(1);}} while(0)
static unsigned heap_blocks, mutex_count, ticks, reads_done, normalized_calls, clicks, batches;
static unsigned locks[4];
static int read_result, init_result;
static luat_tp_data_t report[LUAT_TP_TOUCH_MAX], legacy[LUAT_TP_TOUCH_MAX];
static luat_tp_config_t config;
static airui_ctx_t ui;
static lv_indev_t *pointers[2];
static uint8_t callback_contacts;
void *luat_heap_malloc(size_t n) {void *p=malloc(n);if(p)heap_blocks++;return p;}
void *luat_heap_calloc(size_t n,size_t s) {void *p=calloc(n,s);if(p)heap_blocks++;return p;}
void luat_heap_free(void *p) {if(p){heap_blocks--;free(p);}}
uint32_t luat_mcu_ticks(void) {return ++ticks;}
void test_log(const char *s, ...) {(void)s;}
int luat_rtos_mutex_create(luat_rtos_mutex_t *m) {CHECK(mutex_count<4);*m=&locks[mutex_count++];return 0;}
int luat_rtos_mutex_lock(luat_rtos_mutex_t m,uint32_t t) {(void)t;unsigned *v=m;CHECK(v&&!(*v));*v=1;return 0;}
int luat_rtos_mutex_unlock(luat_rtos_mutex_t m) {unsigned *v=m;CHECK(v&&*v);*v=0;return 0;}
int luat_rtos_task_create(luat_rtos_task_handle *t,uint32_t s,uint32_t p,const char*n,void(*f)(void*),void*d,uint32_t q)
{(void)s;(void)p;(void)n;(void)f;(void)d;(void)q;*t=(void*)1;return 0;}
void luat_rtos_task_sleep(uint32_t t) {(void)t;}
int luat_rtos_message_recv(luat_rtos_task_handle t,uint32_t*i,void*p,uint32_t w) {(void)t;(void)i;(void)p;(void)w;return -1;}
int luat_gpio_irq_enable(int p,uint8_t e,int t,void*d) {(void)p;(void)e;(void)t;(void)d;return 0;}
static int driver_init(luat_tp_config_t *c) {CHECK(!luat_tp_input_id(c));return init_result;}
static int driver_read(luat_tp_config_t *c,luat_tp_data_t *d) {(void)c;CHECK(locks[1]);memcpy(d,report,sizeof(report));return read_result;}
static void driver_done(luat_tp_config_t*c) {(void)c;CHECK(locks[1]);reads_done++;}
static int driver_control(luat_tp_config_t*c) {(void)c;CHECK(locks[1]);return 0;}
static int legacy_callback(luat_tp_config_t*c,luat_tp_data_t*d) {(void)c;CHECK(!locks[0]&&!locks[1]);memcpy(legacy,d,sizeof(legacy));normalized_calls++;return 0;}
static luat_tp_opts_t opts={.name="fixture-tp",.init=driver_init,.read=driver_read,.read_done=driver_done,.deinit=driver_control,.sleep=driver_control,.wakeup=driver_control};
void airui_touch_notify(airui_ctx_t *ctx,const airui_touch_point_t *points,uint8_t n)
{(void)ctx;CHECK(!locks[0]);batches++;callback_contacts=n;for(unsigned i=0;i<n;i++)CHECK(points[i].track_id<5);}
static void read_pointer(lv_indev_t *i,lv_indev_data_t*d) {airui_input_touch_read(&ui,i,d,&config,i==pointers[0]?0:1);}
static void click(lv_event_t*e) {(void)e;clicks++;}
static void poll(void) {lv_tick_inc(10);lv_indev_read(pointers[0]);lv_indev_read(pointers[1]);}
static int send(unsigned slot,unsigned event,unsigned x,unsigned y)
{
    for(unsigned i=0;i<LUAT_TP_TOUCH_MAX;i++)report[i].event=TP_EVENT_TYPE_NONE;
    report[slot]=(luat_tp_data_t){.timestamp=++ticks,.track_id=slot,.event=event,.x_coordinate=x,.y_coordinate=y,.width=9};
    return luat_tp_process(&config);
}
static int32_t value(unsigned slot,unsigned code)
{
    luat_input_handle_t h;int32_t v;
    luat_input_service_lock();CHECK(!luat_input_lookup(luat_input_service_core(),luat_tp_input_id(&config),&h));
    CHECK(!luat_input_get_value(h,LUAT_INPUT_EV_ABS,code,slot,&v));luat_input_service_unlock();return v;
}
int main(void)
{
    CHECK(!luat_input_service_init());
    config=(luat_tp_config_t){.opts=&opts,.w=800,.h=480,.tp_num=5,.callback=legacy_callback};
    init_result=-1;CHECK(luat_tp_init(&config)<0);CHECK(!config.input_id&&!config.input_context&&!heap_blocks);
    init_result=0;CHECK(!luat_tp_init(&config));uint32_t first=config.input_id;CHECK(first&&heap_blocks==1);
    lv_init();ui.display=lv_display_create(800,480);ui.native_width=800;ui.native_height=480;ui.indev_ptr_count=2;ui.touch_callback_ref=1;
    lv_timer_pause(lv_display_get_refr_timer(ui.display));
    for(unsigned i=0;i<2;i++) {
        pointers[i]=lv_indev_create();lv_indev_set_type(pointers[i],LV_INDEV_TYPE_POINTER);lv_indev_set_read_cb(pointers[i],read_pointer);
        lv_obj_t*b=lv_button_create(lv_screen_active());lv_obj_set_pos(b,i?500:50,50);lv_obj_set_size(b,180,180);lv_obj_add_event_cb(b,click,LV_EVENT_CLICKED,NULL);
    }
    lv_obj_update_layout(lv_screen_active());poll();CHECK(!clicks);
    /* Down and up before any GUI poll must survive as two samples. */
    CHECK(send(0,TP_EVENT_TYPE_DOWN,100,100)==1);int32_t tracking=value(0,LUAT_INPUT_ABS_MT_TRACKING_ID);CHECK(tracking>0);
    CHECK(send(0,TP_EVENT_TYPE_UP,9999,9999)==1);CHECK(legacy[0].x_coordinate==100);CHECK(value(0,LUAT_INPUT_ABS_MT_TRACKING_ID)==-1);
    poll();CHECK(clicks==1);
    CHECK(send(0,TP_EVENT_TYPE_DOWN,100,100)==1);CHECK(value(0,LUAT_INPUT_ABS_MT_TRACKING_ID)>tracking);poll();
    CHECK(luat_tp_process(&config)==0); /* Identical stale raw report. */
    CHECK(send(1,TP_EVENT_TYPE_DOWN,600,100)==1);poll();CHECK(callback_contacts==2);
    CHECK(send(0,TP_EVENT_TYPE_UP,0,0)==1);poll();CHECK(clicks==2);CHECK(value(1,LUAT_INPUT_ABS_MT_TRACKING_ID)>0);
    CHECK(send(1,TP_EVENT_TYPE_UP,0,0)==1);poll();CHECK(clicks==3);
    /* Cancellation and overflow must never finish a click. */
    CHECK(send(0,TP_EVENT_TYPE_DOWN,100,100)==1);poll();unsigned before=clicks;
    CHECK(!luat_tp_sleep(&config));poll();CHECK(clicks==before);CHECK(value(0,LUAT_INPUT_ABS_MT_TRACKING_ID)==-1);
    unsigned done=reads_done;CHECK(luat_tp_process(&config)==0&&reads_done==done);
    CHECK(!luat_tp_wakeup(&config));poll();CHECK(luat_tp_process(&config)==0);
    CHECK(send(0,TP_EVENT_TYPE_DOWN,100,100)==1);poll();
    for(unsigned i=0;i<45;i++) CHECK(send(0,TP_EVENT_TYPE_MOVE,101+i,100)==1);
    CHECK(send(0,TP_EVENT_TYPE_UP,0,0)==1);poll();CHECK(clicks==before);
    /* Bad whole batches reject atomically; transport error produces reset. */
    CHECK(send(0,TP_EVENT_TYPE_DOWN,100,100)==1);poll();
    report[0]=(luat_tp_data_t){.track_id=0,.event=TP_EVENT_TYPE_MOVE,.x_coordinate=200,.y_coordinate=100,.timestamp=++ticks};
    report[1]=(luat_tp_data_t){.track_id=9,.event=TP_EVENT_TYPE_DOWN,.x_coordinate=20,.y_coordinate=20,.timestamp=++ticks};
    CHECK(luat_tp_process(&config)<0);poll();CHECK(clicks==before&&value(0,LUAT_INPUT_ABS_MT_TRACKING_ID)==-1);
    read_result=-1;CHECK(luat_tp_process(&config)<0);read_result=0;poll();
    CHECK(!luat_tp_deinit(&config));poll();CHECK(!heap_blocks&&!config.input_id);CHECK(luat_tp_process(&config)==0);
    luat_input_service_lock();luat_input_handle_t stale;CHECK(luat_input_lookup(luat_input_service_core(),first,&stale)==LUAT_INPUT_ESTALE);luat_input_service_unlock();
    /* Every direction/mirror combination, including the second touch point. */
    for(unsigned direction=0;direction<4;direction++)for(unsigned mirror=0;mirror<4;mirror++) {
        config.direction=direction;config.swap_xy=mirror;CHECK(!luat_tp_init(&config));
        memset(report,0,sizeof(report));
        report[0]=(luat_tp_data_t){.track_id=0,.event=TP_EVENT_TYPE_DOWN,.x_coordinate=0,.y_coordinate=0,.timestamp=++ticks};
        report[1]=(luat_tp_data_t){.track_id=1,.event=TP_EVENT_TYPE_DOWN,.x_coordinate=799,.y_coordinate=479,.timestamp=++ticks};
        CHECK(luat_tp_process(&config)==2);
        const int32_t corners[4][4]={{0,0,799,479},{0,799,479,0},{799,479,0,0},{479,0,0,799}};
        int32_t w=direction%2?480:800,h=direction%2?800:480;
        for(unsigned j=0;j<2;j++) {
            int32_t x=corners[direction][2*j],y=corners[direction][2*j+1];
            if(mirror&1)x=w-1-x;
            if(mirror&2)y=h-1-y;
            CHECK(value(j,LUAT_INPUT_ABS_MT_POSITION_X)==x&&value(j,LUAT_INPUT_ABS_MT_POSITION_Y)==y);
            CHECK(legacy[j].x_coordinate==x&&legacy[j].y_coordinate==y);
        }
        CHECK(!luat_tp_deinit(&config));poll();
    }
    CHECK(!heap_blocks&&!locks[0]&&!locks[1]);CHECK(normalized_calls&&batches);
    puts("TP input PASS: C-only init/failure/stop, frame atomicity, ID reuse, 16 transforms, legacy callback, two LVGL pointers, quick taps, sleep/cancel, overflow");
    return 0;
}
