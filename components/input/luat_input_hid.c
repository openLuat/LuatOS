#include "luat_input_hid.h"
#if defined(LUAT_USE_INPUT) && defined(LUAT_USE_INPUT_HID)
#include <string.h>
#include <limits.h>

#define HID_FIELDS 32U
#define HID_USAGES 128U
#define HID_LOCAL_USAGES 32U
#define HID_REPORTS 8U
#define HID_AXES 8U
#define HID_EVENTS 256U
#define HID_DEPTH 8U
#define HID_RANGE UINT16_MAX

typedef struct {
    uint32_t usage_min;
    int32_t minimum, maximum;
    uint16_t offset, count, usages, usage_count;
    uint16_t flags;
    uint8_t size, report;
    uint32_t application;
} hid_field_t;

typedef struct {
    uint32_t page, size, count;
    int32_t minimum, maximum;
    uint8_t report_id;
} hid_global_t;

struct luat_input_hid {
    luat_input_device_t device;
    luat_input_device_desc_t desc;
    luat_input_link_t link;
    luat_input_handle_t handle;
    hid_field_t fields[HID_FIELDS];
    uint32_t usages[HID_USAGES];
    uint32_t keys[LUAT_INPUT_KEY_WORDS_MAX];
    uint32_t state[LUAT_INPUT_KEY_WORDS_MAX + HID_AXES];
    uint32_t previous[HID_REPORTS][LUAT_INPUT_KEY_WORDS_MAX];
    luat_input_axis_t axes[HID_AXES];
    luat_input_event_t events[HID_EVENTS];
    uint16_t report_bits[HID_REPORTS];
    uint8_t report_ids[HID_REPORTS];
    uint16_t field_count, usage_count;
    uint8_t report_count, has_ids, axis_count;
};

/* USB keyboard usages -> Linux key codes, not ASCII. Numeric mappings only. */
static const uint16_t keyboard[0x74] = {
    [4]=30,48,46,32,18,33,34,35,23,36,37,38,50,49,24,25,16,19,31,20,22,47,17,45,21,44,
    [30]=2,3,4,5,6,7,8,9,10,11,28,1,14,15,57,12,13,26,27,43,43,39,40,41,51,52,53,58,
    [58]=59,60,61,62,63,64,65,66,67,68,87,88,99,70,119,110,102,104,111,107,109,106,105,108,103,
    [83]=69,98,55,74,78,96,79,80,81,75,76,77,71,72,73,82,83,86,127,116,117,
    [104]=183,184,185,186,187,188,189,190,191,192,193,194
};
static const uint16_t modifiers[8] = {29,42,56,125,97,54,100,126};

static int supported_app(uint32_t app)
{
    return app == 0x10001 || app == 0x10002 || app == 0x10006 ||
           app == 0x10007 || app == 0x10080 || app == 0xc0001 ||
           app == 0xd0002 || app == 0xd0004 || app == 0xd0005;
}

static uint16_t key_code(uint32_t usage)
{
    uint16_t page = (uint16_t)(usage >> 16), u = (uint16_t)usage;
    if (page == 7) {
        if (u >= 0xe0 && u <= 0xe7) return modifiers[u - 0xe0];
        return u < sizeof(keyboard)/sizeof(keyboard[0]) ? keyboard[u] : 0;
    }
    if (page == 9 && u >= 1 && u <= 16) return (uint16_t)(0x110 + u - 1);
    if (page == 1) {
        if (u == 0x81) return 116;
        if (u == 0x82) return 142;
        if (u == 0x83) return 143;
    }
    if (page == 0xd && u == 0x42) return LUAT_INPUT_BTN_TOUCH;
    if (page == 0xc) {
        switch (u) {
        case 0x30: return 116;
        case 0xb0: return 207;
        case 0xb1: return 119;
        case 0xb5: return 163;
        case 0xb6: return 165;
        case 0xb7: return 166;
        case 0xcd: return 164;
        case 0xe2: return 113;
        case 0xe9: return 115;
        case 0xea: return 114;
        case 0x183: return 226;
        case 0x18a: return 155;
        case 0x192: return 140;
        case 0x221: return 217;
        case 0x223: return 172;
        case 0x224: return 158;
        case 0x225: return 159;
        case 0x226: return 128;
        case 0x227: return 173;
        default: break;
        }
    }
    return 0;
}

