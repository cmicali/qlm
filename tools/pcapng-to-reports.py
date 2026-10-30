#!/usr/bin/env python3
"""Turns a USB capture into qlm's reports.txt form.

Reads a pcap or pcapng file whose link type is USBPcap (249) or Linux usbmon
(220, or 189 without the mmapped tail). It prints one line per HID report:
seconds from the first packet, `out` or `in`, then the bytes in hex. Reports
come from interrupt transfers, HID SET_REPORT Output, and HID GET_REPORT
Input. Every other control transfer becomes a `#` line with its setup packet
and data. Everything else is skipped.

    python3 -I tools/pcapng-to-reports.py capture.pcapng > reports.txt
    python3 -I tools/pcapng-to-reports.py --device 1:5 capture.pcap > reports.txt
    python3 -I tools/pcapng-to-reports.py --self-test

--device BUS:DEV keeps one device's traffic, in decimal as lsusb prints it.
Repeat it to keep more than one, as when an unplugged adapter comes back at
a new number. Without it, a capture of more than one device converts with a
warning.
"""
import argparse
import struct
import sys

LINKTYPE_USB_LINUX = 189
LINKTYPE_USB_LINUX_MMAPPED = 220
LINKTYPE_USBPCAP = 249
LINKTYPES = (LINKTYPE_USB_LINUX, LINKTYPE_USB_LINUX_MMAPPED, LINKTYPE_USBPCAP)

INTERRUPT = 1
CONTROL = 2

# USBPcap's packet header, packed. The direction is bit 0 of info: 1 is
# device to host. The transfer is 0 iso, 1 interrupt, 2 control, 3 bulk. A
# control transfer carries one more byte, its stage.
HEADER = struct.Struct("<HQiHBHHBBI")
HEADER_LENGTH_MIN = HEADER.size

# usbmon's packet header: pcap_usb_header in libpcap's pcap/usb.h, and struct
# usbmon_packet in the kernel's Documentation/usb/usbmon.rst. It is id, event,
# transfer, endpoint, devnum, busnum, flag_setup, flag_data, ts_sec, ts_usec,
# status, length, len_cap, and setup. Link type 220 adds 16 bytes. The data
# follows the header. A zero flag means the setup or the data is present.
# TRAP: usbmon writes the host's byte order. Like libpcap, take the file's.
USBMON_FORMAT = "QBBBBHBBqiiII8s"
USBMON_LENGTH = {LINKTYPE_USB_LINUX: 48, LINKTYPE_USB_LINUX_MMAPPED: 64}

# HID class requests, from the HID spec, section 7.2.
SET_REPORT = (0x21, 0x09)
GET_REPORT = (0xA1, 0x01)
REPORT_INPUT = 1
REPORT_OUTPUT = 2


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
    if linktype not in LINKTYPES:
        raise ValueError(f"link type {linktype} is not USBPcap or usbmon")
    offset = 24
    while offset + 16 <= len(data):
        seconds, fraction, captured, _ = struct.unpack(order + "IIII", data[offset:offset + 16])
        offset += 16
        yield seconds + fraction / (1e9 if nanos else 1e6), linktype, order, data[offset:offset + captured]
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
            if linktype in LINKTYPES:
                yield ((high << 32) | low) * resolution, linktype, order, body[20:20 + captured]
        offset += length


def packets(data):
    if data[:4] == b"\x0a\x0d\x0d\x0a":
        return packets_pcapng(data)
    return packets_pcap(data)


