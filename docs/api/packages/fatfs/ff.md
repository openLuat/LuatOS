---
title: ff
path: fatfs/ff.c
---
--------------------------------------------------
# ld_word

```c
static WORD ld_word(const BYTE *ptr)
```

-----------------------------------------------------------------------*/
Load/Store multi-byte word in the FAT structure                       */
-----------------------------------------------------------------------*/

static WORD ld_word (const BYTE* ptr)	/*	 Load a 2-byte little-endian word 

## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`WORD`| *无*


--------------------------------------------------
# ld_dword

```c
static DWORD ld_dword(const BYTE *ptr)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`DWORD`| *无*


--------------------------------------------------
# ld_qword

```c
static QWORD ld_qword(const BYTE *ptr)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`QWORD`| *无*


--------------------------------------------------
# st_word

```c
static void st_word(BYTE *ptr, WORD val)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*
**val**|`WORD`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`void`| *无*


--------------------------------------------------
# st_dword

```c
static void st_dword(BYTE *ptr, DWORD val)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*
**val**|`DWORD`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`void`| *无*


--------------------------------------------------
# st_qword

```c
static void st_qword(BYTE *ptr, QWORD val)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ptr**|`BYTE*`| *无*
**val**|`QWORD`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`void`| *无*


--------------------------------------------------
# mem_cmp

```c
static int mem_cmp(const void *dst, const void *src, UINT cnt)
```

-----------------------------------------------------------------------*/
String functions                                                      */
-----------------------------------------------------------------------*/

Copy memory to memory */
static void mem_cpy (void* dst, const void* src, UINT cnt)
{
	BYTE *d = (BYTE*)dst;
	const BYTE *s = (const BYTE*)src;

	if (cnt != 0) {
		do {
			*d++ = *s++;
		} while (--cnt);
	}
}


Fill memory block */
static void mem_set (void* dst, int val, UINT cnt)
{
	BYTE *d = (BYTE*)dst;

	do {
		*d++ = (BYTE)val;
	} while (--cnt);
}


Compare memory block */
static int mem_cmp (const void* dst, const void* src, UINT cnt)	/* ZR:same, NZ:different 

## 参数表

Name | Type | Description
-----|------|--------------
**dst**|`void*`| *无*
**src**|`void*`| *无*
**cnt**|`UINT`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# chk_chr

```c
static int chk_chr(const char *str, int chr)
```

Check if chr is contained in the string */
static int chk_chr (const char* str, int chr)	/* NZ:contained, ZR:not contained 

## 参数表

Name | Type | Description
-----|------|--------------
**str**|`char*`| *无*
**chr**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# enq_lock

```c
static int enq_lock(void null)
```

-----------------------------------------------------------------------*/
File lock control functions                                           */
-----------------------------------------------------------------------*/

static FRESULT chk_lock (	/* Check if the file can be accessed 

## 参数表

Name | Type | Description
-----|------|--------------
**null**|`void`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


