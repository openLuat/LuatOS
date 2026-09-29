/*
* Copyright 2019 Nu-book Inc.
* Copyright 2023 Axel Waggershauser
*/
// SPDX-License-Identifier: Apache-2.0

// Hand-written replacement for the cmake-generated Version.h of zxing-cpp v3.1.1.
// Only what the LuatOS PC simulator build needs: readers enabled, writers disabled.

#pragma once

#define ZXING_READERS 1
/* ZXING_WRITERS disabled */

#define ZXING_ENABLE_1D 1
#define ZXING_ENABLE_AZTEC 1
#define ZXING_ENABLE_DATAMATRIX 1
#define ZXING_ENABLE_MAXICODE 1
#define ZXING_ENABLE_PDF417 1
#define ZXING_ENABLE_QRCODE 1

/* #undef ZXING_EXPERIMENTAL_API */
/* #undef ZXING_USE_ZINT */

// Version numbering
#define ZXING_VERSION_MAJOR 3
#define ZXING_VERSION_MINOR 1
#define ZXING_VERSION_PATCH 1
#define ZXING_VERSION_SUFFIX ""

#define ZXING_VERSION_STR "3.1.1"