def events(data, counts):
    """Yields (timestamp, device, key, completion, transfer, endpoint, setup, payload).

    Counts every packet per (bus, device) into counts.
    """
    for timestamp, linktype, order, packet in packets(data):
        if linktype == LINKTYPE_USBPCAP:
            if len(packet) < HEADER_LENGTH_MIN:
                continue
            header_length, irp, _, _, info, bus, address, endpoint, transfer, data_length = HEADER.unpack(packet[:HEADER_LENGTH_MIN])
            device = (bus, address)
            counts[device] = counts.get(device, 0) + 1
            key, completion, setup = (bus, irp), bool(info & 1), None
            payload = packet[header_length:header_length + data_length]
            if transfer == CONTROL:
                stage = packet[HEADER_LENGTH_MIN] if header_length > HEADER_LENGTH_MIN else None
                # Stage 0 is the setup packet, followed by the data on an OUT transfer.
                if stage == 0:
                    setup, payload = payload[:8], payload[8:]
                elif stage not in (1, 2, 3):
                    continue
        else:
            length = USBMON_LENGTH[linktype]
            if len(packet) < length:
                continue
            urb, event, transfer, endpoint, address, bus, flag_setup, flag_data, _, _, _, _, captured, setup = struct.unpack(order + USBMON_FORMAT, packet[:48])
            device = (bus, address)
            counts[device] = counts.get(device, 0) + 1
            if event not in (ord("S"), ord("C")):
                continue
            key, completion = (bus, urb), event == ord("C")
            payload = packet[length:length + captured] if flag_data == 0 else b""
            if transfer != CONTROL or completion or flag_setup != 0:
                setup = None
        yield timestamp, device, key, completion, transfer, endpoint, setup, payload


def control(setup, payload):
    """Returns (direction, payload, setup), with setup None for a HID report."""
    request = (setup[0], setup[1])
    report_type = setup[3]
    if payload and request == SET_REPORT and report_type == REPORT_OUTPUT:
        return "out", payload, None
    if payload and request == GET_REPORT and report_type == REPORT_INPUT:
        return "in", payload, None
    return "in" if setup[0] & 0x80 else "out", payload, setup


def reports(data, devices=None, counts=None):
    """Yields (seconds, direction, bytes, setup) for each transfer kept.

    Setup is None for a HID report and the setup packet for any other control
    transfer.
    """
    counts = {} if counts is None else counts
    first = None
    pending = {}
    for timestamp, seen, key, completion, transfer, endpoint, setup, payload in events(data, counts):
        if devices is not None and seen not in devices:
            continue
        if first is None:
            first = timestamp
        seconds = timestamp - first
        if transfer == INTERRUPT:
            # OUT data rides the submission, and IN data the completion.
            if payload and completion == bool(endpoint & 0x80):
                yield seconds, "in" if completion else "out", payload, None
        elif transfer == CONTROL:
            if setup is not None:
                # An IN transfer waits for its completion. USBPcap may send
                # OUT data in a stage of its own.
                wanted = struct.unpack("<H", setup[6:8])[0]
                if setup[0] & 0x80 or (wanted and not payload):
                    pending[key] = setup
                    continue
            elif key in pending and (completion or not pending[key][0] & 0x80):
                setup = pending.pop(key)
            else:
                continue
            yield (seconds, *control(setup, payload))


def convert(data, source, devices=None, warn=sys.stderr.write):
    lines = [f"# qlm USB capture, converted from {source}"]
    if devices is not None:
        lines.append("# device " + " ".join(f"{bus}:{address}" for bus, address in devices))
    lines.append("# seconds direction bytes")
    counts = {}
    for seconds, direction, payload, setup in reports(data, devices, counts):
        if setup is None:
            lines.append(f"{seconds:.6f} {direction} {payload.hex(' ').upper()}")
        else:
            line = f"# {seconds:.6f} {direction} control {setup.hex(' ').upper()}"
            lines.append(line + (f" data {payload.hex(' ').upper()}" if payload else ""))
    if devices is None and len(counts) > 1:
        seen = "".join(f"  {bus}:{address} {count} packets\n" for (bus, address), count in sorted(counts.items()))
        warn("warning: the capture holds more than one device; pick one with --device\n" + seen)
    return "\n".join(lines) + "\n"


