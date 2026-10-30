#!/usr/bin/env python3
"""Compares two REW measurements over a band, for Phase 3's measurement.

Reads two files from REW's File > Export > Export measurement as text. A line
starting with `*` is a comment. Each data line holds the frequency in Hz, the
SPL in dB, and the phase in degrees, split by spaces, tabs, commas, or
semicolons. The phase is ignored. A line that starts with no number, such as
`Freq(Hz) SPL(dB) Phase(degrees)`, is a header.

It compares the SPL at every frequency either file has inside the band, and
the band's edges. A file is interpolated linearly in dB over log frequency
between its own points. It prints the largest difference, second minus
first, and the mean. It exits 0 when the largest is within the limit, 1 when
it is above, and 2 when the files cannot be compared.

    python3 -I tools/compare-measurements.py glm-L.txt qlm-L.txt
    python3 -I tools/compare-measurements.py --band 20 20000 --limit 0.2 glm-L.txt qlm-L.txt
    python3 -I tools/compare-measurements.py --table glm-L.txt qlm-L.txt
    python3 -I tools/compare-measurements.py --self-test

docs/measurement.md says how to make the files. tools/measurement-example/
holds a synthetic pair.
"""
import argparse
import bisect
import contextlib
import io
import math
import os
import re
import sys

BAND = (20.0, 20000.0)
LIMIT = 0.2
EXAMPLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "measurement-example")

SPLIT = re.compile(r"[\s,;]+")
# The differences come from SPL values with three decimals. Without this,
# 80.2 - 80.0 would fail a 0.2 dB limit.
SLACK = 1e-9


class Unreadable(Exception):
    pass


class Measurement:
    def __init__(self, name, frequencies, levels, smoothing):
        self.name = name
        self.frequencies = frequencies
        self.levels = levels  # NaN where the file has no level
        self.smoothing = smoothing

    def covers(self, low, high):
        return self.frequencies[0] <= low and self.frequencies[-1] >= high

    # Within the covered range only. A missing level on either side gives NaN.
    def level_at(self, frequency):
        i = bisect.bisect_left(self.frequencies, frequency)
        if self.frequencies[i] == frequency:
            return self.levels[i]
        f0, f1 = self.frequencies[i - 1], self.frequencies[i]
        l0, l1 = self.levels[i - 1], self.levels[i]
        t = math.log(frequency / f0) / math.log(f1 / f0)
        return l0 + t * (l1 - l0)


def parse(text, name):
    points = []
    smoothing = None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("*"):
            key, sep, value = stripped[1:].partition(":")
            if sep and key.strip().lower() == "smoothing":
                smoothing = value.strip()
            continue
        fields = [field for field in SPLIT.split(stripped) if field]
        try:
            frequency = float(fields[0])
        except ValueError:
            continue
        # TRAP: a comma decimal splits each number in two. REW writes a dot
        # unless its export takes the computer's number format.
        if len(fields) not in (2, 3):
            raise Unreadable(f"{name}, line {number}: expected the frequency, the SPL, and the phase, and found "
                             f"{len(fields)} values. Export with a dot as the decimal separator.")
        try:
            level = float(fields[1])
        except ValueError:
            raise Unreadable(f"{name}, line {number}: '{fields[1]}' is not an SPL in dB")
        # A linear export starts at 0 Hz, which has no place on a log axis.
        if not math.isfinite(frequency) or frequency <= 0:
            continue
        points.append((frequency, level if math.isfinite(level) else math.nan))
    points.sort()
    for (f0, _), (f1, _) in zip(points, points[1:]):
        if f0 == f1:
            raise Unreadable(f"{name}: {format_hz(f0)} appears twice. Export one measurement per file.")
    if len(points) < 2:
        raise Unreadable(f"{name}: fewer than two data lines")
    return Measurement(name, [p[0] for p in points], [p[1] for p in points], smoothing)


def read(path):
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as handle:
            return parse(handle.read(), path)
    except OSError as error:
        raise Unreadable(f"{path}: {error.strerror}")


def signed(value):
    # Adding 0.0 turns -0.0 into 0.0, so nothing prints as -0.000.
    return f"{round(value, 3) + 0.0:+.3f}"