static uint32_t usage_at(const luat_input_hid_t *h, const hid_field_t *f, uint32_t i)
{
    if (i >= f->usage_count) i = f->usage_count - 1U;
    return f->usages == HID_RANGE ? f->usage_min + i : h->usages[f->usages + i];
}

static int mapping(const hid_field_t *f, uint32_t usage, uint16_t *type, uint16_t *code)
{
    if (!supported_app(f->application)) return 0;
    *code = key_code(usage);
    if (*code) { *type = LUAT_INPUT_EV_KEY; return 1; }
    if (!(f->flags & 2)) return 0; /* Relative/absolute axes must be Variable. */
    if (usage == 0x10030 || usage == 0x10031) {
        *type = f->flags & 4 ? LUAT_INPUT_EV_REL : LUAT_INPUT_EV_ABS;
        *code = (uint16_t)(usage - 0x10030);
        return 1;
    }
    if (usage == 0x10038 || usage == 0xc0238) {
        if (!(f->flags & 4)) return 0;
        *type = LUAT_INPUT_EV_REL;
        *code = usage == 0x10038 ? LUAT_INPUT_REL_WHEEL : LUAT_INPUT_REL_HWHEEL;
        return 1;
    }
    if (usage == 0xd0030) { *type = LUAT_INPUT_EV_ABS; *code = LUAT_INPUT_ABS_PRESSURE; return 1; }
    return 0;
}

static int add_cap(luat_input_hid_t *h, const hid_field_t *f, uint32_t usage)
{
    uint16_t type, code;
    /* Multi-contact grouping/contact count requires a separate MT adapter. */
    if (supported_app(f->application) && (usage == 0xd0051 || usage == 0xd0054)) return LUAT_INPUT_ENOTSUP;
    if (!mapping(f, usage, &type, &code)) return 0;
    if (type == LUAT_INPUT_EV_KEY) {
        h->keys[code / 32U] |= UINT32_C(1) << (code % 32U);
        if (h->desc.caps.key_words < code / 32U + 1U) h->desc.caps.key_words = (uint16_t)(code / 32U + 1U);
    } else if (type == LUAT_INPUT_EV_REL) {
        h->desc.caps.rel_bits |= UINT32_C(1) << code;
        h->desc.properties |= LUAT_INPUT_PROP_POINTER;
    } else {
        for (unsigned i = 0; i < h->axis_count; i++) {
            if (h->axes[i].code == code) return LUAT_INPUT_ENOTSUP;
        }
        if (h->axis_count == HID_AXES) return LUAT_INPUT_ENOSPC;
        int32_t initial = f->minimum <= 0 && f->maximum >= 0 ? 0 : f->minimum;
        h->axes[h->axis_count++] = (luat_input_axis_t){code,0,f->minimum,f->maximum,initial};
        h->desc.properties |= LUAT_INPUT_PROP_DIRECT;
    }
    return 0;
}

static uint32_t unsigned_item(const uint8_t *p, unsigned n)
{
    uint32_t v = 0;
    for (unsigned i = 0; i < n; i++) v |= (uint32_t)p[i] << (i * 8U);
    return v;
}

static int32_t signed_bits(uint32_t value, unsigned bits)
{
    if (bits < 32 && (value & (UINT32_C(1) << (bits - 1U)))) value |= UINT32_MAX << bits;
    int32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}

