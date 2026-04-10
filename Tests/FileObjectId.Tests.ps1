#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot\..\FileObjectId\FileObjectId.psd1" -Force

    # Shared test data used across multiple Describe blocks
    $script:testPath = 'C:\fakefile.txt'
    $script:testHex  = '0102030405060708090a0b0c0d0e0f10'
    $script:testGuid = '04030201-0605-0807-090a-0b0c0d0e0f10'
    $script:fsutilQueryOutput = @(
        "Object ID : $script:testHex"
        "BirthVolume ID : 00000000000000000000000000000000"
        "BirthObject ID : 00000000000000000000000000000000"
        "Domain ID : 00000000000000000000000000000000"
    )
}

Describe 'ConvertTo-GuidFromHex' {
    It 'Converts a valid 32-char hex string to the correct Guid' {
        $guid = ConvertTo-GuidFromHex -Hex $testHex
        $guid | Should -BeOfType [Guid]
        $guid | Should -Be $testGuid
    }

    It 'Strips dashes and spaces before converting' {
        $expected = ConvertTo-GuidFromHex -Hex $testHex
        ConvertTo-GuidFromHex -Hex '01020304-05060708-090a0b0c-0d0e0f10' | Should -Be $expected
        ConvertTo-GuidFromHex -Hex '01020304 05060708 090a0b0c 0d0e0f10' | Should -Be $expected
    }

    It 'Throws on wrong-length hex string' {
        { ConvertTo-GuidFromHex -Hex 'abcdef' } | Should -Throw '*Expected 32 hex chars*'
    }

    It 'Throws on empty string' {
        { ConvertTo-GuidFromHex -Hex '' } | Should -Throw '*Expected 32 hex chars*'
    }
}

Describe 'Get-FileObjectId' {
    It 'Returns the correct Guid from fsutil query output' {
        Mock fsutil { $fsutilQueryOutput } -ParameterFilter {
            $args[0] -eq 'objectid' -and $args[1] -eq 'query'
        }

        $result = Get-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be $testGuid
    }

    It 'Throws when fsutil returns no Object ID line' {
        Mock fsutil { 'Error: The file or directory is not reparse point.' } -ParameterFilter {
            $args[0] -eq 'objectid' -and $args[1] -eq 'query'
        }

        { Get-FileObjectId -Path $testPath } | Should -Throw '*No Object ID*'
    }
}

Describe 'Set-FileObjectId' {
    It 'Returns existing ID when file already has one' {
        Mock fsutil {
            $global:LASTEXITCODE = 0
            $fsutilQueryOutput
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be $testGuid
        Should -Invoke fsutil -Exactly 2 -ParameterFilter {
            $args[0] -eq 'objectid' -and $args[1] -eq 'query'
        }
    }

    It 'Creates an ID when file has none, then returns it' {
        $script:queryCallCount = 0

        Mock fsutil {
            $script:queryCallCount++
            if ($script:queryCallCount -eq 1) {
                $global:LASTEXITCODE = 1
                'Error: No object id'
            } else {
                $global:LASTEXITCODE = 0
                $fsutilQueryOutput
            }
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'query' }

        Mock fsutil {
            $global:LASTEXITCODE = 0
        } -ParameterFilter { $args[0] -eq 'objectid' -and $args[1] -eq 'set' }

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        Should -Invoke fsutil -Exactly 1 -ParameterFilter {
            $args[0] -eq 'objectid' -and $args[1] -eq 'set'
        }
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
