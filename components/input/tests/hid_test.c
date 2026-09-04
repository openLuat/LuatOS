#include "luat_input_hid.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static const uint8_t keyboard_desc[] = {
    0x05,1,0x09,6,0xa1,1,0x05,7,0x19,0xe0,0x29,0xe7,0x15,0,0x25,1,
    0x75,1,0x95,8,0x81,2,0x95,1,0x75,8,0x81,1,
    0x95,5,0x75,1,0x05,8,0x19,1,0x29,5,0x91,2,0x95,1,0x75,3,0x91,1,
    0x95,6,0x75,8,0x15,0,0x25,0x65,0x05,7,0x19,0,0x29,0x65,0x81,0,0xc0
};
static const uint8_t mouse_desc[] = {
    0x05,1,0x09,2,0xa1,1,0x85,1,0x09,1,0xa1,0,
    0x05,9,0x19,1,0x29,8,0x15,0,0x25,1,0x95,8,0x75,1,0x81,2,
    0x05,1,0x09,0x30,0x09,0x31,0x16,0,0x80,0x26,0xff,0x7f,
    0x75,16,0x95,2,0x81,6,0x09,0x38,0x15,0x81,0x25,0x7f,
    0x75,8,0x95,1,0x81,6,0xc0,0xc0
};
static luat_input_frame_t frame;
static luat_input_event_t events[256];
static unsigned calls;
static void receive(void *p, const luat_input_frame_t *f, const luat_input_event_t *e)
{
    (void)p; frame = *f; calls++;
    assert(f->count <= 256);
    if (f->count) memcpy(events, e, f->count*sizeof(*e));
}
static int has(uint16_t type, uint16_t code, int32_t value)
{
    for (unsigned i=0;i<frame.count;i++) if (events[i].type==type && events[i].code==code && events[i].value==value) return 1;
    return 0;
}
static void test_reports(luat_input_hid_t *h)
{
    luat_input_core_t core;
    luat_input_init(&core);
    assert(!luat_input_hid_init(h, &core, keyboard_desc, sizeof(keyboard_desc), 1, 2, receive, NULL));
    assert(luat_input_hid_report_size(h)==8);
    uint8_t keys[8] = {2,0,4,5,0,0,0,0};
    assert(!luat_input_hid_feed(h, keys, 8, 10));
    assert(frame.count==3 && has(1,42,1) && has(1,30,1) && has(1,48,1));
    unsigned old = calls;
    assert(!luat_input_hid_feed(h, keys, 8, 11) && calls==old);
    keys[2]=1;
    assert(luat_input_hid_feed(h, keys, 8, 12)==LUAT_INPUT_HID_ROLLOVER && calls==old);
    int32_t value;
    assert(!luat_input_get_value(luat_input_hid_handle(h),1,30,0,&value) && value==1);
    assert(luat_input_hid_feed(h, keys, 7, 13)==LUAT_INPUT_EINVAL && calls==old);
    memset(keys,0,sizeof(keys));
    assert(!luat_input_hid_feed(h,keys,8,14) && has(1,30,0) && has(1,48,0) && has(1,42,0));
    assert(!luat_input_hid_deinit(h,15) && !core.devices);

    assert(!luat_input_hid_init(h,&core,mouse_desc,sizeof(mouse_desc),3,4,receive,NULL));
    assert(luat_input_hid_report_size(h)==7);
    uint8_t mouse[7]={1,1,0xfe,0xff,5,0,0xff};
    assert(!luat_input_hid_feed(h,mouse,7,20));
    assert(has(1,0x110,1) && has(2,0,-2) && has(2,1,5) && has(2,8,-1));
    mouse[0]=99; old=calls;
    assert(luat_input_hid_feed(h,mouse,7,21)==LUAT_INPUT_ENOTSUP && calls==old);
    mouse[0]=1;
    assert(!luat_input_hid_reset(h,22));
    assert(!luat_input_hid_feed(h,mouse,7,23) && has(1,0x110,1));
    assert(!luat_input_hid_deinit(h,24));

    /* Two Report IDs on one interface retain each other's held keys/buttons. */
    uint8_t composite[sizeof(mouse_desc)+sizeof(keyboard_desc)+2];
    memcpy(composite,mouse_desc,sizeof(mouse_desc));
    memcpy(composite+sizeof(mouse_desc),keyboard_desc,6);
    composite[sizeof(mouse_desc)+6]=0x85; composite[sizeof(mouse_desc)+7]=2;
    memcpy(composite+sizeof(mouse_desc)+8,keyboard_desc+6,sizeof(keyboard_desc)-6);
    assert(!luat_input_hid_init(h,&core,composite,sizeof(composite),5,6,receive,NULL));
    assert(!luat_input_hid_feed(h,mouse,7,30));
    const uint8_t report2[9]={2,0,0,4,0,0,0,0,0};
    assert(!luat_input_hid_feed(h,report2,9,31) && has(1,30,1) && !has(1,0x110,0));
    const uint8_t release[7]={1,0,0,0,0,0,0};
    assert(!luat_input_hid_feed(h,release,7,32) && has(1,0x110,0) && !has(1,30,0));
    assert(!luat_input_get_value(luat_input_hid_handle(h),1,30,0,&value) && value==1);
    assert(!luat_input_hid_deinit(h,33));
}

