# Module created by Microsoft.PowerShell.Crescendo
# Version: 1.1
# Schema: https://aka.ms/PowerShell/Crescendo/Schemas/2022-06
# Generated at: 04/10/2026 01:35:00
class CrescendoNativeError : System.Exception {
    [string]$Command
    [System.Exception]$InnerException
    [int]$ExitCode
    CrescendoNativeError([string]$command, [int]$exitCode, [System.Exception]$exception) : base($exception.Message) {
        $this.Command = $command
        $this.ExitCode = $exitCode
        $this.InnerException = $exception
    }
}

# Returns available errors
# Assumes that we are being called from within a script cmdlet when EmitAsError is used.
function Pop-CrescendoNativeError {
param ([switch]$EmitAsError)
    while ($__CrescendoNativeErrorQueue.Count -gt 0) {
        if ($EmitAsError) {
            $msg = $__CrescendoNativeErrorQueue.Dequeue()
            $er = [System.Management.Automation.ErrorRecord]::new([system.invalidoperationexception]::new($msg), $PSCmdlet.Name, 'InvalidOperation', $msg)
            $PSCmdlet.WriteError($er)
        }
        else {
            $__CrescendoNativeErrorQueue.Dequeue()
        }
    }
}
# Utility to throw an error if the native command returned a non-zero exit code.
function Invoke-CrescendoNativeErrorHandler {
param (
    [string]$command,
    [int]$exitCode
    )
    if ($exitCode -ne 0 -and $__CrescendoNativeErrorQueue.Count -gt 0) {
        $errorMessage = $__CrescendoNativeErrorQueue.Dequeue()
        $exception = [CrescendoNativeError]::new($command, $exitCode, [System.Exception]::new($errorMessage))
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, $command, 'InvalidOperation', $command)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}

function Get-FsutilObjectId
{
[CmdletBinding()]

param(
[Parameter(Mandatory=$true,Position=0)]
[string]$Path
    )

BEGIN {
    $PSNativeCommandUseErrorActionPreference = $true
    $__CrescendoNativeErrorQueue = [System.Collections.Queue]::new()
    $__PARAMETERMAP = @{
        Path = @{
            OriginalName = ''
            OriginalPosition = '0'
            Position = '2147483647'
            ParameterType = 'string'
            ApplyToExecutable = $False
            NoGap = $False
            ArgumentTransform = '$args'
            ArgumentTransformType = 'inline'
            }
    }

    $__outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = { $input } }
    }
}

