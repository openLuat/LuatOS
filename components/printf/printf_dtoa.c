/* Exact binary64 -> decimal conversion for 64-bit VM builds.  The build
 * switch lives in printf_dtoa.h (PRINTF_SUPPORT_DTOA). */
#include "printf_dtoa.h"

#if defined(PRINTF_SUPPORT_DTOA) && !defined(PRINTF_DISABLE_SUPPORT_FLOAT)

/*
 * Exact binary64 -> decimal conversion for components/printf.
 *
 * Adapted from newlib's mprec.c / dtoa.c.  Both files carry this notice:
 *
 *   The author of this software is David M. Gay.
 *
 *   Copyright (c) 1991 by AT&T.
 *
 *   Permission to use, copy, modify, and distribute this software for any
 *   purpose without fee is hereby granted, provided that this entire notice
 *   is included in all copies of any software which is or includes a copy
 *   or modification of this software and in all copies of the supporting
 *   documentation for such software.
 *
 *   THIS SOFTWARE IS BEING PROVIDED "AS IS", WITHOUT ANY EXPRESS OR IMPLIED
 *   WARRANTY.  IN PARTICULAR, NEITHER THE AUTHOR NOR AT&T MAKES ANY
 *   REPRESENTATION OR WARRANTY OF ANY KIND CONCERNING THE MERCHANTABILITY
 *   OF THIS SOFTWARE OR ITS FITNESS FOR ANY PARTICULAR PURPOSE.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <float.h>
#include <errno.h>

typedef struct dtoa_bigint dtoa_bigint;
#define _Bigint dtoa_bigint

typedef uint32_t dtoa_ulong;
typedef int32_t  dtoa_long;
typedef int32_t  dtoa_int;
/* newlib's headers already define these names; keep our own types */
#undef __ULong
#undef __Long
#undef Long
#undef _Kmax
#define __ULong dtoa_ulong
#define __Long  dtoa_long
#define Long    dtoa_int

/* The copied code says "struct _reent"; point it at our per-call context. */
#define _reent printf_dtoa_ctx

#define IEEE_Arith
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#define IEEE_MC68k
#else
#define IEEE_8087
#endif

union double_union {
    double d;
    __ULong i[2];
};

#ifdef IEEE_8087
#define word0(x) (x.i[1])
#define word1(x) (x.i[0])
#else
#define word0(x) (x.i[0])
#define word1(x) (x.i[1])
#endif

#define Exp_shift   20
#define Exp_shift1  20
#define Exp_msk1    ((__ULong)0x100000L)
#define Exp_msk11   ((__ULong)0x100000L)
#define Exp_mask    ((__ULong)0x7ff00000L)
#define P           53
#define Bias        1023
#define Emin        (-1022)
#define Exp_1       ((__ULong)0x3ff00000L)
#define Exp_11      ((__ULong)0x3ff00000L)
#define Ebits       11
#define Frac_mask   ((__ULong)0xfffffL)
#define Frac_mask1  ((__ULong)0xfffffL)
#define Ten_pmax    22
#define Bletch      0x10
#define Bndry_mask  ((__ULong)0xfffffL)
#define Bndry_mask1 ((__ULong)0xfffffL)
#define LSB         1
#define Sign_bit    ((__ULong)0x80000000L)
#define Log2P       1
#define Tiny0       0
#define Tiny1       1
/* The fast floating-point estimate in dtoa assumes strict binary64
 * arithmetic.  On x87 (i386 without SSE) doubles are evaluated in 80-bit
 * registers and that estimate can produce digits > 9 (e.g. 1e300 formatting
 * as ":000000e+299").  Disable it where the compiler reports excess
 * precision; the integer path is exact everywhere. */
#if (defined(__FLT_EVAL_METHOD__) && (__FLT_EVAL_METHOD__ != 0)) || \
    (defined(_M_IX86) && !defined(_M_IX86_FP))
#define DTOA_NO_QUICK 1
#define Quick_max   0
#else
#define Quick_max   14
#endif
#define Int_max     14
#define Infinite(x) (word0(x) == ((__ULong)0x7ff00000L))

#define Pack_32
#define ULbits 32
#define kshift 5
#define kmask 31
#define ALL_ON 0xffffffff

#define Big0 (Frac_mask1 | Exp_msk1*(DBL_MAX_EXP+Bias-1))
#define Big1 ((__ULong)0xffffffffL)

#define n_bigtens 5

#ifndef RND_PRODQUOT
#define rounded_product(a,b) a *= b
#define rounded_quotient(a,b) a /= b
#endif

#define Storeinc(a,b,c) (*(a)++ = ((b) << 16) | ((c) & 0xffff))
#define Sign_Extend(a,b) /*no-op*/

#define Bcopy(x,y) memcpy((char *)&x->_sign, (char *)&y->_sign, \
                          y->_wds*sizeof(__Long) + 2*sizeof(int))

/* Rename the big-integer helpers so they cannot collide with libc. */
#define Balloc     dtoa_Balloc
#define Bfree      dtoa_Bfree
#define multadd    dtoa_multadd
#define hi0bits    dtoa_hi0bits
#define lo0bits    dtoa_lo0bits
#define i2b        dtoa_i2b
#define mult       dtoa_mult
#define pow5mult   dtoa_pow5mult
#define lshift     dtoa_lshift
#define cmp        dtoa_cmp
#define diff       dtoa_diff
#define d2b        dtoa_d2b
#define tens       dtoa_tens
#define bigtens    dtoa_bigtens
#define tinytens   dtoa_tinytens
#define _dtoa_r    dtoa_internal

_Bigint *Balloc(struct _reent *ptr, int k);
void     Bfree(struct _reent *ptr, _Bigint *v);
_Bigint *multadd(struct _reent *ptr, _Bigint *b, int m, int a);
int      hi0bits(__ULong x);
int      lo0bits(__ULong *y);
_Bigint *i2b(struct _reent *ptr, int i);
_Bigint *mult(struct _reent *ptr, _Bigint *a, _Bigint *b);
_Bigint *pow5mult(struct _reent *ptr, _Bigint *b, int k);
_Bigint *lshift(struct _reent *ptr, _Bigint *b, int k);
int      cmp(_Bigint *a, _Bigint *b);
_Bigint *diff(struct _reent *ptr, _Bigint *a, _Bigint *b);
_Bigint *d2b(struct _reent *ptr, double d, int *e, int *bits);

