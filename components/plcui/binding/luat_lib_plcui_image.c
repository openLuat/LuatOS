/*
@module plcui.image
@summary XML 图片组件与图集裁片
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_component.h"
#include <stdio.h>
#include <string.h>

/**
 * 设置 image 的默认图片资源。
 * @api image:set_src(resource_id)
 * @string resource_id XML resources 中已声明的 image 资源 ID，UTF-8 长度须小于 64 字节
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 参数是资源 ID，不是图片文件路径。
 * @note 禁用、按下、选中状态仍优先使用其对应图片。
 * @note 可见图片先准备当前状态资源，失败返回错误并保留原默认资源；隐藏图片在显示时准备。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_src("logo_online")
 */
static int image_set_src(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_IMAGE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    const char *id = luaL_checkstring(L, 2);
    if (strlen(id) >= PLCUI_ID_MAX || !luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE)) {
        return luat_plcui_binding_error(L, "E_RESOURCE", "Image resource does not exist");
    }
    char previous[PLCUI_ID_MAX];
    memcpy(previous, widget->source[0], sizeof(previous));
    snprintf(widget->source[0], sizeof(widget->source[0]), "%s", id);
    if (widget->document->preparing_page < 0 && !luat_plcui_prepare_widget_image(widget, &error)) {
        memcpy(widget->source[0], previous, sizeof(previous));
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 设置 image 的业务选中状态。
 * @api image:set_checked(checked)
 * @bool checked true 为选中，false 为未选中
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 选中时使用 src-checked，未配置时回退默认图。
 * @note 状态图片优先级为禁用、按下、选中、默认。
 * @note 不派发 on-click；可见状态图准备失败时恢复原选中状态。
 * @usage
 * local image = xml:find("main", "pump")
 * image:set_checked(true)
 */
static int image_set_checked(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_IMAGE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    bool previous = widget->checked;
    widget->checked = lua_toboolean(L, 2) != 0;
    if (widget->document->preparing_page < 0 && !luat_plcui_prepare_widget_image(widget, &error)) {
        widget->checked = previous;
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 同步提交图片显示参数和尺寸，并在资源准备失败时恢复旧配置。
 * @param L Lua 状态机，接收 true 或 nil,error 返回值。
 * @param widget 已暂存新参数的 image 组件。
 * @param previous 修改前的图片显示参数快照。
 * @param old_width 修改前的逻辑宽度，单位像素。
 * @param old_height 修改前的逻辑高度，单位像素。
 * @return Lua 返回值个数：成功为 1，失败为 2。
 * @note 仅为绑定层内部辅助函数，不注册为 Lua 方法。
 * @note prepare 阶段延后资源准备；正常调用在返回前完成准备或回滚。
 */
static int image_commit(lua_State *L, plcui_widget_t *widget, const plcui_image_t *previous,
                        int32_t old_width, int32_t old_height)
{
    plcui_error_t error;
    lv_obj_set_size(widget->obj, widget->w, widget->h);
    luat_plcui_image_sync(widget);
    if (widget->document->preparing_page < 0 && !luat_plcui_prepare_widget_image(widget, &error)) {
        *widget->image = *previous;
        widget->w = old_width;
        widget->h = old_height;
        lv_obj_set_size(widget->obj, old_width, old_height);
        luat_plcui_image_sync(widget);
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 检查调用对象是有效 image 句柄，并按需分配图片显示参数。
 * @param L Lua 状态机，第 1 个参数为组件句柄。
 * @param error 失败时填写类型、生命周期或内存错误。
 * @return 成功返回组件指针，失败返回 NULL；由调用者压入 Lua 错误返回值。
 */
static plcui_widget_t *image_configured(lua_State *L, plcui_error_t *error)
{
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_IMAGE, error);
    if (!widget || !luat_plcui_image_config(widget, error)) return NULL;
    return widget;
}

/**
 * 设置源图片在组件逻辑框内的适配方式。
 * @api image:set_fit(mode)
 * @string mode stretch 拉伸填满、contain 等比完整显示、cover 等比铺满裁边，或 center 按原始尺寸居中
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note XML 默认 stretch；只有 center 模式允许手动缩放、旋转和枢轴。
 * @note 切换到不同模式会重置 zoom=256、rotation=0 和默认源图中心枢轴；同模式调用不重置。
 * @note 裁片模式中调用返回 E_NOT_SUPPORTED，须先 clear_crop；资源准备失败保留旧模式。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_fit("center")
 * image:set_zoom(512)
 */
static int image_set_fit(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    const char *mode = luaL_checkstring(L, 2);
    lv_image_align_t fit;
    if (!strcmp(mode, "stretch")) fit = LV_IMAGE_ALIGN_STRETCH;
    else if (!strcmp(mode, "contain")) fit = LV_IMAGE_ALIGN_CONTAIN;
    else if (!strcmp(mode, "cover")) fit = LV_IMAGE_ALIGN_COVER;
    else if (!strcmp(mode, "center")) fit = LV_IMAGE_ALIGN_CENTER;
    else return luat_plcui_binding_error(L, "E_SCHEMA", "fit must be stretch, contain, cover or center");
    plcui_image_t *image = widget->image;
    if (image->crop) return luat_plcui_binding_error(L, "E_NOT_SUPPORTED", "Clear image crop before changing fit");
    if (image->fit == fit) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->fit = fit;
    image->zoom = 256;
    image->rotation = 0;
    image->pivot_explicit = false;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 为手动图片变换的模式冲突生成统一 Lua 错误返回值。
 * @param L Lua 状态机，接收 nil,error。
 * @param image 当前图片显示参数。
 * @return Lua 返回值个数，固定为 2。
 * @note 裁片模式返回 E_NOT_SUPPORTED；未选择 center 时返回 E_SCHEMA。
 */
static int image_manual_error(lua_State *L, const plcui_image_t *image)
{
    return luat_plcui_binding_error(L, image->crop ? "E_NOT_SUPPORTED" : "E_SCHEMA",
        image->crop ? "Clear image crop before applying transforms" : "Select fit=center before applying transforms");
}

/**
 * 按源图像素尺寸等比缩放图片内容，不改变组件逻辑宽高。
 * @api image:set_zoom(zoom)
 * @int zoom 1～4096，256 表示 100%，128 表示 50%，512 表示 200%
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 默认 256；须先设置 fit="center"，裁片模式不支持。
 * @note 缩放围绕当前枢轴进行，外溢像素不扩大逻辑点击区域，也不减少源图解码内存。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_fit("center")
 * image:set_zoom(512)
 */
static int image_set_zoom(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer zoom = luaL_checkinteger(L, 2);
    if (zoom < 1 || zoom > 4096) return luat_plcui_binding_error(L, "E_SCHEMA", "zoom must be between 1 and 4096");
    plcui_image_t *image = widget->image;
    if (image->crop || image->fit != LV_IMAGE_ALIGN_CENTER) return image_manual_error(L, image);
    if (image->zoom == zoom) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->zoom = (uint16_t)zoom;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 围绕当前枢轴旋转图片内容。
 * @api image:set_rotation(angle)
 * @int angle 顺时针角度，单位为 0.1 度；900 表示 90 度，允许负数和超过一圈的整数
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 默认 0；写入前归一到 0～3599，须先设置 fit="center"，裁片模式不支持。
 * @note 旋转不改变组件逻辑宽高或点击区域；资源格式不支持变换时返回 E_NOT_SUPPORTED。
 * @usage
 * local image = xml:find("main", "pointer")
 * image:set_fit("center")
 * image:set_rotation(900)
 */
static int image_set_rotation(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer angle = luaL_checkinteger(L, 2) % 3600;
    if (angle < 0) angle += 3600;
    plcui_image_t *image = widget->image;
    if (image->crop || image->fit != LV_IMAGE_ALIGN_CENTER) return image_manual_error(L, image);
    if (image->rotation == angle) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->rotation = (uint16_t)angle;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 设置图片缩放和旋转使用的显式枢轴。
 * @api image:set_pivot(x, y)
 * @int x 枢轴横坐标，范围 -4096～4096，单位为未缩放源图像素
 * @int y 枢轴纵坐标，范围 -4096～4096，单位为未缩放源图像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 默认枢轴为当前源图中心；显式坐标相对源图左上角，不是组件或屏幕坐标，允许位于源图外。
 * @note 仅 fit="center" 且未启用裁片时可用；显式枢轴在换源后保持原坐标。
 * @usage
 * local image = xml:find("main", "pointer")
 * image:set_fit("center")
 * image:set_pivot(32, 32) -- 64×64 源图的中心
 * image:set_rotation(450)
 */
static int image_set_pivot(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer x = luaL_checkinteger(L, 2), y = luaL_checkinteger(L, 3);
    if (x < -4096 || x > 4096 || y < -4096 || y > 4096)
        return luat_plcui_binding_error(L, "E_SCHEMA", "pivot coordinates must be between -4096 and 4096");
    plcui_image_t *image = widget->image;
    if (image->crop || image->fit != LV_IMAGE_ALIGN_CENTER) return image_manual_error(L, image);
    if (image->pivot_explicit && image->pivot_x == x && image->pivot_y == y) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->pivot_x = (int32_t)x;
    image->pivot_y = (int32_t)y;
    image->pivot_explicit = true;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 设置图片内容的整体不透明度。
 * @api image:set_opacity(opacity)
 * @int opacity 0～255，0 为完全透明，255 为完全不透明
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 默认 255；与源图 alpha 和父级透明度共同作用，可用于普通图片或裁片。
 * @note 完全透明仍保留原点击能力；需要禁止交互时使用 set_hidden 或 set_disabled。
 * @note 从透明变为可见时可能准备图片资源，失败保留原透明度。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_opacity(128)
 */
static int image_set_opacity(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer opacity = luaL_checkinteger(L, 2);
    if (opacity < 0 || opacity > 255) return luat_plcui_binding_error(L, "E_SCHEMA", "opacity must be between 0 and 255");
    plcui_image_t *image = widget->image;
    if (image->opacity == opacity) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->opacity = (uint8_t)opacity;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 设置 image 的逻辑宽高。
 * @api image:set_size(width, height)
 * @int width 1～4096，单位像素
 * @int height 1～4096，单位像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 自动 fit 模式按新逻辑框重新适配；center 保留手动倍率并按新框居中。
 * @note 裁片模式以新宽高作为源窗口大小，越出源图时报错并回滚。
 * @note 已配置 hit-* 时，其点击矩形必须仍在新逻辑框内，否则返回 E_SCHEMA。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_size(160, 120)
 */
static int image_set_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer width = luaL_checkinteger(L, 2), height = luaL_checkinteger(L, 3);
    if (width < 1 || width > 4096 || height < 1 || height > 4096)
        return luat_plcui_binding_error(L, "E_SCHEMA", "Image dimensions must be between 1 and 4096");
    if (widget->has_hit_rect && ((int64_t)widget->hit_x + widget->hit_w > width
        || (int64_t)widget->hit_y + widget->hit_h > height))
        return luat_plcui_binding_error(L, "E_SCHEMA", "Hit rectangle exceeds new image dimensions");
    if (widget->w == width && widget->h == height) return luat_plcui_binding_success(L);
    plcui_image_t previous = *widget->image;
    int32_t old_width = widget->w, old_height = widget->h;
    widget->w = (int32_t)width;
    widget->h = (int32_t)height;
    return image_commit(L, widget, &previous, old_width, old_height);
}

/**
 * 设置图片缩放、旋转重采样的抗锯齿开关。
 * @api image:set_antialias(enabled)
 * @bool enabled true 为开启，false 为关闭
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 默认开启；关闭可能降低部分绘制开销，但边缘更粗，效果需结合平台验证。
 * @note 固定 1:1 裁片没有重采样，该开关通常不改变其画面。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_antialias(false)
 */
static int image_set_antialias(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    bool enabled = lua_toboolean(L, 2) != 0;
    if (widget->image->antialias == enabled) return luat_plcui_binding_success(L);
    plcui_image_t previous = *widget->image;
    widget->image->antialias = enabled;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 显示源图片中的一个矩形窗口，用于图集和局部状态高亮。
 * @api image:set_crop(x, y)
 * @int x 源窗口左上角横坐标，范围 0～4096，单位源图像素
 * @int y 源窗口左上角纵坐标，范围 0～4096，单位源图像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 源窗口宽高取组件当前 w/h，按 1:1 显示；不改变组件位置或 hit-* 点击矩形。
 * @note 要求 zoom=256、rotation=0 且未设置显式 pivot，否则返回 E_NOT_SUPPORTED。
 * @note 可见状态下窗口越出当前源图返回 E_RESOURCE 并回滚；隐藏时在显示前校验资源。
 * @note 多个裁片共享基础资源与解码缓存，仍须读取和解码整张源图。
 * @note 可叠放在正常态整图上；XML 配置 clickable="true"、src 和 src-pressed 后，按下时自动切换同一源窗口的状态图。
 * @usage
 * local image = xml:find("main", "atlas_button")
 * image:set_crop(80, 120) -- 组件 w/h 决定裁片宽高
 */
static int image_set_crop(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer x = luaL_checkinteger(L, 2), y = luaL_checkinteger(L, 3);
    if (x < 0 || x > 4096 || y < 0 || y > 4096)
        return luat_plcui_binding_error(L, "E_SCHEMA", "Crop coordinates must be between 0 and 4096");
    plcui_image_t *image = widget->image;
    if (image->zoom != 256 || image->rotation || image->pivot_explicit)
        return luat_plcui_binding_error(L, "E_NOT_SUPPORTED", "Reset manual transforms before cropping");
    if (image->crop && image->crop_x == x && image->crop_y == y) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->crop = true;
    image->crop_x = (int32_t)x;
    image->crop_y = (int32_t)y;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 清除图片源窗口裁剪并恢复默认拉伸显示。
 * @api image:clear_crop()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 恢复 fit="stretch"、zoom=256、rotation=0 和默认枢轴，不改变位置、逻辑尺寸或透明度。
 * @note 未启用裁片时直接成功；恢复所需资源准备失败则保留原裁片配置。
 * @usage
 * local image = xml:find("main", "atlas_button")
 * image:clear_crop()
 * image:set_fit("center")
 */
static int image_clear_crop(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = image_configured(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_image_t *image = widget->image;
    if (!image->crop) return luat_plcui_binding_success(L);
    plcui_image_t previous = *image;
    image->crop = false;
    image->crop_x = image->crop_y = 0;
    image->fit = LV_IMAGE_ALIGN_STRETCH;
    image->zoom = 256;
    image->rotation = 0;
    image->pivot_explicit = false;
    return image_commit(L, widget, &previous, widget->w, widget->h);
}

/**
 * 注册 image 的专属方法与公共组件方法。
 * @param L Lua 状态机。
 * @note 仅为 C 层注册入口；Lua 通过 xml:find 获取 image 句柄。
 */
void luat_plcui_register_image_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_src", image_set_src},
        {"set_checked", image_set_checked},
        {"set_fit", image_set_fit},
        {"set_zoom", image_set_zoom},
        {"set_rotation", image_set_rotation},
        {"set_pivot", image_set_pivot},
        {"set_opacity", image_set_opacity},
        {"set_size", image_set_size},
        {"set_antialias", image_set_antialias},
        {"set_crop", image_set_crop},
        {"clear_crop", image_clear_crop},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_IMAGE_MT);
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
