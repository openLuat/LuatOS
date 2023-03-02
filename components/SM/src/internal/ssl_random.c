/*
 * @Author: Weijie Li
 * @Date: 2017-11-02 10:32:40
 * @Last Modified by: Peiran Luo
 * @Last Modified time: 2018-04-11 15:00:00
 */

#include <stdbool.h>
#include <internal/ssl_random.h>
#include <sm3/sm3.h>

#if defined(ANDROID_VER) && defined(_DEBUG_)
#include <android/log.h>
#define LOG(...) __android_log_print(ANDROID_LOG_DEBUG, "SSL_RANDOM", __VA_ARGS__)
#else
#define LOG(...)
#endif

//  Windows
#ifdef _WIN32

#include <intrin.h>
uint64_t rdtsc()
{
	return __rdtsc();
}

//  Linux/GCC
#else

#ifdef ENABLE_RDTSC
uint64_t rdtsc()
{
	unsigned int lo, hi;
	__asm__ __volatile__("rdtsc"
						 : "=a"(lo), "=d"(hi));
	return ((uint64_t)hi << 32) | lo;
}
#endif

#endif

// Android
#ifdef ANDROID_VER

#ifdef ENABLE_SEED_ANDROID_SENSOR
ASensorEventQueue *sensor_event_queue_;
ASensorVector gravityData;

int getAndroidSensorData(int fd, int events, void *data)
{
	ASensorEvent event;
	while (sensor_event_queue_ && ASensorEventQueue_getEvents(sensor_event_queue_, &event, 1) > 0)
	{
		memcpy(&gravityData, &event.acceleration, sizeof(gravityData));
		LOG("SENSOR: %f %f %f", gravityData.x, gravityData.y, gravityData.z);
		break;
	}
	return 1;
}
#endif // END ENABLE_SEED_ANDROID_SENSOR

#endif // END ANDROID_VER

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IOS == 1
#include <objc/runtime.h>
#include <objc/objc.h>
#include <objc/message.h>
#include <unistd.h>

typedef struct
{
	double x;
	double y;
	double z;
} PP;

BOOL (*msgSend_bool)
(id, SEL) = (BOOL(*)(id, SEL))objc_msgSend;

#if defined(__arm64__)
PP (*msgSend_pp)
(id, SEL) = (PP(*)(id, SEL))objc_msgSend;
#else
PP (*msgSend_pp)
(id, SEL) = (PP(*)(id, SEL))objc_msgSend_stret;
#endif

#endif

#if defined(unix) || defined(__unix__) || defined(__unix) || defined(__APPLE__) || defined(ANDROID_VER)
static int read_file(const char *filename, unsigned char *buf, int size)
{
	FILE *fd = NULL;
	int ret = 0;
	fd = fopen(filename, "rb");
	if (fd)
	{
		ret = fread(buf, size, 1, fd);
		fclose(fd);
	}
	return ret;
}
#endif

int ssl_random_init(ssl_random_context *ctx)
{
	// 0. Set MD Info
	int ret;
	ctx->md_info = mbedtls_md_info_from_type(RANDOM_HASH_ALGORITHM);
	if (ctx->md_info == NULL)
	{
		return SSL_RANDOM_ERROR_HASH_ALGO_NOT_FOUND;
	}

	// 1. Init and Setup MD
	ctx->md_ctx = (mbedtls_md_context_t *)malloc(sizeof(mbedtls_md_context_t));
	mbedtls_md_init(ctx->md_ctx);

	ret = mbedtls_md_setup(ctx->md_ctx, ctx->md_info, 0);
	if (ret != 0)
		return ret;

	// 2. Init HMAC-DRBG
	ctx->drbg_ctx = (mbedtls_hmac_drbg_context *)malloc(sizeof(mbedtls_hmac_drbg_context));
	mbedtls_hmac_drbg_init(ctx->drbg_ctx);

	// 3. Init Hash Buffer
	ctx->hashLen = mbedtls_md_get_size(ctx->md_info);
	ctx->hash = (unsigned char *)malloc(ctx->hashLen);
	memset(ctx->hash, 0, ctx->hashLen);



	// 4. Set isInitial
	ctx->isInitial = 1;

	return 0;
}

int ssl_random_seed(void *rand_ctx, unsigned char *seed_buf, size_t buf_size)
{
	return ssl_random_seed_with_option(rand_ctx, seed_buf, buf_size, 0);
}