#undef _REENT_CHECK_MP
#undef _REENT_MP_FREELIST
#undef _REENT_MP_P5S
#undef _REENT_MP_RESULT
#undef _REENT_MP_RESULT_K
#undef _REENT_ERRNO
#define _REENT_CHECK_MP(p)    ((void)0)
#define _REENT_MP_FREELIST(p) ((p)->freelist)
#define _REENT_MP_P5S(p)      ((p)->p5s)
#define _REENT_MP_RESULT(p)   ((p)->result)
#define _REENT_MP_RESULT_K(p) ((p)->result_k)
#define _REENT_ERRNO(p)       ((p)->err)
#define _Kmax PRINTF_DTOA_KMAX

static void *dtoa_pool_calloc(struct _reent *ctx, size_t n)
{
    size_t off = (ctx->used + 7u) & ~(size_t)7u;
    if (n > sizeof(ctx->pool) || off > sizeof(ctx->pool) - n) {
        return NULL;
    }
    memset((char *)ctx->pool + off, 0, n);
    ctx->used = off + n;
    return (char *)ctx->pool + off;
}

#define _calloc_r(p, n, sz) dtoa_pool_calloc((p), (size_t)(n) * (size_t)(sz))

static _Bigint *dtoa_eballoc(struct _reent *ptr, int k)
{
    _Bigint *b = Balloc(ptr, k);
    if (b != NULL) {
        b->_maxwds = 1 << k;
    }
    return b;
}

#define eBalloc(ptr, k) dtoa_eballoc((ptr), (k))


_Bigint *
Balloc (struct _reent *ptr, int k)
{
  int x;
  _Bigint *rv ;

  _REENT_CHECK_MP(ptr);
  if (_REENT_MP_FREELIST(ptr) == NULL)
    {
      /* Allocate a list of pointers to the mprec objects */
      _REENT_MP_FREELIST(ptr) = (struct _Bigint **) _calloc_r (ptr, 
						      sizeof (struct _Bigint *),
						      _Kmax + 1);
      if (_REENT_MP_FREELIST(ptr) == NULL)
	{
	  return NULL;
	}
    }

  if ((rv = _REENT_MP_FREELIST(ptr)[k]) != 0)
    {
      _REENT_MP_FREELIST(ptr)[k] = rv->_next;
    }
  else
    {
      x = 1 << k;
      /* Allocate an mprec Bigint and stick in in the freelist */
      rv = (_Bigint *) _calloc_r (ptr,
				  1,
				  sizeof (_Bigint) +
				  (x-1) * sizeof(rv->_x));
      if (rv == NULL) return NULL;
      rv->_k = k;
      rv->_maxwds = x;
    }
  rv->_sign = rv->_wds = 0;
  return rv;
}

void
Bfree (struct _reent *ptr, _Bigint * v)
{
  _REENT_CHECK_MP(ptr);
  if (v)
    {
      v->_next = _REENT_MP_FREELIST(ptr)[v->_k];
      _REENT_MP_FREELIST(ptr)[v->_k] = v;
    }
}

_Bigint *
multadd (struct _reent *ptr,
	_Bigint * b,
	int m,
	int a)
{
  int i, wds;
  __ULong *x, y;
#ifdef Pack_32
  __ULong xi, z;
#endif
  _Bigint *b1;

  wds = b->_wds;
  x = b->_x;
  i = 0;
  do
    {
#ifdef Pack_32
      xi = *x;
      y = (xi & 0xffff) * m + a;
      z = (xi >> 16) * m + (y >> 16);
      a = (int) (z >> 16);
      *x++ = (z << 16) + (y & 0xffff);
#else
      y = *x * m + a;
      a = (int) (y >> 16);
      *x++ = y & 0xffff;
#endif
    }
  while (++i < wds);
  if (a)
    {
      if (wds >= b->_maxwds)
	{
	  b1 = eBalloc (ptr, b->_k + 1);
	  Bcopy (b1, b);
	  Bfree (ptr, b);
	  b = b1;
	}
      b->_x[wds++] = a;
      b->_wds = wds;
    }
  return b;
}
int
hi0bits (register __ULong x)
{
  register int k = 0;

  if (!(x & 0xffff0000))
    {
      k = 16;
      x <<= 16;
    }
  if (!(x & 0xff000000))
    {
      k += 8;
      x <<= 8;
    }
  if (!(x & 0xf0000000))
    {
      k += 4;
      x <<= 4;
    }
  if (!(x & 0xc0000000))
    {
      k += 2;
      x <<= 2;
    }
  if (!(x & 0x80000000))
    {
      k++;
      if (!(x & 0x40000000))
	return 32;
    }
  return k;
}

int
lo0bits (__ULong *y)
{
  register int k;
  register __ULong x = *y;

  if (x & 7)
    {
      if (x & 1)
	return 0;
      if (x & 2)
	{
	  *y = x >> 1;
	  return 1;
	}
      *y = x >> 2;
      return 2;
    }
  k = 0;
  if (!(x & 0xffff))
    {
      k = 16;
      x >>= 16;
    }
  if (!(x & 0xff))
    {
      k += 8;
      x >>= 8;
    }
  if (!(x & 0xf))
    {
      k += 4;
      x >>= 4;
    }
  if (!(x & 0x3))
    {
      k += 2;
      x >>= 2;
    }
  if (!(x & 1))
    {
      k++;
      x >>= 1;
      if (!x & 1)
	return 32;
    }
  *y = x;
  return k;
}

_Bigint *
i2b (struct _reent * ptr, int i)
{
  _Bigint *b;

  b = eBalloc (ptr, 1);
  b->_x[0] = i;
  b->_wds = 1;
  return b;
}

