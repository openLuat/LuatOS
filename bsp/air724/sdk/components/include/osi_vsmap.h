/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef _OSI_VSMAP_H_
#define _OSI_VSMAP_H_

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "kernel_config.h"
#include "osi_compiler.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * helper macro for constant map
 *
 * For constants by *\#define* or *enum*, the followings can be used:
 * \code{.cpp}
 * osiValueStrMap_t array[] = {
 *     {OSI_VSMAP_CONST_DECL(SOME_MACRO)},
 *     {OSI_VSMAP_CONST_DECL(SOME_ENUM)},
 * };
 * \endcode
 */
#define OSI_VSMAP_CONST_DECL(name) name, #name

/**
 * helper data structure for integer string map
 */
typedef struct
{
    uint32_t value;  ///< integer value
    const char *str; ///< string value
} osiValueStrMap_t;

/**
 * data structure to define an unsigned integer range
 */
typedef struct
{
    uint32_t minval; ///< minimal value, inclusive
    uint32_t maxval; ///< maximum value, inclusive
} osiUintRange_t;

/**
 * data structure to define a signed integer range
 */
typedef struct
{
    int minval; ///< minimal value, inclusive
    int maxval; ///< maximum value, inclusive
} osiIntRange_t;

/**
 * data structure to define a unsigned 64bits integer range
 */
typedef struct
{
    uint64_t minval; ///< minimal value, inclusive
    uint64_t maxval; ///< maximum value, inclusive
} osiUint64Range_t;

/**
 * data structure to define a signed 64bits integer range
 */
typedef struct
{
    int64_t minval; ///< minimal value, inclusive
    int64_t maxval; ///< maximum value, inclusive
} osiInt64Range_t;

/**
 * @brief function for comparison
 *
 * In bsearch(3) and qsort(3), a comparison function is needed.
 * When the key for comparing struct is \p uint32_t and it is the
 * first field, this helper function can be used. For example:
 *
 * \code{.cpp}
 * struct {
 *     uint32_t id;
 *     // ......
 * };
 * \endcode
 *
 * @param key       key to be compared
 * @param p         value to be compared
 * @return
 *      - -1 if key < value, though negative can conform
 *      - 0 if key == value
 *      - 1 if key > value, though positive can conform
 */
int osiUintIdCompare(const void *key, const void *p);

/**
 * @brief bsearch in value-string map
 *
 * The map must be sorted ascending by \p value.
 *
 * When \p value isn't found in the map, \p defval will be returned.
 *
 * @param value     value to be searched
 * @param vs        value-string map array, must be valid and sorted
 * @param count     value-string map count
 * @param defval    default string when not found
 * @return
 *      - found mapped string
 *      - \p defval if not found
 */
const char *osiVsmapBsearch(uint32_t value, const osiValueStrMap_t *vs, size_t count, const char *defval);

/**
 * @brief check whether value-string map is sorted
 *
 * In \p osiVsmapBsearch, value-string map must be sorted ascending
 * by \p value. This is to check whether the map is sorted.
 *
 * @param vs        value-string map array, must be valid
 * @param count     value-string map count
 * @return
 *      - true if the map is sorted ascending
 *      - false if not sorted
 */
bool osiVsmapIsSorted(const osiValueStrMap_t *vs, size_t count);

/**
 * @brief customized bsearch in value-string map
 *
 * The real data structure of \p vs is not \p osiValueStrMap_t, but it is
 * started with \p osiValueStrMap_t, with customized size.
 *
 * @param value     value to be searched
 * @param vs        value-string map array, must be valid and sorted
 * @param count     value-string map count
 * @param size      real data structure size
 * @param defval    default string when not found
 * @return
 *      - found mapped string
 *      - \p defval if not found
 */
const char *osiVsmapBsearchEx(uint32_t value, const osiValueStrMap_t *vs, size_t count, size_t size, const char *defval);

/**
 * @brief check whether customized value-string map is sorted
 *
 * The real data structure of \p vs is not \p osiValueStrMap_t, but it is
 * started with \p osiValueStrMap_t, with customized size.
 *
 * @param vs        value-string map array, must be valid
 * @param count     value-string map count
 * @param size      real data structure size
 * @return
 *      - true if the map is sorted ascending
 *      - false if not sorted
 */
bool osiVsmapIsSortedEx(const osiValueStrMap_t *vs, size_t count, size_t size);

/**
 * @brief find value by string, case insensitive
 *
 * The map is ended by NULL of \a str
 *
 * @param vsmap     integer/string map
 * @param str       string value
 * @return
 *      - a map item if found
 *      - NULL if not found
 */
const osiValueStrMap_t *osiVsmapFindByIStr(const osiValueStrMap_t *vsmap, const char *str);

/**
 * @brief find value by string, case sensitive
 *
 * The map is ended by NULL of \a str
 *
 * @param vsmap     integer/string map
 * @param str       string value
 * @return
 *      - a map item if found
 *      - NULL if not found
 */
const osiValueStrMap_t *osiVsmapFindByStr(const osiValueStrMap_t *vsmap, const char *str);

/**
 * @brief find string by value
 *
 * The map is ended by NULL of \a str
 *
 * @param vsmap     integer/string map
 * @param value     integer value
 * @return
 *      - a map item if found
 *      - NULL if not found
 */
const osiValueStrMap_t *osiVsmapFindByVal(const osiValueStrMap_t *vsmap, uint32_t value);