def format_hz(frequency):
    return f"{frequency:.1f} Hz" if frequency < 1000 else f"{frequency:.0f} Hz"


def compare(first, second, low, high):
    """The (frequency, first, second) rows over the band, in order."""
    for measurement in (first, second):
        if not measurement.covers(low, high):
            raise Unreadable(f"{measurement.name} runs from {format_hz(measurement.frequencies[0])} to "
                             f"{format_hz(measurement.frequencies[-1])}, short of the band, {format_hz(low)} to "
                             f"{format_hz(high)}. Export the measurement's whole range.")
    frequencies = {low, high}
    for measurement in (first, second):
        frequencies.update(f for f in measurement.frequencies if low <= f <= high)
    rows = [(f, first.level_at(f), second.level_at(f)) for f in sorted(frequencies)]
    for f, *levels in rows:
        for measurement, level in zip((first, second), levels):
            if math.isnan(level):
                raise Unreadable(f"{measurement.name} has no level at {format_hz(f)}, inside the band")
    return rows


def report(first, second, low, high, limit, table):
    """The exit status, and the text to print."""
    lines = [f"{label}: {m.name}, {len(m.frequencies)} points from {format_hz(m.frequencies[0])} to "
             f"{format_hz(m.frequencies[-1])}" for label, m in (("first", first), ("second", second))]
    if first.smoothing is None or second.smoothing is None:
        lines.append("smoothing: a file does not state it. Check that REW exported both with the same.")
    elif first.smoothing == second.smoothing:
        lines.append(f"smoothing: {first.smoothing}, in both")
    else:
        raise Unreadable(f"the smoothing differs: '{first.smoothing}' in {first.name}, and '{second.smoothing}' in "
                         f"{second.name}. Export both with the same.")

    rows = compare(first, second, low, high)
    differences = [(f, b - a) for f, a, b in rows]
    mean = sum(d for _, d in differences) / len(differences)
    at, largest = max(differences, key=lambda row: abs(row[1]))
    shape_at, shape = max(differences, key=lambda row: abs(row[1] - mean))

    lines.append(f"band: {format_hz(low)} to {format_hz(high)}, {len(rows)} frequencies")
    if table:
        lines.append("frequency first second difference")
        lines += [f"{f:.3f} {a:.3f} {b:.3f} {signed(b - a)}" for f, a, b in rows]
    lines += [
        f"largest difference: {abs(largest):.3f} dB at {format_hz(at)}, second minus first {signed(largest)} dB",
        f"mean difference: {signed(mean)} dB",
        f"largest difference from the mean: {abs(shape - mean):.3f} dB at {format_hz(shape_at)}",
    ]
    if abs(largest) <= limit + SLACK:
        status = 0
        lines.append(f"PASS: within {limit:g} dB")
    else:
        status = 1
        lines.append(f"FAIL: {abs(largest):.3f} dB is above {limit:g} dB")
    return status, "\n".join(lines) + "\n"


def decibels(text):
    value = float(text)
    if not (math.isfinite(value) and value >= 0):
        raise argparse.ArgumentTypeError("must be a number of dB, 0 or more")
    return value


def main(argv):
    parser = argparse.ArgumentParser(prog="compare-measurements.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("first", nargs="?", help="the first REW text export, GLM's")
    parser.add_argument("second", nargs="?", help="the second REW text export, qlm's")
    parser.add_argument("--band", nargs=2, type=float, metavar=("LOW", "HIGH"), default=BAND,
                        help=f"the band in Hz, {BAND[0]:g} to {BAND[1]:g} unless given")
    parser.add_argument("--limit", type=decibels, default=LIMIT,
                        help=f"the largest difference that passes, in dB, {LIMIT:g} unless given")
    parser.add_argument("--table", action="store_true", help="print every compared frequency")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv[1:])
    if args.self_test:
        if args.first is not None:
            parser.error("--self-test takes no files")
        return self_test()
    if args.second is None:
        parser.error("give two REW text exports")
    low, high = args.band
    if not 0 < low < high:
        parser.error(f"the band must run up from above 0 Hz, and {format_hz(low)} to {format_hz(high)} does not")
    try:
        status, text = report(read(args.first), read(args.second), low, high, args.limit, args.table)
    except Unreadable as error:
        sys.stderr.write(f"compare-measurements.py: {error}\n")
        return 2
    sys.stdout.write(text)
    return status