_Bigint *
mult (struct _reent * ptr, _Bigint * a, _Bigint * b)
{
  _Bigint *c;
  int k, wa, wb, wc;
  __ULong carry, y, z;
  __ULong *x, *xa, *xae, *xb, *xbe, *xc, *xc0;
#ifdef Pack_32
  __ULong z2;
#endif

  if (a->_wds < b->_wds)
    {
      c = a;
      a = b;
      b = c;
    }
  k = a->_k;
  wa = a->_wds;
  wb = b->_wds;
  wc = wa + wb;
  if (wc > a->_maxwds)
    k++;
  c = eBalloc (ptr, k);
  for (x = c->_x, xa = x + wc; x < xa; x++)
    *x = 0;
  xa = a->_x;
  xae = xa + wa;
  xb = b->_x;
  xbe = xb + wb;
  xc0 = c->_x;
#ifdef Pack_32
  for (; xb < xbe; xb++, xc0++)
    {
      if ((y = *xb & 0xffff) != 0)
	{
	  x = xa;
	  xc = xc0;
	  carry = 0;
	  do
	    {
	      z = (*x & 0xffff) * y + (*xc & 0xffff) + carry;
	      carry = z >> 16;
	      z2 = (*x++ >> 16) * y + (*xc >> 16) + carry;
	      carry = z2 >> 16;
	      Storeinc (xc, z2, z);
	    }
	  while (x < xae);
	  *xc = carry;
	}
      if ((y = *xb >> 16) != 0)
	{
	  x = xa;
	  xc = xc0;
	  carry = 0;
	  z2 = *xc;
	  do
	    {
	      z = (*x & 0xffff) * y + (*xc >> 16) + carry;
	      carry = z >> 16;
	      Storeinc (xc, z, z2);
	      z2 = (*x++ >> 16) * y + (*xc & 0xffff) + carry;
	      carry = z2 >> 16;
	    }
	  while (x < xae);
	  *xc = z2;
	}
    }
#else
  for (; xb < xbe; xc0++)
    {
      if (y = *xb++)
	{
	  x = xa;
	  xc = xc0;
	  carry = 0;
	  do
	    {
	      z = *x++ * y + *xc + carry;
	      carry = z >> 16;
	      *xc++ = z & 0xffff;
	    }
	  while (x < xae);
	  *xc = carry;
	}
    }
#endif
  for (xc0 = c->_x, xc = xc0 + wc; wc > 0 && !*--xc; --wc);
  c->_wds = wc;
  return c;
}

_Bigint *
pow5mult (struct _reent * ptr, _Bigint * b, int k)
{
  _Bigint *b1, *p5, *p51;
  int i;
  static const int p05[3] = {5, 25, 125};

  if ((i = k & 3) != 0)
    b = multadd (ptr, b, p05[i - 1], 0);

  if (!(k >>= 2))
    return b;
  _REENT_CHECK_MP(ptr);
  if (!(p5 = _REENT_MP_P5S(ptr)))
    {
      /* first time */
      p5 = _REENT_MP_P5S(ptr) = i2b (ptr, 625);
      p5->_next = 0;
    }
  for (;;)
    {
      if (k & 1)
	{
	  b1 = mult (ptr, b, p5);
	  Bfree (ptr, b);
	  b = b1;
	}
      if (!(k >>= 1))
	break;
      if (!(p51 = p5->_next))
	{
	  p51 = p5->_next = mult (ptr, p5, p5);
	  p51->_next = 0;
	}
      p5 = p51;
    }
  return b;
}

_Bigint *
lshift (struct _reent * ptr, _Bigint * b, int k)
{
  int i, k1, n, n1;
  _Bigint *b1;
  __ULong *x, *x1, *xe, z;

#ifdef Pack_32
  n = k >> 5;
#else
  n = k >> 4;
#endif
  k1 = b->_k;
  n1 = n + b->_wds + 1;
  for (i = b->_maxwds; n1 > i; i <<= 1)
    k1++;
  b1 = eBalloc (ptr, k1);
  x1 = b1->_x;
  for (i = 0; i < n; i++)
    *x1++ = 0;
  x = b->_x;
  xe = x + b->_wds;
#ifdef Pack_32
  if (k &= 0x1f)
    {
      k1 = 32 - k;
      z = 0;
      do
	{
	  *x1++ = *x << k | z;
	  z = *x++ >> k1;
	}
      while (x < xe);
      if ((*x1 = z) != 0)
	++n1;
    }
#else
  if (k &= 0xf)
    {
      k1 = 16 - k;
      z = 0;
      do
	{
	  *x1++ = *x << k & 0xffff | z;
	  z = *x++ >> k1;
	}
      while (x < xe);
      if (*x1 = z)
	++n1;
    }
#endif
  else
    do
      *x1++ = *x++;
    while (x < xe);
  b1->_wds = n1 - 1;
  Bfree (ptr, b);
  return b1;
}

int
cmp (_Bigint * a, _Bigint * b)
{
  __ULong *xa, *xa0, *xb, *xb0;
  int i, j;

  i = a->_wds;
  j = b->_wds;
#ifdef DEBUG
  if (i > 1 && !a->_x[i - 1])
    Bug ("cmp called with a->_x[a->_wds-1] == 0");
  if (j > 1 && !b->_x[j - 1])
    Bug ("cmp called with b->_x[b->_wds-1] == 0");
#endif
  if (i -= j)
    return i;
  xa0 = a->_x;
  xa = xa0 + j;
  xb0 = b->_x;
  xb = xb0 + j;
  for (;;)
    {
      if (*--xa != *--xb)
	return *xa < *xb ? -1 : 1;
      if (xa <= xa0)
	break;
    }
  return 0;
}

