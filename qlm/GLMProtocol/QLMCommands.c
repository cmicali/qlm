#include "QLMCommands.h"

#include <math.h>
#include <string.h>

// GLM's word for each step, from 0 dB down.
// TRAP: keep the table. floor(10^(dB/20) * 7FFFFF) misses four of these by
// one count, and 2^23 in its place misses ten.
static const uint32_t QLMVolumeWords[] = {
    0x7FFFFF, 0x78D6FB, 0x721481, 0x6BB2D5, 0x65AC8B, 0x5FFC88, 0x5A9DF7, 0x558C4A,
    0x50C335, 0x4C3EA7, 0x47FACC, 0x43F405, 0x4026E6, 0x3C9038, 0x392CED, 0x35FA26,
    0x32F52C, 0x301B70, 0x2D6A86, 0x2AE025, 0x287A26, 0x263680, 0x241346, 0x220EA9,
    0x2026F2, 0x1E5A84, 0x1CA7D7, 0x1B0D7A, 0x198A13, 0x181C57, 0x16C310, 0x157D1A,
    0x144960, 0x1326DD, 0x12149A, 0x1111AE, 0x101D3F, 0x0F367B, 0x0E5CA1, 0x0D8EF6,
    0x0CCCCC, 0x0C157F, 0x0B6873, 0x0AC515, 0x0A2ADA, 0x099940, 0x090FCB, 0x088E07,
    0x081385, 0x079FDD, 0x0732AE, 0x06CB9A, 0x066A4A, 0x060E6B, 0x05B7B1, 0x0565D0,
    0x051884, 0x04CF8B, 0x048AA7, 0x04499D, 0x040C37, 0x03D240, 0x039B87, 0x0367DD,
    0x033718, 0x03090D, 0x02DD95, 0x02B48C, 0x028DCE, 0x02693B, 0x0246B4, 0x02261C,
    0x020756, 0x01EA49, 0x01CEDC, 0x01B4F7, 0x019C86, 0x018572, 0x016FA9, 0x015B18,
    0x0147AE, 0x013559, 0x01240B, 0x0113B5, 0x010449, 0x00F5B9, 0x00E7FA, 0x00DB00,
    0x00CEC0, 0x00C32F, 0x00B844, 0x00ADF5, 0x00A43A, 0x009B0A, 0x00925E, 0x008A2E,
    0x008273, 0x007B27, 0x007443, 0x006DC2, 0x00679F, 0x0061D3, 0x005C5A, 0x00572F,
    0x00524F, 0x004DB4, 0x00495B, 0x004541, 0x004161, 0x003DB9, 0x003A45, 0x003702,
    0x0033EF, 0x003107, 0x002E49, 0x002BB2, 0x002940, 0x0026F1, 0x0024C4, 0x0022B5,
    0x0020C4, 0x001EEF, 0x001D34, 0x001B92, 0x001A07, 0x001892, 0x001732, 0x0015E6,
    0x0014AC, 0x001384, 0x00126D, 0x001165, 0x00106C, 0x000F81, 0x000EA3, 0x000DD1,
    0x000D0B, 0x000C50, 0x000BA0, 0x000AF9, 0x000A5C, 0x0009C8, 0x00093C, 0x0008B7,
    0x00083B, 0x0007C5, 0x000755, 0x0006EC, 0x000689, 0x00062C, 0x0005D3, 0x000580,
    0x000531, 0x0004E7, 0x0004A0, 0x00045E, 0x000420, 0x0003E4, 0x0003AD, 0x000378,
    0x000346, 0x000317, 0x0002EB, 0x0002C1, 0x00029A, 0x000275, 0x000251, 0x000230,
    0x000211, 0x0001F3, 0x0001D7, 0x0001BD, 0x0001A4, 0x00018C, 0x000176, 0x000161,
    0x00014D, 0x00013B, 0x000129, 0x000118, 0x000109, 0x0000FA, 0x0000EC, 0x0000DF,
    0x0000D2, 0x0000C6, 0x0000BB, 0x0000B1, 0x0000A7, 0x00009E, 0x000095, 0x00008C,
    0x000084, 0x00007D, 0x000076, 0x00006F, 0x000069, 0x000063, 0x00005E, 0x000058,
};
#define QLMVolumeStepCount (sizeof QLMVolumeWords / sizeof QLMVolumeWords[0])

// `step` counts steps down from 0 dB: a whole number, an infinity, or NaN.
// Past the table is the bottom stop.
static uint32_t QLMVolumeWordForStep(double step) {
    if (!(step < (double)QLMVolumeStepCount)) {
        return QLMVolumeWordMin;
    }
    return QLMVolumeWords[step > 0 ? (size_t)step : 0];
}

