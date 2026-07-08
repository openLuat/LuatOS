/**
 * @file luat_camera_pc.c
 * @brief PC 模拟器摄像头适配（Windows Media Foundation）
 *
 * Windows 下通过主机摄像头实现 DVP 式 camera API；
 * Linux/macOS 下为空实现，保证编译与链接通过。
 */

#include "luat_conf_bsp.h"
#include "luat_base.h"
#include "luat_camera.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_zbuff.h"
#include "luat_log.h"

#include <stdio.h>
#include <string.h>

#define LUAT_LOG_TAG "camera.pc"

#ifndef LUAT_USE_LCD
luat_lcd_conf_t* luat_lcd_get_default(void) { return NULL; }
#endif

typedef struct {
    void *reader;
    int id;
    uint16_t width;
    uint16_t height;
    uint8_t quality;
    uint8_t mode;
    uint8_t running;
    uint8_t only_y;
    uint16_t crop_x;
    uint16_t crop_y;
    uint16_t crop_w;
    uint16_t crop_h;
    uint8_t is_mjpg;     /**< current stream subtype is MJPG */
    size_t capture_size; /**< actual MJPG frame size from last read */
} pc_camera_ctx_t;

static pc_camera_ctx_t g_cameras[1] = {0};

static pc_camera_ctx_t* pc_camera_get(int id) {
    if (id != 0) return NULL;
    return g_cameras;
}

static int map_quality(uint8_t q) {
    if (q == 1) return 90;
    if (q == 2) return 95;
    if (q == 3) return 99;
    if (q < 50) q = 50;
    if (q > 95) q = 95;
    return q;
}

#ifdef _WIN32

#include <windows.h>
#include <oleauto.h>
#include <mfidl.h>
#include <mfapi.h>
#include <mfreadwrite.h>
#include <wincodec.h>

#pragma comment(lib, "Mf.lib")
#pragma comment(lib, "Mfplat.lib")
#pragma comment(lib, "Mfreadwrite.lib")
#pragma comment(lib, "Mfuuid.lib")
#pragma comment(lib, "Windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

#define PC_CAST_READER(ctx) ((IMFSourceReader *)((ctx)->reader))

static int pc_mf_init(void) {
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        LLOGE("CoInitializeEx failed hr=0x%08X", (unsigned)hr);
        return -1;
    }
    hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    return SUCCEEDED(hr) ? 0 : -1;
}

static void pc_mf_deinit(void) {
    MFShutdown();
    CoUninitialize();
}