_Bigint *
diff (struct _reent * ptr,
	_Bigint * a, _Bigint * b)
{
  _Bigint *c;
  int i, wa, wb;
  __Long borrow, y;		/* We need signed shifts here. */
  __ULong *xa, *xae, *xb, *xbe, *xc;
#ifdef Pack_32
  __Long z;
#endif

  i = cmp (a, b);
  if (!i)
    {
      c = eBalloc (ptr, 0);
      c->_wds = 1;
      c->_x[0] = 0;
      return c;
    }
  if (i < 0)
    {
      c = a;
      a = b;
      b = c;
      i = 1;
    }
  else
    i = 0;
  c = eBalloc (ptr, a->_k);
  c->_sign = i;
  wa = a->_wds;
  xa = a->_x;
  xae = xa + wa;
  wb = b->_wds;
  xb = b->_x;
  xbe = xb + wb;
  xc = c->_x;
  borrow = 0;
#ifdef Pack_32
  do
    {
      y = (*xa & 0xffff) - (*xb & 0xffff) + borrow;
      borrow = y >> 16;
      Sign_Extend (borrow, y);
      z = (*xa++ >> 16) - (*xb++ >> 16) + borrow;
      borrow = z >> 16;
      Sign_Extend (borrow, z);
      Storeinc (xc, z, y);
    }
  while (xb < xbe);
  while (xa < xae)
    {
      y = (*xa & 0xffff) + borrow;
      borrow = y >> 16;
      Sign_Extend (borrow, y);
      z = (*xa++ >> 16) + borrow;
      borrow = z >> 16;
      Sign_Extend (borrow, z);
      Storeinc (xc, z, y);
    }
#else
  do
    {
      y = *xa++ - *xb++ + borrow;
      borrow = y >> 16;
      Sign_Extend (borrow, y);
      *xc++ = y & 0xffff;
    }
  while (xb < xbe);
  while (xa < xae)
    {
      y = *xa++ + borrow;
      borrow = y >> 16;
      Sign_Extend (borrow, y);
      *xc++ = y & 0xffff;
    }
#endif
  while (!*--xc)
    wa--;
  c->_wds = wa;
  return c;
}
_Bigint *
d2b (struct _reent * ptr,
	double _d,
	int *e,
	int *bits)

{
  union double_union d;
  _Bigint *b;
  int de, i, k;
  __ULong *x, y, z;
#ifdef VAX
  __ULong d0, d1;
#endif
  d.d = _d;
#ifdef VAX
  d0 = word0 (d) >> 16 | word0 (d) << 16;
  d1 = word1 (d) >> 16 | word1 (d) << 16;
#else
#define d0 word0(d)
#define d1 word1(d)
  d.d = _d;
#endif

#ifdef Pack_32
  b = eBalloc (ptr, 1);
#else
  b = eBalloc (ptr, 2);
#endif
  x = b->_x;

  z = d0 & Frac_mask;
  d0 &= 0x7fffffff;		/* clear sign bit, which we ignore */
#ifdef Sudden_Underflow
  de = (int) (d0 >> Exp_shift);
#ifndef IBM
  z |= Exp_msk11;
#endif
#else
  if ((de = (int) (d0 >> Exp_shift)) != 0)
    z |= Exp_msk1;
#endif
#ifdef Pack_32
#ifndef _DOUBLE_IS_32BITS
  if (d1)
    {
      y = d1;
      k = lo0bits (&y);
      if (k)
	{
         x[0] = y | z << (32 - k);
	  z >>= k;
	}
      else
	x[0] = y;
      i = b->_wds = (x[1] = z) ? 2 : 1;
    }
  else
#endif
    {
#ifdef DEBUG
      if (!z)
	Bug ("Zero passed to d2b");
#endif
      k = lo0bits (&z);
      x[0] = z;
      i = b->_wds = 1;
#ifndef _DOUBLE_IS_32BITS
      k += 32;
#endif
    }
#else
  if (d1)
    {
      y = d1;
      k = lo0bits (&y);
      if (k)
	if (k >= 16)
	  {
	    x[0] = y | z << 32 - k & 0xffff;
	    x[1] = z >> k - 16 & 0xffff;
	    x[2] = z >> k;
	    i = 2;
	  }
	else
	  {
	    x[0] = y & 0xffff;
	    x[1] = y >> 16 | z << 16 - k & 0xffff;
	    x[2] = z >> k & 0xffff;
	    x[3] = z >> k + 16;
	    i = 3;
	  }
      else
	{
	  x[0] = y & 0xffff;
	  x[1] = y >> 16;
	  x[2] = z & 0xffff;
	  x[3] = z >> 16;
	  i = 3;
	}
    }
  else
    {
#ifdef DEBUG
      if (!z)
	Bug ("Zero passed to d2b");
#endif
      k = lo0bits (&z);
      if (k >= 16)
	{
	  x[0] = z;
	  i = 0;
	}
      else
	{
	  x[0] = z & 0xffff;
	  x[1] = z >> 16;
	  i = 1;
	}
      k += 32;
    }
  while (!x[i])
    --i;
  b->_wds = i + 1;
#endif
#ifndef Sudden_Underflow
  if (de)
    {
#endif
#ifdef IBM
      *e = (de - Bias - (P - 1) << 2) + k;
      *bits = 4 * P + 8 - k - hi0bits (word0 (d) & Frac_mask);
#else
      *e = de - Bias - (P - 1) + k;
      *bits = P - k;
#endif
#ifndef Sudden_Underflow
    }
  else
    {
      *e = de - Bias - (P - 1) + 1 + k;
#ifdef Pack_32
      *bits = 32 * i - hi0bits (x[i - 1]);
#else
      *bits = (i + 2) * 16 - hi0bits (x[i]);
#endif
    }
#endif
  return b;
}
#undef d0
#undef d1



const double
  tens[] =
{
  1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
  1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
  1e20, 1e21, 1e22, 1e23, 1e24

};

#if !defined(_DOUBLE_IS_32BITS) && !defined(__v800)
const double bigtens[] =
{1e16, 1e32, 1e64, 1e128, 1e256};

const double tinytens[] =
{1e-16, 1e-32, 1e-64, 1e-128, 1e-256};
#else
const double bigtens[] =
{1e16, 1e32};

