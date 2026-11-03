///////////////////////////////////////////////////////////////////////////////
// \author (c) Marco Paland (info@paland.com)
//             2014-2019, PALANDesign Hannover, Germany
//
// \license The MIT License (MIT)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// \brief Tiny printf, sprintf and (v)snprintf implementation, optimized for speed on
//        embedded systems with a very limited resources. These routines are thread
//        safe and reentrant!
//        Use this instead of the bloated standard/newlib printf cause these use
//        malloc for printf (and may not be thread safe).
//
///////////////////////////////////////////////////////////////////////////////

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "printf.h"


// define this globally (e.g. gcc -DPRINTF_INCLUDE_CONFIG_H ...) to include the
// printf_config.h header file
// default: undefined
#ifdef PRINTF_INCLUDE_CONFIG_H
#include "printf_config.h"
#endif


// 'ntoa' conversion buffer size, this must be big enough to hold one converted
// numeric number including padded zeros (dynamically created on stack)
// default: 32 byte
#ifndef PRINTF_NTOA_BUFFER_SIZE
#define PRINTF_NTOA_BUFFER_SIZE    32U
#endif

// 'ftoa' conversion buffer size, this must be big enough to hold one converted
// float number including padded zeros (dynamically created on stack)
// default: 32 byte
#ifndef PRINTF_FTOA_BUFFER_SIZE
#define PRINTF_FTOA_BUFFER_SIZE    32U
#endif

// support for the floating point type (%f)
// default: activated
#ifndef PRINTF_DISABLE_SUPPORT_FLOAT
#define PRINTF_SUPPORT_FLOAT
#endif

// support for exponential floating point notation (%e/%g)
// default: activated
#ifndef PRINTF_DISABLE_SUPPORT_EXPONENTIAL
#define PRINTF_SUPPORT_EXPONENTIAL
#endif

// define the default floating point precision
// default: 6 digits
#ifndef PRINTF_DEFAULT_FLOAT_PRECISION
#define PRINTF_DEFAULT_FLOAT_PRECISION  6U
#endif

// define the largest float suitable to print with %f
// default: 1e9
#ifndef PRINTF_MAX_FLOAT
#define PRINTF_MAX_FLOAT  1e9
#endif

// support for the long long types (%llu or %p)
// default: activated
#ifndef PRINTF_DISABLE_SUPPORT_LONG_LONG
#define PRINTF_SUPPORT_LONG_LONG
#endif

// support for the ptrdiff_t type (%t)
// ptrdiff_t is normally defined in <stddef.h> as long or long long type
// default: activated
#ifndef PRINTF_DISABLE_SUPPORT_PTRDIFF_T
#define PRINTF_SUPPORT_PTRDIFF_T
#endif

// Exact binary64 -> decimal conversion switch (PRINTF_SUPPORT_DTOA) and the
// per-call big-integer context.  Included after the config macros above and
// after any PRINTF_INCLUDE_CONFIG_H header.
#include "printf_dtoa.h"

///////////////////////////////////////////////////////////////////////////////

// internal flag definitions
#define FLAGS_ZEROPAD   (1U <<  0U)
#define FLAGS_LEFT      (1U <<  1U)
#define FLAGS_PLUS      (1U <<  2U)
#define FLAGS_SPACE     (1U <<  3U)
#define FLAGS_HASH      (1U <<  4U)
#define FLAGS_UPPERCASE (1U <<  5U)
#define FLAGS_CHAR      (1U <<  6U)
#define FLAGS_SHORT     (1U <<  7U)
#define FLAGS_LONG      (1U <<  8U)
#define FLAGS_LONG_LONG (1U <<  9U)
#define FLAGS_PRECISION (1U << 10U)
#define FLAGS_ADAPT_EXP (1U << 11U)


// import float.h for DBL_MAX
#if defined(PRINTF_SUPPORT_FLOAT)
#include <float.h>
#endif


// output function type
typedef void (*out_fct_type)(char character, void* buffer, size_t idx, size_t maxlen);


// wrapper (used as buffer) for output function type
typedef struct {
  void  (*fct)(char character, void* arg);
  void* arg;
} out_fct_wrap_type;


// internal buffer output
static inline void _out_buffer(char character, void* buffer, size_t idx, size_t maxlen)
{
  if (idx < maxlen) {
    ((char*)buffer)[idx] = character;
  }
}


// internal null output
static inline void _out_null(char character, void* buffer, size_t idx, size_t maxlen)
{
  (void)character; (void)buffer; (void)idx; (void)maxlen;
}


// internal _putchar wrapper
static inline void _out_char(char character, void* buffer, size_t idx, size_t maxlen)
{
  (void)buffer; (void)idx; (void)maxlen;
  if (character) {
    //_putchar(character);
  }
}


// internal output function wrapper
static inline void _out_fct(char character, void* buffer, size_t idx, size_t maxlen)
{
  (void)idx; (void)maxlen;
  if (character) {
    // buffer is the output fct pointer
    ((out_fct_wrap_type*)buffer)->fct(character, ((out_fct_wrap_type*)buffer)->arg);
  }
}