static IMFSourceReader* pc_open_default_reader(void) {
    IMFAttributes *pAttr = NULL;
    IMFActivate **ppDevices = NULL;
    IMFMediaSource *pSource = NULL;
    IMFSourceReader *pReader = NULL;
    UINT32 count = 0;
    HRESULT hr;

    hr = MFCreateAttributes(&pAttr, 1);
    if (SUCCEEDED(hr)) {
        hr = pAttr->lpVtbl->SetGUID(pAttr, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                    &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    }
    if (SUCCEEDED(hr)) {
        hr = MFEnumDeviceSources(pAttr, &ppDevices, &count);
    }
    if (FAILED(hr) || count == 0) {
        LLOGE("no video capture device found");
        goto DONE;
    }
    hr = ppDevices[0]->lpVtbl->ActivateObject(ppDevices[0], &IID_IMFMediaSource, (void**)&pSource);
    if (FAILED(hr)) goto DONE;
    hr = MFCreateSourceReaderFromMediaSource(pSource, NULL, &pReader);

DONE:
    if (ppDevices) {
        for (UINT32 i = 0; i < count; i++) {
            if (ppDevices[i]) ppDevices[i]->lpVtbl->Release(ppDevices[i]);
        }
        CoTaskMemFree(ppDevices);
    }
    if (pAttr) pAttr->lpVtbl->Release(pAttr);
    if (pSource) pSource->lpVtbl->Release(pSource);
    return pReader;
}

static int pc_reader_set_format(IMFSourceReader *reader, uint16_t w, uint16_t h, const GUID *subtype) {
    IMFMediaType *pType = NULL;
    HRESULT hr = MFCreateMediaType(&pType);
    if (SUCCEEDED(hr)) hr = pType->lpVtbl->SetGUID(pType, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    if (SUCCEEDED(hr)) hr = pType->lpVtbl->SetGUID(pType, &MF_MT_SUBTYPE, subtype);
    if (SUCCEEDED(hr)) hr = pType->lpVtbl->SetUINT64(pType, &MF_MT_FRAME_SIZE, ((UINT64)w << 32) | h);
    if (SUCCEEDED(hr)) hr = pType->lpVtbl->SetUINT64(pType, &MF_MT_FRAME_RATE, ((UINT64)30 << 32) | 1);
    if (SUCCEEDED(hr)) {
        hr = reader->lpVtbl->SetCurrentMediaType(reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, pType);
    }
    if (pType) pType->lpVtbl->Release(pType);
    return SUCCEEDED(hr) ? 0 : -1;
}

static void rgb24_to_rgb565(const uint8_t *src, uint16_t *dst, int w, int h) {
    for (int i = 0; i < w * h; i++) {
        uint8_t r = src[i * 3 + 0];
        uint8_t g = src[i * 3 + 1];
        uint8_t b = src[i * 3 + 2];
        dst[i] = (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
    }
}

static void yuy2_to_rgb565(const uint8_t *src, uint16_t *dst, int w, int h) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x += 2) {
            const uint8_t *p = src + y * w * 2 + x * 2;
            int y0 = p[0];
            int u  = p[1] - 128;
            int y1 = p[2];
            int v  = p[3] - 128;
            for (int k = 0; k < 2; k++) {
                int yy = (k == 0) ? y0 : y1;
                int r = yy + (int)(1.402f * v);
                int g = yy - (int)(0.344f * u + 0.714f * v);
                int b = yy + (int)(1.772f * u);
                if (r < 0) r = 0; else if (r > 255) r = 255;
                if (g < 0) g = 0; else if (g > 255) g = 255;
                if (b < 0) b = 0; else if (b > 255) b = 255;
                dst[y * w + x + k] = (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
            }
        }
    }
}

static void yuy2_to_rgb24(const uint8_t *src, uint8_t *dst, int w, int h) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x += 2) {
            const uint8_t *p = src + y * w * 2 + x * 2;
            int y0 = p[0];
            int u  = p[1] - 128;
            int y1 = p[2];
            int v  = p[3] - 128;
            for (int k = 0; k < 2; k++) {
                int yy = (k == 0) ? y0 : y1;
                int r = yy + (int)(1.402f * v);
                int g = yy - (int)(0.344f * u + 0.714f * v);
                int b = yy + (int)(1.772f * u);
                if (r < 0) r = 0; else if (r > 255) r = 255;
                if (g < 0) g = 0; else if (g > 255) g = 255;
                if (b < 0) b = 0; else if (b > 255) b = 255;
                uint8_t *d = dst + (y * w + x + k) * 3;
                /* WIC JPEG encoder expects BGR order. */
                d[0] = (uint8_t)b;
                d[1] = (uint8_t)g;
                d[2] = (uint8_t)r;
            }
        }
    }
}

static int pc_get_subtype(IMFSourceReader *reader, GUID *subtype) {
    IMFMediaType *pType = NULL;
    HRESULT hr = reader->lpVtbl->GetCurrentMediaType(reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &pType);
    if (SUCCEEDED(hr)) {
        hr = pType->lpVtbl->GetGUID(pType, &MF_MT_SUBTYPE, subtype);
        pType->lpVtbl->Release(pType);
    }
    return SUCCEEDED(hr) ? 0 : -1;
}

