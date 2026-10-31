#ifndef QLMFRAME_H
#define QLMFRAME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The bus addresses. The host broadcasts on FF, the adapter alone multicasts
// on F0, every monitor replies from 01, and a leased session ID runs 02 to FE.
// The host reaches the adapter itself at 01.
enum {
    QLMAddressReply = 0x01,
    QLMAddressAdapter = 0x01,
    QLMAddressSessionFirst = 0x02,
    QLMAddressSessionLast = 0xFE,
    QLMAddressMulticast = 0xF0,
    QLMAddressBroadcast = 0xFF,
};

// True for a session ID qlm may lease. F0 is the adapter's multicast, and
// the encoder refuses an address of 7D or 7E.
bool QLMAddressIsLeasable(uint8_t address);

enum {
    QLMFrameFlag = 0x7E,
    QLMFrameEscape = 0x7D,
    QLMFrameEscapeXor = 0x20,
};

// Room for the longest reply the adapter can deliver: a frame of three input
// reports, less the address, the CRC, and the flag. A monitor's system info
// runs 66 bytes. What qlm sends must fit one output report; QLMReport.h has
// that limit.
#define QLMPayloadMax 185
// Address, payload, and CRC with every byte escaped, then the flag.
#define QLMFrameMax (2 * (1 + QLMPayloadMax + 2) + 1)

typedef struct {
    uint8_t address;
    size_t length;
    uint8_t payload[QLMPayloadMax];
} QLMMessage;

// A message to `address` with a copy of the payload, cut at QLMPayloadMax.
QLMMessage QLMMessageMake(uint8_t address, const uint8_t *payload, size_t length);

typedef enum {
    QLMFrameOK = 0,
    QLMFrameErrorLength,
    QLMFrameErrorForbidden,
    QLMFrameErrorFlag,
    QLMFrameErrorEscape,
    QLMFrameErrorCRC,
} QLMFrameStatus;

// The safety allowlist. True only for a payload qlm may send. A monitor's
// flash commit (15), the test signals (05), the standalone settings
// (3A 01, 3A 02, 3A 06), and the startup level (10 01 05) are never allowed.
// Of 2D, only 2D 00 is, and the encoder sends it only as a broadcast. Of 3C,
// 3E, and 42, only a payload of 00 00 is, of 43 only 43 00 02, and of 4B
// only 4B 00 00 00 01. The encoder sends each of those only to a session.
bool QLMFrameAllows(const uint8_t *payload, size_t length);

// Encodes a message as one bus frame: the address, the payload, the CRC
// big-endian, then the flag, with 7E and 7D in the payload and CRC escaped
// after the CRC is computed. Refuses a payload the allowlist rejects, an
// address of 7D or 7E, a 2D to any address but the broadcast, and a 3C, 3E,
// 42, 43, or 4B to any address but a session.
QLMFrameStatus QLMFrameEncode(const QLMMessage *message, uint8_t *out, size_t capacity, size_t *outLength);

// Decodes one complete frame, which must end in the flag. It does not consult
// the allowlist, so captured frames of every opcode decode.
QLMFrameStatus QLMFrameDecode(const uint8_t *bytes, size_t length, QLMMessage *message);

#endif