static int parse(luat_input_hid_t *h, const uint8_t *data, size_t length)
{
    hid_global_t g = {0}, stack[HID_DEPTH];
    uint32_t apps[HID_DEPTH], app = 0, local[HID_LOCAL_USAGES], usage_min = 0, usage_max = 0;
    unsigned globals = 0, depth = 0, locals = 0, have_min = 0, have_max = 0;
    for (size_t pos = 0; pos < length;) {
        uint8_t prefix = data[pos++];
        if (prefix == 0xfe) return LUAT_INPUT_ENOTSUP; /* Reserved long item format. */
        unsigned n = prefix & 3U; if (n == 3) n = 4;
        if (n > length - pos) return LUAT_INPUT_EINVAL;
        uint32_t value = unsigned_item(data + pos, n);
        pos += n;
        unsigned tag = prefix >> 4, type = (prefix >> 2) & 3U;
        if (type == 1) {
            switch (tag) {
            case 0: if (value > 0xffff) return LUAT_INPUT_ENOTSUP; g.page = value; break;
            case 1: if (!n) return LUAT_INPUT_EINVAL; g.minimum = signed_bits(value, n*8); break;
            case 2:
                if (!n || (g.minimum >= 0 && value > INT32_MAX)) return LUAT_INPUT_ENOTSUP;
                g.maximum = g.minimum < 0 ? signed_bits(value, n*8) : (int32_t)value;
                break;
            case 7: g.size = value; break;
            case 8:
                if (!value || value > 255) return LUAT_INPUT_EINVAL;
                g.report_id = (uint8_t)value; h->has_ids = 1; break;
            case 9: g.count = value; break;
            case 10: if (globals == HID_DEPTH) return LUAT_INPUT_ENOSPC; stack[globals++] = g; break;
            case 11: if (!globals) return LUAT_INPUT_EINVAL; g = stack[--globals]; break;
            default: break; /* Physical units/ranges don't alter bit offsets. */
            }
        } else if (type == 2) {
            uint32_t usage = n == 4 ? value : (g.page << 16) | value;
            if (tag == 0) {
                if (!n || locals == HID_LOCAL_USAGES || have_min) return LUAT_INPUT_ENOTSUP;
                local[locals++] = usage;
            } else if (tag == 1) {
                if (!n || locals || have_min) return LUAT_INPUT_ENOTSUP;
                usage_min = usage; have_min = 1;
            } else if (tag == 2) {
                if (!n || !have_min || have_max || usage < usage_min ||
                    (usage >> 16) != (usage_min >> 16)) return LUAT_INPUT_EINVAL;
                usage_max = usage; have_max = 1;
            } else if (tag == 10) return LUAT_INPUT_ENOTSUP; /* Delimiter sets. */
        } else if (type == 0) {
            if (tag == 10) {
                if (!n || depth == HID_DEPTH) return LUAT_INPUT_ENOSPC;
                apps[depth++] = app;
                if (value == 1) app = locals ? local[0] : have_min ? usage_min : 0;
            } else if (tag == 12) {
                if (!depth) return LUAT_INPUT_EINVAL;
                app = apps[--depth];
            } else if (tag == 8) {
                if (!depth || !n || !g.size || g.size > 32 || !g.count ||
                    g.count > LUAT_INPUT_HID_REPORT_BYTES * 8U / g.size || g.minimum > g.maximum) return LUAT_INPUT_EINVAL;
                unsigned r;
                for (r = 0; r < h->report_count && h->report_ids[r] != g.report_id; r++) {}
                if (r == h->report_count) {
                    if (r == HID_REPORTS) return LUAT_INPUT_ENOSPC;
                    h->report_ids[r] = g.report_id; h->report_count++;
                }
                uint32_t bits = g.size * g.count;
                if (bits > LUAT_INPUT_HID_REPORT_BYTES*8U - h->report_bits[r]) return LUAT_INPUT_ENOSPC;
                uint16_t offset = h->report_bits[r];
                h->report_bits[r] = (uint16_t)(h->report_bits[r] + bits);
                if (!(value & 1) && supported_app(app)) {
                    /* Variable, Relative and Null State are supported. */
                    if (value & ~UINT32_C(0x46)) return LUAT_INPUT_ENOTSUP;
                    if (h->field_count == HID_FIELDS || (!locals && !(have_min && have_max))) return LUAT_INPUT_ENOTSUP;
                    uint32_t count = locals ? locals : usage_max - usage_min + 1U;
                    if (!count || count > 1024) return LUAT_INPUT_ENOSPC;
                    hid_field_t f = {.usage_min=usage_min,.minimum=g.minimum,.maximum=g.maximum,
                        .offset=offset,.count=(uint16_t)g.count,.usages=HID_RANGE,.usage_count=(uint16_t)count,
                        .flags=(uint16_t)value,.size=(uint8_t)g.size,.report=(uint8_t)r,.application=app};
                    if (locals) {
                        if (locals > HID_USAGES - h->usage_count) return LUAT_INPUT_ENOSPC;
                        f.usages = h->usage_count;
                        memcpy(h->usages + h->usage_count, local, locals*sizeof(*local));
                        h->usage_count = (uint16_t)(h->usage_count + locals);
                    }
                    unsigned items = (value & 2) ? g.count : count;
                    if (items > 1024) return LUAT_INPUT_ENOSPC;
                    for (unsigned i = 0; i < items; i++) {
                        int ret = add_cap(h, &f, usage_at(h, &f, i));
                        if (ret) return ret;
                    }
                    h->fields[h->field_count++] = f;
                }
            } else if (tag != 9 && tag != 11) return LUAT_INPUT_ENOTSUP;
            locals = have_min = have_max = 0;
        } else return LUAT_INPUT_ENOTSUP;
    }
    if (depth || globals || !h->field_count) return LUAT_INPUT_EINVAL;
    for (unsigned i = 0; i < h->report_count; i++) {
        if (h->has_ids && !h->report_ids[i]) return LUAT_INPUT_EINVAL;
        if ((h->report_bits[i]+7U)/8U + h->has_ids > LUAT_INPUT_HID_REPORT_BYTES) return LUAT_INPUT_ENOSPC;
    }
    if (!h->desc.caps.key_words && !h->axis_count && !h->desc.caps.rel_bits) return LUAT_INPUT_ENOTSUP;
    for (unsigned i = 1; i < h->axis_count; i++) {
        luat_input_axis_t a = h->axes[i]; unsigned j = i;
        while (j && h->axes[j-1].code > a.code) { h->axes[j] = h->axes[j-1]; j--; }
        h->axes[j] = a;
    }
    h->desc.caps.keys = h->keys;
    h->desc.caps.abs = h->axes;
    h->desc.caps.abs_count = h->axis_count;
    return 0;
}

