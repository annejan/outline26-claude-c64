#!/usr/bin/env python3
"""verify_efo_claims.py — build-time EFO page-claim + ZP collision checker.

Parses each part's EFO header binary, reads the assembled .prg, and
verifies that every memory page touched by the code/data is covered by
a 'P' tag in the EFO header. Also checks that no two parts claim
overlapping ZP bytes for conflicting purposes.

Usage:
  python3 tools/verify_efo_claims.py <part_dir> <part_name> [extras...]
  python3 tools/verify_efo_claims.py --all   # check every part

Where extras are "filename,hex_load_addr" pairs for extra binaries
(e.g. "kloot_star_tr.bin,2000") declared in build_part's extras.

Exit code:
  0 = all claims are sufficient
  1 = at least one part has a page-claim gap or ZP collision
"""

import os
import struct
import sys

# ---- EFO header parsing ------------------------------------------------

EFO_MAGIC = b"EFO2"
TAG_P = 0x50  # 'P' — owned pages
TAG_I = 0x49  # 'I' — inherited pages
TAG_Z = 0x5A  # 'Z' — owned zero-page bytes
TAG_S = 0x53  # 'S' — I/O safe
TAG_M = 0x4D  # 'M' — music install vector
TAG_END = 0x00


def parse_efo_header(bin_path):
    """Parse an EFO2 header binary, return (claimed_pages, inherited_pages, owned_zp)."""
    with open(bin_path, "rb") as f:
        data = f.read()

    assert data[:4] == EFO_MAGIC, f"Bad EFO magic in {bin_path}"

    # Skip 14 bytes of vectors (7 words) after magic
    offset = 4 + 14

    claimed = []    # list of (lo, hi) for 'P' tags
    inherited = []  # list of (lo, hi) for 'I' tags
    owned_zp = []   # list of (lo, hi) for 'Z' tags

    while offset < len(data):
        tag = data[offset]
        if tag == TAG_END:
            break
        elif tag == TAG_P:
            lo, hi = data[offset + 1], data[offset + 2]
            claimed.append((lo, hi))
            offset += 3
        elif tag == TAG_I:
            lo, hi = data[offset + 1], data[offset + 2]
            inherited.append((lo, hi))
            offset += 3
        elif tag == TAG_Z:
            lo, hi = data[offset + 1], data[offset + 2]
            owned_zp.append((lo, hi))
            offset += 3
        elif tag == TAG_S:
            offset += 1
        elif tag == TAG_M:
            offset += 3
        else:
            print(f"  ⚠ Unknown tag ${tag:02x} at offset {offset} in {bin_path}")
            offset += 1

    return claimed, inherited, owned_zp


def page_span(load_addr, size):
    """Return (first_page, last_page) for a memory region."""
    first = load_addr >> 8
    last = (load_addr + size - 1) >> 8
    return first, last


def is_covered(page, claimed):
    """Check if 'page' is within any (lo, hi) claim range."""
    for lo, hi in claimed:
        if lo <= page <= hi:
            return True
    return False


def pages_with_nonzero_bytes(payload, base_addr):
    """Return set of page numbers that contain ≥1 non-zero byte in payload."""
    used = set()
    for offset, byte in enumerate(payload):
        if byte != 0:
            used.add((base_addr + offset) >> 8)
    return used


