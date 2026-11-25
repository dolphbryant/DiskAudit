
# DiskAudit

DiskAudit is a PowerShell-based project for collecting and auditing logical disk inventory and utilization across Windows infrastructure.

The project is designed to provide reusable, pipeline-friendly tools for infrastructure administrators, with an emphasis on structured output, error handling, and automated testing.

## Current Functionality

### Get-DiskInventory

Collects fixed logical disk inventory from local and remote Windows computers using the `Win32_LogicalDisk` CIM class.

Features include:

- Local and remote disk inventory collection.
- Support for multiple computer names and existing CIM sessions.
- Pipeline input by value and property name.
- Structured PowerShell object output.
- Per-target CIM error handling.
- Capacity data validation.
- Hostname resolution with fallback handling.
- Verbose diagnostic output.
- Native PowerShell comment-based help.

## Requirements

- Windows operating system.
- PowerShell with the `CimCmdlets` module available.
- Access to the `Win32_LogicalDisk` CIM class.
- Appropriate permissions and network connectivity for remote inventory collection.
- Pester 5.x for running unit tests.

No additional third-party modules are required for inventory collection.

## Getting Started

Clone the repository:

```powershell
git clone https://github.com/dolphbryant/DiskAudit.git
Set-Location DiskAudit
```

Dot-source the script to make the function available in the current PowerShell session:

```powershell
. .\Get-DiskInventory.ps1
```

View the function's built-in documentation:

```powershell
Get-Help Get-DiskInventory -Full
```

## Usage

### Local Inventory

Collect disk inventory from the local computer:

```powershell
Get-DiskInventory
```

### Remote Inventory

Collect disk inventory from one or more remote computers:

```powershell
Get-DiskInventory -ComputerName 'SERVER01', 'SERVER02'
```

### Pipeline Input

Supply computer names through the pipeline:

```powershell
'SERVER01', 'SERVER02' | Get-DiskInventory
```

### CIM Sessions

Collect inventory using an existing CIM session:

```powershell
$Session = New-CimSession -ComputerName 'SERVER01'

Get-DiskInventory -CimSession $Session

Remove-CimSession -CimSession $Session
```

Existing CIM sessions allow callers to manage authentication and connection configuration independently of the inventory function.

### Filtering Results

Identify volumes with less than 20 percent free space:

```powershell
Get-DiskInventory |
    Where-Object { $_.FreePercent -lt 20 }
```

### Sorting Results

Sort volumes by available capacity percentage:

```powershell
Get-DiskInventory |
    Sort-Object FreePercent
```

### Formatted Output

Display selected properties with capacity converted to gigabytes:

```powershell
Get-DiskInventory | Format-Table ComputerName, DriveLetter,
    @{Name = 'CapacityGB'; Expression = {
        [math]::Round($_.CapacityBytes / 1GB, 2)
    }},
    @{Name = 'FreeGB'; Expression = {
        [math]::Round($_.FreeBytes / 1GB, 2)
    }},
    @{Name = 'FreePercent'; Expression = {
        [math]::Round($_.FreePercent, 2)
    }}
```

### CSV Export

Export inventory results for reporting or further analysis:

```powershell
Get-DiskInventory -ComputerName 'SERVER01', 'SERVER02' |
    Export-Csv -Path '.\DiskInventory.csv' -NoTypeInformation
```

### Verbose Diagnostics

Enable verbose output to display inventory collection activity:

```powershell
Get-DiskInventory -ComputerName 'SERVER01', 'SERVER02' -Verbose
```

## Parameters

| Parameter | Type | Description |
| --- | --- | --- |
| `ComputerName` | `String[]` | One or more Windows computers to query. Defaults to the local computer. |
| `CimSession` | `CimSession[]` | One or more existing CIM sessions. |

The `ComputerName` parameter supports the aliases `CN`, `Server`, and `HostName`.

`ComputerName` and `CimSession` belong to separate parameter sets and cannot be specified together.

## Output

`Get-DiskInventory` returns one `PSCustomObject` per fixed logical disk.

| Property | Description |
| --- | --- |
| `ComputerName` | Computer hosting the logical disk. |
| `DriveLetter` | Logical disk identifier. |
| `VolumeLabel` | Assigned volume label. |
| `FileSystem` | File system type. |
| `CapacityBytes` | Total capacity in bytes. |
| `FreeBytes` | Available capacity in bytes. |
| `UsedBytes` | Utilized capacity in bytes. |
| `FreePercent` | Percentage of available capacity. |
| `UsedPercent` | Percentage of utilized capacity. |

Capacity values are returned in bytes, and percentages are returned as numeric values without explicit rounding. This preserves precision for downstream calculations, filtering, formatting, and reporting.

## Error Handling and Validation

CIM queries are performed independently for each target. Under default error handling behavior, a failed query produces a non-terminating error without preventing inventory collection from subsequent targets.

Volumes are skipped with a warning when:

- Total capacity or free space is null.
- Total capacity is zero or negative.
- Free space is negative.
- Free space exceeds total capacity.

When the CIM response does not contain a valid system name, the supplied target name is used instead.

The function supports standard PowerShell common parameters, including `-Verbose` and `-ErrorAction`.

## Scope and Limitations

- Inventory collection is limited to fixed logical disks (`DriveType = 3`) exposed through `Win32_LogicalDisk`.
- Physical disk health, SMART attributes, RAID configuration, and storage performance are outside the current scope.
- Remote inventory collection depends on CIM connectivity and sufficient permissions.
- The function performs read-only inventory collection and does not modify disk configuration or contents.
- Threshold evaluation and consolidated audit reporting are not currently implemented as dedicated functions.

## Testing

The project includes a Pester unit test suite covering inventory collection, parameter handling, output calculations, error handling, and data validation.

Install Pester if it is not already available:

```powershell
Install-Module -Name Pester -Scope CurrentUser
```

Run the unit tests from the repository root:

```powershell
Invoke-Pester -Path .\Tests -Output Detailed
```

Run tests with code coverage:

```powershell
$Config = New-PesterConfiguration

$Config.Run.Path = '.\Tests'
$Config.Output.Verbosity = 'Detailed'
$Config.CodeCoverage.Enabled = $true
$Config.CodeCoverage.Path = '.\Get-DiskInventory.ps1'

Invoke-Pester -Configuration $Config
```

Unit tests use mocked CIM responses to validate function behavior without requiring access to remote infrastructure.

## Repository Structure

```text
DiskAudit/
├── .gitignore
├── Get-DiskInventory.ps1
├── README.md
└── Tests/
    └── Get-DiskInventory.Tests.ps1
```

## Roadmap

Potential future development includes:

- Configurable disk utilization thresholds.
- Dedicated disk audit functionality.
- Consolidated audit results and summary reporting.
- Additional reporting and export capabilities.

## Project Status

DiskAudit is under active development. `Get-DiskInventory` provides the inventory collection foundation for future disk auditing and reporting functionality.