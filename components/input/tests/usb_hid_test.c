/* Migrated transport regression: real common adapter, deterministic IRQ/task interleavings. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include "../luat_input_usb_hid.c"
#ifdef LUAT_USE_AIRUI_LUATOS
#include "luat_input_airui.h"
#endif

static unsigned allocations, wakes, critical_depth, mutexes, task_creates;
static unsigned locked[4];
static int fail_wake, fail_alloc, fail_task, fail_mutex;
static void (*log_hook)(void);
static void (*worker_entry)(void *);
static jmp_buf pump_done;
static unsigned receives;
static uint32_t last_wait;
static void pump(void);

void *luat_heap_calloc(size_t n, size_t size)
{
    assert(!critical_depth);
    if (fail_alloc) return NULL;
    void *p = calloc(n, size);
    if (p) allocations++;
    return p;
}
void luat_heap_free(void *p) { if (p) { assert(allocations); allocations--; free(p); } }
int luat_log_get_level(void) { return 1; }
void luat_log_log(int level, const char *tag, const char *format, ...)
{
    assert(!critical_depth && !strcmp(tag, "input"));
    (void)level; (void)format;
    if (log_hook) log_hook();
}
int luat_rtos_mutex_create(luat_rtos_mutex_t *lock)
{
    if (fail_mutex) return -1;
    assert(mutexes < 3); *lock = (void *)(uintptr_t)++mutexes; return 0;
}
int luat_rtos_mutex_lock(luat_rtos_mutex_t lock, uint32_t timeout)
{
    unsigned id = (unsigned)(uintptr_t)lock; (void)timeout;
    assert(id && id <= mutexes && !critical_depth && !locked[id]);
    locked[id] = 1; return 0;
}
int luat_rtos_mutex_unlock(luat_rtos_mutex_t lock)
{
    unsigned id = (unsigned)(uintptr_t)lock;
    assert(id && locked[id]); locked[id] = 0; return 0;
}
uint32_t luat_rtos_entry_critical(void) { assert(!critical_depth); critical_depth = 1; return 0; }
void luat_rtos_exit_critical(uint32_t token) { (void)token; assert(critical_depth); critical_depth = 0; }
uint64_t luat_mcu_tick64_ms(void) { return 1234; }
luat_rtos_task_handle luat_rtos_get_current_handle(void) { return (void *)5; }
int luat_rtos_task_create(luat_rtos_task_handle *handle, uint32_t stack, uint8_t priority,
    const char *name, void (*entry)(void *), void *arg, uint16_t count)
{
    (void)priority; (void)name; (void)arg;
    assert(stack >= 4096 && count); task_creates++;
    if (fail_task) return -1;
    /* A higher-priority task can run before task_create publishes its handle. */
    assert(!*handle);
    worker_entry = entry;
    pump();
    *handle = (void *)5;
    return 0;
}
int luat_rtos_event_send(luat_rtos_task_handle handle, uint32_t id, uint32_t a,
    uint32_t b, uint32_t c, uint32_t timeout)
{
    assert(handle && id && !a && !b && !c && !timeout);
    if (fail_wake) return -1;
    wakes++; return 0;
}
int luat_rtos_event_recv(luat_rtos_task_handle handle, uint32_t id, luat_event_t *event,
    void *callback, uint32_t timeout)
{
    assert(handle == (void *)5);
    (void)id; (void)callback;
    last_wait = timeout;
    if (receives++) longjmp(pump_done, 1);
    memset(event, 0, sizeof(*event)); return -1; /* Timer retry, even with no wake. */
}
static void pump(void)
{
    receives = 0;
    if (!setjmp(pump_done)) worker_entry(NULL);
}
#ifdef LUAT_USE_AIRUI_LUATOS
static unsigned airui_frames;
int airui_input_service_start(void);
void luat_input_airui_set_lock(luat_input_airui_lock_t lock,
    luat_input_airui_unlock_t unlock, void *userdata)
{
    uintptr_t token = lock(userdata); unlock(userdata, token);
}
void luat_input_airui_receive(void *userdata, const luat_input_frame_t *frame,
    const luat_input_event_t *events)
{
    (void)userdata; (void)frame; (void)events; airui_frames++;
}
#endif

static const uint8_t descriptor[] = {
    5,1,9,6,0xa1,1,5,7,0x19,4,0x29,11,0x15,0,0x25,1,0x75,1,0x95,8,0x81,2,0xc0
};
static luat_usb_hid_host_t device = {
    .report_descriptor = descriptor, .report_descriptor_len = sizeof(descriptor), .packet_size = 1
};
static unsigned injected;
static void inject_once(void)
{
    if (!injected++) { uint8_t bits = 0; luat_usb_hid_host_callback(&device, LUAT_USB_HID_REPORT, &bits, 1); }
}
static int key_state(luat_usb_hid_host_t *dev)
{
    int32_t value;
    usb_hid_input_t *input = dev->userdata;
    assert(!luat_input_get_value(luat_input_hid_handle(input->parser), LUAT_INPUT_EV_KEY, LUAT_INPUT_KEY_A, 0, &value));
    return value;
}
static void send_bits(uint8_t bits) { luat_usb_hid_host_callback(&device, LUAT_USB_HID_REPORT, &bits, 1); }