const double tinytens[] =
{1e-16, 1e-32};
#endif
static int
quorem (_Bigint * b, _Bigint * S)
{
  int n;
  __Long borrow, y;
  __ULong carry, q, ys;
  __ULong *bx, *bxe, *sx, *sxe;
#ifdef Pack_32
  __Long z;
  __ULong si, zs;
#endif

  n = S->_wds;
#ifdef DEBUG
  /*debug*/ if (b->_wds > n)
    /*debug*/ Bug ("oversize b in quorem");
#endif
  if (b->_wds < n)
    return 0;
  sx = S->_x;
  sxe = sx + --n;
  bx = b->_x;
  bxe = bx + n;
  q = *bxe / (*sxe + 1);	/* ensure q <= true quotient */
#ifdef DEBUG
  /*debug*/ if (q > 9)
    /*debug*/ Bug ("oversized quotient in quorem");
#endif
  if (q)
    {
      borrow = 0;
      carry = 0;
      do
	{
#ifdef Pack_32
	  si = *sx++;
	  ys = (si & 0xffff) * q + carry;
	  zs = (si >> 16) * q + (ys >> 16);
	  carry = zs >> 16;
	  y = (*bx & 0xffff) - (ys & 0xffff) + borrow;
	  borrow = y >> 16;
	  Sign_Extend (borrow, y);
	  z = (*bx >> 16) - (zs & 0xffff) + borrow;
	  borrow = z >> 16;
	  Sign_Extend (borrow, z);
	  Storeinc (bx, z, y);
#else
	  ys = *sx++ * q + carry;
	  carry = ys >> 16;
	  y = *bx - (ys & 0xffff) + borrow;
	  borrow = y >> 16;
	  Sign_Extend (borrow, y);
	  *bx++ = y & 0xffff;
#endif
	}
      while (sx <= sxe);
      if (!*bxe)
	{
	  bx = b->_x;
	  while (--bxe > bx && !*bxe)
	    --n;
	  b->_wds = n;
	}
    }
  if (cmp (b, S) >= 0)
    {
      q++;
      borrow = 0;
      carry = 0;
      bx = b->_x;
      sx = S->_x;
      do
	{
#ifdef Pack_32
	  si = *sx++;
	  ys = (si & 0xffff) + carry;
	  zs = (si >> 16) + (ys >> 16);
	  carry = zs >> 16;
	  y = (*bx & 0xffff) - (ys & 0xffff) + borrow;
	  borrow = y >> 16;
	  Sign_Extend (borrow, y);
	  z = (*bx >> 16) - (zs & 0xffff) + borrow;
	  borrow = z >> 16;
	  Sign_Extend (borrow, z);
	  Storeinc (bx, z, y);
#else
	  ys = *sx++ + carry;
	  carry = ys >> 16;
	  y = *bx - (ys & 0xffff) + borrow;
	  borrow = y >> 16;
	  Sign_Extend (borrow, y);
	  *bx++ = y & 0xffff;
#endif
	}
      while (sx <= sxe);
      bx = b->_x;
      bxe = bx + n;
      if (!*bxe)
	{
	  while (--bxe > bx && !*bxe)
	    --n;
	  b->_wds = n;
	}
    }
  return q;
}

/* dtoa for IEEE arithmetic (dmg): convert double to ASCII string.
 *
 * Inspired by "How to Print Floating-Point Numbers Accurately" by
 * Guy L. Steele, Jr. and Jon L. White [Proc. ACM SIGPLAN '90, pp. 92-101].
 *
 * Modifications:
 *	1. Rather than iterating, we use a simple numeric overestimate
 *	   to determine k = floor(log10(d)).  We scale relevant
 *	   quantities using O(log2(k)) rather than O(k) multiplications.
 *	2. For some modes > 2 (corresponding to ecvt and fcvt), we don't
 *	   try to generate digits strictly left to right.  Instead, we
 *	   compute with fewer bits and propagate the carry if necessary
 *	   when rounding the final digit up.  This is often faster.
 *	3. Under the assumption that input will be rounded nearest,
 *	   mode 0 renders 1e23 as 1e23 rather than 9.999999999999999e22.
 *	   That is, we allow equality in stopping tests when the
 *	   round-nearest rule will give the same floating-point value
 *	   as would satisfaction of the stopping test with strict
 *	   inequality.
 *	4. We remove common factors of powers of 2 from relevant
 *	   quantities.
 *	5. When converting floating-point integers less than 1e16,
 *	   we use floating-point arithmetic rather than resorting
 *	   to multiple-precision integers.
 *	6. When asked to produce fewer than 15 digits, we first try
 *	   to get by with floating-point arithmetic; we resort to
 *	   multiple-precision integer arithmetic only if we cannot
 *	   guarantee that the floating-point calculation has given
 *	   the correctly rounded result.  For k requested digits and
 *	   "uniformly" distributed input, the probability is
 *	   something like 10^(k-15) that we must resort to the long
 *	   calculation.
 */