int ssl_random_seed_with_option(void *rand_ctx, unsigned char *seed_buf, size_t buf_size, int options)
{
	int ret;
	ssl_random_context *ctx = (ssl_random_context *)rand_ctx;
	if (ctx->isInitial != 1)
		return SSL_RANDOM_ERROR_NOT_INITIAL;

	


	// 0. Init MD
	mbedtls_md_init(ctx->md_ctx);

	ret = mbedtls_md_setup(ctx->md_ctx, ctx->md_info, 0);
	if (ret)
		return ret;

	// 1. Set time() as seed
	// General
	if ((options & SSL_RANDOM_DISABLE_TIME) == 0)
	{
		time_t t = time(NULL);
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&t, sizeof(t));
	}

// 2. Set /dev/urandom as seed
// FOR Linux/Unix
#if defined(unix) || defined(__unix__) || defined(__unix) || defined(__APPLE__) || defined(ANDROID_VER)
	if ((options & SSL_RANDOM_DISABLE_URANDOM) == 0)
	{
		unsigned char urandomBuf[1024];

		ret = read_file("/dev/urandom", urandomBuf, sizeof(urandomBuf));
		if (ret)
		{
			mbedtls_md_update(ctx->md_ctx, urandomBuf, sizeof(urandomBuf));
		}
		LOG("URANDOM: %d ", ret);
	}
#endif

// 3. Set CPU Cycle Count
// FOR Windows
#if defined(_WIN32)
	if ((options & SSL_RANDOM_DISABLE_CPU_CYCLE) == 0)
	{
		unsigned long long cpuCycle = rdtsc();
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&cpuCycle, sizeof(cpuCycle));
	}
#endif

// 4. Set rand_s
// FOR Windows
#if defined(_WIN32) && defined(_CRT_RAND_S)
	if ((options & SSL_RANDOM_DISABLE_RAND_S) == 0)
	{
		int i;
		unsigned int tmp;
		for (i = 0; i < 5; i++)
		{
			if (rand_s(&tmp) != 0)
				goto skipRandS;
			mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&tmp, sizeof(tmp));
		}
	}
skipRandS:
#endif

// 5. Set Android Hardware Info
#ifdef ANDROID_VER
	if ((options & AISINOSSL_RANDOM_DISABLE_ANDROID_INFO) == 0)
	{
		char buf[PROP_VALUE_MAX];

		__system_property_get("ro.build.version.release", buf);
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)buf, strlen(buf));

		__system_property_get("ro.hardware", buf);
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)buf, strlen(buf));

		__system_property_get("ro.serialno", buf);
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)buf, strlen(buf));
	}
#endif // END ANDROID_VER

// 6. Set Android sensor data as seed
#if defined(ANDROID_VER) && defined(ENABLE_SEED_ANDROID_SENSOR)
	if ((options & AISINOSSL_RANDOM_DISABLE_ANDROID_SENSOR) == 0)
	{
		mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&gravityData, sizeof(gravityData));
	}
#endif // END defined(ANDROID_VER) && defined(ENABLE_SEED_ANDROID_SENSOR)

#if defined(ENABLE_SEED_IOS_SENSOR) && TARGET_OS_IOS == 1

	Class CMMotionManager = objc_getClass("CMMotionManager");
	if (CMMotionManager)
	{

		SEL sel = sel_registerName("init");
		id motionManager = class_createInstance(CMMotionManager, 0);
		motionManager = objc_msgSend(motionManager, sel);

		//acceleration
		BOOL isAccelerometerAvailable = msgSend_bool(motionManager, sel_registerName("isAccelerometerAvailable"));
		if (isAccelerometerAvailable)
		{
			objc_msgSend(motionManager, sel_registerName("startAccelerometerUpdates"));

			BOOL isAccelerometerActive = NO;
			while (!isAccelerometerActive)
			{
				isAccelerometerActive = msgSend_bool(motionManager, sel_registerName("isAccelerometerActive"));
				sleep(1);
			}
			id accelerometerData = NULL;
			while (!accelerometerData)
				accelerometerData = objc_msgSend(motionManager, sel_registerName("accelerometerData"));
			PP acceleration;
			acceleration = msgSend_pp(accelerometerData, sel_registerName("acceleration"));
			mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&acceleration, sizeof(acceleration));
#if defined(DEBUG)
			printf("acceleration x:%lf y:%lf z:%lf\n", acceleration.x, acceleration.y, acceleration.z);
#endif
			objc_msgSend(motionManager, sel_registerName("stopAccelerometerUpdates"));
		}

		//rotation
		BOOL isGyroAvailable = msgSend_bool(motionManager, sel_registerName("isGyroAvailable"));
		if (isGyroAvailable)
		{
			objc_msgSend(motionManager, sel_registerName("startGyroUpdates"));
			BOOL isGyroActive = NO;
			while (!isGyroActive)
			{
				isGyroActive = msgSend_bool(motionManager, sel_registerName("isGyroActive"));
				sleep(1);
			}
			id gyroData = NULL;
			while (!gyroData)
				gyroData = objc_msgSend(motionManager, sel_registerName("gyroData"));
			PP rotationRate;
			rotationRate = msgSend_pp(gyroData, sel_registerName("rotationRate"));
			mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&rotationRate, sizeof(rotationRate));
