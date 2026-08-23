#ifndef LUAT_AUDIO_DSP_SPEEXDSP_CONFIG_H
#define LUAT_AUDIO_DSP_SPEEXDSP_CONFIG_H

/* PC simulator SpeexDSP build configuration: use fixed-point arithmetic.
   FIXED_POINT is selected here to stay compatible with the OPUS codec,
   which globally defines FIXED_POINT=1 in this xmake project. */
#define FIXED_POINT    1
#define HAVE_STDINT_H  1

/* Use KISS FFT implementation inside SpeexDSP */
#define USE_KISS_FFT   1

/* The LuatOS project also pulls in Windows headers that may #define EXPORT
   to __declspec(dllexport) or similar. SpeexDSP expects EXPORT to be empty
   for a static build, so make sure it is cleared before the resampler code
   sees it. */
#undef EXPORT
#define EXPORT

#include "luat_audio_dsp_speexdsp_config_types.h"

#endif /* LUAT_AUDIO_DSP_SPEEXDSP_CONFIG_H */
