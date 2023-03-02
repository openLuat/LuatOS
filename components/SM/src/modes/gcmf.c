#include <openssl/modes.h>

int gcmf_init(gcmf_context *ctx, void *key, block128_f block)
{
	memset(ctx->tag, 0, sizeof(GCM_FILE_TAG_LEN));
	ctx->gcm = (GCM128_CONTEXT *)malloc(sizeof(GCM128_CONTEXT));
	CRYPTO_gcm128_init(ctx->gcm, key, block);
	return 0;
}

int gcmf_free(gcmf_context *ctx)
{
	int ret = CRYPTO_gcm128_finish(ctx->gcm, ctx->tag, GCM_FILE_TAG_LEN);
	if (ret != 0)
	{
		return ret;
	}
	CRYPTO_gcm128_release(ctx->gcm);
	//    free(ctx->gcm);
	memset(ctx, 0, sizeof(gcmf_context));
	return 0;
}

int gcmf_set_iv(gcmf_context *ctx, const unsigned char *iv, size_t len)
{
	CRYPTO_gcm128_setiv(ctx->gcm, iv, len);
	return 0;
}

int gcmf_encrypt_file(gcmf_context *ctx, char *infpath, char *outfpath)
{
	int len_outfpath, file_size, block_size;
	FILE *infp, *tmpfp, *outfp;
	char *tmp_file_path = NULL;
	unsigned char buf[GCM_FILE_MAX_BLOCK_LEN];
	unsigned char out[GCM_FILE_MAX_BLOCK_LEN];
	unsigned char size_buf[sizeof(size_t)];

	int ver = GCM_FILE_VERSION;
	// #0 Open file
	len_outfpath = strlen(outfpath);
	tmp_file_path = (char *)malloc((len_outfpath + 5) * sizeof(char));
	memcpy(tmp_file_path, outfpath, len_outfpath);
	memcpy(tmp_file_path + len_outfpath, ".tmp", 5);

	if ((infp = fopen(infpath, "rb")) == NULL)
		return -1;
	if ((tmpfp = fopen(tmp_file_path, "wb+")) == NULL)
		return -2;
	if ((outfp = fopen(outfpath, "wb+")) == NULL)
		return -3;

	// #1 Encrypt file (slice blocks)

	memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
	memset(out, 0, GCM_FILE_MAX_BLOCK_LEN);

	// Get size of file
	fseek(infp, 0, SEEK_END);
	file_size = ftell(infp);
	memset(size_buf, 0, sizeof(size_t));
	memcpy(size_buf, &file_size, sizeof(size_t));
	fseek(infp, 0, SEEK_SET);

	// GCM Block encrypt
	while (
		(block_size = fread(buf, sizeof(unsigned char), GCM_FILE_MAX_BLOCK_LEN, infp)) &&
		block_size != 0)
	{
		CRYPTO_gcm128_encrypt(ctx->gcm, buf, out, block_size);
		fwrite(out, sizeof(unsigned char), block_size, tmpfp);

		memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
		memset(out, 0, GCM_FILE_MAX_BLOCK_LEN);
	}

	// Get Tag of GCM encrypt
	CRYPTO_gcm128_tag(ctx->gcm, ctx->tag, GCM_FILE_TAG_LEN);

	// Finish encrypt
	fflush(tmpfp);
	fseek(tmpfp, 0, SEEK_SET);
	fclose(infp);

	// #2 Write cipher file

	// add file flag
	fputs(GCM_FILE_MAGIC_TAG, outfp);
	// add version (default: 1)

	fwrite(&ver, sizeof(int), 1, outfp);
	// add tag
	fwrite(&ctx->tag, sizeof(unsigned char), GCM_FILE_TAG_LEN, outfp);
	// add file len
	fwrite(size_buf, sizeof(unsigned char), sizeof(size_t), outfp);
	// copy cipher
	memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
	while (
		(block_size = fread(buf, sizeof(unsigned char), GCM_FILE_MAX_BLOCK_LEN, tmpfp)) &&
		block_size != 0)
	{
		fwrite(buf, sizeof(unsigned char), block_size, outfp);
		memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
	}

	fclose(tmpfp);
	fclose(outfp);
	remove(tmp_file_path);
	free(tmp_file_path);

	return 0;
}

int gcmf_decrypt_file(gcmf_context *ctx, char *infpath, char *outfpath)
{
	int ret = 0;
	int file_size = 0, read_size = 0, block_size;
	unsigned char size_buf[sizeof(size_t)];
	char flag[GCM_FILE_TAG_LEN + 1];
	FILE *infp, *outfp;
	int version;
	unsigned char buf[GCM_FILE_MAX_BLOCK_LEN];
	unsigned char out[GCM_FILE_MAX_BLOCK_LEN];
	memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
	memset(out, 0, GCM_FILE_MAX_BLOCK_LEN);

	if ((infp = fopen(infpath, "rb")) == NULL)
	{
		return -1;
	}

	memset(flag, 0, sizeof(flag));
	//read file flag
	fgets(flag, GCM_FILE_MAGIC_TAG_LEN + 1, infp);
	if (strcmp(flag, GCM_FILE_MAGIC_TAG))
	{
		ret = -2;
		goto end;
	}

	//read version

	if (fread(&version, sizeof(version), 1, infp) == 0)
	{
		ret = -3;
		goto end;
	}
	if (version != GCM_FILE_VERSION)
	{
		ret = -3;
		goto end;
	}

	//read tag
	if (fread(ctx->tag, sizeof(unsigned char), GCM_FILE_TAG_LEN, infp) == 0)
	{
		ret = -4;
		goto end;
	}

	memset(size_buf, 0, sizeof(size_t));
	// read real length
	if (fread(size_buf, sizeof(unsigned char), sizeof(size_t), infp) == 0)
	{
		ret = -5;
		goto end;
	}
	file_size = (int)((((size_buf[3] & 0xff) << 24) | ((size_buf[2] & 0xff) << 16) | ((size_buf[1] & 0xff) << 8) | ((size_buf[0] & 0xff) << 0)));

	// Write Plaintext
	if ((outfp = fopen(outfpath, "wb+")) == NULL)
	{
		ret = -6;
		goto end;
	}

	CRYPTO_gcm128_tag(ctx->gcm, ctx->tag, GCM_FILE_TAG_LEN);

	while (
		(block_size = fread(buf, sizeof(unsigned char), GCM_FILE_MAX_BLOCK_LEN, infp)) &&
		block_size != 0)
	{
		CRYPTO_gcm128_decrypt(ctx->gcm, buf, out, block_size);
		read_size += block_size;
		fwrite(out, sizeof(unsigned char), block_size, outfp);

		memset(buf, 0, GCM_FILE_MAX_BLOCK_LEN);
		memset(out, 0, GCM_FILE_MAX_BLOCK_LEN);
	}

	fflush(outfp);
	// Invalid file
	if (read_size != file_size)
	{
		ret = -7;
		goto end;
	}

end:
	fclose(infp);
	fclose(outfp);

	return ret;
}