// internal secure strlen
// \return The length of the string (excluding the terminating 0) limited by 'maxsize'
static inline unsigned int _strnlen_s(const char* str, size_t maxsize)
{
  const char* s;
  for (s = str; *s && maxsize--; ++s);
  return (unsigned int)(s - str);
}


// internal test if char is a digit (0-9)
// \return true if char is a digit
static inline bool _is_digit(char ch)
{
  return (ch >= '0') && (ch <= '9');
}


// internal ASCII string to unsigned int conversion
static unsigned int _atoi(const char** str)
{
  unsigned int i = 0U;
  while (_is_digit(**str)) {
    i = i * 10U + (unsigned int)(*((*str)++) - '0');
  }
  return i;
}


// output the specified string in reverse, taking care of any zero-padding
static size_t _out_rev(out_fct_type out, char* buffer, size_t idx, size_t maxlen, const char* buf, size_t len, unsigned int width, unsigned int flags)
{
  const size_t start_idx = idx;

  // pad spaces up to given width
  if (!(flags & FLAGS_LEFT) && !(flags & FLAGS_ZEROPAD)) {
    for (size_t i = len; i < width; i++) {
      out(' ', buffer, idx++, maxlen);
    }
  }

  // reverse string
  while (len) {
    out(buf[--len], buffer, idx++, maxlen);
  }

  // append pad spaces up to given width
  if (flags & FLAGS_LEFT) {
    while (idx - start_idx < width) {
      out(' ', buffer, idx++, maxlen);
    }
  }

  return idx;
}


#if defined(PRINTF_SUPPORT_DTOA) && defined(PRINTF_SUPPORT_FLOAT)

// Upper bound for the exact path.  Lua's MAX_ITEM is 428, so %.400f of a
// value <= 1e9 (411 chars) is the largest spec that can still fit; beyond
// this the caller falls back to the approximate path.
#define PRINTF_DTOA_MAX_PREC 400U
#define PRINTF_DTOA_NUMBUF   (PRINTF_DTOA_MAX_PREC + 32U)

static char* _dtoa_utoa(char* p, unsigned int v, unsigned int min_digits)
{
  char tmp[12];
  unsigned int n = 0U;

  do {
    tmp[n++] = (char)('0' + (v % 10U));
    v /= 10U;
  } while (v != 0U);
  while (n < min_digits) {
    tmp[n++] = '0';
  }
  while (n) {
    *p++ = tmp[--n];
  }
  return p;
}

