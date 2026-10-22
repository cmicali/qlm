#!/usr/bin/env python3
"""Copies a GLM 5 setup file with every identifying value replaced.

Serial numbers, and the fields that refer to them, map to a made-up series
so the links between them survive. Barcodes and session IDs are blanked.
Everything else, the structure included, is kept. CRLF line endings stay.

    python3 -I tools/redact-setup.py Main.sam > Tests/Setups/Fixtures/Main.sam
"""
import sys

SERIAL_KEYS = {"Serial", "WooferSystemWithSerial", "PhaseCalibratedWith", "MicrophoneSerial",
               "Group_Microphone_Serial", "hpoutSn"}
BLANK_KEYS = {"Barcode": "REDACTED", "Session_ID": "redacted"}


def redact(text):
    serials = {}
    out = []
    for line in text.split("\n"):
        body = line.rstrip("\r")
        ending = line[len(body):]
        key, sep, value = body.partition(":")
        if sep and key in SERIAL_KEYS:
            stripped = value.strip()
            if stripped.isdigit() and int(stripped) != 0:
                if stripped not in serials:
                    serials[stripped] = str(1000001 + len(serials))
                value = serials[stripped]
            body = f"{key}:{value}"
        elif sep and key in BLANK_KEYS:
            body = f"{key}:{BLANK_KEYS[key]}"
        out.append(body + ending)
    return "\n".join(out)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1], "rb") as handle:
        text = handle.read().decode("utf-8")
    sys.stdout.write(redact(text))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
