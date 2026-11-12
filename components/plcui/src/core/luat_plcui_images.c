/** @file luat_plcui_images.c Visible-image preparation and per-page cache leases. */
#include "luat_base.h"
#ifdef LUAT_USE_PLCUI
#include "luat_plcui.h"
#include "luat_plcui_fs.h"
#include "luat_plcui_perf.h"
#include "lvgl9/src/core/lv_global.h"
#include "lvgl9/src/core/lv_obj_draw_private.h"
#include "lvgl9/src/misc/lv_area_private.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/lv_cache_entry.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include "lvgl9/src/misc/cache/instance/lv_image_header_cache.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint32_t luat_plcui_image_cache_capacity(void)
{
    if (!lv_is_initialized()) return 0;
    lv_cache_t *cache = LV_GLOBAL_DEFAULT()->img_cache;
    return cache ? (uint32_t)lv_cache_get_max_size(cache, NULL) : 0;
}

uint32_t luat_plcui_image_header_cache_capacity(void)
{
    if (!lv_is_initialized()) return 0;
    lv_cache_t *cache = LV_GLOBAL_DEFAULT()->img_header_cache;
    return cache ? (uint32_t)lv_cache_get_max_size(cache, NULL) : 0;
}

struct plcui_image_pin {
    plcui_image_pin_t *next;
    lv_cache_t *cache;
    lv_cache_entry_t *entry;
    const lv_draw_buf_t *decoded;
    lv_image_decoder_t *decoder;
    unsigned resource_index;
};

/* Entries live until free_description unregisters their document. Keys, unlike
 * physical paths, distinguish a candidate XML from the still-working old XML. */
static plcui_document_t *image_documents;
static uint32_t image_sequence;

static bool namespace_in_use(uint32_t value)
{
    for (plcui_document_t *doc = image_documents; doc; doc = doc->image_next)
        if (doc->image_namespace == value) return true;
    return false;
}

bool luat_plcui_register_images(plcui_document_t *doc, plcui_error_t *error)
{
    if (!doc || doc->closed) {
        luat_plcui_error(error, "E_RESOURCE", "Cannot register a closed image document");
        return false;
    }
    for (plcui_document_t *registered = image_documents; registered; registered = registered->image_next)
        if (registered == doc) return true;
    do { ++image_sequence; } while (!image_sequence || namespace_in_use(image_sequence));
    for (unsigned i = 0; i < doc->resource_count; ++i) {
        plcui_resource_t *resource = &doc->resources[i];
        if (resource->type != PLCUI_RES_IMAGE) continue;
        const char *extension = strrchr(resource->path, '.');
        const char *slash = strrchr(resource->path, '/');
        if (!extension || (slash && extension < slash)) extension = ".img";
        int count = snprintf(resource->cache_key, sizeof(resource->cache_key),
                             "/.plcui/%08x/%u%s", (unsigned)image_sequence, i, extension);
        if (count < 0 || (size_t)count >= sizeof(resource->cache_key)) {
            luat_plcui_error(error, "E_RESOURCE", "Image extension is too long: %s", resource->path);
            return false;
        }
    }
    doc->image_namespace = image_sequence;
    doc->image_next = image_documents;
    image_documents = doc;
    return true;
}

const char *luat_plcui_image_path(const char *source)
{
    if (!source || strncmp(source, "/.plcui/", 8)) return source;
    for (plcui_document_t *doc = image_documents; doc; doc = doc->image_next) {
        for (unsigned i = 0; i < doc->resource_count; ++i) {
            plcui_resource_t *resource = &doc->resources[i];
            if (resource->type == PLCUI_RES_IMAGE && !strcmp(resource->cache_key, source))
                return resource->path;
        }
    }
    /* An expired/unknown private key must never become a physical file path. */
    return NULL;
}

void luat_plcui_unregister_images(plcui_document_t *doc)
{
    if (!doc) return;
    plcui_document_t **link = &image_documents;
    while (*link && *link != doc) link = &(*link)->image_next;
    if (*link) *link = doc->image_next;
    doc->image_next = NULL;
    doc->image_namespace = 0;
}

static bool image_visible(const plcui_widget_t *widget)
{
    if (!widget || !widget->obj || !widget->document) return false;
    if (lv_obj_has_flag(widget->obj, LV_OBJ_FLAG_HIDDEN)
        || lv_obj_get_style_opa_recursive(widget->obj, LV_PART_MAIN) == LV_OPA_TRANSP
        || lv_obj_get_style_image_opa(widget->obj, LV_PART_MAIN) == LV_OPA_TRANSP) return false;
    lv_area_t visible;
    lv_obj_get_coords(widget->obj, &visible);
    int32_t ext = lv_obj_get_ext_draw_size(widget->obj);
    lv_area_increase(&visible, ext, ext);
    lv_area_t screen = {0, 0, widget->document->width - 1, widget->document->height - 1};
    if (!lv_area_intersect(&visible, &visible, &screen)) return false;
    /* lv_obj_is_visible() cannot be used before candidate screen activation. */
    for (lv_obj_t *parent = lv_obj_get_parent(widget->obj); parent; parent = lv_obj_get_parent(parent)) {
        if (lv_obj_has_flag(parent, LV_OBJ_FLAG_HIDDEN)) return false;
        lv_area_t clip;
        lv_obj_get_coords(parent, &clip);
        if (lv_obj_has_flag(parent, LV_OBJ_FLAG_OVERFLOW_VISIBLE)) {
            ext = lv_obj_get_ext_draw_size(parent);
            lv_area_increase(&clip, ext, ext);
        }
        if (!lv_area_intersect(&visible, &visible, &clip)) return false;
    }
    return true;
}