static int pc_read_frame(pc_camera_ctx_t *ctx, uint8_t *rgb24_out, uint16_t *rgb565_out) {
    IMFSourceReader *reader = PC_CAST_READER(ctx);
    IMFSample *pSample = NULL;
    IMFMediaBuffer *pBuffer = NULL;
    GUID subtype;
    DWORD flags = 0, streamIndex = 0;
    LONGLONG timestamp = 0;
    HRESULT hr = S_OK;
    int retries = 0;

    /* Source reader may return stream ticks without a sample on first reads. */
    while (retries < 30) {
        if (pSample) {
            pSample->lpVtbl->Release(pSample);
            pSample = NULL;
        }
        hr = reader->lpVtbl->ReadSample(reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                            0, &streamIndex, &flags, &timestamp, &pSample);
        if (FAILED(hr)) {
            LLOGE("ReadSample failed hr=0x%08X", (unsigned)hr);
            return -1;
        }
        if (flags & (0x1 | 0x2)) { /* ERROR or ENDOFSTREAM */
            LLOGE("ReadSample error flags=%u", (unsigned)flags);
            if (pSample) pSample->lpVtbl->Release(pSample);
            return -1;
        }
        if (pSample) break;
        retries++;
    }
    if (!pSample) {
        LLOGE("ReadSample no sample after retries");
        return -1;
    }

    hr = pSample->lpVtbl->ConvertToContiguousBuffer(pSample, &pBuffer);
    if (FAILED(hr)) {
        LLOGE("ConvertToContiguousBuffer failed hr=0x%08X", (unsigned)hr);
        pSample->lpVtbl->Release(pSample);
        return -1;
    }

    if (pc_get_subtype(reader, &subtype) != 0) {
        LLOGE("pc_get_subtype failed");
        pBuffer->lpVtbl->Release(pBuffer);
        pSample->lpVtbl->Release(pSample);
        return -1;
    }

    BYTE *pData = NULL;
    DWORD cbBuffer = 0, cbMax = 0;
    hr = pBuffer->lpVtbl->Lock(pBuffer, &pData, &cbMax, &cbBuffer);
    if (SUCCEEDED(hr)) {
        if (IsEqualGUID(&subtype, &MFVideoFormat_RGB24)) {
            ctx->is_mjpg = 0;
            if (rgb565_out) rgb24_to_rgb565((uint8_t*)pData, rgb565_out, ctx->width, ctx->height);
            if (rgb24_out) memcpy(rgb24_out, pData, ctx->width * ctx->height * 3);
        } else if (IsEqualGUID(&subtype, &MFVideoFormat_YUY2)) {
            ctx->is_mjpg = 0;
            if (rgb565_out) yuy2_to_rgb565((uint8_t*)pData, rgb565_out, ctx->width, ctx->height);
            if (rgb24_out) yuy2_to_rgb24((uint8_t*)pData, rgb24_out, ctx->width, ctx->height);
        } else if (IsEqualGUID(&subtype, &MFVideoFormat_MJPG)) {
            ctx->is_mjpg = 1;
            if (rgb565_out) {
                /* MJPG stream can not directly produce RGB565 */
                LLOGE("MJPG can not convert to RGB565");
                hr = E_FAIL;
            }
            if (rgb24_out && cbBuffer <= (DWORD)(ctx->width * ctx->height)) {
                memcpy(rgb24_out, pData, cbBuffer);
                ctx->capture_size = cbBuffer;
            } else if (rgb24_out) {
                LLOGE("MJPG frame too large for buffer");
                hr = E_FAIL;
            }
        } else {
            LLOGE("unsupported subtype %08X-%04X-%04X", subtype.Data1, subtype.Data2, subtype.Data3);
            hr = E_FAIL;
        }
        pBuffer->lpVtbl->Unlock(pBuffer);
    } else {
        LLOGE("Lock failed hr=0x%08X", (unsigned)hr);
    }
    pBuffer->lpVtbl->Release(pBuffer);
    pSample->lpVtbl->Release(pSample);
    return SUCCEEDED(hr) ? 0 : -1;
}

