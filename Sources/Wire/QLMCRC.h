#ifndef QLMCRC_H
#define QLMCRC_H

#include <stddef.h>
#include <stdint.h>

// CRC-16/GSM: polynomial 0x1021, initial value 0, no reflection, output XOR
// 0xFFFF. A bus frame carries it big-endian, computed over the unescaped
// address and payload bytes.
uint16_t QLMCRC16GSM(const uint8_t *bytes, size_t length);

#endif
