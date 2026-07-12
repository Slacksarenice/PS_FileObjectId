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
        Mock Get-FsutilErrorDetail { 'The specified file has no object id' } -ModuleName PSFileObjectId

        { Get-FileObjectId -Path $testPath } | Should -Throw '*No Object ID*use Set-FileObjectId first*'
    }

    It 'Surfaces the fsutil error detail when the file is missing' {
        Mock Get-FsutilObjectId { } -ModuleName PSFileObjectId
        Mock Get-FsutilErrorDetail { 'Error 2: The system cannot find the file specified.' } -ModuleName PSFileObjectId

        { Get-FileObjectId -Path $testPath } | Should -Throw '*cannot find the file specified*'
    }

    It 'Parses the ID line even when fsutil labels are localized' {
        # fsutil labels are MUI resource strings that language packs translate,
        # so the parser must key on the hex payload, not the English label.
        Mock Get-FsutilObjectId {
            @(
                "Objektbezeichner : $script:testHex"
                "BirthVolume-ID : 00000000000000000000000000000000"
            )
        } -ModuleName PSFileObjectId

        Get-FileObjectId -Path $testPath | Should -Be $testGuid
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

    It 'Throws with fsutil error detail when create fails' {
        Mock Get-FsutilObjectId { } -ModuleName PSFileObjectId
        Mock New-FsutilObjectId { } -ModuleName PSFileObjectId
        Mock Get-FsutilErrorDetail { 'Error 2: The system cannot find the file specified.' } -ModuleName PSFileObjectId

        { Set-FileObjectId -Path $testPath } | Should -Throw '*Failed to create*cannot find the file specified*'
    }

    It 'Prefers the create call''s own error text over the re-query detail' {
        # fsutil writes errors to stdout, so a failed create emits its cause
        # (e.g. access denied) on the success stream; that beats re-querying,
        # which would only restate that the file has no ID.
        Mock Get-FsutilObjectId { } -ModuleName PSFileObjectId
        Mock New-FsutilObjectId { 'Error 5: Access is denied.' } -ModuleName PSFileObjectId
        Mock Get-FsutilErrorDetail { 'The specified file has no object id' } -ModuleName PSFileObjectId

        { Set-FileObjectId -Path $testPath } | Should -Throw '*Failed to create*Access is denied*'
    }

    It 'Does not create an ID under -WhatIf' {
        Mock Get-FsutilObjectId { 'The specified file has no object id' } -ModuleName PSFileObjectId
        Mock New-FsutilObjectId { } -ModuleName PSFileObjectId

        Set-FileObjectId -Path $testPath -WhatIf | Should -BeNullOrEmpty
        Should -Invoke New-FsutilObjectId -Exactly 0 -ModuleName PSFileObjectId
    }
}

Describe 'Resolve-FileObjectId' -Tag 'Integration' {
    It 'Handles paths longer than the initial 1024-char buffer without truncation' {
        # fsutil itself is MAX_PATH-limited, so we can't Set-FileObjectId on a
        # long path directly. Instead, assign the ID on a short path, then move
        # the file into a deep directory tree so Resolve-FileObjectId's P/Invoke
        # path has to return a >1024-char path. Requires long-path support on
        # the host for Move-Item / New-Item to succeed on the destination.
        $shortFile = New-TemporaryFile
        $segment = 'a' * 200
        $longRoot = Join-Path $env:TEMP "longpath-test-$(Get-Random)"
        $longDir = $longRoot
        1..6 | ForEach-Object { $longDir = Join-Path $longDir $segment }
        $longFile = Join-Path $longDir "moved-$(Get-Random).tmp"

        try {
            $id = Set-FileObjectId -Path $shortFile.FullName

            try {
                New-Item -ItemType Directory -Path $longDir -Force -ErrorAction Stop | Out-Null
                Move-Item -Path $shortFile.FullName -Destination $longFile -ErrorAction Stop
            } catch {
                Set-ItResult -Skipped -Because "host does not support long paths: $($_.Exception.Message)"
                return
            }

            $longFile.Length | Should -BeGreaterThan 1024

            $resolved = Resolve-FileObjectId -ObjectId $id

            # If the resize branch didn't fire, $resolved would be silently
            # truncated at 1024 chars and Test-Path on it would fail.
            $resolved.Length | Should -BeGreaterThan 1024
            Test-Path $resolved | Should -BeTrue
        } finally {
            if (Test-Path $longRoot) { Remove-Item $longRoot -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $shortFile.FullName) { Remove-Item $shortFile.FullName -Force -ErrorAction SilentlyContinue }
        }
    }

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
