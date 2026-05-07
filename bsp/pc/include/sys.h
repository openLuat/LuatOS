/**
 * @file sys.h
 * @brief PC simulator stub for RTOS <sys.h> used by mp4player ring-buffer headers.
 *
 * The original CCM42xx platform provides a proprietary <sys.h> from its RTOS.
 * On PC, none of the symbols it exports are actually used by the portable
 * ring-buffer code (audio_rb.h / video_rb.h); the include is vestigial.
 * This empty stub satisfies the preprocessor without pulling in any
 * platform-specific declarations.
 */
#pragma once
#include <stdint.h>
#include <stddef.h>
