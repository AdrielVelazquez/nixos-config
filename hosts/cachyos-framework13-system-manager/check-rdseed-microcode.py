#!/usr/bin/env python3
"""Structured AMD early-microcode inspection for check-rdseed-microcode.sh."""

from __future__ import annotations

import os
import struct
import sys
import unittest

AMD_MAGIC = 0x00414D44
AMD_CONTAINER_TYPE = 0
AMD_PATCH_TYPE = 1
AMD_CONTAINER_HEADER_SIZE = 12
AMD_SECTION_HEADER_SIZE = 8
AMD_PATCH_HEADER_SIZE = 64
AMD_EARLY_CPIO_PATH = "kernel/x86/microcode/AuthenticAMD.bin"
READ_LIMIT = 64 * 1024 * 1024


class FormatError(ValueError):
    """Input is not a complete early CPIO or AMD microcode structure."""


def _align4(offset: int) -> int:
    return (offset + 3) & ~3


def extract_early_amd_microcode(initrd: bytes) -> bytes:
    offset = 0
    while offset < len(initrd):
        while offset < len(initrd) and initrd[offset] == 0:
            offset += 1
        if len(initrd) - offset < 110:
            raise FormatError("truncated early CPIO header")

        header = initrd[offset : offset + 110]
        if header[:6] not in (b"070701", b"070702"):
            raise FormatError(f"invalid early CPIO magic at offset {offset}")
        try:
            fields = [int(header[pos : pos + 8], 16) for pos in range(6, 110, 8)]
        except ValueError as exc:
            raise FormatError(f"invalid early CPIO header at offset {offset}") from exc

        file_size = fields[6]
        name_size = fields[11]
        if name_size < 1:
            raise FormatError(f"invalid early CPIO name size at offset {offset}")

        name_start = offset + 110
        name_end = name_start + name_size
        if name_end > len(initrd) or initrd[name_end - 1] != 0:
            raise FormatError(f"truncated early CPIO name at offset {offset}")
        name = initrd[name_start : name_end - 1].decode("utf-8", "surrogateescape")

        data_start = _align4(name_end)
        data_end = data_start + file_size
        if data_end > len(initrd):
            raise FormatError(f"truncated early CPIO data for {name!r}")
        if name == AMD_EARLY_CPIO_PATH:
            return initrd[data_start:data_end]
        if name == "TRAILER!!!":
            break
        offset = _align4(data_end)

    raise FormatError(f"early CPIO member {AMD_EARLY_CPIO_PATH!r} not found")


def parse_amd_patch_ids(blob: bytes) -> list[int]:
    patch_ids: list[int] = []
    offset = 0

    while offset < len(blob):
        if len(blob) - offset < AMD_CONTAINER_HEADER_SIZE:
            raise FormatError(f"truncated AMD container header at offset {offset}")
        magic, container_type, equiv_size = struct.unpack_from("<III", blob, offset)
        if magic != AMD_MAGIC:
            raise FormatError(f"invalid AMD container magic at offset {offset}")
        if container_type != AMD_CONTAINER_TYPE:
            raise FormatError(
                f"invalid AMD container type {container_type} at offset {offset}"
            )

        offset += AMD_CONTAINER_HEADER_SIZE
        if equiv_size > len(blob) - offset:
            raise FormatError("truncated AMD equivalence table")
        offset += equiv_size

        while offset < len(blob):
            if len(blob) - offset >= 4 and struct.unpack_from("<I", blob, offset)[0] == AMD_MAGIC:
                break
            if len(blob) - offset < AMD_SECTION_HEADER_SIZE:
                raise FormatError(f"truncated AMD patch section at offset {offset}")

            section_type, patch_size = struct.unpack_from("<II", blob, offset)
            if section_type != AMD_PATCH_TYPE:
                raise FormatError(
                    f"invalid AMD patch section type {section_type} at offset {offset}"
                )
            if patch_size < AMD_PATCH_HEADER_SIZE:
                raise FormatError(f"AMD patch at offset {offset} is too short")

            patch_start = offset + AMD_SECTION_HEADER_SIZE
            patch_end = patch_start + patch_size
            if patch_end > len(blob):
                raise FormatError(f"truncated AMD patch at offset {offset}")
            patch_ids.append(struct.unpack_from("<I", blob, patch_start + 4)[0])
            offset = patch_end

    if not patch_ids:
        raise FormatError("AMD container contains no patch sections")
    return patch_ids


def inspect_initrd(initrd: bytes) -> tuple[list[int], str | None]:
    try:
        return parse_amd_patch_ids(extract_early_amd_microcode(initrd)), None
    except FormatError as exc:
        return [], str(exc)


