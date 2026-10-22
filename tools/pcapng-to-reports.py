#!/usr/bin/env python3
"""Turns a USBPcap capture into qlm's reports.txt form.

Reads a pcap or pcapng file whose link type is USBPcap (249) and prints one
line per interrupt or control data transfer: seconds from the first packet,
`out` or `in`, then the bytes in hex. Everything else is skipped.

    python3 -I tools/pcapng-to-reports.py capture.pcapng > reports.txt
    python3 -I tools/pcapng-to-reports.py --self-test
"""
import struct
import sys

LINKTYPE_USBPCAP = 249

# USBPcap's packet header, packed. The direction is bit 0 of info: 1 is
# device to host. The transfer is 0 iso, 1 interrupt, 2 control, 3 bulk. A
# control transfer carries one more byte, its stage.
HEADER = struct.Struct("<HQiHBHHBBI")
HEADER_LENGTH_MIN = HEADER.size


def packets_pcap(data):
    magic = struct.unpack("<I", data[:4])[0]
    if magic in (0xA1B2C3D4, 0xA1B23C4D):
        order = "<"
    elif magic in (0xD4C3B2A1, 0x4D3CB2A1):
        order = ">"
    else:
        raise ValueError("not a pcap file")
    nanos = magic in (0xA1B23C4D, 0x4D3CB2A1)
    linktype = struct.unpack(order + "I", data[20:24])[0]
    if linktype != LINKTYPE_USBPCAP:
        raise ValueError(f"link type {linktype} is not USBPcap")
    offset = 24
    while offset + 16 <= len(data):
        seconds, fraction, captured, _ = struct.unpack(order + "IIII", data[offset:offset + 16])
        offset += 16
        yield seconds + fraction / (1e9 if nanos else 1e6), data[offset:offset + captured]
        offset += captured


def packets_pcapng(data):
    offset = 0
    order = "<"
    interfaces = []
    while offset + 12 <= len(data):
        block_type = struct.unpack(order + "I", data[offset:offset + 4])[0]
        if block_type == 0x0A0D0D0A:
            order = "<" if data[offset + 8:offset + 12] == b"\x4d\x3c\x2b\x1a" else ">"
            interfaces = []
        length = struct.unpack(order + "I", data[offset + 4:offset + 8])[0]
        if length < 12:
            raise ValueError("bad pcapng block")
        body = data[offset + 8:offset + length - 4]
        if block_type == 1:
            linktype = struct.unpack(order + "H", body[:2])[0]
            resolution = 1e-6
            option_offset = 8
            while option_offset + 4 <= len(body):
                code, option_length = struct.unpack(order + "HH", body[option_offset:option_offset + 4])
                if code == 0:
                    break
                if code == 9 and option_length == 1:
                    value = body[option_offset + 4]
                    resolution = 2.0 ** -(value & 0x7F) if value & 0x80 else 10.0 ** -(value & 0x7F)
                option_offset += 4 + ((option_length + 3) & ~3)
            interfaces.append((linktype, resolution))
        elif block_type == 6:
            interface, high, low, captured, _ = struct.unpack(order + "IIIII", body[:20])
            linktype, resolution = interfaces[interface]
            if linktype == LINKTYPE_USBPCAP:
                yield ((high << 32) | low) * resolution, body[20:20 + captured]
        offset += length


def packets(data):
    if data[:4] == b"\x0a\x0d\x0d\x0a":
        return packets_pcapng(data)
    return packets_pcap(data)


def reports(data):
    """Yields (seconds, direction, bytes) for each transfer that carries data."""
    first = None
    for timestamp, packet in packets(data):
        if len(packet) < HEADER_LENGTH_MIN:
            continue
        header_length, _, _, _, info, _, _, _, transfer, data_length = HEADER.unpack(packet[:HEADER_LENGTH_MIN])
        if transfer not in (1, 2):
            continue
        payload = packet[header_length:header_length + data_length]
        if transfer == 2:
            stage = packet[HEADER_LENGTH_MIN] if header_length > HEADER_LENGTH_MIN else None
            # Stage 0 is the setup packet, followed by the data on an OUT transfer.
            if stage == 0:
                payload = payload[8:]
            elif stage != 1:
                continue
        if not payload:
            continue
        if first is None:
            first = timestamp
        yield timestamp - first, "in" if info & 1 else "out", payload


def convert(data, source):
    lines = [f"# qlm USB capture, converted from {source}", "# seconds direction bytes"]
    for seconds, direction, payload in reports(data):
        lines.append(f"{seconds:.6f} {direction} {payload.hex(' ').upper()}")
    return "\n".join(lines) + "\n"


def synthetic_pcapng():
    """A pcapng with one OUT interrupt report and one IN interrupt report."""
    def block(block_type, body):
        length = 12 + len(body)
        return struct.pack("<II", block_type, length) + body + struct.pack("<I", length)

    shb = block(0x0A0D0D0A, struct.pack("<IHHq", 0x1A2B3C4D, 1, 0, -1))
    idb = block(1, struct.pack("<HHI", LINKTYPE_USBPCAP, 0, 0) + struct.pack("<HHBxxx", 9, 1, 6) + struct.pack("<HH", 0, 0))

    def usb(info, endpoint, transfer, payload, stage=None):
        extra = b"" if stage is None else bytes([stage])
        header = HEADER.pack(HEADER_LENGTH_MIN + len(extra), 1, 0, 9, info, 1, 2, endpoint, transfer, len(payload))
        return header + extra + payload

    def epb(micros, packet):
        padded = packet + b"\0" * (-len(packet) % 4)
        return block(6, struct.pack("<IIIII", 0, micros >> 32, micros & 0xFFFFFFFF, len(packet), len(packet)) + padded)

    out = usb(0, 0x01, 1, bytes([0x80, 0x05, 0xFF, 0x04, 0xBC, 0x84, 0x7E]))
    reply = usb(1, 0x81, 1, bytes([0x63, 0x01, 0x09, 0x5D, 0xE7, 0x7E]))
    setup = usb(0, 0x00, 2, bytes(8) + bytes([0x80, 0x01, 0xFE]), stage=0)
    status = usb(1, 0x80, 2, b"", stage=2)
    return shb + idb + epb(1_000_000, out) + epb(1_000_500, reply) + epb(1_002_000, setup) + epb(1_002_100, status)


def self_test():
    text = convert(synthetic_pcapng(), "self-test")
    expected = (
        "# qlm USB capture, converted from self-test\n"
        "# seconds direction bytes\n"
        "0.000000 out 80 05 FF 04 BC 84 7E\n"
        "0.000500 in 63 01 09 5D E7 7E\n"
        "0.002000 out 80 01 FE\n"
    )
    if text != expected:
        sys.stderr.write("self-test failed\n--- got\n" + text + "--- expected\n" + expected)
        return 1
    print("self-test passed")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1], "rb") as handle:
        data = handle.read()
    sys.stdout.write(convert(data, argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
