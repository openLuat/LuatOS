
#include "audioCfg.h"   //struct AudioConfig_t

const AudioConfig_t audio_cfg_default =
{
	.amrEncodeBypass = 0,
	.amrDecodeBypass = 0,
	.amrAllowDtx 	 = 1,

	.speechCfgTx =
	{

#if defined(TX_AEC)
	    .CVT_AEC = {
	    .bypass = 0,
	    .delay = 0,//yww if>= 0,use this value//ori = 100, modify to 10(10*4=40ms)
	    .cngMode = 1,
	    .echoMode = 3,//ori=1,default=3
	    .nlpFlag = 1,
	    },
#endif

#if defined(TX_ANS)
	.CVT_ANS = {
		.bypass = 0,
		.mode = 0,
		.eqBypass = 0,
		.eqBand[0] = 32767,//20240229	//[0-32767]
		.eqBand[1] = 32767,
		.eqBand[2] = 32767,
		.eqBand[3] = 32767,
		.eqBand[4] = 32767,
		.eqBand[5] = 32767,
		.eqBand[6] = 32767,
		.eqBand[7] = 32767,
		.eqBand[8] = 32767,
		.eqBand[9] = 32767,
		.eqBand[10] = 32767,
		.eqBand[11] = 32767,
		.eqBand[12] = 32767,
		.eqBand[13] = 32767,
		.eqBand[14] = 32767,
		.eqBand[15] = 32767,
		.eqBand[16] = 32767,
		.eqBand[17] = 32767,
		.eqBand[18] = 32767,
		.eqBand[19] = 32767,
		.eqBand[20] = 32767,
		.eqBand[21] = 32767,
		.eqBand[22] = 32767,
		.eqBand[23] = 32767,
		.eqBand[24] = 32767,
		.eqBand[25] = 32767,
		.eqBand[26] = 32767,
		.eqBand[27] = 32767,
		.eqBand[28] = 32767,
		.eqBand[29] = 32767,
		.eqBand[30] = 32767,
		.eqBand[31] = 32767,
		},
#endif

#if defined(TX_DRC)
	    .CVT_DRC = {
	    .bypass = 1,
	    .compThreshold = -960,	//-15*2^6=960,Q6
	    .compRatio = 32,	//=(1-1/r)*2^6=(1-1/2)*2^6=32; Q6
	    .expandThreshold = -2880,	// -45*2^6=-2880;Q6
	    .expandRatio = -51,	//=(1-1/r)*2^6=(1-1/0.555f)*2^6=-51; Q6
	    .attackTime = 14459,	//type 1, exp(1/(attack_time * sample_rate))=exp(-1/0.001*8000)*2^14=
	    .releaseTime = 16046,	//type 1,exp(1/(release_time * sample_rate))=exp(-1/0.006*8000)*2^14=
	    .makeupGain = 1,	// 10^(old/20)=10^(6/20)=1.9953,Q?	//last gain, fake ,2 be deleted
	    },

#endif

#if defined(TX_AGC)
	    .CVT_AGC = {
	    .bypass             = 0,
	    .targetLevel       = 3,
	    .compressionGain   = 6,
	    .limiterEnable     = 1,
	    },
#endif

#if defined(TX_EQ)
	    .CVT_EQ = {
	    .bypass = 0,
	    .gain = 0,
	    .num = 1,
	    .params = 
		    {
			    {	
			    	.type = IIR_BIQUARD_QTY,
			    	.filt = { .design = { 500, 0, 5790 } }
			    },// can Add more filters
		    },

	    },
#endif
	},

	.speechCfgRx = 
	{

#if defined(RX_ANS)
	.CVT_ANS_RX = {
		.bypass = 1,
		.mode = 0,
		.eqBypass = 0,
		.eqBand[0] = 32767,//20240229	//[0-32767]
		.eqBand[1] = 32767,
		.eqBand[2] = 32767,
		.eqBand[3] = 32767,
		.eqBand[4] = 32767,
		.eqBand[5] = 32767,
		.eqBand[6] = 32767,
		.eqBand[7] = 32767,
		.eqBand[8] = 32767,
		.eqBand[9] = 32767,
		.eqBand[10] = 32767,
		.eqBand[11] = 32767,
		.eqBand[12] = 32767,
		.eqBand[13] = 32767,
		.eqBand[14] = 32767,
		.eqBand[15] = 32767,
		.eqBand[16] = 32767,
		.eqBand[17] = 32767,
		.eqBand[18] = 32767,
		.eqBand[19] = 32767,
		.eqBand[20] = 32767,
		.eqBand[21] = 32767,
		.eqBand[22] = 32767,
		.eqBand[23] = 32767,
		.eqBand[24] = 32767,
		.eqBand[25] = 32767,
		.eqBand[26] = 32767,
		.eqBand[27] = 32767,
		.eqBand[28] = 32767,
		.eqBand[29] = 32767,
		.eqBand[30] = 32767,
		.eqBand[31] = 32767,
		},
#endif

#if defined(RX_DRC)

	    .CVT_DRC_RX = {
	    .bypass = 0,
	    //.type = 1,
	    .compThreshold = -960,	//-15*2^6=960,Q6
	    .compRatio = 32,	//=(1-1/r)*2^6=(1-1/2)*2^6=32; Q6
	    .expandThreshold = -2880,	// -45*2^6=-2880;Q6
	    .expandRatio = -51,	//=(1-1/r)*2^6=(1-1/0.555f)*2^6=-51; Q6
	    .attackTime = 14459,	//type 1, exp(1/(attack_time * sample_rate))=exp(-1/0.001*8000)*2^14=
	    .releaseTime = 16046,	//type 1,exp(1/(release_time * sample_rate))=exp(-1/0.006*8000)*2^14=
	    .makeupGain = 1,	// 10^(old/20)=10^(6/20)=1.9953,Q?	//last gain, fake ,2 be deleted
	    //.delay = 32,
	    //.tav = 0,	//fake,2 be deleted
	    },

#endif

#if defined(RX_AGC)
	    .CVT_AGC_RX = {
	    .bypass = 0,
	    .targetLevel = 3,
	    .compressionGain = 9,
	    .limiterEnable = 1,
	    },
#endif

#if defined(RX_EQ)
	    .CVT_EQ_RX = {
	    .bypass = 0,
	    .gain = 0,
	    .num = 1,
	    .params = {
		    { 	
		    	.type = IIR_BIQUARD_QTY,
		    	.filt = { .design = { 500, 0, 5790 } }
		    },// can Add more filters
	    },

	    },
#endif
	},
};

