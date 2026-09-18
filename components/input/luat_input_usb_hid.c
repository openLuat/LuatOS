/* USB HID application policy. The BSP only supplies raw lifecycle/data callbacks. */
#include "luat_base.h"
#ifdef LUAT_USE_INPUT_HID
#include "luat_input_usb_hid.h"
#include "luat_input_hid.h"
#include "luat_input_service.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include "luat_malloc.h"
#include <string.h>
#define LUAT_LOG_TAG "input"
#include "luat_log.h"

#ifndef LUAT_INPUT_USB_HID_DEPTH
#define LUAT_INPUT_USB_HID_DEPTH 32U
#endif
_Static_assert(LUAT_INPUT_USB_HID_DEPTH >= 2 && LUAT_INPUT_USB_HID_DEPTH <= 65535,
               "HID report ring depth must fit uint16_t");

typedef struct usb_hid_input {
    struct usb_hid_input *next;
    luat_input_hid_t *parser;
    uint8_t *reports;
    uint32_t dropped, invalid;
    uint16_t stride, packet_size, head, tail;
    uint8_t pending, lost, interface_number;
} usb_hid_input_t;
typedef struct {
    uint32_t timestamp_ms;
    uint16_t length, reserved;
    uint8_t data[];
} usb_hid_input_packet_t;

static usb_hid_input_t *sessions;
static luat_rtos_mutex_t session_lock;
static luat_rtos_task_handle worker;

#ifdef LUAT_USE_INPUT_SERVICE
#define USB_INPUT_CORE luat_input_service_core()
#define USB_INPUT_LOCK() luat_input_service_lock()
#define USB_INPUT_UNLOCK() luat_input_service_unlock()
#else
static luat_input_core_t input_core;
#define USB_INPUT_CORE (&input_core)
#define USB_INPUT_LOCK() ((void)0)
#define USB_INPUT_UNLOCK() ((void)0)
#endif


/* Called with session_lock and core serialization held; IRQ never takes them. */
static void process(usb_hid_input_t *input)
{
    uint8_t data[LUAT_INPUT_HID_REPORT_BYTES];
    for (unsigned budget = 0; budget < LUAT_INPUT_USB_HID_DEPTH; budget++) {
        uint32_t critical = luat_rtos_entry_critical();
        if (input->lost) {
            input->head = input->tail = 0;
            input->pending = input->lost = 0;
            luat_rtos_exit_critical(critical);
            luat_input_hid_reset(input->parser, (uint32_t)luat_mcu_tick64_ms());
            LLOGW("HID state lost intf=%u dropped=%lu", input->interface_number,
                  (unsigned long)input->dropped);
            break;
        }
        if (input->head == input->tail) {
            input->pending = 0;
            luat_rtos_exit_critical(critical);
            break;
        }
        usb_hid_input_packet_t *packet = (void *)(input->reports + input->head * input->stride);
        uint16_t length = packet->length;
        uint32_t timestamp_ms = packet->timestamp_ms;
        memcpy(data, packet->data, length);
        input->head = (input->head + 1U) % LUAT_INPUT_USB_HID_DEPTH;
        luat_rtos_exit_critical(critical);
        int ret = luat_input_hid_feed(input->parser, data, length, timestamp_ms);
        if (ret && ret != LUAT_INPUT_ENOTSUP && ret != LUAT_INPUT_HID_ROLLOVER) {
            uint32_t errors = __sync_add_and_fetch(&input->invalid, 1);
            luat_input_hid_reset(input->parser, timestamp_ms);
            if (errors == 1 || !(errors % 100))
                LLOGW("HID malformed intf=%u ret=%d len=%u errors=%lu",
                      input->interface_number, ret, length, (unsigned long)errors);
        }
    }
    uint32_t critical = luat_rtos_entry_critical();
    if (input->head == input->tail && !input->lost) input->pending = 0;
    luat_rtos_exit_critical(critical);
}

static void drain(void)
{
    luat_rtos_mutex_lock(session_lock, UINT32_MAX);
    USB_INPUT_LOCK();
    for (usb_hid_input_t *input = sessions; input; input = input->next) process(input);
    USB_INPUT_UNLOCK();
    luat_rtos_mutex_unlock(session_lock);
}

static void task(void *userdata)
{
    (void)userdata;
    /* A higher-priority worker can preempt its creator before task_create
     * stores worker. Receive on our own handle, never that unpublished output. */
    luat_rtos_task_handle self = luat_rtos_get_current_handle();
    while (1) {
        luat_event_t event;
        /* Wake is only a hint, with no session pointer/tag to become stale.
         * Timeout also drains a last release after a failed wake/full queue,
         * and reports left over after the bounded per-device dispatch. */
        luat_rtos_mutex_lock(session_lock, UINT32_MAX);
        uint32_t timeout = sessions ? 10U : UINT32_MAX;
        luat_rtos_mutex_unlock(session_lock);
        luat_rtos_event_recv(self, 0, &event, NULL, timeout);
        drain();
    }
}

/* Transport serializes OPEN/CLOSE. First OPEN lazily creates the shared worker;
 * it remains parked with an infinite wait when no devices are attached. */
static int init(void)
{
    if (worker) return 0;
#ifdef LUAT_USE_INPUT_SERVICE
    if (!luat_input_service_is_ready()) {
        LLOGW("input service not initialized by application startup");
        return LUAT_INPUT_SERVICE_ENOTREADY;
    }
#endif
    if (!session_lock && luat_rtos_mutex_create(&session_lock)) return -1;
#ifndef LUAT_USE_INPUT_SERVICE
    luat_input_init(&input_core);
#endif
    return luat_rtos_task_create(&worker, 4096, 90, "input_hid", task, NULL, 32);
}

