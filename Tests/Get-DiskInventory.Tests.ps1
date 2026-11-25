[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'PSScriptAnalyzer does not understand Pester variable scoping.'
)]
param()

BeforeAll {
    . "$PSScriptRoot\..\Get-DiskInventory.ps1"
}

Describe 'Get-DiskInventory' {

    BeforeAll {
        function New-MockDisk {
            param(
                [AllowNull()]
                [AllowEmptyString()]
                $SystemName = 'TEST-SERVER',

                [string]$DeviceID = 'C:',

                [AllowEmptyString()]
                [string]$VolumeName = 'Windows',

                [string]$FileSystem = 'NTFS',

                $Size = [UInt64](100GB),

                $FreeSpace = [UInt64](25GB)
            )

            [PSCustomObject]@{
                SystemName = $SystemName
                DeviceID   = $DeviceID
                VolumeName = $VolumeName
                FileSystem = $FileSystem
                Size       = $Size
                FreeSpace  = $FreeSpace
            }
        }

        $MockDisk = New-MockDisk
    }

    Context 'Local computer detection' {

        BeforeEach {
            Mock Get-CimInstance {
                $MockDisk
            }
        }

        It 'Queries the local computer by default' {
            $Result = Get-DiskInventory

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_LogicalDisk' -and
                $Filter -eq 'DriveType = 3' -and
                $null -eq $ComputerName -and
                $null -eq $CimSession
            }

            $Result.ComputerName | Should -Be 'TEST-SERVER'
            $Result.DriveLetter | Should -Be 'C:'
        }

        It 'Queries locally when ComputerName is <Computer>' -ForEach @(
            @{ Computer = 'localhost' }
            @{ Computer = 'LOCALHOST' }
            @{ Computer = '.' }
            @{ Computer = $env:COMPUTERNAME }
        ) {
            $Result = Get-DiskInventory -ComputerName $Computer

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_LogicalDisk' -and
                $Filter -eq 'DriveType = 3' -and
                $null -eq $ComputerName -and
                $null -eq $CimSession
            }

            $Result.ComputerName | Should -Be 'TEST-SERVER'
        }

    }

    Context 'Remote computer targeting' {

        BeforeEach {
            Mock Get-CimInstance {
                $MockDisk
            }
        }

        It 'Passes a remote computer name to Get-CimInstance' {
            $Result = Get-DiskInventory -ComputerName 'TEST-SRV01'

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV01' -and
                $ClassName -eq 'Win32_LogicalDisk' -and
                $Filter -eq 'DriveType = 3' -and
                $null -eq $CimSession
            }

            $Result.ComputerName | Should -Be 'TEST-SERVER'
        }

        It 'Queries each remote computer independently' {
            $Result = Get-DiskInventory -ComputerName 'TEST-SRV01', 'TEST-SRV02'

            Should -Invoke Get-CimInstance -Times 2 -Exactly

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV01'
            }

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV02'
            }

            $Result.Count | Should -Be 2
        }

        It 'Does not carry remote connection parameters into local queries' {
            $Result = Get-DiskInventory -ComputerName 'TEST-SRV01', 'localhost'

            Should -Invoke Get-CimInstance -Times 2 -Exactly

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV01'
            }

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $null -eq $ComputerName -and
                $null -eq $CimSession
            }

            $Result.Count | Should -Be 2
        }
    }

    Context 'CIM session handling' {

        BeforeAll {
            $SessionOption = New-CimSessionOption -Protocol Wsman

            $TestSession01 = New-CimSession `
                -ComputerName 'TEST-SRV01' `
                -SessionOption $SessionOption `
                -SkipTestConnection

            $TestSession02 = New-CimSession `
                -ComputerName 'TEST-SRV02' `
                -SessionOption $SessionOption `
                -SkipTestConnection
        }

        BeforeEach {
            Mock Get-CimInstance {
                $MockDisk
            }
        }

        AfterAll {
            Remove-CimSession -CimSession $TestSession01, $TestSession02
        }

        It 'Accepts a caller-supplied CIM session' {
            $Result = Get-DiskInventory -CimSession $TestSession01

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $CimSession.ComputerName -eq 'TEST-SRV01' -and
                $null -eq $ComputerName -and
                $ClassName -eq 'Win32_LogicalDisk' -and
                $Filter -eq 'DriveType = 3'
            }

            $Result.ComputerName | Should -Be 'TEST-SERVER'
        }

        It 'Queries each CIM session independently' {
            $Result = Get-DiskInventory -CimSession $TestSession01, $TestSession02

            Should -Invoke Get-CimInstance -Times 2 -Exactly

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $CimSession.ComputerName -eq 'TEST-SRV01'
            }

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $CimSession.ComputerName -eq 'TEST-SRV02'
            }

            $Result.Count | Should -Be 2
        }

        It 'Accepts CIM sessions through the pipeline' {
            $Result = @($TestSession01, $TestSession02) | Get-DiskInventory

            Should -Invoke Get-CimInstance -Times 2 -Exactly

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $CimSession.ComputerName -eq 'TEST-SRV01'
            }

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $CimSession.ComputerName -eq 'TEST-SRV02'
            }

            $Result.Count | Should -Be 2
        }

        It 'Does not remove caller-supplied CIM sessions' {
            Mock Remove-CimSession {}

            Get-DiskInventory -CimSession $TestSession01 | Out-Null

            Should -Invoke Remove-CimSession -Times 0 -Exactly
        }
    }

    Context 'Capacity calculations' {

        BeforeEach {
            Mock Get-CimInstance {
                $MockDisk
            }
        }

        It 'Preserves raw capacity and free space values' {
            $Result = Get-DiskInventory

            $Result.CapacityBytes | Should -Be (100GB)
            $Result.FreeBytes | Should -Be (25GB)
        }

        It 'Correctly calculates used capacity' {
            $Result = Get-DiskInventory

            $Result.UsedBytes | Should -Be (75GB)
        }

        It 'Correctly calculates utilization percentages' {
            $Result = Get-DiskInventory

            $Result.FreePercent | Should -Be 25
            $Result.UsedPercent | Should -Be 75
        }

        It 'Preserves expected numerical types' {
            $Result = Get-DiskInventory

            $Result.CapacityBytes | Should -BeOfType ([UInt64])
            $Result.FreeBytes | Should -BeOfType ([UInt64])
            $Result.UsedBytes | Should -BeOfType ([UInt64])
            $Result.FreePercent | Should -BeOfType ([double])
            $Result.UsedPercent | Should -BeOfType ([double])
        }

        It 'Correctly calculates utilization for <State> volume' -ForEach @(
            @{
                State               = 'completely empty'
                AvailableBytes      = 100GB
                ExpectedUsedPercent = 0
            }
            @{
                State               = 'completely full'
                AvailableBytes      = 0
                ExpectedUsedPercent = 100
            }
        ) {
            Mock Get-CimInstance {
                New-MockDisk -VolumeName 'Data' -FreeSpace ([UInt64]$AvailableBytes)
            }

            $Result = Get-DiskInventory

            $Result.UsedPercent | Should -Be $ExpectedUsedPercent
            $Result.FreePercent | Should -Be (100 - $ExpectedUsedPercent)
        }

        It 'Preserves percentage precision without rounding' {
            Mock Get-CimInstance {
                New-MockDisk -VolumeName 'Data' -Size ([UInt64]100000) -FreeSpace ([UInt64]10004)
            }

            $Result = Get-DiskInventory

            $Result.UsedPercent | Should -BeLessThan 90
            $Result.UsedPercent | Should -BeGreaterThan 89.99
        }
    }

    Context 'Invalid capacity data' {

        It 'Skips volumes with <Condition>' -ForEach @(
            @{ Condition = 'null capacity';        Size = $null; FreeSpace = 500 }
            @{ Condition = 'null free space';      Size = 1000;  FreeSpace = $null }
            @{ Condition = 'zero capacity';        Size = 0;     FreeSpace = 0 }
            @{ Condition = 'negative capacity';    Size = -1000; FreeSpace = 0 }
            @{ Condition = 'negative free space';  Size = 1000; FreeSpace = -100 }
            @{ Condition = 'excessive free space'; Size = 1000; FreeSpace = 1500 }
        ) {
            Mock Get-CimInstance {
                New-MockDisk -VolumeName 'Data' -Size $Size -FreeSpace $FreeSpace
            }

            Mock Write-Warning {}

            $Result = @(Get-DiskInventory)

            $Result.Count | Should -Be 0

            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                $Message -eq 'Invalid capacity data for C: on TEST-SERVER. Skipping volume.'
            }
        }

        It 'Continues processing after encountering an invalid volume' {
            Mock Get-CimInstance {
                New-MockDisk -DeviceID 'D:' -VolumeName 'Invalid' -Size 0 -FreeSpace 0

                $MockDisk
            }

            Mock Write-Warning {}

            $Result = @(Get-DiskInventory)

            $Result.Count | Should -Be 1
            $Result[0].DriveLetter | Should -Be 'C:'
            $Result[0].UsedPercent | Should -Be 75

            Should -Invoke Write-Warning -Times 1 -Exactly
        }
    }

    Context 'Computer name resolution' {

        It 'Preserves the provider-reported computer name' {
            Mock Get-CimInstance {
                $MockDisk
            }

            $Result = Get-DiskInventory -ComputerName 'TEST-SRV01'

            $Result.ComputerName | Should -Be 'TEST-SERVER'
        }

        It 'Falls back to the requested computer name when SystemName is <Condition>' -ForEach @(
            @{ Condition = 'null';       ReportedName = $null }
            @{ Condition = 'empty';      ReportedName = '' }
            @{ Condition = 'whitespace'; ReportedName = '   ' }
        ) {
            Mock Get-CimInstance {
                New-MockDisk -SystemName $ReportedName
            }

            $Result = Get-DiskInventory -ComputerName 'TEST-SRV01'

            $Result.ComputerName | Should -Be 'TEST-SRV01'
        }

        It 'Falls back to the local hostname when no target is specified' {
            Mock Get-CimInstance {
                New-MockDisk -SystemName $null
            }

            $Result = Get-DiskInventory

            $Result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It 'Falls back to the CIM session computer name' {
            $TestSession = New-CimSession `
                -ComputerName 'TEST-SRV01' `
                -SkipTestConnection

            try {
                Mock Get-CimInstance {
                    New-MockDisk -SystemName $null
                }

                $Result = Get-DiskInventory -CimSession $TestSession

                $Result.ComputerName | Should -Be 'TEST-SRV01'
            }
            finally {
                Remove-CimSession -CimSession $TestSession
            }
        }
    }

    Context 'Error handling' {

        It 'Invokes CIM queries with ErrorAction Stop' {
            Mock Get-CimInstance {
                $MockDisk
            }

            Get-DiskInventory | Out-Null

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ErrorAction -eq 'Stop'
            }
        }

        It 'Returns no inventory objects when a query fails' {
            Mock Get-CimInstance {
                throw 'Simulated CIM query failure.'
            }

            $Result = @(Get-DiskInventory -ErrorAction SilentlyContinue)

            $Result.Count | Should -Be 0
        }

        It 'Preserves the original error message' {
            Mock Get-CimInstance {
                throw 'Simulated CIM query failure.'
            }

            Get-DiskInventory `
                -ErrorAction SilentlyContinue `
                -ErrorVariable QueryErrors |
                Out-Null

            $QueryErrors[-1].Exception.Message |
                Should -Be 'Simulated CIM query failure.'
        }

        It 'Continues processing after a target fails' {
            Mock Get-CimInstance {
                $MockDisk
            }

            Mock Get-CimInstance {
                throw 'Simulated CIM query failure.'
            } -ParameterFilter {
                $ComputerName -eq 'TEST-SRV01'
            }

            $Result = @(Get-DiskInventory `
                -ComputerName 'TEST-SRV01', 'TEST-SRV02' `
                -ErrorAction SilentlyContinue)

            Should -Invoke Get-CimInstance -Times 2 -Exactly

            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV02'
            }

            $Result.Count | Should -Be 1
            $Result[0].UsedPercent | Should -Be 75
        }

        It 'Terminates processing when the caller specifies ErrorAction Stop' {
            Mock Get-CimInstance {
                $MockDisk
            }

            Mock Get-CimInstance {
                throw 'Simulated CIM query failure.'
            } -ParameterFilter {
                $ComputerName -eq 'TEST-SRV01'
            }

            {
                Get-DiskInventory `
                    -ComputerName 'TEST-SRV01', 'TEST-SRV02' `
                    -ErrorAction Stop
            } | Should -Throw '*Simulated CIM query failure*'

            Should -Invoke Get-CimInstance -Times 0 -Exactly -ParameterFilter {
                $ComputerName -eq 'TEST-SRV02'
            }
        }
    }
}