static int pc_rgb24_to_jpeg(const uint8_t *rgb24, int w, int h, int quality,
                            uint8_t **out_buf, size_t *out_size) {
    IWICImagingFactory *pFactory = NULL;
    IWICBitmapEncoder *pEncoder = NULL;
    IWICBitmapFrameEncode *pFrame = NULL;
    IPropertyBag2 *pBag = NULL;
    IStream *pStream = NULL;
    HGLOBAL hMem = NULL;
    HRESULT hr;

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&pFactory);
    if (SUCCEEDED(hr)) hr = CreateStreamOnHGlobal(NULL, TRUE, &pStream);
    if (SUCCEEDED(hr)) hr = pFactory->lpVtbl->CreateEncoder(pFactory, &GUID_ContainerFormatJpeg, NULL, &pEncoder);
    if (SUCCEEDED(hr)) hr = pEncoder->lpVtbl->Initialize(pEncoder, pStream, WICBitmapEncoderNoCache);
    if (SUCCEEDED(hr)) hr = pEncoder->lpVtbl->CreateNewFrame(pEncoder, &pFrame, &pBag);
    if (SUCCEEDED(hr)) {
        PROPBAG2 opt = {0};
        VARIANT var;
        opt.pstrName = (LPOLESTR)L"ImageQuality";
        VariantInit(&var);
        var.vt = VT_R4;
        var.fltVal = quality / 100.0f;
        pBag->lpVtbl->Write(pBag, 1, &opt, &var);
        hr = pFrame->lpVtbl->Initialize(pFrame, pBag);
    }
    if (SUCCEEDED(hr)) {
        WICPixelFormatGUID fmt = GUID_WICPixelFormat24bppBGR;
        hr = pFrame->lpVtbl->SetPixelFormat(pFrame, &fmt);
    }
    if (SUCCEEDED(hr)) hr = pFrame->lpVtbl->SetSize(pFrame, (UINT)w, (UINT)h);
    if (SUCCEEDED(hr)) hr = pFrame->lpVtbl->WritePixels(pFrame, (UINT)h, w * 3, w * h * 3, (BYTE*)rgb24);
    if (SUCCEEDED(hr)) hr = pFrame->lpVtbl->Commit(pFrame);
    if (SUCCEEDED(hr)) hr = pEncoder->lpVtbl->Commit(pEncoder);

    if (SUCCEEDED(hr)) {
        hr = GetHGlobalFromStream(pStream, &hMem);
        if (SUCCEEDED(hr)) {
            SIZE_T sz = GlobalSize(hMem);
            uint8_t *buf = (uint8_t *)GlobalLock(hMem);
            *out_buf = (uint8_t *)luat_heap_malloc(sz);
            if (*out_buf) {
                memcpy(*out_buf, buf, sz);
                *out_size = sz;
            } else {
                hr = E_OUTOFMEMORY;
            }
            GlobalUnlock(hMem);
        }
    }

    if (FAILED(hr)) {
        LLOGE("jpeg encode failed hr=0x%08X", (unsigned)hr);
    }

    if (pFrame) pFrame->lpVtbl->Release(pFrame);
    if (pBag) pBag->lpVtbl->Release(pBag);
    if (pEncoder) pEncoder->lpVtbl->Release(pEncoder);
    if (pStream) pStream->lpVtbl->Release(pStream);
    if (pFactory) pFactory->lpVtbl->Release(pFactory);
    return SUCCEEDED(hr) ? 0 : -1;
}

#endif /* _WIN32 */

int luat_camera_init(luat_camera_conf_t *conf) {
    if (g_cameras[0].reader) return -1;

    uint16_t w = conf && conf->sensor_width ? conf->sensor_width : 640;
    uint16_t h = conf && conf->sensor_height ? conf->sensor_height : 480;

#ifdef _WIN32
    if (pc_mf_init() != 0) return -1;
    IMFSourceReader *reader = pc_open_default_reader();
    if (!reader) {
        pc_mf_deinit();
        return -1;
    }
    g_cameras[0].is_mjpg = 0;
    if (pc_reader_set_format(reader, w, h, &MFVideoFormat_RGB24) != 0 &&
        pc_reader_set_format(reader, w, h, &MFVideoFormat_YUY2) != 0 &&
        pc_reader_set_format(reader, w, h, &MFVideoFormat_MJPG) != 0) {
        reader->lpVtbl->Release(reader);
        pc_mf_deinit();
        return -1;
    }
    g_cameras[0].is_mjpg = 1;
    g_cameras[0].reader = reader;
#else
    (void)w; (void)h;
    LLOGD("camera not supported on this host");
    return -1;
#endif

    g_cameras[0].id = 0;
    g_cameras[0].width = w;
    g_cameras[0].height = h;
    g_cameras[0].quality = 90;
    g_cameras[0].mode = LUAT_CAMERA_MODE_AUTO;
    g_cameras[0].running = 0;
    g_cameras[0].is_mjpg = 0;
    g_cameras[0].capture_size = 0;

    if (conf && conf->async) {
        extern void luat_camera_async_init_result(int result);
        luat_camera_async_init_result(0);
    }
    return 0;
}

int luat_camera_start(int id) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
    ctx->running = 1;
    return 0;
}