PROCESS {
    $__boundParameters = $PSBoundParameters
    $__defaultValueParameters = $PSCmdlet.MyInvocation.MyCommand.Parameters.Values.Where({$_.Attributes.Where({$_.TypeId.Name -eq "PSDefaultValueAttribute"})}).Name
    $__defaultValueParameters.Where({ !$__boundParameters.ContainsKey($_) }).ForEach({$__boundParameters[$_] = get-variable -value $_})
    $__commandArgs = @()
    $MyInvocation.MyCommand.Parameters.Values.Where({$_.SwitchParameter -and $_.Name -notmatch "Debug|Coverage|Verbose|ErrorAction|WarningAction|InformationAction|ErrorVariable|WarningVariable|InformationVariable|OutVariable|OutBuffer|PipelineVariable"}).ForEach({$__boundParameters[$_.Name] = if ($__boundParameters.ContainsKey($_.Name)) { [bool]$__boundParameters[$_.Name] } else { [switch]::new($false) } })
    if ($__boundParameters["Debug"]){wait-debugger}
    foreach ($paramName in $__boundParameters.Keys |
            Where-Object {!$__PARAMETERMAP[$_].ApplyToExecutable} |
            Where-Object {!$__PARAMETERMAP[$_].ExcludeAsArgument}  |
            Sort-Object {$__PARAMETERMAP[$_].OriginalPosition}
        ) {
        $value = $__boundParameters[$paramName]
        $param = $__PARAMETERMAP[$paramName]
        if ($param) {
            if ($value -is [switch]) {
                 if ($value.IsPresent) {
                     if ($param.OriginalName) { $__commandArgs += $param.OriginalName }
                 }
                 elseif ($param.DefaultMissingValue) { $__commandArgs += $param.DefaultMissingValue }
            }
            elseif ( $param.NoGap ) {
                # if a transform is specified, use it and target the value provided
                if($param.ArgumentTransform -ne '$args') {
                    $transform = $param.ArgumentTransform
                    if($param.ArgumentTransformType -eq 'inline') {
                        $__commandArgs += & {param($args) $transform } $value
                    }
                    else {
                        $__commandArgs += & $transform $value
                    }
                }
                else {
                    $pFmt = "{0}{1}"
                    # quote the strings if they have spaces
                    if($value -match "\s") { $pFmt = "{0}""{1}""" }
                    $__commandArgs += $pFmt -f $param.OriginalName, $value
                }
            }
            else {
                if($param.OriginalName) { $__commandArgs += $param.OriginalName }
                if($param.ArgumentTransformType -eq 'inline') {
                   $transform = $param.ArgumentTransform
                   if ( $transform -ne '$args' ) {
                       $__commandArgs += & {param($args) $transform } $value
                   }
                   else {
                       $__commandArgs += $value
                   }
                }
                else {
                    $__commandArgs += & $param.ArgumentTransform $value
                }
            }
        }
    }
    $__commandArgs = $__commandArgs | Where-Object {$_ -ne $null}
    if ($__boundParameters["Debug"]){wait-debugger}
    if ( $__boundParameters["Verbose"]) {
         Write-Verbose -Verbose -Message "fsutil.exe"
         $__commandArgs | Write-Verbose -Verbose
    }
    $__handlerInfo = $__outputHandlers[$PSCmdlet.ParameterSetName]
    if (! $__handlerInfo ) {
        $__handlerInfo = $__outputHandlers["Default"] # Guaranteed to be present
    }
    $__handler = $__handlerInfo.Handler
    if ( $__handlerInfo.StreamOutput ) {
        & "fsutil.exe" objectid query $__commandArgs 2>&1| Push-CrescendoNativeError | & $__handler
    }
    else {
        $result = & "fsutil.exe" objectid query $__commandArgs 2>&1| Push-CrescendoNativeError
        & $__handler $result
    }
    # Pop-CrescendoNativeError -EmitAsError
} # end PROCESS

<#
.SYNOPSIS
Query the NTFS Object ID of a file using fsutil objectid query.

.DESCRIPTION
Query the NTFS Object ID of a file using fsutil objectid query.

.PARAMETER Path
Path to the file to query.


.EXAMPLE
PS> Get-FsutilObjectId

Original Command Elements: objectid,query


#>
}


function New-FsutilObjectId
{
[CmdletBinding()]

param(
[Parameter(Mandatory=$true,Position=0)]
[string]$Path
    )

BEGIN {
    $PSNativeCommandUseErrorActionPreference = $true
    $__CrescendoNativeErrorQueue = [System.Collections.Queue]::new()
    $__PARAMETERMAP = @{
        Path = @{
            OriginalName = ''
            OriginalPosition = '0'
            Position = '2147483647'
            ParameterType = 'string'
            ApplyToExecutable = $False
            NoGap = $False
            ArgumentTransform = '$args'
            ArgumentTransformType = 'inline'
            }
    }

    $__outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = { $input } }
    }
}