char *
_dtoa_r (struct _reent *ptr,
	double _d,
	int mode,
	int ndigits,
	int *decpt,
	int *sign,
	char **rve)
{
  /*	Arguments ndigits, decpt, sign are similar to those
	of ecvt and fcvt; trailing zeros are suppressed from
	the returned string.  If not null, *rve is set to point
	to the end of the return value.  If d is +-Infinity or NaN,
	then *decpt is set to 9999.

	mode:
		0 ==> shortest string that yields d when read in
			and rounded to nearest.
		1 ==> like 0, but with Steele & White stopping rule;
			e.g. with IEEE P754 arithmetic , mode 0 gives
			1e23 whereas mode 1 gives 9.999999999999999e22.
		2 ==> max(1,ndigits) significant digits.  This gives a
			return value similar to that of ecvt, except
			that trailing zeros are suppressed.
		3 ==> through ndigits past the decimal point.  This
			gives a return value similar to that from fcvt,
			except that trailing zeros are suppressed, and
			ndigits can be negative.
		4-9 should give the same return values as 2-3, i.e.,
			4 <= mode <= 9 ==> same return as mode
			2 + (mode & 1).  These modes are mainly for
			debugging; often they run slower but sometimes
			faster than modes 2-3.
		4,5,8,9 ==> left-to-right digit generation.
		6-9 ==> don't try fast floating-point estimate
			(if applicable).

		Values of mode other than 0-9 are treated as mode 0.

		Sufficient space is allocated to the return value
		to hold the suppressed trailing zeros.
	*/

  int bbits, b2, b5, be, dig, i, ieps, ilim, ilim0, ilim1, j, j1, k, k0,
    k_check, leftright, m2, m5, s2, s5, spec_case, try_quick;
  union double_union d, d2, eps;
  __Long L;
#ifndef Sudden_Underflow
  int denorm;
  __ULong x;
#endif
  _Bigint *b, *b1, *delta, *mlo = NULL, *mhi, *S;
  double ds;
  char *s, *s0;

  d.d = _d;

  _REENT_CHECK_MP(ptr);
  if (_REENT_MP_RESULT(ptr))
    {
      _REENT_MP_RESULT(ptr)->_k = _REENT_MP_RESULT_K(ptr);
      _REENT_MP_RESULT(ptr)->_maxwds = 1 << _REENT_MP_RESULT_K(ptr);
      Bfree (ptr, _REENT_MP_RESULT(ptr));
      _REENT_MP_RESULT(ptr) = 0;
    }

  if (word0 (d) & Sign_bit)
    {
      /* set sign for everything, including 0's and NaNs */
      *sign = 1;
      word0 (d) &= ~Sign_bit;	/* clear sign bit */
    }
  else
    *sign = 0;

#if defined(IEEE_Arith) + defined(VAX)
#ifdef IEEE_Arith
  if ((word0 (d) & Exp_mask) == Exp_mask)
#else
  if (word0 (d) == 0x8000)
#endif
    {
      /* Infinity or NaN */
      *decpt = 9999;
      s =
#ifdef IEEE_Arith
	!word1 (d) && !(word0 (d) & 0xfffff) ? "Infinity" :
#endif
	"NaN";
      if (rve)
	*rve =
#ifdef IEEE_Arith
	  s[3] ? s + 8 :
#endif
	  s + 3;
      return s;
    }
#endif
#ifdef IBM
  d.d += 0;			/* normalize */
#endif
  if (!d.d)
    {
      *decpt = 1;
      s = "0";
      if (rve)
	*rve = s + 1;
      return s;
    }

  b = d2b (ptr, d.d, &be, &bbits);
#ifdef Sudden_Underflow
  i = (int) (word0 (d) >> Exp_shift1 & (Exp_mask >> Exp_shift1));
#else
  if ((i = (int) (word0 (d) >> Exp_shift1 & (Exp_mask >> Exp_shift1))) != 0)
    {
#endif
      d2.d = d.d;
      word0 (d2) &= Frac_mask1;
      word0 (d2) |= Exp_11;
#ifdef IBM
      if (j = 11 - hi0bits (word0 (d2) & Frac_mask))
	d2.d /= 1 << j;
#endif

      /* log(x)	~=~ log(1.5) + (x-1.5)/1.5
		 * log10(x)	 =  log(x) / log(10)
		 *		~=~ log(1.5)/log(10) + (x-1.5)/(1.5*log(10))
		 * log10(d) = (i-Bias)*log(2)/log(10) + log10(d2)
		 *
		 * This suggests computing an approximation k to log10(d) by
		 *
		 * k = (i - Bias)*0.301029995663981
		 *	+ ( (d2-1.5)*0.289529654602168 + 0.176091259055681 );
		 *
		 * We want k to be too large rather than too small.
		 * The error in the first-order Taylor series approximation
		 * is in our favor, so we just round up the constant enough
		 * to compensate for any error in the multiplication of
		 * (i - Bias) by 0.301029995663981; since |i - Bias| <= 1077,
		 * and 1077 * 0.30103 * 2^-52 ~=~ 7.2e-14,
		 * adding 1e-13 to the constant term more than suffices.
		 * Hence we adjust the constant term to 0.1760912590558.
		 * (We could get a more accurate k by invoking log10,
		 *  but this is probably not worthwhile.)
		 */

      i -= Bias;
#ifdef IBM
      i <<= 2;
      i += j;
#endif
#ifndef Sudden_Underflow
      denorm = 0;
    }
  else
    {
      /* d is denormalized */

      i = bbits + be + (Bias + (P - 1) - 1);
#if defined (_DOUBLE_IS_32BITS)
      x = word0 (d) << (32 - i);
#else
      x = (i > 32) ? (word0 (d) << (64 - i)) | (word1 (d) >> (i - 32))
       : (word1 (d) << (32 - i));
#endif
      d2.d = x;
      word0 (d2) -= 31 * Exp_msk1;	/* adjust exponent */
      i -= (Bias + (P - 1) - 1) + 1;
      denorm = 1;
    }
#endif
#if defined (_DOUBLE_IS_32BITS)
  ds = (d2.d - 1.5) * 0.289529651 + 0.176091269 + i * 0.30103001;
#else
  ds = (d2.d - 1.5) * 0.289529654602168 + 0.1760912590558 + i * 0.301029995663981;
#endif
  k = (int) ds;
  if (ds < 0. && ds != k)
    k--;			/* want k = floor(ds) */
  k_check = 1;
  if (k >= 0 && k <= Ten_pmax)
    {
      if (d.d < tens[k])
	k--;
      k_check = 0;
    }
  j = bbits - i - 1;
  if (j >= 0)
    {
      b2 = 0;
      s2 = j;
    }
  else
    {
      b2 = -j;
      s2 = 0;
    }
  if (k >= 0)
    {
      b5 = 0;
      s5 = k;
      s2 += k;
    }
  else
    {
      b2 -= k;
      b5 = -k;
      s5 = 0;
    }
  if (mode < 0 || mode > 9)
    mode = 0;
  try_quick = 1;
  if (mode > 5)
    {
      mode -= 4;
      try_quick = 0;
    }
  leftright = 1;
  ilim = ilim1 = -1;
  switch (mode)
    {
    case 0:
    case 1:
      i = 18;
      ndigits = 0;
      break;
    case 2:
      leftright = 0;
      /* no break */
    case 4:
      if (ndigits <= 0)
	ndigits = 1;
      ilim = ilim1 = i = ndigits;
      break;
    case 3:
      leftright = 0;
      /* no break */
    case 5:
      i = ndigits + k + 1;
      ilim = i;
      ilim1 = i - 1;
      if (i <= 0)
	i = 1;
    }
  j = sizeof (__ULong);
  for (_REENT_MP_RESULT_K(ptr) = 0; sizeof (_Bigint) - sizeof (__ULong) + j <= i;
       j <<= 1)
    _REENT_MP_RESULT_K(ptr)++;
  _REENT_MP_RESULT(ptr) = eBalloc (ptr, _REENT_MP_RESULT_K(ptr));
  s = s0 = (char *) _REENT_MP_RESULT(ptr);

  if (ilim >= 0 && ilim <= Quick_max && try_quick)
    {
      /* Try to get by with floating-point arithmetic. */

      i = 0;
      d2.d = d.d;
      k0 = k;
      ilim0 = ilim;
      ieps = 2;			/* conservative */
      if (k > 0)
	{
	  ds = tens[k & 0xf];
	  j = k >> 4;
	  if (j & Bletch)
	    {
	      /* prevent overflows */
	      j &= Bletch - 1;
	      d.d /= bigtens[n_bigtens - 1];
	      ieps++;
	    }
	  for (; j; j >>= 1, i++)
	    if (j & 1)
	      {
		ieps++;
		ds *= bigtens[i];
	      }
	  d.d /= ds;
	}
      else if ((j1 = -k) != 0)
	{
	  d.d *= tens[j1 & 0xf];
	  for (j = j1 >> 4; j; j >>= 1, i++)
	    if (j & 1)
	      {
		ieps++;
		d.d *= bigtens[i];
	      }
	}
      if (k_check && d.d < 1. && ilim > 0)
	{
	  if (ilim1 <= 0)
	    goto fast_failed;
	  ilim = ilim1;
	  k--;
	  d.d *= 10.;
	  ieps++;
	}
      eps.d = ieps * d.d + 7.;
      word0 (eps) -= (P - 1) * Exp_msk1;
      if (ilim == 0)
	{
	  S = mhi = 0;
	  d.d -= 5.;
	  if (d.d > eps.d)
	    goto one_digit;
	  if (d.d < -eps.d)
	    goto no_digits;
	  goto fast_failed;
	}
#ifndef No_leftright
      if (leftright)
	{
	  /* Use Steele & White method of only
	   * generating digits needed.
	   */
	  eps.d = 0.5 / tens[ilim - 1] - eps.d;
	  for (i = 0;;)
	    {
	      L = d.d;
	      d.d -= L;
	      *s++ = '0' + (int) L;
	      if (d.d < eps.d)
		goto ret1;
	      if (1. - d.d < eps.d)
		goto bump_up;
	      if (++i >= ilim)
		break;
	      eps.d *= 10.;
	      d.d *= 10.;
	    }
	}
      else
	{
#endif
	  /* Generate ilim digits, then fix them up. */
	  eps.d *= tens[ilim - 1];
	  for (i = 1;; i++, d.d *= 10.)
	    {
	      L = d.d;
	      d.d -= L;
	      *s++ = '0' + (int) L;
	      if (i == ilim)
		{
		  if (d.d > 0.5 + eps.d)
		    goto bump_up;
		  else if (d.d < 0.5 - eps.d)
		    {
		      while (*--s == '0');
		      s++;
		      goto ret1;
		    }
		  break;
		}
	    }
#ifndef No_leftright
	}
#endif
    fast_failed:
      s = s0;
      d.d = d2.d;
      k = k0;
      ilim = ilim0;
    }

  /* Do we have a "small" integer? */

  if (be >= 0 && k <= Int_max)
    {
      /* Yes. */
      ds = tens[k];
      if (ndigits < 0 && ilim <= 0)
	{
	  S = mhi = 0;
	  if (ilim < 0 || d.d <= 5 * ds)
	    goto no_digits;
	  goto one_digit;
	}
      for (i = 1;; i++)
	{
	  L = d.d / ds;
	  d.d -= L * ds;
#ifdef Check_FLT_ROUNDS
	  /* If FLT_ROUNDS == 2, L will usually be high by 1 */
	  if (d.d < 0)
	    {
	      L--;
	      d.d += ds;
	    }
#endif
	  *s++ = '0' + (int) L;
	  if (i == ilim)
	    {
	      d.d += d.d;
             if ((d.d > ds) || ((d.d == ds) && (L & 1)))
		{
		bump_up:
		  while (*--s == '9')
		    if (s == s0)
		      {
			k++;
			*s = '0';
			break;
		      }
		  ++*s++;
		}
	      break;
	    }
	  if (!(d.d *= 10.))
	    break;
	}
      goto ret1;
    }

  m2 = b2;
  m5 = b5;
  mhi = mlo = 0;
  if (leftright)
    {
      if (mode < 2)
	{
	  i =
#ifndef Sudden_Underflow
	    denorm ? be + (Bias + (P - 1) - 1 + 1) :
#endif
#ifdef IBM
	    1 + 4 * P - 3 - bbits + ((bbits + be - 1) & 3);
#else
	    1 + P - bbits;
#endif
	}
      else
	{
	  j = ilim - 1;
	  if (m5 >= j)
	    m5 -= j;
	  else
	    {
	      s5 += j -= m5;
	      b5 += j;
	      m5 = 0;
	    }
	  if ((i = ilim) < 0)
	    {
	      m2 -= i;
	      i = 0;
	    }
	}
      b2 += i;
      s2 += i;
      mhi = i2b (ptr, 1);
    }
  if (m2 > 0 && s2 > 0)
    {
      i = m2 < s2 ? m2 : s2;
      b2 -= i;
      m2 -= i;
      s2 -= i;
    }
  if (b5 > 0)
    {
      if (leftright)
	{
	  if (m5 > 0)
	    {
	      mhi = pow5mult (ptr, mhi, m5);
	      b1 = mult (ptr, mhi, b);
	      Bfree (ptr, b);
	      b = b1;
	    }
         if ((j = b5 - m5) != 0)
	    b = pow5mult (ptr, b, j);
	}
      else
	b = pow5mult (ptr, b, b5);
    }
  S = i2b (ptr, 1);
  if (s5 > 0)
    S = pow5mult (ptr, S, s5);

  /* Check for special case that d is a normalized power of 2. */

  spec_case = 0;
  if (mode < 2)
    {
      if (!word1 (d) && !(word0 (d) & Bndry_mask)
#ifndef Sudden_Underflow
	  && word0 (d) & Exp_mask
#endif
	)
	{
	  /* The special case */
	  b2 += Log2P;
	  s2 += Log2P;
	  spec_case = 1;
	}
    }

  /* Arrange for convenient computation of quotients:
   * shift left if necessary so divisor has 4 leading 0 bits.
   *
   * Perhaps we should just compute leading 28 bits of S once
   * and for all and pass them and a shift to quorem, so it
   * can do shifts and ors to compute the numerator for q.
   */

#ifdef Pack_32
  if ((i = ((s5 ? 32 - hi0bits (S->_x[S->_wds - 1]) : 1) + s2) & 0x1f) != 0)
    i = 32 - i;
#else
  if ((i = ((s5 ? 32 - hi0bits (S->_x[S->_wds - 1]) : 1) + s2) & 0xf) != 0)
    i = 16 - i;
#endif
  if (i > 4)
    {
      i -= 4;
      b2 += i;
      m2 += i;
      s2 += i;
    }
  else if (i < 4)
    {
      i += 28;
      b2 += i;
      m2 += i;
      s2 += i;
    }
  if (b2 > 0)
    b = lshift (ptr, b, b2);
  if (s2 > 0)
    S = lshift (ptr, S, s2);
  if (k_check)
    {
      if (cmp (b, S) < 0)
	{
	  k--;
	  b = multadd (ptr, b, 10, 0);	/* we botched the k estimate */
	  if (leftright)
	    mhi = multadd (ptr, mhi, 10, 0);
	  ilim = ilim1;
	}
    }
  if (ilim <= 0 && mode > 2)
    {
      if (ilim < 0 || cmp (b, S = multadd (ptr, S, 5, 0)) <= 0)
	{
	  /* no digits, fcvt style */
	no_digits:
	  k = -1 - ndigits;
	  goto ret;
	}
    one_digit:
      *s++ = '1';
      k++;
      goto ret;
    }
  if (leftright)
    {
      if (m2 > 0)
	mhi = lshift (ptr, mhi, m2);

      /* Compute mlo -- check for special case
       * that d is a normalized power of 2.
       */

      mlo = mhi;
      if (spec_case)
	{
	  mhi = eBalloc (ptr, mhi->_k);
	  Bcopy (mhi, mlo);
	  mhi = lshift (ptr, mhi, Log2P);
	}

      for (i = 1;; i++)
	{
	  dig = quorem (b, S) + '0';
	  /* Do we yet have the shortest decimal string
	   * that will round to d?
	   */
	  j = cmp (b, mlo);
	  delta = diff (ptr, S, mhi);
	  j1 = delta->_sign ? 1 : cmp (b, delta);
	  Bfree (ptr, delta);
#ifndef ROUND_BIASED
	  if (j1 == 0 && !mode && !(word1 (d) & 1))
	    {
	      if (dig == '9')
		goto round_9_up;
	      if (j > 0)
		dig++;
	      *s++ = dig;
	      goto ret;
	    }
#endif
         if ((j < 0) || ((j == 0) && !mode
#ifndef ROUND_BIASED
	      && !(word1 (d) & 1)
#endif
           ))
	    {
	      if (j1 > 0)
		{
		  b = lshift (ptr, b, 1);
		  j1 = cmp (b, S);
                 if (((j1 > 0) || ((j1 == 0) && (dig & 1)))
		      && dig++ == '9')
		    goto round_9_up;
		}
	      *s++ = dig;
	      goto ret;
	    }
	  if (j1 > 0)
	    {
	      if (dig == '9')
		{		/* possible if i == 1 */
		round_9_up:
		  *s++ = '9';
		  goto roundoff;
		}
	      *s++ = dig + 1;
	      goto ret;
	    }
	  *s++ = dig;
	  if (i == ilim)
	    break;
	  b = multadd (ptr, b, 10, 0);
	  if (mlo == mhi)
	    mlo = mhi = multadd (ptr, mhi, 10, 0);
	  else
	    {
	      mlo = multadd (ptr, mlo, 10, 0);
	      mhi = multadd (ptr, mhi, 10, 0);
	    }
	}
    }
  else
    for (i = 1;; i++)
      {
	*s++ = dig = quorem (b, S) + '0';
	if (i >= ilim)
	  break;
	b = multadd (ptr, b, 10, 0);
      }

  /* Round off last digit */

  b = lshift (ptr, b, 1);
  j = cmp (b, S);
  if ((j > 0) || ((j == 0) && (dig & 1)))
    {
    roundoff:
      while (*--s == '9')
	if (s == s0)
	  {
	    k++;
	    *s++ = '1';
	    goto ret;
	  }
      ++*s++;
    }
  else
    {
      while (*--s == '0');
      s++;
    }
ret:
  Bfree (ptr, S);
  if (mhi)
    {
      if (mlo && mlo != mhi)
	Bfree (ptr, mlo);
      Bfree (ptr, mhi);
    }
ret1:
  Bfree (ptr, b);
  *s = 0;
  *decpt = k + 1;
  if (rve)
    *rve = s;
  return s0;
}

void printf_dtoa_ctx_init(printf_dtoa_ctx *ctx)
{
    ctx->freelist = NULL;
    ctx->p5s = NULL;
    ctx->result = NULL;
    ctx->result_k = 0;
    ctx->err = 0;
    ctx->used = 0;
}

char *printf_dtoa(printf_dtoa_ctx *ctx, double d, int mode, int ndigits,
                  int *decpt, int *sign, char **rve)
{
    return dtoa_internal(ctx, d, mode, ndigits, decpt, sign, rve);
}

#endif  /* PRINTF_SUPPORT_DTOA && !PRINTF_DISABLE_SUPPORT_FLOAT */