/**
 * @brief find string by value, with default string
 *
 * The map is ended by NULL of \a str. When \p value is not found, \p defval
 * is returned.
 *
 * @param vsmap     integer/string map
 * @param value     integer value
 * @param defval    default string at not found
 * @return  string value
 */
const char *osiVsmapFindStr(const osiValueStrMap_t *vsmap, uint32_t value, const char *defval);

/**
 * @brief find value by string, with default value
 *
 * The map is ended by NULL of \a str. When \p str is not found, \p defval
 * is returned.
 *
 * @param vsmap     integer/string map
 * @param str       string value
 * @param defval    default integer value at not found
 * @return
 *      - a map item if found
 *      - NULL if not found
 */
uint32_t osiVsmalFindVal(const osiValueStrMap_t *vsmap, const char *str, uint32_t defval);

/**
 * @brief find value by case insensitive string, with default value
 *
 * The map is ended by NULL of \a str. When \p str is not found, \p defval
 * is returned.
 *
 * @param vsmap     integer/string map
 * @param str       string value
 * @param defval    default integer value at not found
 * @return
 *      - a map item if found
 *      - NULL if not found
 */
uint32_t osiVsmalFindIVal(const osiValueStrMap_t *vsmap, const char *str, uint32_t defval);

/**
 * little helper to check wether an unsigned integer in list
 *
 * \param value     value to be checked
 * \param varlist   value list
 * \param count     value list count
 * \return
 *      - true if value in the list
 *      - false if value not in the list
 */
bool osiIsUintInList(uint32_t value, const uint32_t *varlist, unsigned count);

/**
 * little helper to check wether an unsigned integer in range
 *
 * \param value     value to be checked
 * \param minval    minimal value, inclusive
 * \param maxval    maximum value, inclusive
 * \return
 *      - true if value in the range
 *      - false if value not in the range
 */
bool osiIsUintInRange(uint32_t value, uint32_t minval, uint32_t maxval);

/**
 * little helper to check wether an unsigned integer in range list
 *
 * \param value     value to be checked
 * \param ranges    valid range list
 * \param count     valid range list count
 * \return
 *      - true if value in the range list
 *      - false if value not in the range list
 */
bool osiIsUintInRanges(uint32_t value, const osiUintRange_t *ranges, unsigned count);

/**
 * little helper to check wether a signed integer in list
 *
 * \param value     value to be checked
 * \param varlist   value list
 * \param count     value list count
 * \return
 *      - true if value in the list
 *      - false if value not in the list
 */
bool osiIsIntInList(int value, const int *varlist, unsigned count);

/**
 * little helper to check wether a signed integer in range
 *
 * \param value     value to be checked
 * \param minval    minimal value, inclusive
 * \param maxval    maximum value, inclusive
 * \return
 *      - true if value in the range
 *      - false if value not in the range
 */
bool osiIsIntInRange(int value, int minval, int maxval);

/**
 * little helper to check wether a signed integer in range list
 *
 * \param value     value to be checked
 * \param ranges    valid range list
 * \param count     valid range list count
 * \return
 *      - true if value in the range list
 *      - false if value not in the range list
 */
bool osiIsIntInRanges(int value, const osiIntRange_t *ranges, unsigned count);

/**
 * little helper to check wether an unsigned 64bits integer in list
 *
 * \param value     value to be checked
 * \param varlist   value list
 * \param count     value list count
 * \return
 *      - true if value in the list
 *      - false if value not in the list
 */
bool osiIsUint64InList(uint64_t value, const uint64_t *varlist, unsigned count);

/**
 * little helper to check wether an unsigned 64bits integer in range
 *
 * \param value     value to be checked
 * \param minval    minimal value, inclusive
 * \param maxval    maximum value, inclusive
 * \return
 *      - true if value in the range
 *      - false if value not in the range
 */
bool osiIsUint64InRange(uint64_t value, uint64_t minval, uint64_t maxval);

/**
 * little helper to check wether an unsigned 64bits integer in range list
 *
 * \param value     value to be checked
 * \param ranges    valid range list
 * \param count     valid range list count
 * \return
 *      - true if value in the range list
 *      - false if value not in the range list
 */
bool osiIsUint64InRanges(uint64_t value, const osiUint64Range_t *ranges, unsigned count);

/**
 * little helper to check wether a signed 64bits integer in list
 *
 * \param value     value to be checked
 * \param varlist   value list
 * \param count     value list count
 * \return
 *      - true if value in the list
 *      - false if value not in the list
 */
bool osiIsInt64InList(int64_t value, const int64_t *varlist, unsigned count);

/**
 * little helper to check wether a signed 64bits integer in range
 *
 * \param value     value to be checked
 * \param minval    minimal value, inclusive
 * \param maxval    maximum value, inclusive
 * \return
 *      - true if value in the range
 *      - false if value not in the range
 */
bool osiIsInt64InRange(int64_t value, int64_t minval, int64_t maxval);

/**
 * little helper to check wether a signed 64bits integer in range list
 *
 * \param value     value to be checked
 * \param ranges    valid range list
 * \param count     valid range list count
 * \return
 *      - true if value in the range list
 *      - false if value not in the range list
 */
bool osiIsInt64InRanges(int64_t value, const osiInt64Range_t *ranges, unsigned count);

#ifdef __cplusplus
}
#endif
#endif