static plcui_resource_t *current_resource(plcui_widget_t *widget)
{
    bool disabled = widget->disabled || lv_obj_has_state(widget->obj, LV_STATE_DISABLED);
    unsigned state = disabled ? 3U : widget->pressed ? 1U : widget->checked ? 2U : 0U;
    const char *id = widget->source[state][0] ? widget->source[state] : widget->source[0];
    return luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE);
}

static bool image_error(plcui_widget_t *widget, plcui_resource_t *resource,
                        plcui_error_t *error, const char *code, const char *message)
{
    luat_plcui_error(error, code, "%s: %s", message, resource ? resource->path : widget->id);
    if (error) {
        snprintf(error->id, sizeof(error->id), "%s", widget->id);
        snprintf(error->file, sizeof(error->file), "%s", resource ? resource->path : widget->document->path);
    }
    return false;
}

static bool header_allowed(const lv_image_header_t *header)
{
    uint64_t bytes = (uint64_t)header->w * header->h * 4U;
    return header->w && header->h && bytes <= PLCUI_MAX_IMAGE_BYTES
           && bytes <= luat_plcui_image_cache_capacity();
}

/* Re-publish a retained pixel entry's information if the independent, smaller
 * header cache evicted it. This prevents set_src from reopening the same file. */
static bool publish_header(const char *key, const plcui_image_pin_t *pin)
{
    if (!lv_image_header_cache_is_enabled()) return true;
    lv_cache_t *cache = LV_GLOBAL_DEFAULT()->img_header_cache;
    if (!cache) return false;
    lv_image_header_cache_data_t search;
    memset(&search, 0, sizeof(search));
    search.src_type = LV_IMAGE_SRC_FILE;
    search.src = key;
    lv_cache_entry_t *entry = lv_cache_acquire(cache, &search, NULL);
    if (entry) { lv_cache_release(cache, entry, NULL); return true; }
    search.src = lv_strdup(key);
    if (!search.src) return false;
    search.header = pin->decoded->header;
    search.decoder = pin->decoder;
    entry = lv_cache_add(cache, &search, NULL);
    if (!entry) { lv_free((void *)search.src); return false; }
    lv_cache_release(cache, entry, NULL);
    return true;
}

static bool assign_image(plcui_widget_t *widget, plcui_resource_t *resource,
                         const plcui_image_pin_t *pin, plcui_error_t *error)
{
    if (!publish_header(resource->cache_key, pin))
        return image_error(widget, resource, error, "E_MEMORY", "Cannot retain prepared image information");
    lv_image_set_src(widget->obj, resource->cache_key);
    const void *source = lv_image_get_src(widget->obj);
    if (!source || lv_image_src_get_type(source) != LV_IMAGE_SRC_FILE
        || strcmp((const char *)source, resource->cache_key))
        return image_error(widget, resource, error, "E_RESOURCE", "Cannot assign prepared image");
    return true;
}

