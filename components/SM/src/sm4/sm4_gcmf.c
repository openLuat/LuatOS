/*
* sm4gcmf.c
*
*  Created on: 2017-10-18
*      Author: lzj
*      Updated: Payne
*
*/

#include <sm4/sm4.h>

int sm4_gcmf_init(sm4_gcmf_context *ctx, const SM4_KEY *sm4_key) {
	return gcmf_init(ctx, (void *)sm4_key, (block128_f)sm4_encrypt);
}

int sm4_gcmf_free(sm4_gcmf_context *ctx) {
	return gcmf_free(ctx);
}

int sm4_gcmf_set_iv(sm4_gcmf_context *ctx, const unsigned char * iv, size_t len) {
	return gcmf_set_iv(ctx, iv, len);
}

int sm4_gcmf_encrypt_file(sm4_gcmf_context * ctx, char *infpath, char *outfpath) {
	return gcmf_encrypt_file(ctx, infpath, outfpath);
}

int sm4_gcmf_decrypt_file(sm4_gcmf_context * ctx, char *infpath, char *outfpath) {
	return gcmf_decrypt_file(ctx, infpath, outfpath);
}