static void test_bitmap_and_absolute(luat_input_hid_t *h)
{
    const uint8_t bitmap[] = {5,1,9,6,0xa1,1,5,7,0x19,4,0x29,11,0x15,0,0x25,1,0x75,1,0x95,8,0x81,2,0xc0};
    const uint8_t touch[] = {5,0xd,9,4,0xa1,1,9,0x42,0x15,0,0x25,1,0x75,1,0x95,1,0x81,2,
        0x75,7,0x81,1,5,1,9,0x30,9,0x31,0x15,0,0x26,0xff,0x0f,0x75,16,0x95,2,0x81,2,0xc0};
    luat_input_core_t core;
    luat_input_init(&core);
    assert(!luat_input_hid_init(h,&core,bitmap,sizeof(bitmap),0,0,receive,NULL));
    uint8_t bits=5;
    assert(!luat_input_hid_feed(h,&bits,1,0) && has(1,30,1) && has(1,46,1));
    assert(!luat_input_hid_deinit(h,0));
    assert(!luat_input_hid_init(h,&core,touch,sizeof(touch),0,0,receive,NULL));
    const uint8_t point[]={1,0x23,1,0x56,4};
    assert(!luat_input_hid_feed(h,point,sizeof(point),0));
    assert(has(1,LUAT_INPUT_BTN_TOUCH,1) && has(3,0,0x123) && has(3,1,0x456));
    assert(!luat_input_hid_deinit(h,0));
}

static void test_malformed(luat_input_hid_t *h)
{
    luat_input_core_t core;
    luat_input_init(&core);
    for (size_t n=1;n<sizeof(mouse_desc);n++) {
        assert(luat_input_hid_init(h,&core,mouse_desc,n,0,0,receive,NULL)<0 && !core.devices);
    }
    /* Deterministic descriptor mutations exercise size/count/stack/usage bounds. */
    uint32_t random=12345;
    uint8_t data[sizeof(keyboard_desc)], report[512]={0};
    for (unsigned i=0;i<10000;i++) {
        memcpy(data,keyboard_desc,sizeof(data));
        for (unsigned j=0;j<3;j++) {
            random=random*1664525U+1013904223U;
            data[(random>>8)%sizeof(data)]=(uint8_t)random;
        }
        int ret=luat_input_hid_init(h,&core,data,sizeof(data),0,0,receive,NULL);
        if (!ret) {
            (void)luat_input_hid_feed(h,report,sizeof(report),0);
            assert(!luat_input_hid_deinit(h,0));
        }
        assert(!core.devices);
    }
}

int main(void)
{
    luat_input_hid_t *h=malloc(luat_input_hid_size());
    assert(h);
    test_reports(h); test_bitmap_and_absolute(h); test_malformed(h);
    printf("HID adapter PASS: arrays/bitmap, modifiers, signed mouse, Report IDs, rollover, ABS touch, truncation and 10000 mutations; context=%zu bytes\n",luat_input_hid_size());
    free(h);
    return 0;
}
