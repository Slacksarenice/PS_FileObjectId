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

function ConvertTo-GuidFromHex {
    <#
    .SYNOPSIS
        Converts a 32-character hex string (as printed by fsutil objectid) into a [Guid].
    .DESCRIPTION
        Takes a raw 32-character hex string in the byte order used by fsutil objectid
        query and converts it to a [Guid]. Dashes, spaces, and other non-hex characters
        are stripped before conversion.
    .PARAMETER Hex
        A 32-character hexadecimal string. Dashes and spaces are allowed and will be
        stripped automatically.
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
    param([Parameter(Mandatory)][string]$Path)
    $query = Get-FsutilObjectId -Path $Path 2>&1
    $match = $query | Select-String '^Object ID'
    if (-not $match) {
        $null = New-FsutilObjectId -Path $Path 2>&1
        $query = Get-FsutilObjectId -Path $Path 2>&1
        $match = $query | Select-String '^Object ID'
        if (-not $match) {
            throw "Failed to create Object ID on $Path"
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
    $line = Get-FsutilObjectId -Path $Path | Select-String '^Object ID'
    if (-not $line) { throw "No Object ID on $Path (use Set-FileObjectId first)" }
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

    $GENERIC_READ               = [uint32]2147483648
    $FILE_SHARE_RW              = [uint32]3
    $OPEN_EXISTING              = [uint32]3
    $FILE_FLAG_BACKUP_SEMANTICS = [uint32]0x02000000

    # Open the volume root as a directory hint — no admin required
    $vol = [Win32.FileId]::CreateFileW("$Volume\",
        [uint32]0, $FILE_SHARE_RW, [IntPtr]::Zero,
        $OPEN_EXISTING, $FILE_FLAG_BACKUP_SEMANTICS, [IntPtr]::Zero)
    if ($vol.IsInvalid) {
        throw "CreateFileW failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $desc = New-Object Win32.FileId+FILE_ID_DESCRIPTOR
    $desc.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($desc)
    $desc.Type = 1  # ObjectId
    $desc.Id = $ObjectId

    $h = [Win32.FileId]::OpenFileById($vol, [ref]$desc,
        $GENERIC_READ, $FILE_SHARE_RW, [IntPtr]::Zero, $FILE_FLAG_BACKUP_SEMANTICS)
    if ($h.IsInvalid) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $vol.Dispose()
        throw "OpenFileById failed: $err"
    }

    $sb = New-Object System.Text.StringBuilder 1024
    [void][Win32.FileId]::GetFinalPathNameByHandleW($h, $sb, $sb.Capacity, 0)
    $h.Dispose(); $vol.Dispose()

    # Strip the \\?\ prefix that GetFinalPathNameByHandle prepends
    $sb.ToString() -replace '^\\\\\?\\',''
}

Export-ModuleMember -Function Set-FileObjectId, Get-FileObjectId, Resolve-FileObjectId, ConvertTo-GuidFromHex