int luat_camera_stop(int id) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
    ctx->running = 0;
    return 0;
}

int luat_camera_close(int id) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
#ifdef _WIN32
    if (ctx->reader) {
        IMFSourceReader *reader = PC_CAST_READER(ctx);
        reader->lpVtbl->Release(reader);
        ctx->reader = NULL;
    }
    pc_mf_deinit();
#endif
    memset(ctx, 0, sizeof(*ctx));
    return 0;
}

int luat_camera_work_mode(int id, int mode) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
    ctx->mode = mode;
    return 0;
}

int luat_camera_config(int id, int key, int value) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
    if (key == LUAT_CAMERA_CONF_LOG_LEVEL) {
        extern int32_t g_camera_log_level;
        g_camera_log_level = value;
    }
    (void)value;
    return 0;
}

int luat_camera_capture_config(int id, uint16_t start_x, uint16_t start_y, uint16_t new_w, uint16_t new_h) {
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx) return -1;
    ctx->crop_x = start_x;
    ctx->crop_y = start_y;
    ctx->crop_w = new_w;
    ctx->crop_h = new_h;
    return 0;
}

int luat_camera_capture(int id, uint8_t quality, const char *path) {
#ifndef _WIN32
    (void)id; (void)quality; (void)path;
    return -1;
#else
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx || !ctx->reader) return -1;

    /* MJPG stream: frame buffer is compressed, allocate larger. */
    int img_size = ctx->is_mjpg ? (ctx->width * ctx->height) : (ctx->width * ctx->height * 3);
    uint8_t *frame_buf = (uint8_t *)luat_heap_malloc(img_size);
    if (!frame_buf) return -1;
    int ok = -1;
    uint8_t *jpeg = NULL;
    size_t jsize = 0;
    if (pc_read_frame(ctx, frame_buf, NULL) == 0) {
        if (ctx->is_mjpg) {
            jpeg = frame_buf;
            jsize = ctx->capture_size > 0 ? ctx->capture_size : img_size;
        } else if (pc_rgb24_to_jpeg(frame_buf, ctx->width, ctx->height, map_quality(quality), &jpeg, &jsize) == 0) {
            /* jpeg allocated by pc_rgb24_to_jpeg */
        }
        if (jpeg && jsize > 0) {
            FILE *fd = luat_fs_fopen(path, "wb");
            if (fd) {
                luat_fs_fwrite(jpeg, 1, jsize, fd);
                luat_fs_fclose(fd);
                ok = 0;
            }
            if (!ctx->is_mjpg) luat_heap_free(jpeg);
        }
    }
    luat_heap_free(frame_buf);
    luat_msgbug_put2(l_camera_handler, NULL, id, ok ? 0 : 1, 0);
    return ok;
#endif
}

int luat_camera_capture_in_ram(int id, uint8_t quality, void *buffer) {
#ifndef _WIN32
    (void)id; (void)quality; (void)buffer;
    return -1;
#else
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    luat_zbuff_t *zbuff = (luat_zbuff_t *)buffer;
    if (!ctx || !ctx->reader || !zbuff) return -1;

    int img_size = ctx->width * ctx->height * 3;
    uint8_t *rgb24 = (uint8_t *)luat_heap_malloc(img_size);
    if (!rgb24) return -1;
    int ok = -1;
    uint8_t *jpeg = NULL;
    size_t jsize = 0;
    if (pc_read_frame(ctx, rgb24, NULL) == 0 &&
        pc_rgb24_to_jpeg(rgb24, ctx->width, ctx->height, map_quality(quality), &jpeg, &jsize) == 0) {
        if (jsize <= zbuff->len) {
            memcpy(zbuff->addr, jpeg, jsize);
            zbuff->used = jsize;
            ok = 0;
        }
        luat_heap_free(jpeg);
    }
    luat_heap_free(rgb24);
    luat_msgbug_put2(l_camera_handler, NULL, id, ok ? 0 : 1, 0);
    return ok;
#endif
}

