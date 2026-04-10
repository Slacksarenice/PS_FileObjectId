#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot\..\FileObjectId\FileObjectId.psd1" -Force
}

Describe 'ConvertTo-GuidFromHex' {
    It 'Converts a valid 32-char hex string to the correct Guid' {
        $hex  = '0102030405060708090a0b0c0d0e0f10'
        $guid = ConvertTo-GuidFromHex -Hex $hex
        $guid | Should -BeOfType [Guid]
        $guid | Should -Be '04030201-0605-0807-090a-0b0c0d0e0f10'
    }

    It 'Strips dashes and spaces before converting' {
        $hex      = '01020304-05060708-090a0b0c-0d0e0f10'
        $hexSpace = '01020304 05060708 090a0b0c 0d0e0f10'
        $expected = ConvertTo-GuidFromHex -Hex '0102030405060708090a0b0c0d0e0f10'

        ConvertTo-GuidFromHex -Hex $hex      | Should -Be $expected
        ConvertTo-GuidFromHex -Hex $hexSpace | Should -Be $expected
    }

    It 'Throws on wrong-length hex string' {
        { ConvertTo-GuidFromHex -Hex 'abcdef' } | Should -Throw '*Expected 32 hex chars*'
    }

    It 'Throws on empty string' {
        { ConvertTo-GuidFromHex -Hex '' } | Should -Throw '*Expected 32 hex chars*'
    }
}

Describe 'Get-FileObjectId' {
    BeforeAll {
        $script:testPath = 'C:\fakefile.txt'
    }

    It 'Returns the correct Guid from fsutil query output' {
        Mock fsutil {
            @(
                "Object ID : 0102030405060708090a0b0c0d0e0f10"
                "BirthVolume ID : 00000000000000000000000000000000"
                "BirthObject ID : 00000000000000000000000000000000"
                "Domain ID : 00000000000000000000000000000000"
            )
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        $result = Get-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be '04030201-0605-0807-090a-0b0c0d0e0f10'
    }

    It 'Throws when fsutil returns no Object ID line' {
        Mock fsutil {
            @("Error: The file or directory is not reparse point.")
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        { Get-FileObjectId -Path $testPath } | Should -Throw '*No Object ID*'
    }
}

Describe 'Set-FileObjectId' {
    BeforeAll {
        $script:testPath = 'C:\fakefile.txt'
        $script:testHex  = '0102030405060708090a0b0c0d0e0f10'
    }

    It 'Returns existing ID when file already has one' {
        Mock fsutil {
            $global:LASTEXITCODE = 0
            @(
                "Object ID : $testHex"
                "BirthVolume ID : 00000000000000000000000000000000"
                "BirthObject ID : 00000000000000000000000000000000"
                "Domain ID : 00000000000000000000000000000000"
            )
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be '04030201-0605-0807-090a-0b0c0d0e0f10'
        Should -Invoke fsutil -Times 2 -Exactly
    }

    It 'Creates an ID when file has none, then returns it' {
        $script:queryCallCount = 0

        Mock fsutil {
            $script:queryCallCount++
            if ($script:queryCallCount -eq 1) {
                # First query call: simulate no ID (non-zero exit code)
                $global:LASTEXITCODE = 1
                "Error: No object id"
            } else {
                # Second query call (after create): return the new ID
                $global:LASTEXITCODE = 0
                @(
                    "Object ID : $testHex"
                    "BirthVolume ID : 00000000000000000000000000000000"
                    "BirthObject ID : 00000000000000000000000000000000"
                    "Domain ID : 00000000000000000000000000000000"
                )
            }
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        Mock fsutil {
            $global:LASTEXITCODE = 0
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'set' }

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        Should -Invoke fsutil -Times 1 -Exactly -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'set' }
    }
}

Describe 'Resolve-FileObjectId' -Tag 'Integration' {
    It 'Resolves a moved file by its Object ID' {
        $tempFile = New-TemporaryFile
        try {
            $id = Set-FileObjectId -Path $tempFile.FullName
            $id | Should -BeOfType [Guid]

            $newPath = Join-Path $env:TEMP "moved-$(Get-Random).tmp"
            Move-Item $tempFile.FullName $newPath

            $resolved = Resolve-FileObjectId -ObjectId $id
            $resolved | Should -Be $newPath
        } finally {
            if (Test-Path $newPath) { Remove-Item $newPath -Force }
            if (Test-Path $tempFile.FullName) { Remove-Item $tempFile.FullName -Force }
        }
    }
}
