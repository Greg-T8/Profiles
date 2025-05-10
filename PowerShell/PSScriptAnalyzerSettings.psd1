# PSScriptAnalyzerSettings.psd1
# Rules reference:
# https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme?view=ps-modules

@{
    # Severity=@('Error','Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidUsingWriteHost'
        'PSReviewUnusedParameter'
    )
    Rules = @{
        PSAlignAssignmentStatement = @{
            Enable         = $false
            CheckHashtable = $true
        }
        PSAvoidLongLines = @{
            Enable            = $false
            MaximumLineLength = 115
        }
        PSAvoidSemicolonsAsLineTerminators  = @{
            Enable     = $true
        }
        PSPlaceCloseBrace = @{
            Enable             = $true
            NoEmptyLineBefore  = $false
            IgnoreOneLineBlock = $true
            NewLineAfter       = $true
        }
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }
        PSUseConsistentWhitespace = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $false
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}
