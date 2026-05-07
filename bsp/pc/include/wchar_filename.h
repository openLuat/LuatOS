/*
 * PC simulator stub for libavutil/wchar_filename.h
 * Provides a minimal utf8towchar() that signals "no conversion" so
 * file_open.c falls through to the plain _sopen() ASCII fallback path.
 * Sufficient for the PC simulator where filenames are typically ASCII.
 */
#ifndef WCHAR_FILENAME_H
#define WCHAR_FILENAME_H

static inline int utf8towchar(const char *filename_utf8, wchar_t **filename_w)
{
    *filename_w = NULL; /* triggers fallback to _sopen() in file_open.c */
    return 0;
}

#endif /* WCHAR_FILENAME_H */
