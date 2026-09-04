#include "luat_input.h"
#include <assert.h>

static unsigned frames;
static void receive(void *p, const luat_input_frame_t *f, const luat_input_event_t *e)
{
    (void)p;
    if (!f->flags) {
        assert(f->count == 1 && e[0].value == -1);
        frames++;
    }
}

int main(void)
{
    luat_input_core_t core;
    luat_input_device_t dev = {0};
    luat_input_link_t link = {0};
    luat_input_handle_t h;
    const luat_input_device_desc_t desc = {.caps = {.rel_bits = 1}};
    luat_input_init(&core);
    assert(luat_input_register(&core, &dev, &desc, 0, 0, &h) == 0);
    assert(luat_input_bind(h, &link, receive, 0) == 0);
    const luat_input_event_t event = {LUAT_INPUT_EV_REL, LUAT_INPUT_REL_X, -1};
    assert(luat_input_submit(h, 0, &event, 1) == 0 && frames == 1);
    return luat_input_unregister(h, 0);
}