// Exact binary64 conversion, shared by %f (mode 0), %e (mode 1) and %g
// (mode 2).  Returns (size_t)-1 when the caller should fall back to the
// approximate path (scratch pool too small, or an oversized precision).
static size_t _dtoa_format(out_fct_type out, char* buffer, size_t idx, size_t maxlen,
                           double value, unsigned int prec, unsigned int width,
                           unsigned int flags, int mode)
{
  char num[PRINTF_DTOA_NUMBUF];
  char* q = num;
  char* digits;
  char* rve;
  char sign_char;
  int sign = 0;
  int decpt = 0;
  int exp10;
  int use_exp;
  int g_mode = (mode == 2);
  unsigned int p;
  size_t ndig, len, i;
  printf_dtoa_ctx ctx;

  // special values
  if (value != value) {
    return _out_rev(out, buffer, idx, maxlen, "nan", 3, width, flags);
  }
  if (value < -DBL_MAX) {
    return _out_rev(out, buffer, idx, maxlen, "fni-", 4, width, flags);
  }
  if (value > DBL_MAX) {
    return _out_rev(out, buffer, idx, maxlen, (flags & FLAGS_PLUS) ? "fni+" : "fni",
                    (flags & FLAGS_PLUS) ? 4U : 3U, width, flags);
  }

  if (!(flags & FLAGS_PRECISION)) {
    prec = PRINTF_DEFAULT_FLOAT_PRECISION;
  }
  if (g_mode && (prec == 0U)) {
    prec = 1U;  // C: a precision of 0 is taken as 1 for %g
  }
  if (prec > PRINTF_DTOA_MAX_PREC) {
    return (size_t)-1;
  }

  printf_dtoa_ctx_init(&ctx);
  if (mode == 0) {
    digits = printf_dtoa(&ctx, value, 3, (int)prec, &decpt, &sign, &rve);
  }
  else if (mode == 1) {
    digits = printf_dtoa(&ctx, value, 2, (int)prec + 1, &decpt, &sign, &rve);
  }
  else {
    digits = printf_dtoa(&ctx, value, 2, (int)prec, &decpt, &sign, &rve);
  }
  if (digits == NULL) {
    return (size_t)-1;
  }
  ndig = (size_t)(rve - digits);

  sign_char = sign ? '-' : ((flags & FLAGS_PLUS) ? '+' : ((flags & FLAGS_SPACE) ? ' ' : '\0'));
  if (sign_char != '\0') {
    *q++ = sign_char;
  }

  if (g_mode) {
    int x = decpt - 1;
    use_exp = (x < -4) || (x >= (int)prec);
    if (use_exp) {
      p = prec - 1U;
    }
    else {
      p = (unsigned int)((int)prec - 1 - x);  // x is in [-4, prec)
    }
  }
  else {
    use_exp = (mode == 1);
    p = prec;
  }

  if (use_exp) {
    exp10 = decpt - 1;
    *q++ = (ndig > 0U) ? digits[0] : '0';
    if ((p > 0U) || (flags & FLAGS_HASH)) {
      *q++ = '.';
      for (i = 0U; i < p; i++) {
        *q++ = ((1U + i) < ndig) ? digits[1U + i] : '0';
      }
    }
    *q++ = (flags & FLAGS_UPPERCASE) ? 'E' : 'e';
    if (exp10 < 0) {
      *q++ = '-';
      exp10 = -exp10;
    }
    else {
      *q++ = '+';
    }
    q = _dtoa_utoa(q, (unsigned int)exp10, 2U);
  }
  else {
    if (decpt > 0) {
      for (i = 0U; i < (size_t)decpt; i++) {
        *q++ = (i < ndig) ? digits[i] : '0';
      }
    }
    else {
      *q++ = '0';
    }
    if ((p > 0U) || (flags & FLAGS_HASH)) {
      *q++ = '.';
      for (i = 0U; i < p; i++) {
        int pos = decpt + (int)i;
        *q++ = ((pos >= 0) && ((size_t)pos < ndig)) ? digits[pos] : '0';
      }
    }
  }

  len = (size_t)(q - num);

  if (g_mode && !(flags & FLAGS_HASH)) {
    // %g strips trailing zeros in the fractional part; never touch the
    // exponent digits that follow it
    char* dot = (char*)memchr(num, '.', len);
    if (dot != NULL) {
      char* exp_ptr = (char*)memchr(num, 'e', len);
      if (exp_ptr == NULL) {
        exp_ptr = (char*)memchr(num, 'E', len);
      }
      size_t frac_end = (exp_ptr != NULL) ? (size_t)(exp_ptr - num) : len;
      size_t keep = frac_end;
      while ((keep > (size_t)(dot - num) + 1U) && (num[keep - 1U] == '0')) {
        keep--;
      }
      if ((keep > 0U) && (num[keep - 1U] == '.')) {
        keep--;
      }
      if (exp_ptr != NULL) {
        memmove(num + keep, exp_ptr, len - frac_end);
        len = keep + (len - frac_end);
      }
      else {
        len = keep;
      }
    }
  }

  {
    unsigned int pad = (width > len) ? (width - (unsigned int)len) : 0U;

    if (flags & FLAGS_LEFT) {
      for (i = 0U; i < len; i++) {
        out(num[i], buffer, idx++, maxlen);
      }
      while (pad > 0U) {
        pad--;
        out(' ', buffer, idx++, maxlen);
      }
    }
    else if (flags & FLAGS_ZEROPAD) {
      size_t s = (sign_char != '\0') ? 1U : 0U;
      for (i = 0U; i < s; i++) {
        out(num[i], buffer, idx++, maxlen);
      }
      while (pad > 0U) {
        pad--;
        out('0', buffer, idx++, maxlen);
      }
      for (i = s; i < len; i++) {
        out(num[i], buffer, idx++, maxlen);
      }
    }
    else {
      while (pad > 0U) {
        pad--;
        out(' ', buffer, idx++, maxlen);
      }
      for (i = 0U; i < len; i++) {
        out(num[i], buffer, idx++, maxlen);
      }
    }
  }

  return idx;
}

#endif  // PRINTF_SUPPORT_DTOA && PRINTF_SUPPORT_FLOAT


// internal itoa format
static size_t _ntoa_format(out_fct_type out, char* buffer, size_t idx, size_t maxlen, char* buf, size_t len, bool negative, unsigned int base, unsigned int prec, unsigned int width, unsigned int flags)
{
  // pad leading zeros
  if (!(flags & FLAGS_LEFT)) {
    if (width && (flags & FLAGS_ZEROPAD) && (negative || (flags & (FLAGS_PLUS | FLAGS_SPACE)))) {
      width--;
    }
    while ((len < prec) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = '0';
    }
    while ((flags & FLAGS_ZEROPAD) && (len < width) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = '0';
    }
  }

  // handle hash
  if (flags & FLAGS_HASH) {
    if (!(flags & FLAGS_PRECISION) && len && ((len == prec) || (len == width))) {
      len--;
      if (len && (base == 16U)) {
        len--;
      }
    }
    if ((base == 16U) && !(flags & FLAGS_UPPERCASE) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = 'x';
    }
    else if ((base == 16U) && (flags & FLAGS_UPPERCASE) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = 'X';
    }
    else if ((base == 2U) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = 'b';
    }
    if (len < PRINTF_NTOA_BUFFER_SIZE) {
      buf[len++] = '0';
    }
  }

  if (len < PRINTF_NTOA_BUFFER_SIZE) {
    if (negative) {
      buf[len++] = '-';
    }
    else if (flags & FLAGS_PLUS) {
      buf[len++] = '+';  // ignore the space if the '+' exists
    }
    else if (flags & FLAGS_SPACE) {
      buf[len++] = ' ';
    }
  }

  return _out_rev(out, buffer, idx, maxlen, buf, len, width, flags);
}