def classify_journal(status: int, journal: str) -> str:
    if status != 0:
        return f"UNKNOWN (journalctl exited with status {status})"
    if "rdseed32 is broken" in journal.lower():
        return "FLAGGED (microcode too old)"
    return "not flagged"


def scan_boot(root: str, fixed_rev: int, old_rev: int) -> None:
    found_any = False
    for current_root, _dirs, files in os.walk(root):
        for filename in sorted(files):
            lower_name = filename.lower()
            if not any(token in lower_name for token in ("initrd", "initramfs", "ucode")):
                continue

            path = os.path.join(current_root, filename)
            found_any = True
            try:
                with open(path, "rb") as handle:
                    image = handle.read(READ_LIMIT + 1)
                if len(image) > READ_LIMIT:
                    image = image[:READ_LIMIT]
                patch_ids, error = inspect_initrd(image)
            except OSError as exc:
                print(f"{path}: UNKNOWN ({exc})")
                continue

            if error is not None:
                print(f"{path}: UNKNOWN ({error})")
                continue
            revisions = ",".join(f"0x{patch_id:08x}" for patch_id in patch_ids)
            print(
                f"{path}: structured_patch_ids={revisions} "
                f"fixed_0x{fixed_rev:08x}={'YES' if fixed_rev in patch_ids else 'no'} "
                f"old_0x{old_rev:08x}={'YES' if old_rev in patch_ids else 'no'}"
            )

    if not found_any:
        print(f"No initrd/initramfs/ucode files found under {root}")


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SelfTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if len(argv) == 2 and argv[0] == "journal-status":
        print(classify_journal(int(argv[1]), sys.stdin.read()))
        return 0
    if len(argv) == 4 and argv[0] == "scan":
        scan_boot(argv[1], int(argv[2], 0), int(argv[3], 0))
        return 0

    print(
        "usage: check-rdseed-microcode.py --self-test | "
        "journal-status STATUS | scan ROOT FIXED_REV OLD_REV",
        file=sys.stderr,
    )
    return 2


class SelfTests(unittest.TestCase):
    FIXED_REV = 0x0B204037
    OTHER_REV = 0x0B20401B

    @staticmethod
    def _newc_entry(name: str, data: bytes, ino: int = 1) -> bytes:
        name_bytes = name.encode() + b"\0"
        fields = (ino, 0o100644, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name_bytes), 0)
        header = b"070701" + b"".join(f"{field:08x}".encode() for field in fields)
        entry = header + name_bytes
        entry += b"\0" * (-len(entry) % 4)
        entry += data
        entry += b"\0" * (-len(entry) % 4)
        return entry

    @classmethod
    def _initrd(cls, microcode: bytes) -> bytes:
        return cls._newc_entry(
            "kernel/x86/microcode/AuthenticAMD.bin", microcode
        ) + cls._newc_entry("TRAILER!!!", b"", 2)

    @staticmethod
    def _amd_blob(patch_id: int, equiv_data: bytes = b"") -> bytes:
        patch = bytearray(64)
        struct.pack_into("<I", patch, 4, patch_id)
        return (
            struct.pack("<III", 0x00414D44, 0, len(equiv_data))
            + equiv_data
            + struct.pack("<II", 1, len(patch))
            + patch
        )

    def test_unrelated_raw_revision_bytes_do_not_count(self) -> None:
        blob = self._amd_blob(
            self.OTHER_REV, struct.pack("<I", self.FIXED_REV)
        )
        patch_ids, error = inspect_initrd(self._initrd(blob))
        self.assertIsNone(error)
        self.assertNotIn(self.FIXED_REV, patch_ids)
        self.assertEqual(patch_ids, [self.OTHER_REV])

    def test_structured_patch_id_counts(self) -> None:
        patch_ids, error = inspect_initrd(
            self._initrd(self._amd_blob(self.FIXED_REV))
        )
        self.assertIsNone(error)
        self.assertEqual(patch_ids, [self.FIXED_REV])

    def test_malformed_data_is_reported_safely(self) -> None:
        patch_ids, error = inspect_initrd(self._initrd(b"not an AMD container"))
        self.assertEqual(patch_ids, [])
        self.assertIsNotNone(error)

    def test_journal_failure_is_unknown(self) -> None:
        self.assertTrue(classify_journal(1, "").startswith("UNKNOWN"))
        self.assertNotIn("not flagged", classify_journal(1, "").lower())

    def test_journal_flag_is_reported(self) -> None:
        self.assertTrue(
            classify_journal(0, "kernel: RDSEED32 is broken").startswith("FLAGGED")
        )

    def test_clean_read_is_not_flagged(self) -> None:
        self.assertEqual(classify_journal(0, "kernel: microcode updated"), "not flagged")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
