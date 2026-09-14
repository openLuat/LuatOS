/* AirUI owns consumer policy; producers never include or initialize AirUI. */
#include "luat_conf_bsp.h"
#include "luat_input_service.h"
#if defined(LUAT_USE_AIRUI_LUATOS) && defined(LUAT_USE_INPUT_SERVICE)
#include "luat_input_airui.h"
#include "luat_rtos.h"

static luat_input_link_t links[LUAT_INPUT_SERVICE_DEVICES];

static uintptr_t lock(void *userdata)
{
    (void)userdata;
    return luat_rtos_entry_critical();
}
static void unlock(void *userdata, uintptr_t token)
{
    (void)userdata;
    luat_rtos_exit_critical((uint32_t)token);
}
static void attach(void *userdata, luat_input_handle_t handle)
{
    (void)userdata;
    const luat_input_device_desc_t *desc;
    if (luat_input_get_desc(handle, &desc)) return;
    /* Touch continues through AirUI's existing explicit binding path. */
    if (desc->caps.mt_slots || (desc->properties & LUAT_INPUT_PROP_DIRECT)) return;
    if (!desc->caps.rel_bits && !desc->caps.key_words) return;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++) {
        if (!links[i].device) {
            luat_input_bind(handle, &links[i], luat_input_airui_receive, NULL);
            return;
        }
    }
}
static void detach(void *userdata, luat_input_handle_t handle)
{
    (void)userdata;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
        if (links[i].device == handle.device) luat_input_unbind(&links[i]);
}
static luat_input_service_observer_t observer = {.attach = attach, .detach = detach};

int airui_input_service_start(void)
{
    if (!luat_input_service_is_ready()) return LUAT_INPUT_SERVICE_ENOTREADY;
    luat_input_service_lock();
    if (!observer.active) {
        luat_input_airui_set_lock(lock, unlock, NULL);
        luat_input_service_observe(&observer);
    }
    luat_input_service_unlock();
    return 0;
}
#endif
