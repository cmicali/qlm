#include "QLMCommands.h"

#include <math.h>
#include <string.h>

static const double QLMVolumeScale = 8388608.0; // 2^23

uint32_t QLMVolumeWordForDecibels(double decibels) {
    if (!(decibels > QLMVolumeDecibelsMin)) {
        return QLMVolumeWordMin;
    }
    if (decibels >= QLMVolumeDecibelsMax) {
        return QLMVolumeWordMax;
    }
    double word = floor(pow(10.0, decibels / 20.0) * QLMVolumeScale);
    if (word > (double)QLMVolumeWordMax) {
        return QLMVolumeWordMax;
    }
    if (word < (double)QLMVolumeWordMin) {
        return QLMVolumeWordMin;
    }
    return (uint32_t)word;
}

double QLMVolumeDecibelsForWord(uint32_t word) {
    return 20.0 * log10((double)word / QLMVolumeScale);
}

static QLMMessage QLMCommand(uint8_t address, const uint8_t *payload, size_t length) {
    QLMMessage message;
    memset(&message, 0, sizeof message);
    message.address = address;
    message.length = length;
    memcpy(message.payload, payload, length);
    return message;
}

QLMMessage QLMCommandProbe(void) {
    const uint8_t payload[] = {0xFE};
    return QLMCommand(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandAssignSession(const uint8_t hardwareID[3], uint8_t session) {
    const uint8_t payload[] = {0x02, hardwareID[0], hardwareID[1], hardwareID[2], session};
    return QLMCommand(QLMAddressMulticast, payload, sizeof payload);
}

QLMMessage QLMCommandKeepAlive(void) {
    const uint8_t payload[] = {0x04};
    return QLMCommand(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandPoll(uint8_t session) {
    const uint8_t payload[] = {0x08};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandSerialNumber(uint8_t session) {
    const uint8_t payload[] = {0x19, 0x01};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandSystemInfo(uint8_t session) {
    const uint8_t payload[] = {0x39};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandMute(uint8_t session, uint8_t value) {
    const uint8_t payload[] = {0x2B, value};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandPower(QLMPowerStep step) {
    const uint8_t payload[] = {0x3A, 0x03, (uint8_t)step};
    return QLMCommand(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandVolumeWord(uint32_t word, uint32_t ceilingWord) {
    if (ceilingWord > QLMVolumeWordMax) {
        ceilingWord = QLMVolumeWordMax;
    }
    if (word > ceilingWord) {
        word = ceilingWord;
    }
    const uint8_t payload[] = {0x1F, (uint8_t)(word >> 16), (uint8_t)(word >> 8), (uint8_t)word};
    return QLMCommand(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandVolume(double decibels, double ceilingDecibels) {
    return QLMCommandVolumeWord(QLMVolumeWordForDecibels(decibels), QLMVolumeWordForDecibels(ceilingDecibels));
}

QLMMessage QLMCommandDim(double decibels, double ceilingDecibels) {
    return QLMCommandVolume(decibels - QLMDimDecibels, ceilingDecibels);
}

QLMMessage QLMCommandDuck(void) {
    return QLMCommandVolumeWord(QLMVolumeWordDuck, QLMVolumeWordMax);
}

uint32_t QLMLevelWordForDecibels(double decibels) {
    if (decibels >= 0) {
        return QLMVolumeWordMax;
    }
    double word = round(pow(10.0, decibels / 20.0) * 8388607.0);
    return word < 0 ? 0 : (uint32_t)word;
}

QLMMessage QLMCommandPrepare(uint8_t session) {
    const uint8_t payload[] = {0x17, 0x01};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandDelay(uint8_t session, uint32_t samples) {
    const uint8_t payload[] = {0x10, 0x02, (uint8_t)(samples >> 24), (uint8_t)(samples >> 16), (uint8_t)(samples >> 8),
                               (uint8_t)samples};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandLevel(uint8_t session, uint32_t word) {
    if (word > QLMVolumeWordMax) {
        word = QLMVolumeWordMax;
    }
    const uint8_t payload[] = {0x10, 0x01, 0x00, (uint8_t)(word >> 16), (uint8_t)(word >> 8), (uint8_t)word};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandLevelUnknown(uint8_t session) {
    const uint8_t payload[] = {0x10, 0x01, 0x09, 0x00, 0x00, 0x00};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandPEQ(uint8_t session, uint8_t slot, const uint8_t coefficients[20]) {
    uint8_t payload[24] = {0x10, 0x0E, slot};
    memcpy(payload + 3, coefficients, 20);
    payload[23] = 0x00;
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandCrossover(uint8_t session, uint16_t value) {
    const uint8_t payload[] = {0x3B, (uint8_t)(value >> 8), (uint8_t)value};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandInputSync(uint8_t session) {
    const uint8_t payload[] = {0x3D, 0x00, 0x00};
    return QLMCommand(session, payload, sizeof payload);
}

QLMMessage QLMCommandRouting(uint8_t session, uint8_t inputIndex, uint8_t source, uint8_t pair, uint8_t aesChannel) {
    const uint8_t payload[] = {0x40, inputIndex, source, pair, aesChannel};
    return QLMCommand(session, payload, sizeof payload);
}
