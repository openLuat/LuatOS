/** @file luat_plcui_images.c Visible-image preparation and per-page cache leases. */
#include "luat_base.h"
#ifdef LUAT_USE_PLCUI
#include "luat_plcui_component.h"
#include "luat_plcui_fs.h"
#include "luat_plcui_perf.h"
#include "lvgl9/src/core/lv_global.h"
#include "lvgl9/src/core/lv_obj_draw_private.h"
#include "lvgl9/src/widgets/image/lv_image_private.h"
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

bool luat_plcui_component_visible(const plcui_widget_t *widget)
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
    if (widget->type == PLCUI_IMAGE && widget->image && !widget->image->crop
        && widget->image->fit == LV_IMAGE_ALIGN_CENTER) {
        unsigned state = widget->disabled || lv_obj_has_state(widget->obj, LV_STATE_DISABLED) ? 3U
            : widget->pressed ? 1U : widget->checked ? 2U : 0U;
        const char *id = widget->source[state][0] ? widget->source[state] : widget->source[0];
        plcui_resource_t *resource = luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE);
        const void *bound = lv_image_get_src(widget->obj);
        bool known = resource && bound && lv_image_src_get_type(bound) == LV_IMAGE_SRC_FILE
            && !strcmp((const char *)bound, resource->cache_key);
        /* Until the prospective source is bound, its natural size/pivot can make
           an offscreen logical box draw into the viewport. Conservatively prepare
           it once, without a second header IO pass; sync supplies exact native
           source-based extents after binding. Ancestor clipping is still checked. */
        if (!known) visible = screen;
    }
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
    const lv_image_header_t *header = &pin->decoded->header;
    if (widget->type == PLCUI_IMAGE && !luat_plcui_image_validate_source(widget, header->w, header->h, header->cf, error)) return false;
    if (widget->type == PLCUI_ANIMIMG && (header->w != (uint32_t)widget->w || header->h != (uint32_t)widget->h))
        return image_error(widget, resource, error, "E_RESOURCE", "Animation frame dimensions must match its viewport");
    if (widget->type == PLCUI_SLIDER) {
        uint32_t side = (uint32_t)(widget->slider->vertical ? widget->w : widget->h);
        if (header->w != side || header->h != side)
            return image_error(widget, resource, error, "E_RESOURCE", "Slider knob image must match its square knob dimensions");
    }
    if (!publish_header(resource->cache_key, pin))
        return image_error(widget, resource, error, "E_MEMORY", "Cannot retain prepared image information");
    if (widget->type == PLCUI_SLIDER) {
        lv_obj_set_style_bg_image_src(widget->obj, resource->cache_key, LV_PART_KNOB);
        return lv_obj_get_style_bg_image_src(widget->obj, LV_PART_KNOB) != NULL;
    }
    /* The resource is immutable for this XML instance. Same-source geometry
       updates need neither another header lookup nor a duplicated path. */
    const void *bound = lv_image_get_src(widget->obj);
    if (!bound || lv_image_src_get_type(bound) != LV_IMAGE_SRC_FILE || strcmp((const char *)bound, resource->cache_key))
        lv_image_set_src(widget->obj, resource->cache_key);
    const void *source = lv_image_get_src(widget->obj);
    if (!source || lv_image_src_get_type(source) != LV_IMAGE_SRC_FILE
        || strcmp((const char *)source, resource->cache_key))
        return image_error(widget, resource, error, "E_RESOURCE", "Cannot assign prepared image");
    if (widget->type == PLCUI_IMAGE) luat_plcui_image_sync(widget);
    return true;
}

bool luat_plcui_image_bind(plcui_widget_t *widget, const char *id, const plcui_image_pin_t *lease, plcui_error_t *error)
{
    plcui_resource_t *resource = luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE);
    if (!resource || !lease || lease->resource_index != (unsigned)(resource - widget->document->resources))
        return image_error(widget, resource, error, "E_RESOURCE", "Invalid image lease");
    return assign_image(widget, resource, lease, error);
}

void luat_plcui_image_release(plcui_image_pin_t **lease)
{
    if (!lease || !*lease) return;
    plcui_image_pin_t *pin = *lease;
    *lease = NULL;
    if (pin->entry) lv_cache_release(pin->cache, pin->entry, NULL);
    free(pin);
}

