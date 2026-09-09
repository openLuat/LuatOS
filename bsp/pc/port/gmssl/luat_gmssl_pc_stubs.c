/*
 * PC 模拟器专用的 gmssl 缺符号兜底。
 *
 * components/gmssl 是 LuatOS 裁剪过的 GmSSL 分支: 只保留 SM2/SM3/SM4 及其直接依赖,
 * 没有收录 x509 / pem / pkcs8 / ec / digest / base64 / aes 等实现。但保留的源码里仍有
 * 一些**未被调用**的辅助函数引用这些上游符号:
 *
 *   - ARM 固件构建用 -ffunction-sections + --gc-sections 把未引用函数整段丢弃,
 *     所以那些未定义符号不会进链接;
 *   - MSVC 没有等价能力(/Gy + /OPT:REF 只用于减体积, 未引用函数里的未定义符号照样报
 *     LNK2019/LNK2001), 因此 PC 构建需要这些符号存在才能链接通过。
 *
 * 这些函数都不在 Lua 绑定(gmssl 的 sm2 / sm3 / sm4 接口)的调用链上:
 *   - 打印类(format_/sm2_bn_print/asn1_object_identifier_print)给出最小实现;
 *   - 校验类(asn1_string_is_utf8_string/ia5_string)给出真实实现;
 *   - 其余功能类(ec_/pem_/pkcs8_/x509_/DIGEST_sm3/pbkdf2_genkey)按"PC 未编译该功能"
 *     处理: 打印告警并返回失败, 不静默返回错误结果。
 *
 * 本文件位于 bsp/pc/port/ 下, 只参与 PC 模拟器构建, 不会进入固件。
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <string.h>

#include <gmssl/error.h>
#include <gmssl/sm2.h>
#include <gmssl/asn1.h>
#include <gmssl/ec.h>
#include <gmssl/pem.h>
#include <gmssl/pkcs8.h>
#include <gmssl/x509_alg.h>
#include <gmssl/digest.h>
#include <gmssl/pbkdf2.h>
#include <gmssl/aes.h>

#define GMSSL_PC_UNSUPPORTED(name) \
	LLOGW("PC 模拟器未编译 gmssl 的 " name ", 该接口不可用(仅被未调用的上游辅助函数引用)")

/* ---------------------------------------------------------------- 打印类 */

int format_print(FILE *fp, int format, int indent, const char *str, ...)
{
	va_list ap;
	int i;

	(void)format;
	if (!fp || !str) {
		return -1;
	}
	for (i = 0; i < indent; i++) {
		fputc(' ', fp);
	}
	va_start(ap, str);
	vfprintf(fp, str, ap);
	va_end(ap);
	return 1;
}

int format_bytes(FILE *fp, int format, int indent, const char *str,
	const uint8_t *data, size_t datalen)
{
	size_t i;
	int j;

	(void)format;
	if (!fp || !str || (!data && datalen)) {
		return -1;
	}
	for (j = 0; j < indent; j++) {
		fputc(' ', fp);
	}
	fprintf(fp, "%s", str);
	for (i = 0; i < datalen; i++) {
		fprintf(fp, "%02X", data[i]);
	}
	fputc('\n', fp);
	return 1;
}

int format_string(FILE *fp, int format, int indent, const char *str,
	const uint8_t *data, size_t datalen)
{
	int j;

	(void)format;
	if (!fp || !str || (!data && datalen)) {
		return -1;
	}
	for (j = 0; j < indent; j++) {
		fputc(' ', fp);
	}
	fprintf(fp, "%s: %.*s\n", str, (int)datalen, (const char *)data);
	return 1;
}

int sm2_bn_print(FILE *fp, int fmt, int ind, const char *label, const SM2_BN a)
{
	uint8_t buf[32];

	sm2_bn_to_bytes(a, buf);
	return format_bytes(fp, fmt, ind, label, buf, sizeof(buf));
}