static bool prepare_image(plcui_widget_t *widget, plcui_error_t *error)
{
    if (!image_visible(widget)) return true;
    plcui_document_t *doc = widget->document;
    plcui_page_t *page = &doc->pages[widget->page_index];
    plcui_resource_t *resource = current_resource(widget);
    if (!resource || !resource->cache_key[0])
        return image_error(widget, resource, error, "E_RESOURCE", "Image resource is not registered");
    unsigned index = (unsigned)(resource - doc->resources);
    for (plcui_image_pin_t *pin = page->image_pins; pin; pin = pin->next) {
        if (pin->resource_index != index) continue;
        plcui_perf_add(PERF_REUSED, 0, 0);
        if (!plcui_fs_scope_begin(resource->cache_key))
            return image_error(widget, resource, error, "E_RESOURCE", "Image IO scope is busy");
        bool assigned = assign_image(widget, resource, pin, error);
        plcui_fs_scope_end();
        return assigned;
    }
    plcui_image_pin_t *pin = calloc(1, sizeof(*pin));
    if (!pin) return image_error(widget, resource, error, "E_MEMORY", "Cannot allocate prepared image lease");
    if (!plcui_fs_scope_begin(resource->cache_key)) {
        free(pin);
        return image_error(widget, resource, error, "E_RESOURCE", "Image IO scope is busy");
    }
    uint32_t started = plcui_perf_now();
    plcui_perf_sample_t before = {0};
    plcui_perf_snapshot(&before);
    bool ok = false, opened = false;
    lv_image_decoder_dsc_t decoder;
    memset(&decoder, 0, sizeof(decoder));
    if (!resource->image_validated) {
        lv_image_header_t header;
        memset(&header, 0, sizeof(header));
        uint32_t at = plcui_perf_now();
        lv_result_t info = lv_image_decoder_get_info(resource->cache_key, &header);
        plcui_perf_add(PERF_INFO, plcui_perf_now() - at, 0);
        if (info != LV_RESULT_OK || !header_allowed(&header)) {
            image_error(widget, resource, error, "E_RESOURCE", "Image information is invalid or exceeds file/pixel/cache limits");
            goto done;
        }
    }
    /* Reused validation is not reused pixels: every new page lease opens the
     * normal decoder, which either acquires cached pixels or decodes once. */
    uint32_t at = plcui_perf_now();
    lv_result_t result = lv_image_decoder_open(&decoder, resource->cache_key, NULL);
    plcui_perf_add(PERF_PROBE, plcui_perf_now() - at, 0);
    opened = result == LV_RESULT_OK;
    if (!opened || !decoder.decoded || !decoder.decoded->data
        || !header_allowed(&decoder.decoded->header)) {
        image_error(widget, resource, error, "E_RESOURCE", "Image cannot be fully prepared or exceeds its pixel budget");
        goto done;
    }
    if (!decoder.cache || !decoder.cache_entry || !decoder.decoder) {
        image_error(widget, resource, error, "E_MEMORY", "Prepared image requires an enabled pixel cache");
        goto done;
    }
    pin->cache = decoder.cache;
    pin->entry = lv_cache_acquire(decoder.cache, lv_cache_entry_get_data(decoder.cache_entry), NULL);
    if (pin->entry != decoder.cache_entry) {
        if (pin->entry) lv_cache_release(pin->cache, pin->entry, NULL);
        pin->entry = NULL;
        image_error(widget, resource, error, "E_MEMORY", "Cannot retain prepared image pixels");
        goto done;
    }
    pin->decoded = decoder.decoded;
    pin->decoder = decoder.decoder;
    pin->resource_index = index;
    resource->image_validated = true;
    resource->decoded_bytes = decoder.decoded->data_size;
    /* Closing a successful open frees codec session/file state immediately;
     * the additional cache reference above keeps only the decoded pixels. */
    at = plcui_perf_now();
    lv_image_decoder_close(&decoder);
    plcui_perf_add(PERF_PROBE_CLOSE, plcui_perf_now() - at, 0);
    opened = false;
    if (!assign_image(widget, resource, pin, error)) goto done;
    pin->next = page->image_pins;
    page->image_pins = pin;
    pin = NULL;
    ok = true;
done:
    if (opened) lv_image_decoder_close(&decoder);
    if (pin) {
        if (pin->entry) lv_cache_release(pin->cache, pin->entry, NULL);
        free(pin);
    }
    plcui_fs_scope_end();
    plcui_perf_add(PERF_CHECKED, plcui_perf_now() - started, 0);
    plcui_perf_slow(0, resource->path, plcui_perf_now() - started, &before);
    return ok;
}

bool luat_plcui_prepare_widget_image(plcui_widget_t *widget, plcui_error_t *error)
{
    if (!widget || !widget->document || !widget->obj
        || widget->page_index >= widget->document->page_count) {
        luat_plcui_error(error, "E_RESOURCE", "Image component is not instantiated");
        return false;
    }
    if (widget->type != PLCUI_IMAGE) return true;
    for (lv_obj_t *object = widget->obj; object; object = lv_obj_get_parent(object))
        if (lv_obj_has_flag(object, LV_OBJ_FLAG_HIDDEN)) return true;
    lv_obj_update_layout(widget->document->pages[widget->page_index].screen);
    return prepare_image(widget, error);
}

static void release_until(plcui_page_t *page, plcui_image_pin_t *stop)
{
    while (page->image_pins != stop) {
        plcui_image_pin_t *pin = page->image_pins;
        if (!pin) break;
        page->image_pins = pin->next;
        lv_cache_release(pin->cache, pin->entry, NULL);
        free(pin);
    }
}

bool luat_plcui_prepare_page_images(plcui_document_t *doc, int page, plcui_error_t *error)
{
    if (!doc || page < 0 || (unsigned)page >= doc->page_count || !doc->pages[page].screen) {
        luat_plcui_error(error, "E_RESOURCE", "Target page is not instantiated");
        return false;
    }
    lv_obj_update_layout(doc->pages[page].screen);
    plcui_image_pin_t *checkpoint = doc->pages[page].image_pins;
    for (unsigned i = 0; i < doc->pages[page].count; ++i) {
        plcui_widget_t *widget = &doc->pages[page].widgets[i];
        if (widget->type == PLCUI_IMAGE && !prepare_image(widget, error)) {
            release_until(&doc->pages[page], checkpoint);
            return false;
        }
    }
    return true;
}

void luat_plcui_release_page_images(plcui_document_t *doc, int page)
{
    if (!doc || page < 0 || (unsigned)page >= doc->page_count) return;
    release_until(&doc->pages[page], NULL);
}
#endif
