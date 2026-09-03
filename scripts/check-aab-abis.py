# -*- coding: utf-8 -*-
"""Check that a release AAB reaches every device it used to, and still satisfies
Google's 16 KB page-size rule.

    python scripts/check-aab-abis.py [path/to/app-release.aab]

Two properties, both learned from the same mistake.

On 2 May 2026 the 16 KB page-size commit added `abiFilters "arm64-v8a"` and
excluded `lib/armeabi-v7a/**` from packaging. That does satisfy the 16 KB rule
-- by shipping no 32-bit code at all -- and nothing noticed for four months,
because the phones on hand are 64-bit. Play noticed at the next release:
anyone on a 32-bit device, from a bundle published before that date, had
nothing they could upgrade to, so the whole release was refused with "this
release will not be available to any existing users".

So the guard asserts both halves at once:

  every ABI in REQUIRED_ABIS is present   nobody is stranded on an old build
  every 64-bit .so has p_align >= 16 KB   the rule that started this

Checking alignment directly from the ELF program headers keeps this honest and
dependency-free: p_align on each PT_LOAD segment is exactly what the loader
reads, and it is what `zipalign -P 16 -c` and the NDK's own checks look at.
The 16 KB rule governs 64-bit ABIs only, so 32-bit libraries are read for
presence and not for alignment.
"""
import struct
import sys
import zipfile
from collections import defaultdict

# What a bundle must contain to reach everyone who already has the app. x86_64
# is here for emulators and the handful of x86 Chromebooks; it costs little and
# its absence is the same class of silent exclusion.
REQUIRED_ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64')

# ABIs the 16 KB page-size requirement applies to.
SIXTY_FOUR_BIT = ('arm64-v8a', 'x86_64')

MIN_ALIGN = 0x4000  # 16 KB
PT_LOAD = 1
ELFCLASS64 = 2

DEFAULT_AAB = ('flutter_vocabmaster/build/app/outputs/bundle/release/'
               'app-release.aab')


def max_load_align(data):
    """Largest p_align across the PT_LOAD segments of a 64-bit ELF.

    Returns None when the file is not a 64-bit ELF, which is the signal to
    skip it rather than to fail: a 32-bit library has no 16 KB obligation.
    """
    if len(data) < 0x40 or data[:4] != b'\x7fELF' or data[4] != ELFCLASS64:
        return None
    little = data[5] == 1
    end = '<' if little else '>'
    e_phoff, = struct.unpack_from(end + 'Q', data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from(end + 'HH', data, 0x36)
    best = 0
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if off + 0x38 > len(data):
            break
        p_type, = struct.unpack_from(end + 'I', data, off)
        if p_type == PT_LOAD:
            p_align, = struct.unpack_from(end + 'Q', data, off + 0x30)
            best = max(best, p_align)
    return best


def main(argv):
    path = argv[1] if len(argv) > 1 else DEFAULT_AAB

    try:
        archive = zipfile.ZipFile(path)
    except (IOError, OSError, zipfile.BadZipFile) as error:
        print('FAIL: cannot read %s (%s)' % (path, error))
        return 2

    libs = defaultdict(list)
    with archive:
        for name in archive.namelist():
            if '/lib/' in name and name.endswith('.so'):
                libs[name.split('/lib/')[1].split('/')[0]].append(name)

        print('Bundle: %s' % path)
        if not libs:
            print('FAIL: the bundle contains no native libraries at all')
            return 1

        for abi in sorted(libs):
            print('  %-14s %d libraries' % (abi, len(libs[abi])))

        failures = []

        missing = [abi for abi in REQUIRED_ABIS if abi not in libs]
        if missing:
            failures.append(
                'missing ABI(s): %s -- users on those devices cannot install '
                'or upgrade, and Play refuses the release' % ', '.join(missing))

        print('')
        for abi in SIXTY_FOUR_BIT:
            for name in sorted(libs.get(abi, [])):
                align = max_load_align(archive.read(name))
                if align is None:
                    failures.append('%s is not a 64-bit ELF but sits under %s'
                                    % (name, abi))
                    continue
                ok = align >= MIN_ALIGN
                print('  %-52s p_align=0x%-6x %s'
                      % (name.split('/lib/')[1], align,
                         'ok' if ok else 'NOT 16 KB ALIGNED'))
                if not ok:
                    failures.append(
                        '%s has p_align=0x%x, below the 16 KB minimum'
                        % (name, align))

    print('')
    if failures:
        print('FAIL:')
        for failure in failures:
            print('  - %s' % failure)
        return 1

    print('PASS: every required ABI is present and every 64-bit library is '
          '16 KB aligned')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
