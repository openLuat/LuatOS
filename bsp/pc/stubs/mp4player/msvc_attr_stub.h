/**
 * @file msvc_attr_stub.h
 * @brief PC simulator shim that neutralises GCC's __attribute__ syntax on MSVC.
 *
 * Force-included into luatos-ext-components/mp4player/video_decode/mp4_decode.c
 * (see the mp4player block in bsp/pc/xmake.lua). That file declares
 *
 *     static unsigned short s_video_rgb_buf[...] __attribute__((aligned(4)));
 *
 * MSVC has no equivalent keyword and no way to reach it through the include
 * path, so the attribute is simply dropped. The buffer is a plain static array
 * and MSVC already aligns it to at least 4 bytes, so nothing is lost.
 *
 * This only applies to MSVC; GCC/clang builds (real firmware) keep the original
 * attribute because the guard below is false there.
 */

#if defined(_MSC_VER) && !defined(__GNUC__)
#ifndef __attribute__
#define __attribute__(x)
#endif
#endif
