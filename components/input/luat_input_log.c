#include "luat_input.h"

#ifdef LUAT_USE_INPUT
#include <stdio.h>
#define LUAT_LOG_TAG "input"
#include "luat_log.h"

/* Optional synchronous sink; core and HID decoder have no logging dependency. */
void luat_input_log_receive(void *userdata, const luat_input_frame_t *frame,
                            const luat_input_event_t *events)
{
    (void)userdata;
    if (!frame || (frame->count && !events) || luat_log_get_level() > LUAT_LOG_DEBUG) return;
    char line[512];
    unsigned pos = 0, shown = 0;
    line[0] = 0;
    for (; shown < frame->count; shown++) {
        int n = snprintf(line + pos, sizeof(line) - pos, "%u:%u=%ld ",
            events[shown].type, events[shown].code, (long)events[shown].value);
        if (n < 0 || (unsigned)n >= sizeof(line) - pos) {
            line[pos] = 0; /* Only include complete events in the displayed prefix. */
            break;
        }
        pos += (unsigned)n;
    }
    LLOGD("INPUT dev=%lu seq=%lu flags=%u count=%u shown=%u events=%s",
        (unsigned long)frame->device_id, (unsigned long)frame->sequence,
        frame->flags, frame->count, shown, line);
}

#endif