static void open_device(luat_usb_hid_host_t *device)
{
    if (device->userdata) return;
    uint16_t packet_size = device->packet_size;
    if (!packet_size || packet_size > LUAT_INPUT_HID_REPORT_BYTES || init()) {
        LLOGW("HID transport/init unsupported intf=%u", device->interface_number);
        return;
    }
    luat_rtos_mutex_lock(session_lock, UINT32_MAX);
    USB_INPUT_LOCK();
    size_t prefix = (sizeof(usb_hid_input_t) + 7U) & ~(size_t)7U;
    size_t parser_size = (luat_input_hid_size() + 7U) & ~(size_t)7U;
    size_t stride = (sizeof(usb_hid_input_packet_t) + packet_size + 3U) & ~(size_t)3U;
    usb_hid_input_t *input = luat_heap_calloc(1, prefix + parser_size + stride * LUAT_INPUT_USB_HID_DEPTH);
    int ret = -1;
    if (!input) goto OUT;
    input->parser = (void *)((uint8_t *)input + prefix);
    input->reports = (uint8_t *)input + prefix + parser_size;
    input->stride = stride;
    input->packet_size = packet_size;
    input->interface_number = device->interface_number;
    ret = luat_input_hid_init(input->parser, USB_INPUT_CORE, device->report_descriptor,
        device->report_descriptor_len, device->vendor, device->product, luat_input_log_receive, NULL);
    if (ret) goto FREE;
    /* A callback contains one interrupt packet, not an assembled long report. */
    if (luat_input_hid_report_size(input->parser) > packet_size) {
        ret = LUAT_INPUT_ENOTSUP;
        goto DEINIT;
    }
#ifdef LUAT_USE_INPUT_SERVICE
    ret = luat_input_service_attach(luat_input_hid_handle(input->parser));
    if (ret) goto DEINIT;
#endif
    input->next = sessions;
    sessions = input;
    uint32_t critical = luat_rtos_entry_critical();
    device->userdata = input;
    luat_rtos_exit_critical(critical);
    LLOGI("HID attached bus=%u addr=%u intf=%u id=%lu buffer=%u context=%u",
        device->bus, device->address, device->interface_number,
        (unsigned long)luat_input_hid_handle(input->parser).id,
        (unsigned)(stride * LUAT_INPUT_USB_HID_DEPTH), (unsigned)parser_size);
    /* Ensure an idle worker switches to the bounded retry wait before RX. */
    luat_rtos_event_send(worker, 1, 0, 0, 0, 0);
    goto OUT;
DEINIT:
    luat_input_hid_deinit(input->parser, (uint32_t)luat_mcu_tick64_ms());
FREE:
    luat_heap_free(input);
OUT:
    if (ret) LLOGW("HID unsupported/init failed addr=%u intf=%u ret=%d; transport remains active",
        device->address, device->interface_number, ret);
    USB_INPUT_UNLOCK();
    luat_rtos_mutex_unlock(session_lock);
}

static void close_device(luat_usb_hid_host_t *device)
{
    /* Failed OPEN may have been rejected before transport setup. */
    if (!session_lock || !device->userdata) return;
    luat_rtos_mutex_lock(session_lock, UINT32_MAX);
    USB_INPUT_LOCK();
    uint32_t critical = luat_rtos_entry_critical();
    usb_hid_input_t *input = device->userdata;
    device->userdata = NULL;
    luat_rtos_exit_critical(critical);
    if (input) {
        usb_hid_input_t **link = &sessions;
        while (*link && *link != input) link = &(*link)->next;
        if (*link) *link = input->next;
        LLOGI("HID close intf=%u dropped=%lu invalid=%lu", input->interface_number,
              (unsigned long)input->dropped, (unsigned long)input->invalid);
#ifdef LUAT_USE_INPUT_SERVICE
        luat_input_service_detach(luat_input_hid_handle(input->parser));
#endif
        luat_input_hid_deinit(input->parser, (uint32_t)luat_mcu_tick64_ms());
        luat_heap_free(input);
    }
    USB_INPUT_UNLOCK();
    luat_rtos_mutex_unlock(session_lock);
}

static void report(luat_usb_hid_host_t *device, const uint8_t *data, uint32_t length)
{
    uint32_t critical = luat_rtos_entry_critical();
    usb_hid_input_t *input = device->userdata;
    if (!input) {
        luat_rtos_exit_critical(critical);
        return;
    }
    unsigned next = (input->tail + 1U) % LUAT_INPUT_USB_HID_DEPTH;
    if (input->lost || !data || !length || length > input->packet_size || next == input->head) {
        input->lost = 1;
        __sync_add_and_fetch(&input->dropped, 1);
    } else {
        usb_hid_input_packet_t *packet = (void *)(input->reports + input->tail * input->stride);
        packet->timestamp_ms = (uint32_t)luat_mcu_tick64_ms();
        packet->length = length;
        memcpy(packet->data, data, length);
        input->tail = next;
    }
    int notify = !input->pending;
    input->pending = 1;
    luat_rtos_exit_critical(critical);
    if (notify) luat_rtos_event_send(worker, 1, 0, 0, 0, 0);
}

void luat_input_usb_hid_callback(luat_usb_hid_host_t *device,
    luat_usb_hid_event_t event, const uint8_t *data, uint32_t length)
{
    if (!device) return;
    switch (event) {
    case LUAT_USB_HID_OPEN: open_device(device); break;
    case LUAT_USB_HID_CLOSE: close_device(device); break;
    case LUAT_USB_HID_REPORT: report(device, data, length); break;
    case LUAT_USB_HID_RX_ERROR: report(device, NULL, 0); break;
    }
}
#endif