size_t luat_input_hid_size(void) { return sizeof(luat_input_hid_t); }

size_t luat_input_hid_report_size(const luat_input_hid_t *h)
{
    size_t maximum = 0;
    if (!h || !h->handle.id) return 0;
    for (unsigned i = 0; i < h->report_count; i++) {
        size_t size = (h->report_bits[i] + 7U)/8U + h->has_ids;
        if (maximum < size) maximum = size;
    }
    return maximum;
}

int luat_input_hid_init(luat_input_hid_t *h, luat_input_core_t *core,
    const uint8_t *descriptor, size_t length, uint16_t vendor, uint16_t product,
    luat_input_receive_t receive, void *userdata)
{
    if (!h || !core || !descriptor || !length || length > 1024 || !receive) return LUAT_INPUT_EINVAL;
    memset(h, 0, sizeof(*h));
    int ret = parse(h, descriptor, length);
    if (ret) return ret;
    h->desc.name = "USB HID"; h->desc.bus = 3;
    h->desc.vendor = vendor; h->desc.product = product;
    ret = luat_input_register(core, &h->device, &h->desc, h->state,
        sizeof(h->state)/sizeof(h->state[0]), &h->handle);
    if (ret) return ret;
    ret = luat_input_bind(h->handle, &h->link, receive, userdata);
    if (ret) { luat_input_unregister(h->handle, 0); memset(&h->handle, 0, sizeof(h->handle)); }
    return ret;
}

static uint32_t field_value(const uint8_t *data, uint32_t offset, unsigned size)
{
    uint32_t value = 0;
    for (unsigned bit = 0; bit < size; bit++) {
        if (data[(offset+bit)/8U] & (1U << ((offset+bit)%8U))) value |= UINT32_C(1) << bit;
    }
    return value;
}

static int event_add(luat_input_hid_t *h, unsigned *count, uint16_t type, uint16_t code, int32_t value)
{
    if (*count == HID_EVENTS) return LUAT_INPUT_ENOSPC;
    h->events[(*count)++] = (luat_input_event_t){type,code,value};
    return 0;
}

