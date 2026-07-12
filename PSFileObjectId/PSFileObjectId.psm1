# PSFileObjectId.psm1
# Track files by NTFS Object ID so you can find them after they're moved
# or renamed anywhere on the same volume.

if (-not ('Win32.FileId' -as [type])) {
    Add-Type -Namespace Win32 -Name FileId -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct FILE_ID_DESCRIPTOR {
    public uint dwSize;
    public int Type;
    public System.Guid Id;
}

[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(
    string lpFileName, uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwCreationDisposition,
    uint dwFlagsAndAttributes, IntPtr hTemplateFile);

[DllImport("kernel32.dll", SetLastError=true)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle OpenFileById(
    Microsoft.Win32.SafeHandles.SafeFileHandle hVolumeHint,
    ref FILE_ID_DESCRIPTOR lpFileId,
    uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwFlagsAndAttributes);

[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern uint GetFinalPathNameByHandleW(
    Microsoft.Win32.SafeHandles.SafeFileHandle hFile,
    System.Text.StringBuilder lpszFilePath,
    uint cchFilePath, uint dwFlags);
'@
}

function ConvertFrom-ObjectIdLine {
    # Private helper: parses the "Object ID : <hex>" line from fsutil output into a [Guid].
    param([Parameter(Mandatory)]$Line)
    $hex = ($Line.ToString() -split ':',2)[1].Trim()
    ConvertTo-GuidFromHex $hex
}

function Find-ObjectIdLine {
    # Private helper: returns the first line of fsutil objectid output whose
    # value is a 32-char hex string. fsutil always prints the Object ID line
    # first (before BirthVolume ID, BirthObjectId ID, and Domain ID), and its
    # labels are MUI-localized, so match on the hex payload rather than the
    # English "Object ID" label.
    param($Output)
    $Output | Select-String ':\s*[0-9a-fA-F]{32}\s*$' | Select-Object -First 1
}

function Get-Win32ErrorMessage {
    # Private helper: renders a Win32 error code as its system message plus
    # the numeric code, e.g. "Access is denied. (error 5)".
    param([Parameter(Mandatory)][int]$Code)
    '{0} (error {1})' -f [System.ComponentModel.Win32Exception]::new($Code).Message, $Code
}

function Get-FsutilErrorDetail {
    # Private helper: the Crescendo wrappers swallow fsutil's stderr into an
    # unread queue, so re-invoke fsutil directly to recover the error text.
    # Always uses the read-only `query` verb so repeating the call can't
    # mutate state. Returns the first non-empty line of fsutil output, or
    # $null if fsutil produced nothing or couldn't be invoked. Callers own
    # the formatting of the result into their error message.
    #
    # Uses a fully-qualified System32 path rather than a PATH lookup so a
    # rogue fsutil.exe earlier in PATH or the working directory can't be
    # substituted for the system binary.
    param([Parameter(Mandatory)][string]$Path)
    $fsutil = Join-Path $env:SystemRoot 'System32\fsutil.exe'
    try {
        & $fsutil objectid query $Path 2>&1 |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ } |
            Select-Object -First 1
    } catch {
        $null
    }
}

function ConvertTo-GuidFromHex {
    <#
    .SYNOPSIS
        Converts a 32-character hex string (as printed by fsutil objectid) into a [Guid].
    .DESCRIPTION
        Takes a raw 32-character hex string in the byte order used by fsutil objectid
        query and converts it to a [Guid]. Dashes, spaces, and other non-hex characters
        are stripped before conversion.
    .PARAMETER Hex
        A 32-character hexadecimal string in fsutil's raw on-disk byte order.
        Dashes and spaces are allowed and will be stripped automatically.
        Do not pass the dashed display form of an existing [Guid] (for example
        the string printed by Get-FileObjectId): the first three fields would
        be silently byte-swapped and a different Guid returned. To parse a
        dashed Guid string, cast it with [Guid] instead.
    .EXAMPLE
        ConvertTo-GuidFromHex '0102030405060708090a0b0c0d0e0f10'
    .OUTPUTS
        [Guid]
    .LINK
        https://github.com/Slacksarenice/PS_FileObjectId
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Hex)
    $Hex = $Hex -replace '[^0-9a-fA-F]',''
    if ($Hex.Length -ne 32) { throw "Expected 32 hex chars, got $($Hex.Length)" }
    $bytes = [byte[]]::new(16)
    for ($i = 0; $i -lt 16; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    [Guid]::new($bytes)
}

function Set-FileObjectId {
    <#
    .SYNOPSIS
        Ensures a file has an NTFS Object ID, creating one if needed, and returns it.
    .DESCRIPTION
        Checks whether the file already has an NTFS Object ID. If not, creates one
        using fsutil objectid create. Returns the Object ID as a [Guid] either way.
    .PARAMETER Path
        Path to the file to assign an Object ID to.
    .EXAMPLE
        $id = Set-FileObjectId C:\notes\todo.txt
    .OUTPUTS
        [Guid]
    .LINK
        https://github.com/Slacksarenice/PS_FileObjectId
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    $query = Get-FsutilObjectId -Path $Path -ErrorAction SilentlyContinue
    $match = Find-ObjectIdLine $query
    if (-not $match) {
        if (-not $PSCmdlet.ShouldProcess($Path, 'Create NTFS Object ID')) { return }
        $create = New-FsutilObjectId -Path $Path -ErrorAction SilentlyContinue
        $query = Get-FsutilObjectId -Path $Path -ErrorAction SilentlyContinue
        $match = Find-ObjectIdLine $query
        if (-not $match) {
            # fsutil writes its error text to stdout, so the create call's own
            # output is the most accurate detail (e.g. "Error 5: Access is
            # denied."). Fall back to re-querying, but drop a "no object id"
            # detail there: it restates what we already know and would mask
            # the create failure.
            $detail = $create | ForEach-Object { $_.ToString().Trim() } |
                Where-Object { $_ -and $_ -notmatch ':\s*[0-9a-fA-F]{32}\s*$' } |
                Select-Object -First 1
            if (-not $detail) {
                $detail = Get-FsutilErrorDetail -Path $Path
                if ($detail -match '(?i)no object id') { $detail = $null }
            }
            $suffix = if ($detail) { ": $detail" } else { '' }
            throw "Failed to create Object ID on '$Path'$suffix"
        }
    }
    ConvertFrom-ObjectIdLine $match
}

function Get-FileObjectId {
    <#
    .SYNOPSIS
        Reads the existing NTFS Object ID from a file and returns it as a [Guid].
    .DESCRIPTION
        Queries the file's NTFS Object ID using fsutil objectid query. Throws if
        the file has no Object ID assigned. Use Set-FileObjectId to assign one first.
    .PARAMETER Path
        Path to the file to query.
    .EXAMPLE
        Get-FileObjectId C:\notes\todo.txt
    .OUTPUTS
        [Guid]
    .LINK
        https://github.com/Slacksarenice/PS_FileObjectId
    #>
    param([Parameter(Mandatory)][string]$Path)
    $line = Find-ObjectIdLine (Get-FsutilObjectId -Path $Path -ErrorAction SilentlyContinue)
    if (-not $line) {
        $detail = Get-FsutilErrorDetail -Path $Path
        # "The specified file has no object id" is fsutil's way of telling us the
        # file exists but lacks an ID, so redirect the user to Set-FileObjectId.
        # For any other error (missing file, access denied, ...) surface the detail.
        if (-not $detail -or $detail -match '(?i)no object id') {
            throw "No Object ID on '$Path' (use Set-FileObjectId first)"
        }
        throw "No Object ID on '$Path': $detail"
    }
    ConvertFrom-ObjectIdLine $line
}

function Resolve-FileObjectId {
    <#
    .SYNOPSIS
        Looks up a file by its NTFS Object ID and returns its current path.
    .DESCRIPTION
        Opens the volume root as a directory handle, then uses OpenFileById to
        locate the file by its Object ID. Returns the file's current full path.
        No admin privileges are required.
    .PARAMETER ObjectId
        The NTFS Object ID to look up, as a [Guid].
    .PARAMETER Volume
        The volume to search. Defaults to 'C:'. Object IDs are per-volume, so
        you must specify the correct drive.
    .EXAMPLE
        $id = Set-FileObjectId C:\notes\todo.txt
        Move-Item C:\notes\todo.txt C:\archive\todo.txt
        Resolve-FileObjectId $id
        # Returns: C:\archive\todo.txt
    .EXAMPLE
        Resolve-FileObjectId $id -Volume D:
    .OUTPUTS
        [String]
    .LINK
        https://github.com/Slacksarenice/PS_FileObjectId
    #>
    param(
        [Parameter(Mandatory)][Guid]$ObjectId,
        [string]$Volume = 'C:'
    )

    $FILE_SHARE_RWD             = [uint32]7  # read, write, delete
    $OPEN_EXISTING              = [uint32]3
    $FILE_FLAG_BACKUP_SEMANTICS = [uint32]0x02000000

    # Open the volume root as a directory hint (no admin required)
    $vol = [Win32.FileId]::CreateFileW("$Volume\",
        [uint32]0, $FILE_SHARE_RWD, [IntPtr]::Zero,
        $OPEN_EXISTING, $FILE_FLAG_BACKUP_SEMANTICS, [IntPtr]::Zero)
    if ($vol.IsInvalid) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $vol.Dispose()
        throw "CreateFileW failed: $(Get-Win32ErrorMessage $err)"
    }

    try {
        $desc = New-Object Win32.FileId+FILE_ID_DESCRIPTOR
        $desc.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($desc)
        $desc.Type = 1  # ObjectId
        $desc.Id = $ObjectId

        # Attribute-only open (access 0, share all): resolving a path needs no
        # read access, and this way files that are ACL-denied for reading,
        # exclusively locked, or delete-pending can still be resolved.
        $h = [Win32.FileId]::OpenFileById($vol, [ref]$desc,
            [uint32]0, $FILE_SHARE_RWD, [IntPtr]::Zero, $FILE_FLAG_BACKUP_SEMANTICS)
        if ($h.IsInvalid) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $h.Dispose()
            throw "OpenFileById failed: $(Get-Win32ErrorMessage $err)"
        }

        try {
            # 1024 handles most paths; grow once if the full path is longer (up to 32767).
            # Casts to [int] are required because $written is [uint32] and
            # `New-Object StringBuilder $uint` binds to the (string) overload.
            $sb = New-Object System.Text.StringBuilder 1024
            $written = [Win32.FileId]::GetFinalPathNameByHandleW($h, $sb, $sb.Capacity, 0)
            if ($written -eq 0) {
                $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                throw "GetFinalPathNameByHandleW failed: $(Get-Win32ErrorMessage $err)"
            }
            if ($written -ge $sb.Capacity) {
                $sb = New-Object System.Text.StringBuilder ([int]($written + 1))
                $written = [Win32.FileId]::GetFinalPathNameByHandleW($h, $sb, $sb.Capacity, 0)
                if ($written -eq 0 -or $written -ge $sb.Capacity) {
                    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    throw "GetFinalPathNameByHandleW failed after resize: $(Get-Win32ErrorMessage $err)"
                }
            }

            # Strip the \\?\ prefix that GetFinalPathNameByHandle prepends
            $sb.ToString() -replace '^\\\\\?\\',''
        } finally {
            $h.Dispose()
        }
    } finally {
        $vol.Dispose()
    }
}

Export-ModuleMember -Function Set-FileObjectId, Get-FileObjectId, Resolve-FileObjectId, ConvertTo-GuidFromHex
