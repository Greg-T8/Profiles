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

        $candidate.Classification | Should -Be 'Windows Critical system event'
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