// internal itoa for 'long' type
static size_t _ntoa_long(out_fct_type out, char* buffer, size_t idx, size_t maxlen, unsigned long value, bool negative, unsigned long base, unsigned int prec, unsigned int width, unsigned int flags)
{
  char buf[PRINTF_NTOA_BUFFER_SIZE];
  size_t len = 0U;

  // no hash for 0 values
  if (!value) {
    flags &= ~FLAGS_HASH;
  }

  // write if precision != 0 and value is != 0
  if (!(flags & FLAGS_PRECISION) || value) {
    do {
      const char digit = (char)(value % base);
      buf[len++] = digit < 10 ? '0' + digit : (flags & FLAGS_UPPERCASE ? 'A' : 'a') + digit - 10;
      value /= base;
    } while (value && (len < PRINTF_NTOA_BUFFER_SIZE));
  }

  return _ntoa_format(out, buffer, idx, maxlen, buf, len, negative, (unsigned int)base, prec, width, flags);
}


// internal itoa for 'long long' type
#if defined(PRINTF_SUPPORT_LONG_LONG)
static size_t _ntoa_long_long(out_fct_type out, char* buffer, size_t idx, size_t maxlen, unsigned long long value, bool negative, unsigned long long base, unsigned int prec, unsigned int width, unsigned int flags)
{
  char buf[PRINTF_NTOA_BUFFER_SIZE];
  size_t len = 0U;

  // no hash for 0 values
  if (!value) {
    flags &= ~FLAGS_HASH;
  }

  // write if precision != 0 and value is != 0
  if (!(flags & FLAGS_PRECISION) || value) {
    do {
      const char digit = (char)(value % base);
      buf[len++] = digit < 10 ? '0' + digit : (flags & FLAGS_UPPERCASE ? 'A' : 'a') + digit - 10;
      value /= base;
    } while (value && (len < PRINTF_NTOA_BUFFER_SIZE));
  }

  return _ntoa_format(out, buffer, idx, maxlen, buf, len, negative, (unsigned int)base, prec, width, flags);
}
#endif  // PRINTF_SUPPORT_LONG_LONG


#if defined(PRINTF_SUPPORT_FLOAT)

#if defined(PRINTF_SUPPORT_EXPONENTIAL)
// forward declaration so that _ftoa can switch to exp notation for values > PRINTF_MAX_FLOAT
static size_t _etoa(out_fct_type out, char* buffer, size_t idx, size_t maxlen, double value, unsigned int prec, unsigned int width, unsigned int flags);
#endif


// internal ftoa for fixed decimal floating point
static size_t _ftoa(out_fct_type out, char* buffer, size_t idx, size_t maxlen, double value, unsigned int prec, unsigned int width, unsigned int flags)
{
  char buf[PRINTF_FTOA_BUFFER_SIZE];
  size_t len  = 0U;
  double diff = 0.0;

  // powers of 10
  static const double pow10[] = { 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000 };

#if defined(PRINTF_SUPPORT_DTOA)
  // exact conversion for %f (large values fall through to _etoa below)
  if ((value <= PRINTF_MAX_FLOAT) && (value >= -PRINTF_MAX_FLOAT)) {
    const size_t exact = _dtoa_format(out, buffer, idx, maxlen, value, prec, width, flags, 0);
    if (exact != (size_t)-1) {
      return exact;
    }
  }
#endif

  // test for special values
  if (value != value)
    return _out_rev(out, buffer, idx, maxlen, "nan", 3, width, flags);
  if (value < -DBL_MAX)
    return _out_rev(out, buffer, idx, maxlen, "fni-", 4, width, flags);
  if (value > DBL_MAX)
    return _out_rev(out, buffer, idx, maxlen, (flags & FLAGS_PLUS) ? "fni+" : "fni", (flags & FLAGS_PLUS) ? 4U : 3U, width, flags);

  // test for very large values
  // standard printf behavior is to print EVERY whole number digit -- which could be 100s of characters overflowing your buffers == bad
  if ((value > PRINTF_MAX_FLOAT) || (value < -PRINTF_MAX_FLOAT)) {
#if defined(PRINTF_SUPPORT_EXPONENTIAL)
    return _etoa(out, buffer, idx, maxlen, value, prec, width, flags);
#else
    return 0U;
#endif
  }

  // test for negative
  bool negative = false;
  if (value < 0) {
    negative = true;
    value = 0 - value;
  }

  // set default precision, if not set explicitly
  if (!(flags & FLAGS_PRECISION)) {
    prec = PRINTF_DEFAULT_FLOAT_PRECISION;
  }
  // limit precision to 9, cause a prec >= 10 can lead to overflow errors
  while ((len < PRINTF_FTOA_BUFFER_SIZE) && (prec > 9U)) {
    buf[len++] = '0';
    prec--;
  }

  int whole = (int)value;
  double tmp = (value - whole) * pow10[prec];
  unsigned long frac = (unsigned long)tmp;
  diff = tmp - frac;

  if (diff > 0.5) {
    ++frac;
    // handle rollover, e.g. case 0.99 with prec 1 is 1.0
    if (frac >= pow10[prec]) {
      frac = 0;
      ++whole;
    }
  }
  else if (diff < 0.5) {
  }
  else if ((frac == 0U) || (frac & 1U)) {
    // if halfway, round up if odd OR if last digit is 0
    ++frac;
  }

  if (prec == 0U) {
    diff = value - (double)whole;
    if ((!(diff < 0.5) || (diff > 0.5)) && (whole & 1)) {
      // exactly 0.5 and ODD, then round up
      // 1.5 -> 2, but 2.5 -> 2
      ++whole;
    }
  }
  else {
    unsigned int count = prec;
    // now do fractional part, as an unsigned number
    while (len < PRINTF_FTOA_BUFFER_SIZE) {
      --count;
      buf[len++] = (char)(48U + (frac % 10U));
      if (!(frac /= 10U)) {
        break;
      }
    }
    // add extra 0s
    while ((len < PRINTF_FTOA_BUFFER_SIZE) && (count-- > 0U)) {
      buf[len++] = '0';
    }
    if (len < PRINTF_FTOA_BUFFER_SIZE) {
      // add decimal
      buf[len++] = '.';
    }
  }

  // do whole part, number is reversed
  while (len < PRINTF_FTOA_BUFFER_SIZE) {
    buf[len++] = (char)(48 + (whole % 10));
    if (!(whole /= 10)) {
      break;
    }
  }

  // pad leading zeros
  if (!(flags & FLAGS_LEFT) && (flags & FLAGS_ZEROPAD)) {
    if (width && (negative || (flags & (FLAGS_PLUS | FLAGS_SPACE)))) {
      width--;
    }
    while ((len < width) && (len < PRINTF_FTOA_BUFFER_SIZE)) {
      buf[len++] = '0';
    }
  }

  if (len < PRINTF_FTOA_BUFFER_SIZE) {
    if (negative) {
      buf[len++] = '-';
    }
    else if (flags & FLAGS_PLUS) {
      buf[len++] = '+';  // ignore the space if the '+' exists
    }
    else if (flags & FLAGS_SPACE) {
      buf[len++] = ' ';
    }
  }

  return _out_rev(out, buffer, idx, maxlen, buf, len, width, flags);
}


