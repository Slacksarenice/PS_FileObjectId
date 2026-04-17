#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot\..\PSFileObjectId\PSFileObjectId.psd1" -Force

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
        Mock Get-FsutilObjectId { $fsutilQueryOutput } -ModuleName PSFileObjectId

        $result = Get-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be $testGuid
    }

    It 'Throws when fsutil returns no Object ID line' {
        Mock Get-FsutilObjectId { 'Error: The file or directory is not reparse point.' } -ModuleName PSFileObjectId

        { Get-FileObjectId -Path $testPath } | Should -Throw '*No Object ID*'
    }
}

Describe 'Set-FileObjectId' {
    It 'Returns existing ID when file already has one' {
        Mock Get-FsutilObjectId {
            $fsutilQueryOutput
        } -ModuleName PSFileObjectId

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        $result | Should -Be $testGuid
        Should -Invoke Get-FsutilObjectId -Exactly 1 -ModuleName PSFileObjectId
    }

    It 'Creates an ID when file has none, then returns it' {
        $script:queryCallCount = 0

        Mock Get-FsutilObjectId {
            $script:queryCallCount++
            if ($script:queryCallCount -eq 1) {
                'The specified file has no object id'
            } else {
                $fsutilQueryOutput
            }
        } -ModuleName PSFileObjectId

        Mock New-FsutilObjectId {} -ModuleName PSFileObjectId

        $result = Set-FileObjectId -Path $testPath
        $result | Should -BeOfType [Guid]
        Should -Invoke New-FsutilObjectId -Exactly 1 -ModuleName PSFileObjectId
        Should -Invoke Get-FsutilObjectId -Exactly 2 -ModuleName PSFileObjectId
    }
}

Describe 'Resolve-FileObjectId' -Tag 'Integration' {
    It 'Resolves a moved file by its Object ID' {
        $tempFile = New-TemporaryFile
        $newPath = $null
        try {
            $id = Set-FileObjectId -Path $tempFile.FullName
            $id | Should -BeOfType [Guid]

            $newPath = Join-Path $env:TEMP "moved-$(Get-Random).tmp"
            Move-Item $tempFile.FullName $newPath

            $resolved = Resolve-FileObjectId -ObjectId $id
            # Compare by Object ID rather than path string: path normalization can
            # differ (for example, 8.3 short-name segments vs. long-name form), and
            # the Object ID is the strongest identity check available here anyway.
            Test-Path $resolved | Should -BeTrue
            Get-FileObjectId -Path $resolved | Should -Be $id
        } finally {
            if ($newPath -and (Test-Path $newPath)) { Remove-Item $newPath -Force }
            if (Test-Path $tempFile.FullName) { Remove-Item $tempFile.FullName -Force }
        }
    }
}
