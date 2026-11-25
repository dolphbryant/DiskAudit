function Get-DiskInventory {
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(
            ParameterSetName = 'ComputerName',
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Server', 'HostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(
            ParameterSetName = 'CimSession',
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]$CimSession
    )

    process {
        $Targets = switch ($PSCmdlet.ParameterSetName) {
            'ComputerName' { $ComputerName }
            'CimSession'   { $CimSession }
        }

        foreach ($Target in $Targets) {
            $CimParams = @{
                ClassName   = 'Win32_LogicalDisk'
                Filter      = 'DriveType = 3'
                ErrorAction = 'Stop'
            }

            switch ($PSCmdlet.ParameterSetName) {
                'ComputerName' {
                    if ($Target -notin @('localhost', '.', $env:COMPUTERNAME)) {
                        $CimParams['ComputerName'] = $Target
                    }
                }

                'CimSession' {
                    $CimParams['CimSession'] = $Target
                }
            }

            try {
                $Disks = Get-CimInstance @CimParams
            }
            catch {
                $PSCmdlet.WriteError($_)
                continue
            }

            foreach ($Disk in $Disks) {
                if (
                    $null -eq $Disk.Size -or
                    $null -eq $Disk.FreeSpace -or
                    $Disk.Size -le 0 -or
                    $Disk.FreeSpace -lt 0 -or
                    $Disk.FreeSpace -gt $Disk.Size
                ) {
                    Write-Warning "Invalid capacity data for $($Disk.DeviceID) on $($Disk.SystemName). Skipping volume."
                    continue
                }

                $UsedBytes = $Disk.Size - $Disk.FreeSpace

                [PSCustomObject]@{
                    ComputerName  = $Disk.SystemName
                    DriveLetter   = $Disk.DeviceID
                    VolumeLabel   = $Disk.VolumeName
                    FileSystem    = $Disk.FileSystem
                    CapacityBytes = $Disk.Size
                    FreeBytes     = $Disk.FreeSpace
                    UsedBytes     = $UsedBytes
                    FreePercent   = ($Disk.FreeSpace / $Disk.Size) * 100
                    UsedPercent   = ($UsedBytes / $Disk.Size) * 100
                }
            }
        }
    }
}