def rew_text(points, smoothing="1/12 octave", delimiter=" ", header=True):
    lines = []
    if header:
        lines += ["* Measurement data measured by REW", f"* Smoothing: {smoothing}", "*",
                  "* Freq(Hz) SPL(dB) Phase(degrees)"]
    lines += [delimiter.join([f"{f:.6f}", f"{level:.3f}", "0.0"]) for f, level in points]
    return "\n".join(lines) + "\n"


def log_points(low, high, per_octave, level):
    count = round(math.log2(high / low) * per_octave)
    frequencies = [low * 2 ** (k / per_octave) for k in range(count + 1)]
    return [(f, level(f)) for f in frequencies]


def run(argv):
    """main's status, stdout, and stderr, with the example's directory left out."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            status = main(["compare-measurements.py"] + argv)
        except SystemExit as error:
            status = error.code
    prefix = EXAMPLE + os.sep
    return status, out.getvalue().replace(prefix, ""), err.getvalue().replace(prefix, "")


def self_test():
    failures = []

    def check(name, got, expected):
        if got != expected:
            failures.append(f"self-test failed: {name}\n--- got\n{got}\n--- expected\n{expected}\n")

    def compared(first, second):
        return report(parse(first, "first.txt"), parse(second, "second.txt"), BAND[0], BAND[1], LIMIT, False)

    def unreadable(name, action, expected):
        try:
            action()
        except Unreadable as error:
            check(name, str(error), expected)
        else:
            failures.append(f"self-test failed: {name} raised nothing\n")

    glm = os.path.join(EXAMPLE, "glm.txt")
    qlm = os.path.join(EXAMPLE, "qlm.txt")
    check("example", run([glm, qlm]), (0, (
        "first: glm.txt, 133 points from 10.0 Hz to 20480 Hz\n"
        "second: qlm.txt, 133 points from 10.0 Hz to 20480 Hz\n"
        "smoothing: 1/12 octave, in both\n"
        "band: 20.0 Hz to 20000 Hz, 121 frequencies\n"
        "largest difference: 0.120 dB at 63.5 Hz, second minus first +0.120 dB\n"
        "mean difference: +0.051 dB\n"
        "largest difference from the mean: 0.069 dB at 63.5 Hz\n"
        "PASS: within 0.2 dB\n"
    ), ""))
    status, out, err = run(["--band", "10", "20000", glm, qlm])
    check("example from 10 Hz", (status, out.splitlines()[-4:]), (1, [
        "largest difference: 1.000 dB at 10.0 Hz, second minus first -1.000 dB",
        "mean difference: +0.000 dB",
        "largest difference from the mean: 1.000 dB at 10.0 Hz",
        "FAIL: 1.000 dB is above 0.2 dB",
    ]))
    status, out, err = run(["--limit", "0.1", glm, qlm])
    check("example at 0.1 dB", (status, out.splitlines()[-1]), (1, "FAIL: 0.120 dB is above 0.1 dB"))
    check("a missing file", run([glm, os.path.join(EXAMPLE, "missing.txt")]),
          (2, "", "compare-measurements.py: missing.txt: No such file or directory\n"))
    for name, options, expected in [
        ("a band upside down", ["--band", "1000", "100"],
         "the band must run up from above 0 Hz, and 1000 Hz to 100.0 Hz does not"),
        ("a band from 0 Hz", ["--band", "0", "100"], "the band must run up from above 0 Hz, and 0.0 Hz to 100.0 Hz does not"),
        ("a negative limit", ["--limit", "-1"], "argument --limit: must be a number of dB, 0 or more"),
    ]:
        status, out, err = run(options + [glm, qlm])
        check(name, (status, out, err.splitlines()[-1]), (2, "", "compare-measurements.py: error: " + expected))

    def line(f):
        return 70 + 2 * math.log2(f / 20)

    twelfth = log_points(10, 24000, 12, line)
    status, out = compared(rew_text(twelfth), rew_text(sorted(twelfth + [(1000.0, line(1000.0) + 0.3)])))
    check("a bump at 1 kHz", (status, out.splitlines()[-4:]), (1, [
        "largest difference: 0.300 dB at 1000 Hz, second minus first +0.300 dB",
        "mean difference: +0.002 dB",
        "largest difference from the mean: 0.298 dB at 1000 Hz",
        "FAIL: 0.300 dB is above 0.2 dB",
    ]))
    status, out = compared(rew_text(twelfth), rew_text(log_points(10, 24000, 48, line)))
    lines = out.splitlines()
    check("a twelfth against a 48th of an octave", (status, lines[3], lines[-1]),
          (0, "band: 20.0 Hz to 20000 Hz, 480 frequencies", "PASS: within 0.2 dB"))
    check("a twelfth against a 48th, the largest", float(lines[4].split()[2]) <= 0.001, True)

    def flat(level):
        return rew_text(log_points(10, 24000, 3, lambda f: level))

    status, out = compared(flat(80.0), flat(80.2))
    check("exactly at the limit", (status, out.splitlines()[-1]), (0, "PASS: within 0.2 dB"))
    status, out = compared(flat(80.0), flat(79.85))
    check("a level offset", out.splitlines()[-4:], [
        "largest difference: 0.150 dB at 20.0 Hz, second minus first -0.150 dB",
        "mean difference: -0.150 dB",
        "largest difference from the mean: 0.000 dB at 20.0 Hz",
        "PASS: within 0.2 dB",
    ])

    points = [(20.0, 80.0), (1000.0, 81.5), (20000.0, 79.25)]
    expected = parse(rew_text(points), "space")
    for name, text in [
        ("tab", rew_text(points, delimiter="\t")),
        ("comma", rew_text(points, delimiter=",")),
        ("comma and space", rew_text(points, delimiter=", ")),
        ("semicolon", rew_text(points, delimiter=";")),
        ("a bare header and CRLF", ("Freq(Hz) SPL(dB) Phase(degrees)\n" +
                                    rew_text(points, header=False)).replace("\n", "\r\n")),
        ("no phase", "".join(f"{f} {level}\n" for f, level in points)),
        ("0 Hz", "0.0 -Infinity 0.0\n" + rew_text(points, header=False)),
    ]:
        got = parse(text, name)
        check(name, (got.frequencies, got.levels), (expected.frequencies, expected.levels))

    unreadable("a comma decimal", lambda: parse("20,000000\t80,000\t0,0\n", "a.txt"),
               "a.txt, line 1: expected the frequency, the SPL, and the phase, and found 6 values. "
               "Export with a dot as the decimal separator.")
    unreadable("not an SPL", lambda: parse("20 eighty 0\n1000 80 0\n", "a.txt"),
               "a.txt, line 1: 'eighty' is not an SPL in dB")
    unreadable("one point", lambda: parse(rew_text(points[:1]), "a.txt"), "a.txt: fewer than two data lines")
    unreadable("two measurements in one file", lambda: parse(rew_text(points) + rew_text(points), "a.txt"),
               "a.txt: 20.0 Hz appears twice. Export one measurement per file.")
    unreadable("short of the band", lambda: compared(rew_text(twelfth), rew_text(log_points(30, 24000, 12, line))),
               "second.txt runs from 30.0 Hz to 24382 Hz, short of the band, 20.0 Hz to 20000 Hz. "
               "Export the measurement's whole range.")
    unreadable("no level inside the band", lambda: compared(rew_text(points), "500 nan 0\n" + rew_text(points)),
               "second.txt has no level at 500.0 Hz, inside the band")
    unreadable("no level next to the band edge",
               lambda: compared(rew_text(points), "19.9 -Infinity 0\n" + rew_text([(25.0, 80.0)] + points[1:])),
               "second.txt has no level at 20.0 Hz, inside the band")
    unreadable("the smoothing differs", lambda: compared(rew_text(twelfth), rew_text(twelfth, smoothing="1/6 octave")),
               "the smoothing differs: '1/12 octave' in first.txt, and '1/6 octave' in second.txt. "
               "Export both with the same.")
    status, out = compared(rew_text(twelfth), rew_text(twelfth, header=False))
    check("smoothing stated once", out.splitlines()[2],
          "smoothing: a file does not state it. Check that REW exported both with the same.")

    if failures:
        sys.stderr.write("\n".join(failures))
        return 1
    print("self-test passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
