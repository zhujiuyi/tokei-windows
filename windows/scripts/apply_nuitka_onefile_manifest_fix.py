"""Align Nuitka's onefile manifest with the files it actually copies."""

from importlib import import_module, metadata
from pathlib import Path


SUPPORTED_NUITKA_VERSION = "4.2.2"


def main() -> None:
    installed_version = metadata.version("Nuitka")
    if installed_version != SUPPORTED_NUITKA_VERSION:
        raise SystemExit(
            "The onefile manifest fix supports Nuitka "
            f"{SUPPORTED_NUITKA_VERSION}; found {installed_version}."
        )

    onefile_module = import_module("nuitka.freezer.Onefile")
    source_path = onefile_module.__file__
    if source_path is None:
        raise SystemExit("Could not locate Nuitka's onefile builder source.")

    source_file = Path(source_path)
    source = source_file.read_bytes()
    line_ending = b"\r\n" if b"\r\n" in source else b"\n"

    original = line_ending.join(
        (
            b"        for entry_point in getStandaloneEntryPoints():",
            b'            if "copy" in entry_point.tags:',
            b"                expected_files.append(entry_point.dest_path)",
        )
    )
    corrected = line_ending.join(
        (
            b"        for entry_point in getStandaloneEntryPoints():",
            b"            if (",
            b'                "copy" in entry_point.tags',
            b'                and not entry_point.kind.endswith("_ignored")',
            b"            ):",
            b"                expected_files.append(entry_point.dest_path)",
        )
    )

    if corrected in source:
        return

    occurrences = source.count(original)
    if occurrences != 1:
        raise SystemExit(
            "Nuitka's onefile manifest code changed; refusing to patch an "
            f"unexpected source layout (matching blocks: {occurrences})."
        )

    source_file.write_bytes(source.replace(original, corrected, 1))


if __name__ == "__main__":
    main()