int luat_camera_get_raw_start(int id, int w, int h, uint8_t *data, uint32_t max_len) {
#ifndef _WIN32
    (void)id; (void)w; (void)h; (void)data; (void)max_len;
    return -1;
#else
    pc_camera_ctx_t *ctx = pc_camera_get(id);
    if (!ctx || !ctx->reader) return -1;
    uint32_t need = (uint32_t)w * h * 2;
    if (max_len < need) return -1;
    int got = pc_read_frame(ctx, NULL, (uint16_t *)data);
    if (got != 0) {
        luat_msgbug_put2(l_camera_handler, NULL, id, 0, 0);
        return -1;
    }
    luat_msgbug_put2(l_camera_handler, NULL, id, need, 0);
    return 0;
#endif
}

int luat_camera_get_raw_again(int id) {
    (void)id;
    return 0;
}

int luat_camera_video(int id, int w, int h, uint8_t uart_id) {
    (void)id; (void)w; (void)h; (void)uart_id;
    return -1;
}

int luat_camera_setup(int id, luat_spi_camera_t *conf, void* callback, void *param) {
    (void)id; (void)conf; (void)callback; (void)param;
    return -1;
}

int luat_camera_set_image_w_h(int id, uint16_t w, uint16_t h) {
    (void)id; (void)w; (void)h;
    return -1;
}

int luat_camera_start_with_buffer(int id, void *buf) {
    (void)id; (void)buf;
    return -1;
}

void luat_camera_continue_with_buffer(int id, void *buf) {
    (void)id; (void)buf;
}

int luat_camera_pause(int id, uint8_t is_pause) {
    (void)id; (void)is_pause;
    return -1;
}

int luat_camera_image_decode_init(uint8_t type, void *stack, uint32_t stack_length, uint32_t priority) {
    (void)type; (void)stack; (void)stack_length; (void)priority;
    return -1;
}

int luat_camera_image_decode_once(uint8_t *data, uint16_t image_w, uint16_t image_h, uint32_t timeout, void *callback, void *param) {
    (void)data; (void)image_w; (void)image_h; (void)timeout; (void)callback; (void)param;
    return -1;
}

void luat_camera_image_decode_deinit(void) {
}

int luat_camera_image_decode_get_result(uint8_t *buf) {
    (void)buf;
    return -1;
}

int luat_camera_set_cache(int id, uint8_t **cache, uint8_t cache_num, uint32_t cache_len) {
    (void)id; (void)cache; (void)cache_num; (void)cache_len;
    return 0;
}

int luat_camera_preview(int id, uint8_t on_off) {
    (void)id; (void)on_off;
    return -1;
}

void luat_camera_pwdn_pin(int id, uint8_t level) {
    (void)id; (void)level;
}

void luat_camera_reset_pin(int id, uint8_t level) {
    (void)id; (void)level;
}

int luat_usb_camera_stream_on_off(uint8_t app_id, uint8_t on_off) {
    (void)app_id; (void)on_off;
    return -1;
}

int luat_usb_camera_stream_set_config_by_index(uint8_t app_id, uint8_t format_index, uint8_t resolution_index) {
    (void)app_id; (void)format_index; (void)resolution_index;
    return -1;
}

int luat_usb_camera_stream_set_config(uint8_t app_id, uint8_t format_type, uint16_t w, uint16_t h) {
    (void)app_id; (void)format_type; (void)w; (void)h;
    return -1;
}

int luat_usb_camera_stream_get_config_format_num(uint8_t app_id, uint8_t *format_num) {
    (void)app_id; (void)format_num;
    return -1;
}

int luat_usb_camera_stream_get_config_resolution_num(uint8_t app_id, uint8_t format_index, uint8_t *format_type, uint8_t *resolution_num) {
    (void)app_id; (void)format_index; (void)format_type; (void)resolution_num;
    return -1;
}

int luat_usb_camera_stream_get_config_info(uint8_t app_id, uint8_t format_index, uint8_t resolution_index, uint8_t *fps, uint16_t *w, uint16_t *h) {
    (void)app_id; (void)format_index; (void)resolution_index; (void)fps; (void)w; (void)h;
    return -1;
}

int luat_usb_camera_stream_set_min_data_len(uint8_t app_id, uint32_t min_data_len) {
    (void)app_id; (void)min_data_len;
    return -1;
}

int luat_usb_camera_stream_set_jump_frame_cnt(uint8_t app_id, uint8_t jump_frame_cnt) {
    (void)app_id; (void)jump_frame_cnt;
    return -1;
}