bool luat_plcui_image_acquire(plcui_widget_t *widget, const char *id, plcui_image_pin_t **lease, plcui_error_t *error)
{
    *lease = NULL;
    plcui_document_t *doc = widget->document;
    plcui_resource_t *resource = luat_plcui_resource(doc, id, PLCUI_RES_IMAGE);
    if (!resource || !resource->cache_key[0])
        return image_error(widget, resource, error, "E_RESOURCE", "Image resource is not registered");
    unsigned index = (unsigned)(resource - doc->resources);
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
    if (widget->animation && (decoder.decoded->header.w != (uint32_t)widget->w || decoder.decoded->header.h != (uint32_t)widget->h)) {
        image_error(widget, resource, error, "E_RESOURCE", "Animation frame dimensions must match its viewport");
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
    *lease = pin;
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

static bool prepare_image(plcui_widget_t *widget, plcui_error_t *error)
{
    if (!luat_plcui_component_visible(widget)) return true;
    if (widget->type == PLCUI_ANIMIMG) return luat_plcui_animimg_prepare(widget, error);
    plcui_page_t *page = &widget->document->pages[widget->page_index];
    plcui_resource_t *resource = widget->type == PLCUI_SLIDER
        ? luat_plcui_resource(widget->document, widget->slider->knob_source, PLCUI_RES_IMAGE) : current_resource(widget);
    if (!resource) {
        if (widget->type == PLCUI_SLIDER && !widget->slider->knob_source[0]) return true;
        return image_error(widget, resource, error, "E_RESOURCE", "Unknown image resource");
    }
    unsigned index = (unsigned)(resource - widget->document->resources);
    for (plcui_image_pin_t *pin = page->image_pins; pin; pin = pin->next) {
        if (pin->resource_index != index) continue;
        plcui_perf_add(PERF_REUSED, 0, 0);
        return assign_image(widget, resource, pin, error);
    }
    plcui_image_pin_t *pin = NULL;
    if (!luat_plcui_image_acquire(widget, resource->id, &pin, error)) return false;
    if (!assign_image(widget, resource, pin, error)) { luat_plcui_image_release(&pin); return false; }
    pin->next = page->image_pins;
    page->image_pins = pin;
    return true;
}

bool luat_plcui_prepare_widget_image(plcui_widget_t *widget, plcui_error_t *error)
{
    if (!widget || !widget->document || !widget->obj
        || widget->page_index >= widget->document->page_count) {
        luat_plcui_error(error, "E_RESOURCE", "Image component is not instantiated");
        return false;
    }
    if (widget->type != PLCUI_IMAGE && widget->type != PLCUI_SLIDER && widget->type != PLCUI_ANIMIMG) return true;
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

/* A running-page visibility/position transaction can prepare an animation and
   subsequently fail on another component. Keep cache references, not extra
   decoded frames, so rollback cannot lose its old visual to cache pressure. */
typedef struct {
    plcui_widget_t *widget;
    plcui_animimg_t state;
    char *source;
    int32_t source_width, source_height;
    lv_color_format_t source_format;
} animation_image_checkpoint_t;

static bool clone_image_lease(const plcui_image_pin_t *source, plcui_image_pin_t **target)
{
    *target = NULL;
    if (!source) return true;
    plcui_image_pin_t *copy = calloc(1, sizeof(*copy));
    if (!copy) return false;
    *copy = *source;
    copy->next = NULL;
    copy->entry = lv_cache_acquire(source->cache, lv_cache_entry_get_data(source->entry), NULL);
    if (copy->entry != source->entry) {
        if (copy->entry) lv_cache_release(copy->cache, copy->entry, NULL);
        free(copy);
        return false;
    }
    *target = copy;
    return true;
}

static void discard_animation_checkpoints(animation_image_checkpoint_t *saved, unsigned count)
{
    for (unsigned i = 0; i < count; ++i) {
        luat_plcui_image_release(&saved[i].state.current);
        luat_plcui_image_release(&saved[i].state.next);
        luat_plcui_image_release(&saved[i].state.retiring);
        lv_free(saved[i].source);
    }
    free(saved);
}

static bool animation_needs_checkpoint(const plcui_widget_t *widget)
{
    const plcui_animimg_t *animation = widget->animation;
    return animation && (!animation->current || animation->current_frame != animation->frame)
        && luat_plcui_component_visible(widget);
}

static animation_image_checkpoint_t *checkpoint_animation_images(plcui_page_t *page,
                                                                  unsigned count,
                                                                  plcui_error_t *error)
{
    animation_image_checkpoint_t *saved = calloc(count, sizeof(*saved));
    if (!saved) {
        luat_plcui_error(error, "E_MEMORY", "Cannot allocate animation image transaction");
        return NULL;
    }
    unsigned at = 0;
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *widget = &page->widgets[i];
        if (!animation_needs_checkpoint(widget)) continue;
        animation_image_checkpoint_t *item = &saved[at++];
        item->widget = widget;
        item->state = *widget->animation;
        /* Assign clones individually; cleanup must never release an original
           lease when allocation fails partway through this checkpoint. */
        item->state.current = NULL;
        item->state.next = NULL;
        item->state.retiring = NULL;
        if (!clone_image_lease(widget->animation->current, &item->state.current)
            || !clone_image_lease(widget->animation->next, &item->state.next)
            || !clone_image_lease(widget->animation->retiring, &item->state.retiring)) {
            luat_plcui_error(error, "E_MEMORY", "Cannot retain animation image transaction");
            discard_animation_checkpoints(saved, count);
            return NULL;
        }
        if (widget->obj && widget->animation->current) {
            const lv_image_t *native = (const lv_image_t *)widget->obj;
            if (native->src && native->src_type == LV_IMAGE_SRC_FILE) {
                item->source = lv_strdup(native->src);
                if (!item->source) {
                    luat_plcui_error(error, "E_MEMORY", "Cannot retain animation image source");
                    discard_animation_checkpoints(saved, count);
                    return NULL;
                }
                item->source_width = native->w;
                item->source_height = native->h;
                item->source_format = (lv_color_format_t)native->cf;
            }
        }
    }
    return saved;
}

static void rollback_animation_images(animation_image_checkpoint_t *saved, unsigned count)
{
    for (unsigned i = 0; i < count; ++i) {
        animation_image_checkpoint_t *item = &saved[i];
        plcui_widget_t *widget = item->widget;
        plcui_animimg_t *animation = widget->animation;
        luat_plcui_image_release(&animation->current);
        luat_plcui_image_release(&animation->next);
        luat_plcui_image_release(&animation->retiring);
        *animation = item->state;
        /* Transfer the saved references back to the widget. */
        item->state.current = NULL;
        item->state.next = NULL;
        item->state.retiring = NULL;
        if (!widget->obj) continue;
        if (!item->source) {
            lv_image_set_src(widget->obj, NULL);
            continue;
        }
        /* Native set_src duplicates the path and can fail during OOM rollback.
           Restore only these source fields, adopting our preallocated string;
           leave the object's layout, callbacks and native runtime state alone. */
        lv_image_t *native = (lv_image_t *)widget->obj;
        lv_obj_invalidate(widget->obj);
        if (native->src_type == LV_IMAGE_SRC_FILE || native->src_type == LV_IMAGE_SRC_SYMBOL)
            lv_free((void *)native->src);
        native->src = item->source;
        item->source = NULL;
        native->src_type = LV_IMAGE_SRC_FILE;
        native->w = item->source_width;
        native->h = item->source_height;
        native->cf = item->source_format;
        lv_obj_refresh_self_size(widget->obj);
        lv_obj_refresh_ext_draw_size(widget->obj);
        lv_obj_invalidate(widget->obj);
    }
}

bool luat_plcui_prepare_page_images(plcui_document_t *doc, int page, plcui_error_t *error)
{
    if (!doc || page < 0 || (unsigned)page >= doc->page_count || !doc->pages[page].screen) {
        luat_plcui_error(error, "E_RESOURCE", "Target page is not instantiated");
        return false;
    }
    plcui_page_t *target = &doc->pages[page];
    /* Visibility must use the candidate layout (e.g. after moving a container).
       Already-bound same-frame animations do not change lease ownership here. */
    lv_obj_update_layout(target->screen);
    unsigned animation_count = 0;
    for (unsigned i = 0; i < target->count; ++i)
        if (animation_needs_checkpoint(&target->widgets[i])) ++animation_count;
    animation_image_checkpoint_t *saved = animation_count
        ? checkpoint_animation_images(target, animation_count, error) : NULL;
    if (animation_count && !saved) return false;
    plcui_image_pin_t *checkpoint = target->image_pins;
    for (unsigned i = 0; i < target->count; ++i) {
        plcui_widget_t *widget = &target->widgets[i];
        if ((widget->type == PLCUI_IMAGE || widget->type == PLCUI_SLIDER || widget->type == PLCUI_ANIMIMG)
            && !prepare_image(widget, error)) {
            rollback_animation_images(saved, animation_count);
            discard_animation_checkpoints(saved, animation_count);
            release_until(target, checkpoint);
            return false;
        }
    }
    discard_animation_checkpoints(saved, animation_count);
    return true;
}

void luat_plcui_release_page_images(plcui_document_t *doc, int page)
{
    if (!doc || page < 0 || (unsigned)page >= doc->page_count) return;
    release_until(&doc->pages[page], NULL);
}
#endif