#if defined(PRINTF_SUPPORT_EXPONENTIAL)
// internal ftoa variant for exponential floating-point type, contributed by Martijn Jasperse <m.jasperse@gmail.com>
static size_t _etoa(out_fct_type out, char* buffer, size_t idx, size_t maxlen, double value, unsigned int prec, unsigned int width, unsigned int flags)
{
#if defined(PRINTF_SUPPORT_DTOA)
  // exact conversion for %e and %g
  {
    const size_t exact = _dtoa_format(out, buffer, idx, maxlen, value, prec, width, flags,
                                      (flags & FLAGS_ADAPT_EXP) ? 2 : 1);
    if (exact != (size_t)-1) {
      return exact;
    }
  }
#endif

  // check for NaN and special values
  if ((value != value) || (value > DBL_MAX) || (value < -DBL_MAX)) {
    return _ftoa(out, buffer, idx, maxlen, value, prec, width, flags);
  }

  // determine the sign
  const bool negative = value < 0;
  if (negative) {
    value = -value;
  }

  // default precision
  if (!(flags & FLAGS_PRECISION)) {
    prec = PRINTF_DEFAULT_FLOAT_PRECISION;
  }

  // C99 %g prints zero without an exponent and without trailing zeros
  if ((flags & FLAGS_ADAPT_EXP) && (value == 0.0)) {
    return _ftoa(out, buffer, idx, maxlen, value, 0, width,
                 (flags | FLAGS_PRECISION) & ~FLAGS_ADAPT_EXP);
  }

  // determine the decimal exponent
  // based on the algorithm by David Gay (https://www.ampl.com/netlib/fp/dtoa.c)
  union {
    uint64_t U;
    double   F;
  } conv;

  int expval;
  conv.F = value;
  if (value == 0.0) {
    // keep _ftoa's zero mantissa; the exponent stays e+00
    expval = 0;
    conv.F = 1.0;
  }
  else {
    uint32_t biased_exp = (uint32_t)((conv.U >> 52U) & 0x07FFU);
    int decimal_shift = 0;
    int exp2;
    int guard;

    if (biased_exp == 0U) {
      // subnormal: scale by 1e17, which is exactly representable, so the value
      // becomes normal and the decimal exponent only shifts by 17
      value *= 1e17;
      conv.F = value;
      decimal_shift = 17;
    }
    exp2 = (int)((conv.U >> 52U) & 0x07FFU) - 1023;  // effectively log2
    conv.U = (conv.U & ((1ULL << 52U) - 1U)) | (1023ULL << 52U);  // drop the exponent so conv.F is now in [1,2)
    // now approximate log10 from the log2 integer part and an expansion of ln around 1.5
    expval = (int)(0.1760912590558 + exp2 * 0.301029995663981 + (conv.F - 1.5) * 0.289529654602168);
    // compute 10^expval by squaring; relative error ~1e-15 and no table needed,
    // accurate enough for the normalisation below to be reliable
    {
      double p = 1.0;
      double base = (expval < 0) ? 0.1 : 10.0;
      unsigned int n = (expval < 0) ? (unsigned int)(0 - expval) : (unsigned int)expval;
      while (n) {
        if (n & 1U) {
          p *= base;
        }
        base *= base;
        n >>= 1;
      }
      conv.F = p;
    }
    // normalise so that value/conv.F lands in [1, 10); this also fixes the
    // off-by-one cases such as 1e300 printing as 10.000000e+299
    for (guard = 0; (guard < 400) && (conv.F > 0.0); ++guard) {
      const double ratio = value / conv.F;
      if (ratio >= 10.0) {
        conv.F *= 10.0;
        expval++;
      }
      else if (ratio < 1.0) {
        conv.F /= 10.0;
        expval--;
      }
      else {
        break;
      }
    }
    expval -= decimal_shift;
  }

  // the exponent format is "%+03d" and largest value is "307", so set aside 4-5 characters
  unsigned int minwidth = ((expval < 100) && (expval > -100)) ? 4U : 5U;

  // in "%g" mode, "prec" is the number of *significant figures* not decimals
  if (flags & FLAGS_ADAPT_EXP) {
    // do we want to fall-back to "%f" mode?
    if ((value >= 1e-4) && (value < 1e6)) {
      if ((int)prec > expval) {
        prec = (unsigned)((int)prec - expval - 1);
      }
      else {
        prec = 0;
      }
      flags |= FLAGS_PRECISION;   // make sure _ftoa respects precision
      // no characters in exponent
      minwidth = 0U;
      expval   = 0;
    }
    else {
      // we use one sigfig for the whole part
      if ((prec > 0) && (flags & FLAGS_PRECISION)) {
        --prec;
      }
    }
  }

  // if the mantissa rounds up to 10 at the requested precision, carry into the
  // exponent (e.g. 1e300 must print as 1.000000e+300, not 10.000000e+299)
  if (minwidth) {
    unsigned int digits = (prec > 9U) ? 9U : prec;  // _ftoa caps at 9 decimals
    double half = 0.5;
    while (digits--) {
      half /= 10.0;
    }
    if ((value / conv.F) >= (10.0 - half)) {
      conv.F *= 10.0;
      expval++;
      minwidth = ((expval < 100) && (expval > -100)) ? 4U : 5U;
    }
  }

  // will everything fit?
  unsigned int fwidth = width;
  if (width > minwidth) {
    // we didn't fall-back so subtract the characters required for the exponent
    fwidth -= minwidth;
  } else {
    // not enough characters, so go back to default sizing
    fwidth = 0U;
  }
  if ((flags & FLAGS_LEFT) && minwidth) {
    // if we're padding on the right, DON'T pad the floating part
    fwidth = 0U;
  }

  // rescale the float value
  if (expval) {
    value /= conv.F;
  }

  // output the floating part
  const size_t start_idx = idx;
  idx = _ftoa(out, buffer, idx, maxlen, negative ? -value : value, prec, fwidth, flags & ~FLAGS_ADAPT_EXP);

  // output the exponent part
  if (minwidth) {
    // output the exponential symbol
    out((flags & FLAGS_UPPERCASE) ? 'E' : 'e', buffer, idx++, maxlen);
    // output the exponent value
    idx = _ntoa_long(out, buffer, idx, maxlen, (expval < 0) ? -expval : expval, expval < 0, 10, 0, minwidth-1, FLAGS_ZEROPAD | FLAGS_PLUS);
    // might need to right-pad spaces
    if (flags & FLAGS_LEFT) {
      while (idx - start_idx < width) out(' ', buffer, idx++, maxlen);
    }
  }
  return idx;
}
#endif  // PRINTF_SUPPORT_EXPONENTIAL
#endif  // PRINTF_SUPPORT_FLOAT


