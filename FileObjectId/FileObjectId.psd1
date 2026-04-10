@{
    RootModule        = 'FileObjectId.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a7f3c2e1-4b8d-4e9a-9c6f-1d2e3f4a5b6c'
    Author            = 'Seth Miller'
    Description       = 'Track files by NTFS Object ID so they can be found after being moved or renamed on the same volume.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Set-FileObjectId', 'Get-FileObjectId', 'Resolve-FileObjectId', 'ConvertTo-GuidFromHex')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('NTFS','ObjectId','FileSystem','Windows')
            ProjectUri = 'https://github.com/Slacksarenice/PS_FileObjectId'
        }
    }
}
