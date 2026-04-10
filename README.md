# FileObjectId

PowerShell module for tracking files by NTFS Object ID. Once assigned, the ID
stays attached to the file through any move or rename **on the same volume** --
so you can look up the file's current path even if it's been moved elsewhere
on the drive.

## Install

### From PowerShell Gallery

```powershell
Install-Module FileObjectId
```

### From GitHub Releases

Download the signed `.nupkg` from
[Releases](https://github.com/Slacksarenice/PS_FileObjectId/releases),
then install from a local repository:

```powershell
$localRepo = Join-Path $env:TEMP "PSRepo"
New-Item -Path $localRepo -ItemType Directory -Force
# Copy the downloaded .nupkg into $localRepo
Register-PSResourceRepository -Name LocalGH -Uri $localRepo -Trusted
Install-PSResource -Name FileObjectId -Repository LocalGH
```

### From source

```powershell
git clone https://github.com/Slacksarenice/PS_FileObjectId.git
```

Copy the `FileObjectId/` folder into one of your PowerShell module directories:

- **PowerShell 7+:** `$HOME\Documents\PowerShell\Modules\FileObjectId\`
- **Windows PowerShell 5.1:** `$HOME\Documents\WindowsPowerShell\Modules\FileObjectId\`

## Usage

```powershell
# Assign an Object ID (or read the existing one) and save it
$id = Set-FileObjectId "C:\notes\todo.txt"

# ...move or rename the file anywhere on C:...

# Find it again
Resolve-FileObjectId $id
Get-Content (Resolve-FileObjectId $id)
```

Other volumes: pass `-Volume D:` etc. to `Resolve-FileObjectId`. Object IDs
are per-volume, so you need to know which drive the file lives on.

## Commands

| Command | Purpose |
|---|---|
| `Set-FileObjectId -Path` | Assign an Object ID if missing, return it as `[Guid]` |
| `Get-FileObjectId -Path` | Return the existing Object ID as `[Guid]` |
| `Resolve-FileObjectId -ObjectId [-Volume]` | Get the current path of a file by its ID |
| `ConvertTo-GuidFromHex -Hex` | Convert a raw 32-char hex string (e.g. `fsutil` output) to `[Guid]` |

Use `Get-Help <command> -Full` for detailed help on each command.

## Requirements

- Windows with NTFS volumes
- PowerShell 5.1 or later
- No admin privileges required

## Testing

Requires [Pester v5](https://pester.dev/).

Run unit tests:

```powershell
Invoke-Pester ./Tests/ -ExcludeTag Integration
```

Run integration tests (requires a real NTFS volume):

```powershell
Invoke-Pester ./Tests/ -Tag Integration
```

## Releasing

Releases are automated via GitHub Actions. To publish a new version:

1. Bump `ModuleVersion` in `FileObjectId/FileObjectId.psd1`
2. Merge the change to `main`
3. Push an annotated tag: `git tag -a v1.2.3 -m "Release v1.2.3" && git push origin v1.2.3`

The workflow will:
- Validate the tag matches the manifest version
- Run Pester unit tests
- Package the module as a `.nupkg`
- Sign the package with Azure Trusted Signing
- Create a GitHub Release with the signed `.nupkg` attached
- Publish the signed package to the PowerShell Gallery

## Caveats

- NTFS only. ReFS and FAT don't support Object IDs.
- Object IDs don't survive cross-volume moves, copies, or most backup/restore
  cycles. The destination becomes a new file with no ID.
- The Distributed Link Tracking Client service must be running (it is by default).
- No admin required -- the module opens the volume root as a directory hint
  rather than a raw volume handle.

## License

[MIT](LICENSE)