static unsigned observed_attach, observed_detach;
static void observe_attach(void *userdata, luat_input_handle_t h)
{
    assert(userdata == &observed_attach && h.id);
    observed_attach++;
}
static void observe_detach(void *userdata, luat_input_handle_t h)
{
    assert(userdata == &observed_attach && h.id);
    observed_detach++;
}

int main(void)
{
    assert(!luat_input_service_is_ready());
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(!device.userdata && !worker && !session_lock && !allocations && !mutexes);
#ifdef LUAT_USE_AIRUI_LUATOS
    assert(airui_input_service_start() == LUAT_INPUT_SERVICE_ENOTREADY);
#endif
    assert(!luat_input_service_init() && luat_input_service_is_ready());
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_CLOSE, NULL, 0);
    fail_mutex = 1; luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(!device.userdata && !worker && !allocations);
    fail_mutex = 0; fail_task = 1;
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(!device.userdata && !worker && !allocations);
    fail_task = 0; fail_alloc = 1;
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(!device.userdata && worker && !allocations && !USB_INPUT_CORE->devices);
    /* CLOSE after a failed open is harmless. */
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_CLOSE, NULL, 0);
    fail_alloc = 0;
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(device.userdata && allocations == 1);
#ifdef LUAT_USE_AIRUI_LUATOS
    /* Consumer starts after device registration, then follows future hotplug. */
    assert(!airui_input_service_start());
    assert(!airui_input_service_start());
#endif
    luat_input_service_observer_t watch = {
        .attach = observe_attach, .detach = observe_detach, .userdata = &observed_attach
    };
    luat_input_service_lock();
    assert(!luat_input_service_observe(&watch) && observed_attach == 1);
    assert(luat_input_service_observe(&watch) == LUAT_INPUT_EBUSY);
    luat_input_service_unobserve(&watch);
    luat_input_service_unobserve(&watch);
    assert(observed_detach == 1 && !watch.active && !watch.next);
    assert(!luat_input_service_observe(&watch) && observed_attach == 2);
    luat_input_service_unlock();
    unsigned creates = task_creates;
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(allocations == 1 && task_creates == creates);
    usb_hid_input_t *input = device.userdata;
    uint8_t bits = 1;
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_REPORT, &bits, 1); bits = 0;
    pump(); assert(key_state(&device) == 1 && !input->pending && last_wait == 10);
    assert(observed_attach == 2 && observed_detach == 1); /* No lifecycle dispatch per frame. */
    fail_wake = 1; send_bits(0); fail_wake = 0;
    pump(); assert(!key_state(&device)); /* Last release survives failed wake. */
    send_bits(1); pump();
    for (unsigned i = 0; i < LUAT_INPUT_USB_HID_DEPTH; i++) send_bits(1);
    assert(input->lost && input->dropped); pump();
    assert(!key_state(&device) && !input->lost && !input->pending);
    send_bits(1); pump(); assert(key_state(&device));
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_RX_ERROR, NULL, 0);
    pump(); assert(!key_state(&device));
    uint8_t too_long[2] = {1, 1};
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_REPORT, too_long, 2);
    assert(input->lost); pump(); assert(!input->lost);
    for (unsigned i = 0; i < LUAT_INPUT_USB_HID_DEPTH - 1; i++) send_bits((i + 1) & 1);
    log_hook = inject_once; pump(); log_hook = NULL;
    assert(injected && input->head == input->tail && !input->pending && !key_state(&device));
    unsigned old_wakes = wakes; send_bits(1); assert(wakes == old_wakes + 1);
    /* Independent simultaneous interfaces; worker never uses SDK app slots. */
    luat_usb_hid_host_t second = device; second.userdata = NULL; second.interface_number = 1;
    luat_usb_hid_host_callback(&second, LUAT_USB_HID_OPEN, NULL, 0);
    assert(allocations == 2 && task_creates == creates);
    pump(); assert(key_state(&device) && !key_state(&second));
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_CLOSE, NULL, 0);
    assert(!device.userdata && allocations == 1);
    pump(); /* Late wake cannot refer to freed storage. */
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_OPEN, NULL, 0);
    assert(!key_state(&device)); pump(); assert(!key_state(&device));
    send_bits(1); pump(); assert(key_state(&device) && !key_state(&second));
    luat_usb_hid_host_callback(&device, LUAT_USB_HID_CLOSE, NULL, 0);
    luat_usb_hid_host_callback(&second, LUAT_USB_HID_CLOSE, NULL, 0);
    luat_usb_hid_host_callback(&second, LUAT_USB_HID_CLOSE, NULL, 0);
    assert(!allocations && !sessions && !USB_INPUT_CORE->devices && !critical_depth);
    pump(); assert(last_wait == UINT32_MAX);
    for (unsigned i = 0; i < 4; i++) assert(!locked[i]);
#ifdef LUAT_USE_AIRUI_LUATOS
    assert(airui_frames);
#endif
    assert(observed_attach == 4 && observed_detach == 4);
    luat_input_service_lock();
    luat_input_service_unobserve(&watch);
    assert(!watch.active && !watch.next && observed_detach == 4);
    luat_input_service_unlock();
    puts("USB HID common adapter PASS: init failures, raw copy, retry, overflow/reset, exact budget, composite, detach and stale wake");
    return 0;
}