// internal vsnprintf
static int _vsnprintf(out_fct_type out, char* buffer, const size_t maxlen, const char* format, va_list va)
{
  unsigned int flags, width, precision, n;
  size_t idx = 0U;
#if defined(__PRINT_ALIGNED_32BIT__) && !defined(__BK72XX__)
  volatile uint32_t *ap_addr;
  volatile uint32_t ap_value;
  uint32_t d1,d2;
  uint64_t value;
  double f64;
#endif
  if (!buffer) {
    // use null output function
    out = _out_null;
  }

  while (*format)
  {
    // format specifier?  %[flags][width][.precision][length]
    if (*format != '%') {
      // no
      out(*format, buffer, idx++, maxlen);
      format++;
      continue;
    }
    else {
      // yes, evaluate it
      format++;
    }

    // evaluate flags
    flags = 0U;
    do {
      switch (*format) {
        case '0': flags |= FLAGS_ZEROPAD; format++; n = 1U; break;
        case '-': flags |= FLAGS_LEFT;    format++; n = 1U; break;
        case '+': flags |= FLAGS_PLUS;    format++; n = 1U; break;
        case ' ': flags |= FLAGS_SPACE;   format++; n = 1U; break;
        case '#': flags |= FLAGS_HASH;    format++; n = 1U; break;
        default :                                   n = 0U; break;
      }
    } while (n);

    // evaluate width field
    width = 0U;
    if (_is_digit(*format)) {
      width = _atoi(&format);
    }
    else if (*format == '*') {
      const int w = va_arg(va, int);
      if (w < 0) {
        flags |= FLAGS_LEFT;    // reverse padding
        width = (unsigned int)-w;
      }
      else {
        width = (unsigned int)w;
      }
      format++;
    }

    // evaluate precision field
    precision = 0U;
    if (*format == '.') {
      flags |= FLAGS_PRECISION;
      format++;
      if (_is_digit(*format)) {
        precision = _atoi(&format);
      }
      else if (*format == '*') {
        const int prec = (int)va_arg(va, int);
        precision = prec > 0 ? (unsigned int)prec : 0U;
        format++;
      }
    }

    // evaluate length field
    switch (*format) {
      case 'l' :
        flags |= FLAGS_LONG;
        format++;
        if (*format == 'l') {
          flags |= FLAGS_LONG_LONG;
          format++;
        }
        break;
      case 'h' :
        flags |= FLAGS_SHORT;
        format++;
        if (*format == 'h') {
          flags |= FLAGS_CHAR;
          format++;
        }
        break;
#if defined(PRINTF_SUPPORT_PTRDIFF_T)
      case 't' :
        flags |= (sizeof(ptrdiff_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        format++;
        break;
#endif
      case 'j' :
        flags |= (sizeof(intmax_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        format++;
        break;
      case 'z' :
        flags |= (sizeof(size_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        format++;
        break;
      default :
        break;
    }

    // evaluate specifier
    switch (*format) {
      case 'd' :
      case 'i' :
      case 'u' :
      case 'x' :
      case 'X' :
      case 'o' :
      case 'b' : {
        // set the base
        unsigned int base;
        if (*format == 'x' || *format == 'X') {
          base = 16U;
        }
        else if (*format == 'o') {
          base =  8U;
        }
        else if (*format == 'b') {
          base =  2U;
        }
        else {
          base = 10U;
          flags &= ~FLAGS_HASH;   // no hash for dec format
        }
        // uppercase
        if (*format == 'X') {
          flags |= FLAGS_UPPERCASE;
        }

        // no plus or space flag for u, x, X, o, b
        if ((*format != 'i') && (*format != 'd')) {
          flags &= ~(FLAGS_PLUS | FLAGS_SPACE);
        }

        // ignore '0' flag when precision is given
        if (flags & FLAGS_PRECISION) {
          flags &= ~FLAGS_ZEROPAD;
        }

        // convert the integer
        if ((*format == 'i') || (*format == 'd')) {
          // signed
          if (flags & FLAGS_LONG_LONG) {
#if defined(PRINTF_SUPPORT_LONG_LONG)

#if defined(__PRINT_ALIGNED_32BIT__) && !defined(__BK72XX__)
            ap_addr = (uint32_t *)&va;
            ap_value = (*ap_addr);
            if (!(ap_value & 0x07))
            {
              d1 = va_arg(va, uint32_t);
            }
            d1 = va_arg(va, uint32_t);
            d2 = va_arg(va, uint32_t);
            long long value2 = d2;
            value2 = (value2 << 32) | d1;
#else
            const long long value2 = va_arg(va, long long);
#endif
            idx = _ntoa_long_long(out, buffer, idx, maxlen, (unsigned long long)(value2 > 0 ? value2 : 0 - value2), value2 < 0, base, precision, width, flags);
#endif
          }
          else if (flags & FLAGS_LONG) {
            const long value = va_arg(va, long);
            idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned long)(value > 0 ? value : 0 - value), value < 0, base, precision, width, flags);
          }
          else {
            const int value = (flags & FLAGS_CHAR) ? (char)va_arg(va, int) : (flags & FLAGS_SHORT) ? (short int)va_arg(va, int) : va_arg(va, int);
            idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned int)(value > 0 ? value : 0 - value), value < 0, base, precision, width, flags);
          }
        }
        else {
          // unsigned
          if (flags & FLAGS_LONG_LONG) {
#if defined(PRINTF_SUPPORT_LONG_LONG)
#if defined(__PRINT_ALIGNED_32BIT__) && !defined(__BK72XX__)
            ap_addr = (uint32_t *)&va;
            ap_value = (*ap_addr);
            if (!(ap_value & 0x07))
            {
              d1 = va_arg(va, uint32_t);
            }
            d1 = va_arg(va, uint32_t);
            d2 = va_arg(va, uint32_t);
            value = d2;
            value = (value << 32) | d1;
            idx = _ntoa_long_long(out, buffer, idx, maxlen, value, false, base, precision, width, flags);
#else
            idx = _ntoa_long_long(out, buffer, idx, maxlen, va_arg(va, unsigned long long), false, base, precision, width, flags);
#endif
#endif
          }
          else if (flags & FLAGS_LONG) {
            idx = _ntoa_long(out, buffer, idx, maxlen, va_arg(va, unsigned long), false, base, precision, width, flags);
          }
          else {
            const unsigned int value = (flags & FLAGS_CHAR) ? (unsigned char)va_arg(va, unsigned int) : (flags & FLAGS_SHORT) ? (unsigned short int)va_arg(va, unsigned int) : va_arg(va, unsigned int);
            idx = _ntoa_long(out, buffer, idx, maxlen, value, false, base, precision, width, flags);
          }
        }
        format++;
        break;
      }
#if defined(PRINTF_SUPPORT_FLOAT)
      case 'f' :
      case 'F' :
        if (*format == 'F') flags |= FLAGS_UPPERCASE;
#if defined(__PRINT_ALIGNED_32BIT__) && !defined(__BK72XX__)
        ap_addr = (uint32_t *)&va;
        ap_value = (*ap_addr);
        if (!(ap_value & 0x07))
        {
          d1 = va_arg(va, uint32_t);
        }
        d1 = va_arg(va, uint32_t);
        d2 = va_arg(va, uint32_t);
        value = d2;
        value = (value << 32) | d1;
        memcpy(&f64, &value, 8);
        idx = _ftoa(out, buffer, idx, maxlen, f64, precision, width, flags);
#else
        idx = _ftoa(out, buffer, idx, maxlen, va_arg(va, double), precision, width, flags);
#endif
        format++;
        break;
#if defined(PRINTF_SUPPORT_EXPONENTIAL)
      case 'e':
      case 'E':
      case 'g':
      case 'G':
        if ((*format == 'g')||(*format == 'G')) flags |= FLAGS_ADAPT_EXP;
        if ((*format == 'E')||(*format == 'G')) flags |= FLAGS_UPPERCASE;
#if defined(__PRINT_ALIGNED_32BIT__) && !defined(__BK72XX__)
        ap_addr = (uint32_t *)&va;
        ap_value = (*ap_addr);
        if (!(ap_value & 0x07))
        {
          d1 = va_arg(va, uint32_t);
        }
        d1 = va_arg(va, uint32_t);
        d2 = va_arg(va, uint32_t);
        value = d2;
        value = (value << 32) | d1;
        memcpy(&f64, &value, 8);
        idx = _etoa(out, buffer, idx, maxlen, f64, precision, width, flags);
#else
        idx = _etoa(out, buffer, idx, maxlen, va_arg(va, double), precision, width, flags);
#endif
        format++;
        break;
#endif  // PRINTF_SUPPORT_EXPONENTIAL
#endif  // PRINTF_SUPPORT_FLOAT
      case 'c' : {
        unsigned int l = 1U;
        // pre padding
        if (!(flags & FLAGS_LEFT)) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        // char output
        out((char)va_arg(va, int), buffer, idx++, maxlen);
        // post padding
        if (flags & FLAGS_LEFT) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        format++;
        break;
      }

      case 's' : {
        const char* p = va_arg(va, char*);
        unsigned int l = _strnlen_s(p, precision ? precision : (size_t)-1);
        // pre padding
        if (flags & FLAGS_PRECISION) {
          l = (l < precision ? l : precision);
        }
        if (!(flags & FLAGS_LEFT)) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        // string output
        while ((*p != 0) && (!(flags & FLAGS_PRECISION) || precision--)) {
          out(*(p++), buffer, idx++, maxlen);
        }
        // post padding
        if (flags & FLAGS_LEFT) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        format++;
        break;
      }

      case 'p' : {
        width = sizeof(void*) * 2U;
        flags |= FLAGS_ZEROPAD | FLAGS_UPPERCASE;
#if defined(PRINTF_SUPPORT_LONG_LONG)
        const bool is_ll = sizeof(uintptr_t) == sizeof(long long);
        if (is_ll) {
          idx = _ntoa_long_long(out, buffer, idx, maxlen, (uintptr_t)va_arg(va, void*), false, 16U, precision, width, flags);
        }
        else {
#endif
          idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned long)((uintptr_t)va_arg(va, void*)), false, 16U, precision, width, flags);
#if defined(PRINTF_SUPPORT_LONG_LONG)
        }
#endif
        format++;
        break;
      }

      case '%' :
        out('%', buffer, idx++, maxlen);
        format++;
        break;

      default :
        out(*format, buffer, idx++, maxlen);
        format++;
        break;
    }
  }

  // termination
  out((char)0, buffer, idx < maxlen ? idx : maxlen - 1U, maxlen);

  // return written chars without terminating \0
  return (int)idx;
}


