
#ifndef U8G2_LUAT_FONTS_H
#define U8G2_LUAT_FONTS_H

#include "u8x8.h"

/*==========================================*/
/* C++ compatible */

#ifdef __cplusplus
extern "C" {
#endif

/*==========================================*/


/*==========================================*/

/* start font list */

extern const uint8_t u8g2_font_opposansm8[] U8G2_FONT_SECTION("u8g2_font_opposansm8");
extern const uint8_t u8g2_font_opposansm10[] U8G2_FONT_SECTION("u8g2_font_opposansm10");
extern const uint8_t u8g2_font_opposansm12[] U8G2_FONT_SECTION("u8g2_font_opposansm12");
extern const uint8_t u8g2_font_opposansm16[] U8G2_FONT_SECTION("u8g2_font_opposansm16");
extern const uint8_t u8g2_font_opposansm18[] U8G2_FONT_SECTION("u8g2_font_opposansm18");
extern const uint8_t u8g2_font_opposansm20[] U8G2_FONT_SECTION("u8g2_font_opposansm20");
extern const uint8_t u8g2_font_opposansm22[] U8G2_FONT_SECTION("u8g2_font_opposansm22");
extern const uint8_t u8g2_font_opposansm24[] U8G2_FONT_SECTION("u8g2_font_opposansm24");
extern const uint8_t u8g2_font_opposansm32[] U8G2_FONT_SECTION("u8g2_font_opposansm32");
extern const uint8_t u8g2_font_opposansm8_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm8_chinese");
extern const uint8_t u8g2_font_opposansm10_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm10_chinese");
extern const uint8_t u8g2_font_opposansm12_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm12_chinese");
extern const uint8_t u8g2_font_opposansm16_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm16_chinese");
extern const uint8_t u8g2_font_opposansm18_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm18_chinese");
extern const uint8_t u8g2_font_opposansm20_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm20_chinese");
extern const uint8_t u8g2_font_opposansm22_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm22_chinese");
extern const uint8_t u8g2_font_opposansm24_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm24_chinese");
extern const uint8_t u8g2_font_opposansm32_chinese[] U8G2_FONT_SECTION("u8g2_font_opposansm32_chinese");

extern const uint8_t u8g2_font_sarasa_m8_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m8_ascii");
extern const uint8_t u8g2_font_sarasa_m10_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m10_ascii");
extern const uint8_t u8g2_font_sarasa_m12_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m12_ascii");
extern const uint8_t u8g2_font_sarasa_m14_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m14_ascii");
extern const uint8_t u8g2_font_sarasa_m16_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m16_ascii");
extern const uint8_t u8g2_font_sarasa_m18_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m18_ascii");
extern const uint8_t u8g2_font_sarasa_m20_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m20_ascii");
extern const uint8_t u8g2_font_sarasa_m22_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m22_ascii");
extern const uint8_t u8g2_font_sarasa_m24_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m24_ascii");
extern const uint8_t u8g2_font_sarasa_m26_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m26_ascii");
extern const uint8_t u8g2_font_sarasa_m28_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m28_ascii");
extern const uint8_t u8g2_font_sarasa_m30_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m30_ascii");
extern const uint8_t u8g2_font_sarasa_m32_ascii[] U8G2_FONT_SECTION("u8g2_font_sarasa_m32_ascii");

extern const uint8_t u8g2_font_sarasa_m8_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m8_chinese");
extern const uint8_t u8g2_font_sarasa_m10_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m10_chinese");
extern const uint8_t u8g2_font_sarasa_m12_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m12_chinese");
extern const uint8_t u8g2_font_sarasa_m14_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m14_chinese");
extern const uint8_t u8g2_font_sarasa_m16_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m16_chinese");
extern const uint8_t u8g2_font_sarasa_m18_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m18_chinese");
extern const uint8_t u8g2_font_sarasa_m20_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m20_chinese");
extern const uint8_t u8g2_font_sarasa_m22_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m22_chinese");
extern const uint8_t u8g2_font_sarasa_m24_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m24_chinese");
extern const uint8_t u8g2_font_sarasa_m26_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m26_chinese");
extern const uint8_t u8g2_font_sarasa_m28_chinese[] U8G2_FONT_SECTION("u8g2_font_sarasa_m28_chinese");

// include custom fonts
#include "luat_u8g2_fonts_custom.h"

/* end font list */


/*==========================================*/
/* C++ compatible */

#ifdef __cplusplus
}
#endif


#endif