def pcapng(linktype, records):
    """A pcapng of (micros, packet) records on one interface."""
    def block(block_type, body):
        length = 12 + len(body)
        return struct.pack("<II", block_type, length) + body + struct.pack("<I", length)

    def epb(micros, packet):
        padded = packet + b"\0" * (-len(packet) % 4)
        return block(6, struct.pack("<IIIII", 0, micros >> 32, micros & 0xFFFFFFFF, len(packet), len(packet)) + padded)

    shb = block(0x0A0D0D0A, struct.pack("<IHHq", 0x1A2B3C4D, 1, 0, -1))
    idb = block(1, struct.pack("<HHI", linktype, 0, 0) + struct.pack("<HHBxxx", 9, 1, 6) + struct.pack("<HH", 0, 0))
    return shb + idb + b"".join(epb(micros, packet) for micros, packet in records)


def pcap(linktype, records):
    """A pcap of (micros, packet) records."""
    header = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, linktype)
    return header + b"".join(
        struct.pack("<IIII", micros // 1_000_000, micros % 1_000_000, len(packet), len(packet)) + packet
        for micros, packet in records)


def synthetic_usbpcap():
    """A pcapng with one OUT interrupt report, one IN interrupt report, and one SET_REPORT."""
    def usb(info, endpoint, transfer, payload, stage=None):
        extra = b"" if stage is None else bytes([stage])
        header = HEADER.pack(HEADER_LENGTH_MIN + len(extra), 1, 0, 9, info, 1, 2, endpoint, transfer, len(payload))
        return header + extra + payload

    out = usb(0, 0x01, 1, bytes([0x80, 0x05, 0xFF, 0x04, 0xBC, 0x84, 0x7E]))
    reply = usb(1, 0x81, 1, bytes([0x63, 0x01, 0x09, 0x5D, 0xE7, 0x7E]))
    setup = usb(0, 0x00, 2, bytes([0x21, 0x09, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00, 0x80, 0x01, 0xFE]), stage=0)
    status = usb(1, 0x80, 2, b"", stage=2)
    return pcapng(LINKTYPE_USBPCAP, [(1_000_000, out), (1_000_500, reply), (1_002_000, setup), (1_002_100, status)])


def synthetic_usbmon(linktype):
    """usbmon records for the adapter at 1:5, and one for the hub at 1:1."""
    def usb(micros, urb, event, transfer, endpoint, payload=b"", setup=None, address=5):
        flag_setup = 0 if setup is not None else ord("-")
        flag_data = 0 if payload else ord("<" if event == "S" else ">")
        header = struct.pack("<" + USBMON_FORMAT, urb, ord(event), transfer, endpoint, address, 1,
                             flag_setup, flag_data, micros // 1_000_000, micros % 1_000_000, 0,
                             len(payload), len(payload), setup or bytes(8))
        return micros, header + bytes(USBMON_LENGTH[linktype] - 48) + payload

    return [
        usb(10_000_000, 0xA, "S", 2, 0x80, setup=bytes([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])),
        usb(10_000_200, 0xA, "C", 2, 0x80, bytes([0x12, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x40])),
        usb(10_001_000, 0xF, "C", 1, 0x81, bytes([0x02]), address=1),
        usb(10_002_000, 0xB, "S", 1, 0x01, bytes([0x80, 0x05, 0xFF, 0x04, 0xBC, 0x84, 0x7E])),
        usb(10_002_100, 0xB, "C", 1, 0x01),
        usb(10_002_500, 0xC, "S", 1, 0x81),
        usb(10_002_600, 0xC, "C", 1, 0x81, bytes([0x63, 0x01, 0x09, 0x5D, 0xE7, 0x7E])),
        usb(10_003_000, 0xD, "S", 2, 0x00, bytes([0x80, 0x01, 0xFE]),
            setup=bytes([0x21, 0x09, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00])),
        usb(10_003_100, 0xD, "C", 2, 0x00),
        usb(10_004_000, 0xE, "S", 2, 0x80, setup=bytes([0xA1, 0x01, 0x00, 0x03, 0x00, 0x00, 0x01, 0x00])),
        usb(10_004_100, 0xE, "C", 2, 0x80, bytes([0x07])),
        usb(10_005_000, 0x10, "E", 1, 0x01, bytes([0x80, 0x00])),
    ]


def self_test():
    failures = []

    def check(name, got, expected):
        if got != expected:
            failures.append(f"self-test failed: {name}\n--- got\n{got}--- expected\n{expected}")

    warnings = []
    check("usbpcap", convert(synthetic_usbpcap(), "self-test", warn=warnings.append), (
        "# qlm USB capture, converted from self-test\n"
        "# seconds direction bytes\n"
        "0.000000 out 80 05 FF 04 BC 84 7E\n"
        "0.000500 in 63 01 09 5D E7 7E\n"
        "0.002000 out 80 01 FE\n"
    ))
    check("usbpcap warning", "".join(warnings), "")

    adapter = (
        "# 0.000200 in control 80 06 00 01 00 00 12 00 data 12 01 00 02 00 00 00 40\n"
        "0.002000 out 80 05 FF 04 BC 84 7E\n"
        "0.002600 in 63 01 09 5D E7 7E\n"
        "0.003000 out 80 01 FE\n"
        "# 0.004100 in control A1 01 00 03 00 00 01 00 data 07\n"
    )
    captures = [
        ("usbmon pcap", pcap(LINKTYPE_USB_LINUX_MMAPPED, synthetic_usbmon(LINKTYPE_USB_LINUX_MMAPPED))),
        ("usbmon pcapng", pcapng(LINKTYPE_USB_LINUX, synthetic_usbmon(LINKTYPE_USB_LINUX))),
    ]
    for name, capture in captures:
        warnings = []
        check(name + " --device", convert(capture, "self-test", [(1, 5)], warnings.append), (
            "# qlm USB capture, converted from self-test\n"
            "# device 1:5\n"
            "# seconds direction bytes\n" + adapter
        ))
        check(name + " --device warning", "".join(warnings), "")
        lines = adapter.splitlines(keepends=True)
        check(name + " --device twice", convert(capture, "self-test", [(1, 5), (1, 1)], warnings.append), (
            "# qlm USB capture, converted from self-test\n"
            "# device 1:5 1:1\n"
            "# seconds direction bytes\n" + lines[0] + "0.001000 in 02\n" + "".join(lines[1:])
        ))
        check(name + " --device twice warning", "".join(warnings), "")
        warnings = []
        check(name, convert(capture, "self-test", warn=warnings.append), (
            "# qlm USB capture, converted from self-test\n"
            "# seconds direction bytes\n" + lines[0] + "0.001000 in 02\n" + "".join(lines[1:])
        ))
        check(name + " warning", "".join(warnings), (
            "warning: the capture holds more than one device; pick one with --device\n"
            "  1:1 1 packets\n"
            "  1:5 11 packets\n"
        ))

    if failures:
        sys.stderr.write("\n".join(failures))
        return 1
    print("self-test passed")
    return 0


def parse_device(text):
    bus, _, address = text.partition(":")
    if not (bus.isdigit() and address.isdigit()):
        raise argparse.ArgumentTypeError("expected BUS:DEV, in decimal")
    return int(bus), int(address)


def main(argv):
    parser = argparse.ArgumentParser(usage=__doc__, add_help=False)
    parser.add_argument("capture", nargs="?")
    parser.add_argument("--device", type=parse_device, action="append")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv[1:])
    if args.self_test and args.capture is None and args.device is None:
        return self_test()
    if args.self_test or args.capture is None:
        sys.stderr.write(__doc__)
        return 2
    with open(args.capture, "rb") as handle:
        data = handle.read()
    sys.stdout.write(convert(data, args.capture, args.device))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