int asn1_object_identifier_print(FILE *fp, int fmt, int ind, const char *label,
	const char *name, const uint32_t *nodes, size_t nodes_cnt)
{
	size_t i;

	if (!fp || !nodes) {
		return -1;
	}
	format_print(fp, fmt, ind, "%s: ", label);
	if (name) {
		format_print(fp, fmt, 0, "%s (", name);
	}
	for (i = 0; i < nodes_cnt; i++) {
		format_print(fp, fmt, 0, "%u%s", (unsigned)nodes[i],
			(i + 1 < nodes_cnt) ? "." : "");
	}
	format_print(fp, fmt, 0, "%s\n", name ? ")" : "");
	return 1;
}

/* ---------------------------------------------------------------- 校验类 */

int asn1_string_is_ia5_string(const char *d, size_t dlen)
{
	size_t i;

	if (!d) {
		return 0;
	}
	for (i = 0; i < dlen; i++) {
		if ((uint8_t)d[i] > 0x7f) {
			return 0;
		}
	}
	return 1;
}

int asn1_string_is_utf8_string(const char *d, size_t dlen)
{
	size_t i = 0;

	if (!d) {
		return 0;
	}
	while (i < dlen) {
		uint8_t c = (uint8_t)d[i];
		size_t n;
		if (c < 0x80) {
			i++;
			continue;
		} else if ((c & 0xe0) == 0xc0) {
			if (c < 0xc2) {
				return 0;
			}
			n = 1;
		} else if ((c & 0xf0) == 0xe0) {
			n = 2;
		} else if ((c & 0xf8) == 0xf0) {
			if (c > 0xf4) {
				return 0;
			}
			n = 3;
		} else {
			return 0;
		}
		if (i + n >= dlen) {
			return 0;
		}
		while (n--) {
			if (((uint8_t)d[++i] & 0xc0) != 0x80) {
				return 0;
			}
		}
		i++;
	}
	return 1;
}

/* ------------------------------------------------------- 功能类(未编译) */

int aes_set_encrypt_key(AES_KEY *key, const uint8_t *raw_key, size_t raw_key_len)
{
	(void)key; (void)raw_key; (void)raw_key_len;
	GMSSL_PC_UNSUPPORTED("aes_set_encrypt_key");
	return -1;
}

int aes_set_decrypt_key(AES_KEY *key, const uint8_t *raw_key, size_t raw_key_len)
{
	(void)key; (void)raw_key; (void)raw_key_len;
	GMSSL_PC_UNSUPPORTED("aes_set_decrypt_key");
	return -1;
}

void aes_encrypt(const AES_KEY *key, const uint8_t in[AES_BLOCK_SIZE],
	uint8_t out[AES_BLOCK_SIZE])
{
	(void)key; (void)in;
	memset(out, 0, AES_BLOCK_SIZE);
	GMSSL_PC_UNSUPPORTED("aes_encrypt");
}

int aes_gcm_encrypt(const AES_KEY *key, const uint8_t *iv, size_t ivlen,
	const uint8_t *aad, size_t aadlen, const uint8_t *in, size_t inlen,
	uint8_t *out, size_t taglen, uint8_t *tag)
{
	(void)key; (void)iv; (void)ivlen; (void)aad; (void)aadlen; (void)in; (void)inlen;
	(void)out; (void)taglen; (void)tag;
	GMSSL_PC_UNSUPPORTED("aes_gcm_encrypt");
	return -1;
}

int aes_gcm_decrypt(const AES_KEY *key, const uint8_t *iv, size_t ivlen,
	const uint8_t *aad, size_t aadlen, const uint8_t *in, size_t inlen,
	const uint8_t *tag, size_t taglen, uint8_t *out)
{
	(void)key; (void)iv; (void)ivlen; (void)aad; (void)aadlen; (void)in; (void)inlen;
	(void)tag; (void)taglen; (void)out;
	GMSSL_PC_UNSUPPORTED("aes_gcm_decrypt");
	return -1;
}

int ec_named_curve_to_der(int curve, uint8_t **out, size_t *outlen)
{
	(void)curve; (void)out; (void)outlen;
	GMSSL_PC_UNSUPPORTED("ec_named_curve_to_der");
	return -1;
}

