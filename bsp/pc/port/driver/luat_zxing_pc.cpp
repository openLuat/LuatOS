/**
 * @file luat_zxing_pc.cpp
 * @brief PC 模拟器 ZXing-C++ 解码封装（对 C 文件暴露 C ABI）
 *
 * 码制映射与 luatos-sdk-ccm42xx-gcc 的 luat_camera_ccm42xx.c
 * luat_camera_scan() 保持一致。
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include <string>
#include <vector>

#include "ReadBarcode.h"
#include "ReaderOptions.h"
#include "ImageView.h"
#include "BarcodeFormat.h"
#include "Barcode.h"

extern "C" {
#include "luat_camera.h"

int pc_zxing_decode_gray(const uint8_t *gray, int w, int h, uint32_t luat_scan_type,
                         char *out, size_t out_len);
}

static ZXing::BarcodeFormats pc_scan_formats(uint32_t type)
{
    using ZXing::BarcodeFormat;
    if (!type) {
        return BarcodeFormat::All;
    }
    std::vector<BarcodeFormat> list;
    if (LUAT_CAMERA_SCAN_CODE_1D & type) {
        list.push_back(BarcodeFormat::AllLinear);
    }
    if (LUAT_CAMERA_SCAN_CODE_QR_CODE & type) {
        list.push_back(BarcodeFormat::QRCode);
        list.push_back(BarcodeFormat::MicroQRCode);
        list.push_back(BarcodeFormat::RMQRCode);
    }
    if (LUAT_CAMERA_SCAN_CODE_DATA_MATRIX & type) {
        list.push_back(BarcodeFormat::DataMatrix);
    }
    if (LUAT_CAMERA_SCAN_CODE_AZTEC_CODE & type) {
        list.push_back(BarcodeFormat::Aztec);
        list.push_back(BarcodeFormat::AztecRune);
    }
    if (LUAT_CAMERA_SCAN_CODE_PDF417 & type) {
        list.push_back(BarcodeFormat::PDF417);
        list.push_back(BarcodeFormat::CompactPDF417);
        list.push_back(BarcodeFormat::MicroPDF417);
    }
    if (LUAT_CAMERA_SCAN_CODE_MAXICODE & type) {
        list.push_back(BarcodeFormat::MaxiCode);
    }
    ZXing::BarcodeFormats fmts(std::move(list));
    if (fmts.empty()) {
        fmts = BarcodeFormat::All;
    }
    return fmts;
}

/**
 * @brief 对灰度图执行一次扫码解码
 * @param gray 灰度像素（每像素1字节）
 * @param luat_scan_type LUAT_CAMERA_SCAN_CODE_* 组合，0 表示全部码制
 * @return >0 解码结果长度；0 未命中；-1 参数错误
 */
extern "C" int pc_zxing_decode_gray(const uint8_t *gray, int w, int h, uint32_t luat_scan_type,
                                    char *out, size_t out_len)
{
    if (!gray || w <= 0 || h <= 0 || !out || out_len == 0) {
        return -1;
    }
    ZXing::ImageView img(gray, w, h, ZXing::ImageFormat::Lum);
    auto opts = ZXing::ReaderOptions()
                    .setFormats(pc_scan_formats(luat_scan_type))
                    .setTryHarder(true);
    auto results = ZXing::ReadBarcodes(img, opts);
    for (const auto &r : results) {
        if (r.isValid()) {
            std::string txt = r.text();
            size_t n = txt.size() < out_len - 1 ? txt.size() : out_len - 1;
            memcpy(out, txt.data(), n);
            out[n] = 0;
            return (int)n;
        }
    }
    return 0;
}
