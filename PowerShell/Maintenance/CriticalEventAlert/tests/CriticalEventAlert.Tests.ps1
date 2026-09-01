<#
.SYNOPSIS
Tests focused Windows reliability event classification and alert suppression.

.DESCRIPTION
Uses event-shaped fixtures to validate the Critical Event Alert module without
reading the local Windows event log or creating scheduled tasks.

.CONTEXT
Personal PowerShell profile - Windows reliability monitoring

.AUTHOR
Greg Tate

.NOTES
Program: CriticalEventAlert.Tests.ps1
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\CriticalEventAlert.psm1'
    Import-Module -Name $modulePath -Force
}

Describe 'ConvertTo-CriticalEventAlertCandidate' {
    It 'classifies a Disk bad-block event with its disk device identity' {
        $eventRecord = [pscustomobject]@{
            ProviderName = 'Disk'
            Id           = 7
            Level        = 2
            TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
            RecordId     = 1
            Message      = 'The device, \Device\Harddisk2\DR2, has a bad block.'
        }
        $eventRecord | Add-Member -MemberType ScriptMethod -Name FormatDescription -Value {
            $this.Message
        }

        $candidate = $eventRecord |
            ConvertTo-CriticalEventAlertCandidate

        $candidate.Classification | Should -Be 'Disk bad block detected'
        $candidate.Device | Should -Be '\Device\Harddisk2\DR2'
    }

    It 'classifies a generic Critical System event' {
        $eventRecord = [pscustomobject]@{
            ProviderName = 'Microsoft-Windows-Kernel-Power'
            Id           = 41
            Level        = 1
            TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
            RecordId     = 2
            Message      = 'The system rebooted without cleanly shutting down first.'
        }
        $eventRecord | Add-Member -MemberType ScriptMethod -Name FormatDescription -Value {
            $this.Message
        }

        $candidate = $eventRecord |
            ConvertTo-CriticalEventAlertCandidate

        $candidate.Classification | Should -Be 'Unexpected system reboot detected'
    }

    It 'classifies the supported single-event reliability candidates' {
        $cases = @(
            @{ ProviderName = 'Disk'; Id = 154; Level = 2; Classification = 'Disk I/O operation failed due to hardware error'; Severity = 'Critical'; Message = 'The I/O operation failed due to a hardware error.' },
            @{ ProviderName = 'stornvme'; Id = 129; Level = 3; Classification = 'NVMe storage device reset'; Severity = 'Warning'; Message = 'Reset to device, \Device\RaidPort1, was issued.' },
            @{ ProviderName = 'Microsoft-Windows-WHEA-Logger'; Id = 20; Level = 1; Classification = 'Uncorrectable hardware error reported by WHEA'; Severity = 'Critical'; Message = 'A fatal hardware error has occurred.' },
            @{ ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; Level = 1; Classification = 'Unexpected system reboot detected'; Severity = 'Warning'; Message = 'The system has rebooted without cleanly shutting down first.' },
            @{ ProviderName = 'EventLog'; Id = 6008; Level = 2; Classification = 'Unexpected system shutdown detected'; Severity = 'Warning'; Message = 'The previous system shutdown was unexpected.' },
            @{ ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; Level = 2; Classification = 'System bugcheck recorded'; Severity = 'Critical'; Message = 'The computer has rebooted from a bugcheck.' },
            @{ ProviderName = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Id = 2004; Level = 3; Classification = 'Low virtual memory condition detected'; Severity = 'Warning'; Message = 'Windows successfully diagnosed a low virtual memory condition.' }
        )

        foreach ($case in $cases) {
            $eventRecord = [pscustomobject]@{
                ProviderName = $case.ProviderName
                Id           = $case.Id
                Level        = $case.Level
                TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
                RecordId     = $case.Id
                Message      = $case.Message
            }
            $eventRecord | Add-Member -MemberType ScriptMethod -Name FormatDescription -Value {
                $this.Message
            }

            $candidate = $eventRecord |
                ConvertTo-CriticalEventAlertCandidate

            $candidate.Classification | Should -Be $case.Classification
            $candidate.Severity | Should -Be $case.Severity
        }
    }

    It 'ignores non-critical events outside the focused event set' {
        $eventRecord = [pscustomobject]@{
            ProviderName = 'Service Control Manager'
            Id           = 7036
            Level        = 4
            TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
            RecordId     = 3
            Message      = 'A service entered the running state.'
        }
        $eventRecord | Add-Member -MemberType ScriptMethod -Name FormatDescription -Value {
            $this.Message
        }

        $candidate = $eventRecord |
            ConvertTo-CriticalEventAlertCandidate

        $candidate | Should -BeNullOrEmpty
    }
}

Describe 'Critical Event Alert reboot correlation' {
    It 'combines matching reboot records into one incident' {
        $candidates = @(
            [pscustomobject]@{
                ProviderName = 'Microsoft-Windows-Kernel-Power'
                EventId      = 41
                TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
                RecordId     = 10
            }
            [pscustomobject]@{
                ProviderName = 'EventLog'
                EventId      = 6008
                TimeCreated  = [datetime]'2026-08-31T12:00:30Z'
                RecordId     = 11
            }
            [pscustomobject]@{
                ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
                EventId      = 1001
                TimeCreated  = [datetime]'2026-08-31T12:01:00Z'
                RecordId     = 12
            }
        )

        $incidents = @(Get-CriticalEventAlertIncidentCandidate -Candidate $candidates)

        $incidents.Count | Should -Be 1
        $incidents[0].Classification | Should -Be 'Unexpected reboot incident'
        $incidents[0].Description | Should -Match '41'
        $incidents[0].Description | Should -Match '6008'
        $incidents[0].Description | Should -Match '1001'
    }

    It 'keeps separate reboot records outside the correlation window separate' {
        $candidates = @(
            [pscustomobject]@{
                ProviderName = 'Microsoft-Windows-Kernel-Power'
                EventId      = 41
                TimeCreated  = [datetime]'2026-08-31T12:00:00Z'
                RecordId     = 20
            }
            [pscustomobject]@{
                ProviderName = 'EventLog'
                EventId      = 6008
                TimeCreated  = [datetime]'2026-08-31T12:06:00Z'
                RecordId     = 21
            }
        )

        $incidents = @(Get-CriticalEventAlertIncidentCandidate -Candidate $candidates)

        $incidents.Count | Should -Be 2
    }
}

Describe 'Critical Event Alert repeat suppression' {
    It 'suppresses the same device issue for 24 hours' {
        $state = @{ AlertHistory = @{} }
        $signature = 'disk|7|\device\harddisk2\dr2'
        $now = [datetime]'2026-08-31T12:00:00Z'

        Set-CriticalEventAlertSuppression `
            -State $state `
            -Signature $signature `
            -Now $now

        Test-CriticalEventAlertSuppression `
            -State $state `
            -Signature $signature `
            -Now $now.AddHours(23) |
            Should -BeTrue
    }

    It 'does not suppress the same event on a different disk' {
        $state = @{ AlertHistory = @{} }
        $now = [datetime]'2026-08-31T12:00:00Z'
        Set-CriticalEventAlertSuppression `
            -State $state `
            -Signature 'disk|7|\device\harddisk2\dr2' `
            -Now $now

        Test-CriticalEventAlertSuppression `
            -State $state `
            -Signature 'disk|7|\device\harddisk3\dr3' `
            -Now $now.AddHours(1) |
            Should -BeFalse
    }
}