#if defined(DEBUG)
			printf("rotation x:%lf y:%lf z:%lf\n", rotationRate.x, rotationRate.y, rotationRate.z);
#endif
			objc_msgSend(motionManager, sel_registerName("stopGyroUpdates"));
		}

		//magnetic
		BOOL isMagnetometerAvailable = msgSend_bool(motionManager, sel_registerName("isMagnetometerAvailable"));
		if (isMagnetometerAvailable)
		{
			objc_msgSend(motionManager, sel_registerName("startMagnetometerUpdates"));
			bool isMagnetometerActive = NO;
			while (!isMagnetometerActive)
			{
				isMagnetometerActive = msgSend_bool(motionManager, sel_registerName("isMagnetometerActive"));
				sleep(1);
			}
			id magnetometerData = NULL;
			while (!magnetometerData)
				magnetometerData = objc_msgSend(motionManager, sel_registerName("magnetometerData"));
			PP magneticField;
			magneticField = msgSend_pp(magnetometerData, sel_registerName("magneticField"));
			mbedtls_md_update(ctx->md_ctx, (const unsigned char *)&magneticField, sizeof(magneticField));
#if defined(DEBUG)
			printf("magnetic x:%lf y:%lf z:%lf\n", magneticField.x, magneticField.y, magneticField.z);
#endif
			objc_msgSend(motionManager, sel_registerName("stopMagnetometerUpdates"));
		}
	}
#endif

	// Set Additional message
	if (buf_size > 0 && seed_buf != NULL)
	{
		mbedtls_md_update(ctx->md_ctx, seed_buf, buf_size);
	}

	// Last, Finish hash
	ret = mbedtls_md_finish(ctx->md_ctx, ctx->hash);
	if (ret)
		return ret;

	// Set seed
	mbedtls_hmac_drbg_seed_buf(ctx->drbg_ctx, ctx->md_info, ctx->hash, ctx->hashLen);

	// Clear Seed Message
	memset(ctx->hash, 0, ctx->hashLen);

	ctx->isSeeded = 1;

	return 0;
}

int ssl_random_rand(void *rand_ctx, unsigned char *output, size_t size)
{
	int ret;
	ssl_random_context *ctx = (ssl_random_context *)rand_ctx;
	if (ctx->isSeeded != 1)
		return SSL_RANDOM_ERROR_NOT_SEEDED;

	 ret = mbedtls_hmac_drbg_random(ctx->drbg_ctx, output, size);
	switch (ret)
	{
	case MBEDTLS_ERR_HMAC_DRBG_REQUEST_TOO_BIG:
		return SSL_RANDOM_ERROR_OUT_SIZE_TO_LARGE;
	default:
		return ret;
	}
}

int ssl_random_rand_int_array(ssl_random_context *ctx, int *output, int count)
{
	return ssl_random_rand(ctx, (unsigned char *)output, count * sizeof(int));
}

int ssl_random_rand_uint_array(ssl_random_context *ctx, unsigned int *output, int count)
{
	return ssl_random_rand(ctx, (unsigned char *)output, count * sizeof(unsigned int));
}

void ssl_random_free(ssl_random_context *ctx)
{
	if (ctx->isInitial != 1)
		return;

	mbedtls_md_free(ctx->md_ctx);
	free(ctx->md_ctx);

	mbedtls_hmac_drbg_free(ctx->drbg_ctx);
	free(ctx->drbg_ctx);

	free(ctx->hash);


	ctx->isInitial = 0;
	ctx->isSeeded = 0;
}

int ssl_random_shuffle_u8(u8 *list, int len)
{
	unsigned int *randNumbers;

	if (len <= 0)
		return SSL_RANDOM_ERROR_INVLIAD_SIZE;
	randNumbers = (unsigned int *)malloc((len + 10) * sizeof(unsigned int));

	ssl_random_rand_int_array(NULL, (int *)randNumbers, len);

	while (len > 0)
	{
		int r;
		u8 tmp;
		r = randNumbers[len] % len;
		len--;
		tmp = *(list + len);
		*(list + len) = *(list + r);
		*(list + r) = tmp;
	}

	free(randNumbers);
	return 0;
}