PROCESS {
    $__boundParameters = $PSBoundParameters
    $__defaultValueParameters = $PSCmdlet.MyInvocation.MyCommand.Parameters.Values.Where({$_.Attributes.Where({$_.TypeId.Name -eq "PSDefaultValueAttribute"})}).Name
    $__defaultValueParameters.Where({ !$__boundParameters.ContainsKey($_) }).ForEach({$__boundParameters[$_] = get-variable -value $_})
    $__commandArgs = @()
    $MyInvocation.MyCommand.Parameters.Values.Where({$_.SwitchParameter -and $_.Name -notmatch "Debug|Coverage|Verbose|ErrorAction|WarningAction|InformationAction|ErrorVariable|WarningVariable|InformationVariable|OutVariable|OutBuffer|PipelineVariable"}).ForEach({$__boundParameters[$_.Name] = if ($__boundParameters.ContainsKey($_.Name)) { [bool]$__boundParameters[$_.Name] } else { [switch]::new($false) } })
    if ($__boundParameters["Debug"]){wait-debugger}
    foreach ($paramName in $__boundParameters.Keys |
            Where-Object {!$__PARAMETERMAP[$_].ApplyToExecutable} |
            Where-Object {!$__PARAMETERMAP[$_].ExcludeAsArgument}  |
            Sort-Object {$__PARAMETERMAP[$_].OriginalPosition}
        ) {
        $value = $__boundParameters[$paramName]
        $param = $__PARAMETERMAP[$paramName]
        if ($param) {
            if ($value -is [switch]) {
                 if ($value.IsPresent) {
                     if ($param.OriginalName) { $__commandArgs += $param.OriginalName }
                 }
                 elseif ($param.DefaultMissingValue) { $__commandArgs += $param.DefaultMissingValue }
            }
            elseif ( $param.NoGap ) {
                # if a transform is specified, use it and target the value provided
                if($param.ArgumentTransform -ne '$args') {
                    $transform = $param.ArgumentTransform
                    if($param.ArgumentTransformType -eq 'inline') {
                        $__commandArgs += & {param($args) $transform } $value
                    }
                    else {
                        $__commandArgs += & $transform $value
                    }
                }
                else {
                    $pFmt = "{0}{1}"
                    # quote the strings if they have spaces
                    if($value -match "\s") { $pFmt = "{0}""{1}""" }
                    $__commandArgs += $pFmt -f $param.OriginalName, $value
                }
            }
            else {
                if($param.OriginalName) { $__commandArgs += $param.OriginalName }
                if($param.ArgumentTransformType -eq 'inline') {
                   $transform = $param.ArgumentTransform
                   if ( $transform -ne '$args' ) {
                       $__commandArgs += & {param($args) $transform } $value
                   }
                   else {
                       $__commandArgs += $value
                   }
                }
                else {
                    $__commandArgs += & $param.ArgumentTransform $value
                }
            }
        }
    }
    $__commandArgs = $__commandArgs | Where-Object {$_ -ne $null}
    if ($__boundParameters["Debug"]){wait-debugger}
    if ( $__boundParameters["Verbose"]) {
         Write-Verbose -Verbose -Message "fsutil.exe"
         $__commandArgs | Write-Verbose -Verbose
    }
    $__handlerInfo = $__outputHandlers[$PSCmdlet.ParameterSetName]
    if (! $__handlerInfo ) {
        $__handlerInfo = $__outputHandlers["Default"] # Guaranteed to be present
    }
    $__handler = $__handlerInfo.Handler
    if ( $__handlerInfo.StreamOutput ) {
        & "fsutil.exe" objectid create $__commandArgs 2>&1| Push-CrescendoNativeError | & $__handler
    }
    else {
        $result = & "fsutil.exe" objectid create $__commandArgs 2>&1| Push-CrescendoNativeError
        & $__handler $result
    }
    # Pop-CrescendoNativeError -EmitAsError
} # end PROCESS

<#
.SYNOPSIS
Create an NTFS Object ID on a file using fsutil objectid create.

.DESCRIPTION
Create an NTFS Object ID on a file using fsutil objectid create.

.PARAMETER Path
Path to the file.


.EXAMPLE
PS> New-FsutilObjectId

Original Command Elements: objectid,create


#>
}

Export-ModuleMember -Function Get-FsutilObjectId,New-FsutilObjectId
