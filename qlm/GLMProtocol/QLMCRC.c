#include "QLMCRC.h"

uint16_t QLMCRC16GSM(const uint8_t *bytes, size_t length) {
    uint16_t crc = 0;
    for (size_t i = 0; i < length; i++) {
        crc = (uint16_t)(crc ^ (bytes[i] << 8));
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return (uint16_t)(crc ^ 0xFFFF);
}
