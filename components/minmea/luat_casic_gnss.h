#ifndef LUAT_CASIC_GNSS_H
#define LUAT_CASIC_GNSS_H

// 位置结构体
typedef struct
{
	double lat; // 纬度，正数表示北纬，负数表示南纬
	double lon; // 经度，正数表示东经，负数表示西经
	double alt; // 高度，如果高度无法获取，可以设置为0
	int valid;

} POS_LLA_STR;

// 时间结构体(注意：这里是UTC时间！！！与北京时间有8个小时的差距，不要直接使用北京时间！！！)
// 比如北京时间2016.5.8,10:34:23，那么UTC时间应该是2016.5.8,02:34:23
// 比如北京时间2016.5.8,03:34:23，那么UTC时间应该是2016.5.7,19:34:23
typedef struct
{
	int valid; // 时间有效标志，1=有效，否则无效
	int year;
	int month;
	int day;
	int hour;
	int minute;
	int second;
	float ms;

} DATETIME_STR;

// 辅助信息（位置，时间，频率）
typedef struct
{
	double xOrLat, yOrLon, zOrAlt;
	double tow;
	float df;
	float posAcc;
	float tAcc;
	float fAcc;
	unsigned int res;
	unsigned short int wn;
	unsigned char timeSource;
	unsigned char flags;

} AID_INI_STR;

void casicAgnssAidIni(DATETIME_STR *dateTime, POS_LLA_STR* lla, char aidIniMsg[66]);

#endif
