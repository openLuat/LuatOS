# Lua 静态字符串池 的设想

把lua代码中用到的字符串, 以某种格式存放到flash上, 不占用RAM

## 前提条件

* lua 5.3.6+
* 当前平台支持flash地址作为内存指针地址

## 可行性分析

### Lua的字符串在RAM内的表达形式

```c
typedef struct TString {
  CommonHeader;
  lu_byte extra;  /* reserved words for short strings; "has hash" for longs */
  lu_byte shrlen;  /* length for short strings */
  unsigned int hash;
  union {
    size_t lnglen;  /* length for long strings */
    struct TString *hnext;  /* linked list for hash table */
  } u;
} TString;
```

其中 CommonHeader 为

```C
GCObject *next; lu_byte tt; lu_byte marked
```