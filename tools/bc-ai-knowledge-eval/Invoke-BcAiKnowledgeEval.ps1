#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('calibrate', 'prepare', 'run', 'export-run-pack', 'import-response', 'judge', 'export-judge-pack', 'import-judgment', 'report', 'all', 'dry-run')]
    [string] $Mode,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [string] $ImportPath,

    [string] $RunId,

    [switch] $ConfirmPaidRuns,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

Import-Module (Join-Path $PSScriptRoot 'lib/BcAiKnowledgeEval.psm1') -Force

$context = Initialize-BcAiKnowledgeEvaluation -ConfigPath $ConfigPath

switch ($Mode) {
    'dry-run' {
        Write-BcAiKnowledgeEvalValidationSummary -Context $context
    }
    'prepare' {
        New-BcAiKnowledgeEvalWorkspaces -Context $context -Force:$Force
    }
    'export-run-pack' {
        Export-BcAiKnowledgeEvalRunPacks -Context $context -Force:$Force
    }
    'run' {
        Assert-BcAiKnowledgeEvalPaidRunApproval -Confirmed:$ConfirmPaidRuns
        Invoke-BcAiKnowledgeEvalAnswerRuns -Context $context -Force:$Force
    }
    'import-response' {
        if (-not $ImportPath) { throw '-ImportPath is required for import-response.' }
        Import-BcAiKnowledgeEvalResponse -Context $context -ImportPath $ImportPath -RunId $RunId -Force:$Force
    }
    'calibrate' {
        Assert-BcAiKnowledgeEvalPaidRunApproval -Confirmed:$ConfirmPaidRuns
        Invoke-BcAiKnowledgeEvalCalibration -Context $context -Force:$Force
    }
    'export-judge-pack' {
        Export-BcAiKnowledgeEvalJudgePacks -Context $context -Force:$Force
    }
    'judge' {
        Assert-BcAiKnowledgeEvalPaidRunApproval -Confirmed:$ConfirmPaidRuns
        Invoke-BcAiKnowledgeEvalJudging -Context $context -Force:$Force
    }
    'import-judgment' {
        if (-not $ImportPath) { throw '-ImportPath is required for import-judgment.' }
        Import-BcAiKnowledgeEvalJudgment -Context $context -ImportPath $ImportPath -Force:$Force
    }
    'report' {
        Invoke-BcAiKnowledgeEvalAnalysis -Context $context
    }
    'all' {
        Assert-BcAiKnowledgeEvalPaidRunApproval -Confirmed:$ConfirmPaidRuns
        New-BcAiKnowledgeEvalWorkspaces -Context $context -Force:$Force
        Invoke-BcAiKnowledgeEvalCalibration -Context $context -Force:$Force
        Invoke-BcAiKnowledgeEvalAnswerRuns -Context $context -Force:$Force
        Invoke-BcAiKnowledgeEvalJudging -Context $context -Force:$Force
        Invoke-BcAiKnowledgeEvalAnalysis -Context $context
    }
}