///////////////////////////////////////////////////////////////////////////////

int printf_(const char* format, ...)
{
  va_list va;
  va_start(va, format);
  char buffer[1];
  const int ret = _vsnprintf(_out_char, buffer, (size_t)-1, format, va);
  va_end(va);
  return ret;
}


int sprintf_(char* buffer, const char* format, ...)
{
  va_list va;
  va_start(va, format);
  const int ret = _vsnprintf(_out_buffer, buffer, (size_t)-1, format, va);
  va_end(va);
  return ret;
}


int snprintf_(char* buffer, size_t count, const char* format, ...)
{
  va_list va;
  va_start(va, format);
  const int ret = _vsnprintf(_out_buffer, buffer, count, format, va);
  va_end(va);
  return ret;
}


int vprintf_(const char* format, va_list va)
{
  char buffer[1];
  return _vsnprintf(_out_char, buffer, (size_t)-1, format, va);
}


int vsnprintf_(char* buffer, size_t count, const char* format, va_list va)
{
  return _vsnprintf(_out_buffer, buffer, count, format, va);
}


int fctprintf(void (*out)(char character, void* arg), void* arg, const char* format, ...)
{
  va_list va;
  va_start(va, format);
  const out_fct_wrap_type out_fct_wrap = { out, arg };
  const int ret = _vsnprintf(_out_fct, (char*)(uintptr_t)&out_fct_wrap, (size_t)-1, format, va);
  va_end(va);
  return ret;
}
