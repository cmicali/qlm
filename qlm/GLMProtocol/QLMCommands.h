#ifndef QLMCOMMANDS_H
#define QLMCOMMANDS_H

#include <stdbool.h>
#include <stdint.h>

#include "QLMFrame.h"

// A volume word is 24-bit linear gain, floor(10^(dB/20) * 2^23), clipped at
// 0 dB. GLM's slider stops at -120.4 dB. The two words below it are not
// volumes: 2 is the duck under a group apply, and 0 is a hard mute.
enum {
    QLMVolumeWordMax = 0x7FFFFF,
    QLMVolumeWordMin = 0x000008,
    QLMVolumeWordDuck = 0x000002,
    QLMVolumeWordMute = 0x000000,
};
#define QLMVolumeDecibelsMin (-120.4)
#define QLMVolumeDecibelsMax (0.0)
#define QLMDimDecibels (20.0)

// Clamps to [QLMVolumeDecibelsMin, QLMVolumeDecibelsMax] before converting.
uint32_t QLMVolumeWordForDecibels(double decibels);
// The inverse, for display. Word 0 gives -INFINITY.
double QLMVolumeDecibelsForWord(uint32_t word);

// The values GLM sends on 2B: bit 0 is mute, bits 1 and 2 pick the LED color.
enum {
    QLMMuteValueMuted = 0x03,
    QLMMuteValueUnmuted = 0x04,
    QLMMuteValueLEDOff = 0x08,
};

// The subcommands of 3A 03. Sleep is prepare twice, then off twice. Wake is
// the first and second steps three times.
typedef enum {
    QLMPowerStepPowerOff = 0x00,
    QLMPowerStepWakeSecond = 0x01,
    QLMPowerStepStandbyPrepare = 0x02,
    QLMPowerStepWakeFirst = 0x7F,
} QLMPowerStep;

// Builders. Each returns a message the allowlist accepts.
QLMMessage QLMCommandProbe(void);
QLMMessage QLMCommandAssignSession(const uint8_t hardwareID[3], uint8_t session);
QLMMessage QLMCommandKeepAlive(void);
QLMMessage QLMCommandPoll(uint8_t session);
QLMMessage QLMCommandSerialNumber(uint8_t session);
QLMMessage QLMCommandSystemInfo(uint8_t session);
QLMMessage QLMCommandMute(uint8_t session, uint8_t value);
QLMMessage QLMCommandPower(QLMPowerStep step);

// Every volume frame passes through QLMCommandVolumeWord, which caps the word
// at the ceiling. The ceiling is the user's, at most QLMVolumeWordMax.
QLMMessage QLMCommandVolumeWord(uint32_t word, uint32_t ceilingWord);
QLMMessage QLMCommandVolume(double decibels, double ceilingDecibels);
// Dim is a plain volume frame QLMDimDecibels down, floored at the slider's minimum.
QLMMessage QLMCommandDim(double decibels, double ceilingDecibels);
QLMMessage QLMCommandDuck(void);

#endif