static double QLMVolumeStepNearest(double decibels) {
    return round(-decibels / QLMVolumeDecibelsStep);
}

static double QLMVolumeStepAtOrBelow(double decibels) {
    return ceil(-decibels / QLMVolumeDecibelsStep);
}

uint32_t QLMVolumeWordForDecibels(double decibels) {
    return QLMVolumeWordForStep(QLMVolumeStepNearest(decibels));
}

double QLMVolumeDecibelsForWord(uint32_t word) {
    return 20.0 * log10((double)word / (double)QLMVolumeWordMax);
}

QLMMessage QLMCommandProbe(void) {
    const uint8_t payload[] = {0xFE};
    return QLMMessageMake(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandAssignSession(const uint8_t hardwareID[3], uint8_t session) {
    const uint8_t payload[] = {0x02, hardwareID[0], hardwareID[1], hardwareID[2], session};
    return QLMMessageMake(QLMAddressMulticast, payload, sizeof payload);
}

QLMMessage QLMCommandKeepAlive(void) {
    const uint8_t payload[] = {0x04};
    return QLMMessageMake(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandPoll(uint8_t session) {
    const uint8_t payload[] = {0x08};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandSerialNumber(uint8_t session) {
    const uint8_t payload[] = {0x19, 0x01};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandSystemInfo(uint8_t session) {
    const uint8_t payload[] = {0x39};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandMute(uint8_t session, uint8_t value) {
    const uint8_t payload[] = {0x2B, value};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandPower(QLMPowerStep step) {
    const uint8_t payload[] = {0x3A, 0x03, (uint8_t)step};
    return QLMMessageMake(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandVolumeWord(uint32_t word, uint32_t ceilingWord) {
    if (ceilingWord > QLMVolumeWordMax) {
        ceilingWord = QLMVolumeWordMax;
    }
    if (word > ceilingWord) {
        word = ceilingWord;
    }
    const uint8_t payload[] = {0x1F, (uint8_t)(word >> 16), (uint8_t)(word >> 8), (uint8_t)word};
    return QLMMessageMake(QLMAddressBroadcast, payload, sizeof payload);
}

QLMMessage QLMCommandVolume(double decibels, double ceilingDecibels) {
    uint32_t ceilingWord = QLMVolumeWordForStep(QLMVolumeStepAtOrBelow(ceilingDecibels));
    return QLMCommandVolumeWord(QLMVolumeWordForDecibels(decibels), ceilingWord);
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
    double word = round(pow(10.0, decibels / 20.0) * (double)QLMVolumeWordMax);
    return word < 0 ? 0 : (uint32_t)word;
}

QLMMessage QLMCommandPrepare(uint8_t session) {
    const uint8_t payload[] = {0x17, 0x01};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandDelay(uint8_t session, uint32_t samples) {
    const uint8_t payload[] = {0x10, 0x02, (uint8_t)(samples >> 24), (uint8_t)(samples >> 16), (uint8_t)(samples >> 8),
                               (uint8_t)samples};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandLevel(uint8_t session, uint32_t word) {
    if (word > QLMVolumeWordMax) {
        word = QLMVolumeWordMax;
    }
    const uint8_t payload[] = {0x10, 0x01, 0x00, (uint8_t)(word >> 16), (uint8_t)(word >> 8), (uint8_t)word};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandLevelUnknown(uint8_t session) {
    const uint8_t payload[] = {0x10, 0x01, 0x09, 0x00, 0x00, 0x00};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandPEQ(uint8_t session, uint8_t slot, const uint8_t coefficients[20]) {
    uint8_t payload[24] = {0x10, 0x0E, slot};
    memcpy(payload + 3, coefficients, 20);
    payload[23] = 0x00;
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandCrossover(uint8_t session, uint16_t value) {
    const uint8_t payload[] = {0x3B, (uint8_t)(value >> 8), (uint8_t)value};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandInputSync(uint8_t session) {
    const uint8_t payload[] = {0x3D, 0x00, 0x00};
    return QLMMessageMake(session, payload, sizeof payload);
}

QLMMessage QLMCommandRouting(uint8_t session, uint8_t inputIndex, uint8_t source, uint8_t pair, uint8_t aesChannel) {
    const uint8_t payload[] = {0x40, inputIndex, source, pair, aesChannel};
    return QLMMessageMake(session, payload, sizeof payload);
}
