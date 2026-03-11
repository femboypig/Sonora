#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


MAGIC = b"SONORAAR"
SUPPORTED_VERSION = 1
MAX_NAME_LENGTH = 2048
MANIFEST_ENTRY_NAME = "meta/manifest.v1"


class SonoraArchiveError(ValueError):
    pass


@dataclass(frozen=True)
class ArchiveEntry:
    name: str
    payload: bytes


@dataclass(frozen=True)
class SonoraArchive:
    version: int
    entries: list[ArchiveEntry]


def _read_u32(buffer: bytes, offset: int) -> tuple[int, int]:
    end = offset + 4
    if end > len(buffer):
        raise SonoraArchiveError("Unexpected end of file while reading uint32.")
    return struct.unpack(">I", buffer[offset:end])[0], end


def _read_u64(buffer: bytes, offset: int) -> tuple[int, int]:
    end = offset + 8
    if end > len(buffer):
        raise SonoraArchiveError("Unexpected end of file while reading uint64.")
    return struct.unpack(">Q", buffer[offset:end])[0], end


def parse_archive(data: bytes) -> SonoraArchive:
    minimum_header_size = len(MAGIC) + 4 + 4
    if len(data) < minimum_header_size:
        raise SonoraArchiveError("Invalid backup archive file.")

    magic = data[: len(MAGIC)]
    if magic != MAGIC:
        raise SonoraArchiveError("Backup archive header mismatch.")

    offset = len(MAGIC)
    version, offset = _read_u32(data, offset)
    entry_count, offset = _read_u32(data, offset)

    if version != SUPPORTED_VERSION:
        raise SonoraArchiveError(f"Unsupported backup archive version: {version}.")
    if entry_count == 0:
        raise SonoraArchiveError("Backup archive has no entries.")

    entries: list[ArchiveEntry] = []
    for index in range(entry_count):
        name_length, offset = _read_u32(data, offset)
        if name_length == 0 or name_length > MAX_NAME_LENGTH:
            raise SonoraArchiveError(f"Entry {index}: invalid name length {name_length}.")

        name_end = offset + name_length
        if name_end > len(data):
            raise SonoraArchiveError(f"Entry {index}: name exceeds archive bounds.")
        try:
            name = data[offset:name_end].decode("utf-8")
        except UnicodeDecodeError as exc:
            raise SonoraArchiveError(f"Entry {index}: name cannot be decoded as UTF-8.") from exc
        offset = name_end

        payload_length, offset = _read_u64(data, offset)
        payload_end = offset + payload_length
        if payload_end > len(data):
            raise SonoraArchiveError(f"Entry {index}: payload exceeds archive bounds.")

        payload = data[offset:payload_end]
        offset = payload_end
        entries.append(ArchiveEntry(name=name, payload=payload))

    if offset != len(data):
        trailing = len(data) - offset
        raise SonoraArchiveError(f"Archive contains {trailing} trailing bytes.")

    return SonoraArchive(version=version, entries=entries)


def _entry_target_path(output_dir: Path, entry_name: str) -> Path:
    normalized = Path(entry_name)
    if normalized.is_absolute():
        raise SonoraArchiveError(f"Refusing to extract absolute path: {entry_name}")

    target = (output_dir / normalized).resolve()
    root = output_dir.resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise SonoraArchiveError(f"Refusing to extract path outside output dir: {entry_name}") from exc
    return target


def extract_archive(archive: SonoraArchive, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for entry in archive.entries:
        target = _entry_target_path(output_dir, entry.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(entry.payload)


def manifest_summary(archive: SonoraArchive) -> str | None:
    manifest_entry = next((entry for entry in archive.entries if entry.name == MANIFEST_ENTRY_NAME), None)
    if manifest_entry is None:
        return None

    try:
        manifest = json.loads(manifest_entry.payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "Manifest entry exists but could not be decoded as JSON."

    tracks = manifest.get("tracks")
    playlists = manifest.get("playlists")
    favorites = manifest.get("favorites")
    tracks_count = len(tracks) if isinstance(tracks, list) else 0
    playlists_count = len(playlists) if isinstance(playlists, list) else 0
    favorites_count = len(favorites) if isinstance(favorites, list) else 0
    return (
        f"Manifest: {tracks_count} track(s), "
        f"{playlists_count} playlist(s), "
        f"{favorites_count} favorite(s)."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract Sonora .sonoraarc archives created by the iOS app."
    )
    parser.add_argument("archive", type=Path, help="Path to the .sonoraarc file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Directory to extract into. Defaults to <archive-name>.extracted",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List archive entries without extracting files",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    archive_path = args.archive.expanduser().resolve()
    output_dir = args.output.expanduser().resolve() if args.output else archive_path.with_suffix(".extracted")

    try:
        data = archive_path.read_bytes()
    except OSError as exc:
        print(f"Could not read archive: {exc}", file=sys.stderr)
        return 1

    try:
        archive = parse_archive(data)
    except SonoraArchiveError as exc:
        print(f"Invalid .sonoraarc archive: {exc}", file=sys.stderr)
        return 1

    if args.list:
        print(f"Version: {archive.version}")
        print(f"Entries: {len(archive.entries)}")
        for entry in archive.entries:
            print(f"{entry.name}\t{len(entry.payload)} bytes")
        summary = manifest_summary(archive)
        if summary:
            print(summary)
        return 0

    try:
        extract_archive(archive, output_dir)
    except (OSError, SonoraArchiveError) as exc:
        print(f"Extraction failed: {exc}", file=sys.stderr)
        return 1

    print(f"Extracted {len(archive.entries)} entries to {output_dir}")
    summary = manifest_summary(archive)
    if summary:
        print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
