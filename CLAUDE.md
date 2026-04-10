# CLAUDE.md

Context for Claude Code when working in this repository.

**GitHub:** <https://github.com/Slacksarenice/PS_FileObjectId>

## What this is

`FileObjectId` is a small PowerShell module that tracks files by their NTFS
Object ID. The goal: once a file is registered, you can find it again by ID
even after it's been moved or renamed anywhere on the same volume.

## Layout

```
FileObjectId/
    FileObjectId.psm1    # All module code (P/Invoke + functions)
    FileObjectId.psd1    # Module manifest (Author: Seth Miller)
Tests/
    FileObjectId.Tests.ps1  # Pester v5 tests
README.md                # User-facing docs
CLAUDE.md                # This file
```

Single-file module by design. If it grows past ~10 functions, split into
`Public/` and `Private/` subfolders and have the `.psm1` dot-source them.

## Public commands

| Command | Purpose |
|---|---|
| `Set-FileObjectId -Path` | Assign an Object ID if missing, return as `[Guid]` |
| `Get-FileObjectId -Path` | Read existing Object ID as `[Guid]` |
| `Resolve-FileObjectId -ObjectId [-Volume]` | Get current path from an ID |
| `ConvertTo-GuidFromHex -Hex` | Convert raw 32-char hex to `[Guid]` |

All four are listed in `FunctionsToExport` in the manifest and in
`Export-ModuleMember` at the bottom of the `.psm1`. Keep those in sync when
adding or renaming functions.

## How it works

1. **Assigning IDs** — `Set-FileObjectId` shells out to `fsutil objectid create`.
   `fsutil objectid query` is used to check whether one already exists.
2. **Reading IDs** — `Get-FileObjectId` parses `fsutil objectid query` output.
   The hex string it prints is the raw on-disk byte order, which is exactly
   what `[Guid]::new([byte[]])` expects (little-endian for the first three
   fields), so no manual byte swapping is needed.
3. **Resolving IDs to paths** — `Resolve-FileObjectId` uses P/Invoke against
   `kernel32.dll`:
   - `CreateFileW` opens the volume root (`C:\`) as a *directory handle*
     using `FILE_FLAG_BACKUP_SEMANTICS` and zero access rights. This is the
     "volume hint" for `OpenFileById` and crucially does **not** require
     admin — unlike opening the raw volume (`\\.\C:`), which does.
   - `OpenFileById` with a `FILE_ID_DESCRIPTOR` of type `1` (ObjectId)
     returns a handle to the file.
   - `GetFinalPathNameByHandleW` turns that handle back into a path. The
     `\\?\` prefix is stripped before returning.

## Gotchas to watch for when editing

- **PowerShell hex literal overflow.** `0x80000000` parses as a signed
  `Int32` and becomes negative. Always use decimal (`2147483648`) or the
  `u` suffix (PS7+) when assigning to a `[uint32]`. This bit us on
  `GENERIC_READ` specifically.
- **`Add-Type` duplicate definitions.** Re-running the module in the same
  session will throw if the type already exists. The `if (-not ('Win32.FileId' -as [type]))`
  guard at the top handles this — don't remove it.
- **Admin requirement.** The module intentionally avoids needing admin by
  using the directory-handle hint. If you ever switch back to `\\.\$Volume`,
  the module will start failing with error 5 (`ERROR_ACCESS_DENIED`) for
  non-elevated users.
- **fsutil GUID format.** `fsutil objectid create` auto-generates an Object ID
  and requires no arguments beyond the file path. `fsutil objectid set` takes
  four **undashed** 32-character hex strings, not standard dashed GUIDs.
  `fsutil objectid query` prints them the same way. If you add any code that
  passes GUIDs to or parses them from `fsutil`, strip/expect no dashes.
- **Object IDs are per-volume.** They don't survive cross-volume moves,
  copies, or most restore operations. Don't add features that assume
  otherwise without a fallback (content hash, USN journal lookup, etc.).

## Testing

### Pester tests

Tests live in `Tests/FileObjectId.Tests.ps1` (Pester v5). Run unit tests:

```powershell
Invoke-Pester ./Tests/ -ExcludeTag Integration
```

Run integration tests (requires a real NTFS volume and may need admin):

```powershell
Invoke-Pester ./Tests/ -Tag Integration
```

### Manual smoke test

```powershell
Import-Module .\FileObjectId\FileObjectId.psd1 -Force

$f = New-TemporaryFile
$id = Set-FileObjectId $f.FullName
$id | Should-Be-Guid

$newPath = Join-Path $env:TEMP "moved-$(Get-Random).tmp"
Move-Item $f.FullName $newPath

Resolve-FileObjectId $id   # should print $newPath
Remove-Item $newPath
```

## Versioning

Manifest version is `1.0.0`. Bump `ModuleVersion` in `FileObjectId.psd1`
on any user-visible change. Patch for bugfixes, minor for new functions,
major for breaking changes to existing function signatures.

## Out of scope

Things this module intentionally does **not** do, so don't add them without
a conversation first:

- Cross-volume tracking (would need a hash index or similar)
- Persistent database of known IDs (leave that to the caller)
- USN journal reading (separate concern, belongs in its own module)
- ReFS integrity stream handling (different feature entirely)