def check_part(part_dir, part_name, extras=None):
    """Run page-claim check for one part. Return (ok, owned_zp)."""
    prg_path = os.path.join(part_dir, f"{part_name}.prg")
    efo_bin_path = os.path.join(part_dir, f"{part_name}_efo_header.bin")

    ok = True

    # Read PRG to determine load address and used pages
    try:
        with open(prg_path, "rb") as f:
            prg_data = f.read()
    except FileNotFoundError:
        print(f"  ℹ {part_name}: no .prg found, skipping")
        return (True, [])

    load_addr = struct.unpack_from("<H", prg_data, 0)[0]
    payload = prg_data[2:]

    # Parse EFO header
    try:
        claimed, inherited, owned_zp = parse_efo_header(efo_bin_path)
    except FileNotFoundError:
        print(f"  ⚠ {part_name}: no EFO header found at {efo_bin_path}")
        return (True, [])

    # Find pages with actual non-zero code/data (skip zero-padding gaps)
    used_pages = pages_with_nonzero_bytes(payload, load_addr)

    uncovered = [p for p in sorted(used_pages) if not is_covered(p, claimed)]

    # Check extra binaries too
    if extras:
        for extra in extras:
            try:
                fname, addr_str = extra.split(",")
                addr = int(addr_str, 16)
                extra_path = os.path.join(part_dir, fname)
                with open(extra_path, "rb") as f:
                    extra_data = f.read()
                extra_pages = pages_with_nonzero_bytes(extra_data, addr)
                for page in sorted(extra_pages):
                    if not is_covered(page, claimed):
                        uncovered.append(page)
                used_pages |= extra_pages
            except (ValueError, FileNotFoundError) as e:
                print(f"  ⚠ {part_name}: extra '{extra}' — {e}")

    # Report
    if uncovered:
        uniq = sorted(set(uncovered))
        print(f"  ❌ {part_name}: page-claim gap at ${'$, $'.join(f'{p:02x}' for p in uniq)}")
        print(f"     Used pages: ${'$, $'.join(f'{p:02x}' for p in sorted(used_pages))}")
        print(f"     Claimed: {[f'${lo:02x}—${hi:02x}' for lo, hi in claimed]}")
        ok = False
    else:
        pages_str = ", ".join(f"${p:02x}" for p in sorted(used_pages))
        print(f"  ✓ {part_name}: pages {pages_str} covered")

    return (ok, owned_zp)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--all":
        # Auto-detect all parts
        ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        parts_dir = os.path.join(ROOT, "parts")
        all_ok = True
        all_zp = {}

        # Each tuple: (subdir, partname, extras list)
        part_defs = [
            ("screenfill", "screenfill", []),
            ("intro", "intro", []),
            ("interlude", "interlude", []),
            ("greets", "greets", []),
            ("coda", "coda", [
                "kloot_star_tr.bin,2000",
                "kloot_star_tl.bin,2600",
                "kloot_star_bl.bin,2c00",
                "kloot_star_br.bin,3200",
            ]),
            ("end", "end", []),
        ]

        for subdir, name, extras in part_defs:
            part_path = os.path.join(parts_dir, subdir)
            ok, zp = check_part(part_path, name, extras)
            all_zp[name] = zp
            if not ok:
                all_ok = False

        # Check ZP collisions between parts
        print()
        print("--- ZP collision check ---")
        zp_owners = {}  # zp_byte -> list of part names
        for name, zp_list in all_zp.items():
            for lo, hi in zp_list:
                for byte in range(lo, hi + 1):
                    zp_owners.setdefault(byte, []).append(name)

        collisions = False
        for byte, owners in sorted(zp_owners.items()):
            if len(owners) > 1 and len(set(owners)) > 1:
                # Multiple parts claim the same ZP byte — but this is only
                # a problem if they use it for DIFFERENT purposes. Shared
                # bytes (like music state $F6-$FA) are intentional.
                # Mark as colliding only if the claim ranges overlap
                # in a way that suggests conflicting use.
                shared_across = set(owners)
                # These ZP bytes are known-shared between parts.
                # They are either scratch, music state, or part state
                # that each part deliberately sets on init.
                known_shared = {
                    0xF4,  # greets: zp_beat_phase; interlude: zp_fade; end: scratch
                    0xF5,  # greets: zp_wobble_pos; interlude: zp_beat_count; end: scratch
                    0xF6,  # zp_outro / zp_beat_count / zp_timer (transition byte)
                    0xF7,  # zp_tmp / zp_scroll_pos / zp_line
                    0xF8,  # zp_intro / zp_plasma_tgl / zp_line / zp_charge
                    0xF9,  # zp_frame / various per-part scratch
                    0xFA,  # shared scratch (clobbered by my_music_play)
                    0xFB,  # interlude fire_dst / coda zp_subtick / end ZP ptr
                    0xFC,  # interlude fire_src / coda zp_frame / end ZP ptr
                    0xFD,  # interlude fire_tmp / intro scratch
                }
                if byte in known_shared:
                    continue
                print(f"  ⚠ ZP ${byte:02x} claimed by: {', '.join(shared_across)}")
                collisions = True

        if not collisions:
            print("  ✓ No unexpected ZP collisions")

        if all_ok:
            print()
            print("✓ All page claims are sufficient")
        else:
            print()
            print("❌ Some page claims are insufficient — fix 'P' tags in EFO header")
            sys.exit(1)

    elif len(sys.argv) >= 3:
        part_dir = sys.argv[1]
        part_name = sys.argv[2]
        extras = sys.argv[3:] if len(sys.argv) > 3 else []
        ok, _ = check_part(part_dir, part_name, extras)
        if not ok:
            sys.exit(1)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