int ec_named_curve_from_der(int *curve, const uint8_t **in, size_t *inlen)
{
	(void)curve; (void)in; (void)inlen;
	GMSSL_PC_UNSUPPORTED("ec_named_curve_from_der");
	return -1;
}

int ec_private_key_print(FILE *fp, int fmt, int ind, const char *label,
	const uint8_t *d, size_t dlen)
{
	(void)fp; (void)fmt; (void)ind; (void)label; (void)d; (void)dlen;
	GMSSL_PC_UNSUPPORTED("ec_private_key_print");
	return -1;
}

int pem_read(FILE *fp, const char *name, uint8_t *out, size_t *outlen, size_t maxlen)
{
	(void)fp; (void)name; (void)out; (void)outlen; (void)maxlen;
	GMSSL_PC_UNSUPPORTED("pem_read");
	return -1;
}

int pem_write(FILE *fp, const char *name, const uint8_t *in, size_t inlen)
{
	(void)fp; (void)name; (void)in; (void)inlen;
	GMSSL_PC_UNSUPPORTED("pem_write");
	return -1;
}

int pkcs8_enced_private_key_info_to_der(
	const uint8_t *salt, size_t saltlen,
	int iter,
	int keylen,
	int prf,
	int cipher,
	const uint8_t *iv, size_t ivlen,
	const uint8_t *enced, size_t encedlen,
	uint8_t **out, size_t *outlen)
{
	(void)salt; (void)saltlen; (void)iter; (void)keylen; (void)prf; (void)cipher;
	(void)iv; (void)ivlen; (void)enced; (void)encedlen; (void)out; (void)outlen;
	GMSSL_PC_UNSUPPORTED("pkcs8_enced_private_key_info_to_der");
	return -1;
}

int pkcs8_enced_private_key_info_from_der(
	const uint8_t **salt, size_t *saltlen,
	int *iter,
	int *keylen,
	int *prf,
	int *cipher,
	const uint8_t **iv, size_t *ivlen,
	const uint8_t **enced, size_t *encedlen,
	const uint8_t **in, size_t *inlen)
{
	(void)salt; (void)saltlen; (void)iter; (void)keylen; (void)prf; (void)cipher;
	(void)iv; (void)ivlen; (void)enced; (void)encedlen; (void)in; (void)inlen;
	GMSSL_PC_UNSUPPORTED("pkcs8_enced_private_key_info_from_der");
	return -1;
}

int x509_public_key_algor_to_der(int oid, int curve, uint8_t **out, size_t *outlen)
{
	(void)oid; (void)curve; (void)out; (void)outlen;
	GMSSL_PC_UNSUPPORTED("x509_public_key_algor_to_der");
	return -1;
}

int x509_public_key_algor_from_der(int *oid, int *curve_or_null,
	const uint8_t **in, size_t *inlen)
{
	(void)oid; (void)curve_or_null; (void)in; (void)inlen;
	GMSSL_PC_UNSUPPORTED("x509_public_key_algor_from_der");
	return -1;
}

int x509_public_key_algor_print(FILE *fp, int fmt, int ind, const char *label,
	const uint8_t *d, size_t dlen)
{
	(void)fp; (void)fmt; (void)ind; (void)label; (void)d; (void)dlen;
	GMSSL_PC_UNSUPPORTED("x509_public_key_algor_print");
	return -1;
}

const DIGEST *DIGEST_sm3(void)
{
	GMSSL_PC_UNSUPPORTED("DIGEST_sm3");
	return NULL;
}

int pbkdf2_genkey(const DIGEST *digest,
	const char *pass, size_t passlen, const uint8_t *salt, size_t saltlen, size_t iter,
	size_t outlen, uint8_t *out)
{
	(void)digest; (void)pass; (void)passlen; (void)salt; (void)saltlen; (void)iter;
	(void)outlen; (void)out;
	GMSSL_PC_UNSUPPORTED("pbkdf2_genkey");
	return -1;
}
