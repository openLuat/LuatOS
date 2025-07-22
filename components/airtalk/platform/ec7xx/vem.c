#include "csdk.h"
#include "luat_audio_play.h"

#include "audioCfg.h"   //struct AudioConfig_t
#include "mw_nvm_audio.h"
extern void ShareInfoAPGetCPAudioLogCtrl(AudioParaCfgLogControl_t *audioLogCfg);
extern void ShareInfoAPSetCPAudioLogCtrl(AudioParaCfgLogControl_t audioLogCfg);
void log_on(void)
{
	AudioParaCfgLogControl_t audioLogCfg = {0};
	AudioParaCfgCommon_t mAudioCfgCommon = {0};
	AecConfig_t    MwNvmAudioSphTxAEC;
	ecAudioCfgTlvStore *pMwNvmAudioCfg = NULL;
	AudioParaCfgLogControl_t MwNvmAudioLogCtrl;
	pMwNvmAudioCfg  = (ecAudioCfgTlvStore *)luat_heap_malloc(sizeof(ecAudioCfgTlvStore)+ sizeof(AudioParaSphEQBiquard_t)*EC_ADCFG_SPEECH_EQ_BIQUARD_NUMB*EC_ADCFG_SPEECH_TX_NUMB
					+ sizeof(AudioParaSphEQBiquard_t)*EC_ADCFG_SPEECH_EQ_BIQUARD_NUMB*EC_ADCFG_SPEECH_RX_NUMB + sizeof(UINT16)*EC_ADCFG_SPEECH_ANS_EQ_BAND_NUMB*EC_ADCFG_SPEECH_RX_NUMB
					 + sizeof(UINT16)*EC_ADCFG_SPEECH_ANS_EQ_BAND_NUMB*EC_ADCFG_SPEECH_TX_NUMB);

	if (mwNvmAudioCfgRead(pMwNvmAudioCfg) == FALSE)
	{
		if (mwNvmAudioCfgRead(pMwNvmAudioCfg) == FALSE)
		{
			LUAT_DEBUG_PRINT("read config failed");
		}
	}
	mwNvmAudioCfgLogControlGet(&MwNvmAudioLogCtrl, pMwNvmAudioCfg);
	mwNvmAudioCfgSpeechGetTxAEC(&mAudioCfgCommon, &MwNvmAudioSphTxAEC, pMwNvmAudioCfg);
	if (!MwNvmAudioLogCtrl.TxBeforeVem)
	{
		MwNvmAudioLogCtrl.TxBeforeVem = 1;
		MwNvmAudioLogCtrl.TxAfterVem = 1;
		MwNvmAudioLogCtrl.RxBeforeVem = 1;
		MwNvmAudioLogCtrl.RxAfterVem = 1;
		MwNvmAudioLogCtrl.RxBeforeDecoder = 1;
		MwNvmAudioLogCtrl.TxAfterEncoder = 1;
		mwNvmAudioCfgLogControlSet(&MwNvmAudioLogCtrl, pMwNvmAudioCfg);
		LUAT_DEBUG_PRINT("log on");
	}

	audioLogCfg.TxBeforeVem = 1;
	audioLogCfg.TxAfterVem = 1;
	audioLogCfg.RxBeforeVem = 1;
	audioLogCfg.RxAfterVem = 1;
	audioLogCfg.RxBeforeDecoder = 1;
	audioLogCfg.TxAfterEncoder = 1;
	ShareInfoAPSetCPAudioLogCtrl(audioLogCfg);
	luat_heap_free(pMwNvmAudioCfg);
}