int luat_input_hid_feed(luat_input_hid_t *h, const uint8_t *report, size_t length, uint32_t timestamp_ms)
{
    if (!h || !h->handle.id || !report || !length) return LUAT_INPUT_EINVAL;
    unsigned r, id = h->has_ids ? report[0] : 0;
    for (r = 0; r < h->report_count && h->report_ids[r] != id; r++) {}
    if (r == h->report_count) return LUAT_INPUT_ENOTSUP;
    size_t need = (h->report_bits[r]+7U)/8U + h->has_ids;
    if (length < need || length > LUAT_INPUT_HID_REPORT_BYTES) return LUAT_INPUT_EINVAL;
    const uint8_t *data = report + h->has_ids;
    uint32_t pressed[LUAT_INPUT_KEY_WORDS_MAX] = {0};
    unsigned count = 0;
    for (unsigned i = 0; i < h->field_count; i++) {
        const hid_field_t *f = h->fields + i;
        if (f->report != r) continue;
        for (unsigned j = 0; j < f->count; j++) {
            uint32_t raw = field_value(data, (uint32_t)f->offset + j*f->size, f->size);
            int32_t v = f->minimum < 0 ? signed_bits(raw, f->size) : (int32_t)raw;
            if (f->minimum >= 0 && raw > INT32_MAX) return LUAT_INPUT_EINVAL;
            if (v < f->minimum || v > f->maximum) {
                if (f->flags & 0x40) continue;
                return LUAT_INPUT_EINVAL;
            }
            uint32_t usage;
            if (f->flags & 2) usage = usage_at(h, f, j);
            else {
                uint64_t index = (uint64_t)(int64_t)v - (uint64_t)(int64_t)f->minimum;
                if (index >= f->usage_count) continue; /* Unassigned array selector. */
                usage = usage_at(h, f, (uint32_t)index);
                if ((usage >> 16) == 7 && (uint16_t)usage >= 1 && (uint16_t)usage <= 3) return LUAT_INPUT_HID_ROLLOVER;
            }
            uint16_t type, code;
            if (!mapping(f, usage, &type, &code)) continue;
            if (type == LUAT_INPUT_EV_KEY) {
                if (!(f->flags & 2) || v) pressed[code/32U] |= UINT32_C(1) << (code%32U);
            } else if (type == LUAT_INPUT_EV_REL) {
                if (v && event_add(h, &count, type, code, v)) return LUAT_INPUT_ENOSPC;
            } else {
                int32_t old;
                if (luat_input_get_value(h->handle, type, code, 0, &old)) return LUAT_INPUT_EINVAL;
                if (old != v && event_add(h, &count, type, code, v)) return LUAT_INPUT_ENOSPC;
            }
        }
    }
    for (unsigned w = 0; w < h->desc.caps.key_words; w++) {
        uint32_t merged = pressed[w];
        for (unsigned i = 0; i < h->report_count; i++) if (i != r) merged |= h->previous[i][w];
        uint32_t changed = merged ^ h->state[w];
        while (changed) {
            unsigned bit = 0; while (!(changed & (UINT32_C(1) << bit))) bit++;
            if (event_add(h, &count, LUAT_INPUT_EV_KEY, (uint16_t)(w*32U+bit), !!(merged & (UINT32_C(1)<<bit)))) return LUAT_INPUT_ENOSPC;
            changed &= changed - 1U;
        }
    }
    int ret = count ? luat_input_submit(h->handle, timestamp_ms, h->events, (uint16_t)count) : 0;
    if (!ret) memcpy(h->previous[r], pressed, sizeof(pressed));
    return ret;
}

int luat_input_hid_reset(luat_input_hid_t *h, uint32_t timestamp_ms)
{
    if (!h) return LUAT_INPUT_EINVAL;
    int ret = luat_input_reset(h->handle, timestamp_ms);
    if (!ret) memset(h->previous, 0, sizeof(h->previous));
    return ret;
}

int luat_input_hid_deinit(luat_input_hid_t *h, uint32_t timestamp_ms)
{
    if (!h) return LUAT_INPUT_EINVAL;
    int ret = luat_input_unregister(h->handle, timestamp_ms);
    if (!ret) memset(&h->handle, 0, sizeof(h->handle));
    return ret;
}

luat_input_handle_t luat_input_hid_handle(const luat_input_hid_t *h)
{
    return h ? h->handle : (luat_input_handle_t){0};
}
#endif
