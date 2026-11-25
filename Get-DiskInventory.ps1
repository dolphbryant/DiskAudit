<#
.SYNOPSIS
    Collects logical disk inventory from local and remote Windows computers.
.DESCRIPTION
    Retrieves fixed logical disk information using the Win32_LogicalDisk
    CIM class. Returns structured objects containing computer names, drive
    letters, volume labels, file systems, capacity, and utilization metrics.
    Supports local execution, remote computer names, existing CIM sessions,
    and pipeline input.
    CIM query failures are reported per target. Volumes containing invalid
    capacity data are skipped with a warning.
.PARAMETER ComputerName
    Specifies one or more Windows computers to query. Defaults to the
    local computer.
    Accepts pipeline input by value or property name.
.PARAMETER CimSession
    Specifies one or more existing CIM sessions to use when collecting
    disk inventory.
    Accepts CIM sessions through the pipeline.
.EXAMPLE
    Get-DiskInventory
    Collects disk inventory from the local computer.
.EXAMPLE
    Get-DiskInventory -ComputerName 'SERVER01', 'SERVER02'
    Collects disk inventory from multiple remote computers.
.EXAMPLE
    'SERVER01', 'SERVER02' | Get-DiskInventory
    Collects disk inventory using computer names supplied through
    the pipeline.
.EXAMPLE
    $Session = New-CimSession -ComputerName 'SERVER01'
    Get-DiskInventory -CimSession $Session
    Remove-CimSession -CimSession $Session
    Collects disk inventory using an existing CIM session.
.EXAMPLE
    Get-DiskInventory | Export-Csv -Path '.\DiskInventory.csv' -NoTypeInformation
    Exports local disk inventory to a CSV file.
.OUTPUTS
    System.Management.Automation.PSCustomObject
    One object per fixed logical disk containing computer name, drive
    letter, volume label, file system, capacity in bytes, and free and
    used space in both bytes and percentages.
.NOTES
    Target computers must run Windows and provide access to the
    Win32_LogicalDisk CIM class.
    Remote collection requires appropriate permissions and connectivity.
    This function does not modify disk configuration or contents.
#>

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
            $TargetName = switch ($PSCmdlet.ParameterSetName) {
                'ComputerName' { $Target }
                'CimSession'   { $Target.ComputerName }
            }

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

            Write-Verbose "Collecting disk inventory from $TargetName."

            try {
                $Disks = Get-CimInstance @CimParams
            }
            catch {
                $PSCmdlet.WriteError($_)
                continue
            }

            foreach ($Disk in $Disks) {
                $ResolvedName = if ([string]::IsNullOrWhiteSpace($Disk.SystemName)) {
                    $TargetName
                }
                else {
                    $Disk.SystemName
                }

                if (
                    $null -eq $Disk.Size -or
                    $null -eq $Disk.FreeSpace -or
                    $Disk.Size -le 0 -or
                    $Disk.FreeSpace -lt 0 -or
                    $Disk.FreeSpace -gt $Disk.Size
                ) {
                    Write-Warning "Invalid capacity data for $($Disk.DeviceID) on $ResolvedName. Skipping volume."
                    continue
                }

                $UsedBytes = $Disk.Size - $Disk.FreeSpace

                [PSCustomObject]@{
                    ComputerName  = $ResolvedName
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