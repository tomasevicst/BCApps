Describe 'BC AI knowledge evaluation tool' {
    BeforeAll {
        $script:toolRoot = Split-Path $PSScriptRoot -Parent
        $script:repositoryRoot = (Resolve-Path (Join-Path $script:toolRoot '../..')).Path
        $script:entryPoint = Join-Path $script:toolRoot 'Invoke-BcAiKnowledgeEval.ps1'
        $script:exampleRoot = Join-Path $script:toolRoot 'examples'

        function New-TestConfig {
            param(
                [Parameter(Mandatory = $true)] [string] $Root,
                [string] $EvaluationId = 'pester-eval',
                [switch] $WithDependencyContext
            )

            $config = Get-Content -LiteralPath (Join-Path $script:exampleRoot 'evaluation.fake-cli.example.json') -Raw | ConvertFrom-Json
            $config.evaluation_id = $EvaluationId
            $config.output_root = Join-Path $Root 'output'
            $config.questions_file = Join-Path $script:exampleRoot 'questions.example.jsonl'
            $config.docs_manifest = Join-Path $script:exampleRoot 'docs-manifest.example.json'
            if ($WithDependencyContext) {
                $context = Get-Content -LiteralPath (Join-Path $script:exampleRoot 'context-manifest.example.json') -Raw | ConvertFrom-Json
                $contextPath = Join-Path $Root 'context-manifest.json'
                $context | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $contextPath -Encoding UTF8
                $config | Add-Member -NotePropertyName context_manifest -NotePropertyValue $contextPath
                $config.workspace_paths = @(
                    'tools/bc-ai-knowledge-eval/examples/sample-app',
                    'tools/bc-ai-knowledge-eval/examples/sample-dependency'
                )
            }
            $path = Join-Path $Root 'evaluation.json'
            $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
            return $path
        }
    }

    It 'validates a one-question, one-document evaluation' {
        $config = New-TestConfig -Root $TestDrive
        $output = & $script:entryPoint -Mode dry-run -ConfigPath $config | Out-String
        $output | Should Match 'status\s+: valid'
        $output | Should Match 'question_count\s+: 1'
    }

    It 'rejects an unsupported schema major version' {
        $config = New-TestConfig -Root $TestDrive
        $value = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $value.schema_version = '2.0'
        $value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $config -Encoding UTF8
        $threw = $false
        try {
            & $script:entryPoint -Mode dry-run -ConfigPath $config
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'unsupported schema version'
        }
        $threw | Should Be $true
    }

    It 'prepares workspaces that differ only by the docs manifest' {
        $config = New-TestConfig -Root $TestDrive
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        $root = Join-Path (Join-Path $TestDrive 'output') 'pester-eval'
        Test-Path -LiteralPath (Join-Path $root 'workspaces/docs-assisted/tools/bc-ai-knowledge-eval/examples/sample-app/AGENTS.md') | Should Be $true
        Test-Path -LiteralPath (Join-Path $root 'workspaces/code-only/tools/bc-ai-knowledge-eval/examples/sample-app/AGENTS.md') | Should Be $false
        $manifest = Get-Content -LiteralPath (Join-Path $root 'evaluation-manifest.json') -Raw | ConvertFrom-Json
        $manifest.workspace_isolation.status | Should Be 'verified'
        $manifest.workspace_isolation.unexpected_difference_count | Should Be 0
    }

    It 'prepares identical dependency source while excluding dependency documentation from both arms' {
        $config = New-TestConfig -Root $TestDrive -WithDependencyContext
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        $root = Join-Path (Join-Path $TestDrive 'output') 'pester-eval'
        $codeDependency = Join-Path $root 'workspaces/code-only/tools/bc-ai-knowledge-eval/examples/sample-dependency'
        $docsDependency = Join-Path $root 'workspaces/docs-assisted/tools/bc-ai-knowledge-eval/examples/sample-dependency'

        Test-Path -LiteralPath (Join-Path $codeDependency 'src/SharedPolicy.Codeunit.al') | Should Be $true
        Test-Path -LiteralPath (Join-Path $docsDependency 'src/SharedPolicy.Codeunit.al') | Should Be $true
        Test-Path -LiteralPath (Join-Path $codeDependency 'AGENTS.md') | Should Be $false
        Test-Path -LiteralPath (Join-Path $docsDependency 'AGENTS.md') | Should Be $false

        $manifest = Get-Content -LiteralPath (Join-Path $root 'evaluation-manifest.json') -Raw | ConvertFrom-Json
        $manifest.context.profile | Should Be 'dependency-source'
        $manifest.context.adequacy | Should Be 'sufficient'
        $manifest.context.shared_documentation_policy | Should Be 'exclude'
        @($manifest.context.excluded_dependency_documentation).Count | Should Be 1
        @($manifest.context.dependency_paths).Count | Should Be 1
        @($manifest.context.code_only_path_provenance | Where-Object scope -eq 'dependency').Count | Should Be 1
        $manifest.context.code_only_path_provenance[1].tree_hash | Should Be $manifest.context.docs_assisted_path_provenance[1].tree_hash
    }

    It 'rejects a changed context manifest after preparation' {
        $config = New-TestConfig -Root $TestDrive -WithDependencyContext
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        $configValue = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $context = Get-Content -LiteralPath $configValue.context_manifest -Raw | ConvertFrom-Json
        $context.notes = 'Changed after preparation.'
        $context | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configValue.context_manifest -Encoding UTF8
        $threw = $false
        try {
            & $script:entryPoint -Mode export-run-pack -ConfigPath $config
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'context manifest changed'
        }
        $threw | Should Be $true
    }

    It 'discloses shared dependency documentation when configured' {
        $config = New-TestConfig -Root $TestDrive -WithDependencyContext
        $configValue = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $context = Get-Content -LiteralPath $configValue.context_manifest -Raw | ConvertFrom-Json
        $context.shared_documentation_policy = 'include-and-disclose'
        $context | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configValue.context_manifest -Encoding UTF8
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        $root = Join-Path (Join-Path $TestDrive 'output') 'pester-eval'

        Test-Path -LiteralPath (Join-Path $root 'workspaces/code-only/tools/bc-ai-knowledge-eval/examples/sample-dependency/AGENTS.md') | Should Be $true
        Test-Path -LiteralPath (Join-Path $root 'workspaces/docs-assisted/tools/bc-ai-knowledge-eval/examples/sample-dependency/AGENTS.md') | Should Be $true
        $manifest = Get-Content -LiteralPath (Join-Path $root 'evaluation-manifest.json') -Raw | ConvertFrom-Json
        @($manifest.context.shared_dependency_documentation).Count | Should Be 1
        @($manifest.context.excluded_dependency_documentation).Count | Should Be 0
    }

    It 'rejects overlapping target and dependency context paths' {
        $config = New-TestConfig -Root $TestDrive -WithDependencyContext
        $configValue = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $context = Get-Content -LiteralPath $configValue.context_manifest -Raw | ConvertFrom-Json
        $context.dependency_paths[0].path = 'tools/bc-ai-knowledge-eval/examples'
        $context | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configValue.context_manifest -Encoding UTF8
        $threw = $false
        try {
            & $script:entryPoint -Mode dry-run -ConfigPath $config
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'target and dependency paths overlap'
        }
        $threw | Should Be $true
    }

    It 'runs the synthetic automatic and judging workflow without mutating workspaces' {
        $config = New-TestConfig -Root $TestDrive
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        $threw = $false
        try {
            & $script:entryPoint -Mode run -ConfigPath $config
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'ConfirmPaidRuns'
        }
        $threw | Should Be $true
        & $script:entryPoint -Mode calibrate -ConfigPath $config -ConfirmPaidRuns | Out-Null
        & $script:entryPoint -Mode run -ConfigPath $config -ConfirmPaidRuns | Out-Null
        & $script:entryPoint -Mode judge -ConfigPath $config -ConfirmPaidRuns | Out-Null
        & $script:entryPoint -Mode report -ConfigPath $config | Out-Null

        $root = Join-Path (Join-Path $TestDrive 'output') 'pester-eval'
        $runs = @(Get-ChildItem -LiteralPath (Join-Path $root 'runs') -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $judgments = @(Get-ChildItem -LiteralPath (Join-Path $root 'judgments') -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $report = Get-Content -LiteralPath (Join-Path $root 'reports/questions/SAMPLE-001.json') -Raw | ConvertFrom-Json

        $runs.Count | Should Be 2
        @($runs.execution.workspace_unchanged | Where-Object { $_ -ne $true }).Count | Should Be 0
        $judgments.Count | Should Be 3
        @($judgments | ForEach-Object { $_.blind_mapping.($_.winner) } | Where-Object { $_ -ne 'C1' }).Count | Should Be 0
        $report.outcome | Should Be 'docs_win'
        $report.context.profile | Should Be 'app-local'
        $report.context.bounded_case_study | Should Be $true
        $report.quality.primary_consensus.confidence | Should Be 'high'
        $report.consumption.C0_vs_C1.input_tokens.status | Should Be 'unavailable'
    }

    It 'imports a plain-text manual response with prepared provenance' {
        $config = New-TestConfig -Root $TestDrive
        & $script:entryPoint -Mode prepare -ConfigPath $config -Force | Out-Null
        & $script:entryPoint -Mode export-run-pack -ConfigPath $config -Force | Out-Null
        $responsePath = Join-Path $TestDrive 'response.txt'
        'Synthetic manual response.' | Set-Content -LiteralPath $responsePath -Encoding UTF8
        & $script:entryPoint -Mode import-response -ConfigPath $config -ImportPath $responsePath -RunId 'SAMPLE-001--C0--r001' | Out-Null
        $resultPath = Join-Path (Join-Path $TestDrive 'output') 'pester-eval/runs/SAMPLE-001--C0--r001.json'
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $result.generated_by | Should Be 'manual'
        $result.execution.status | Should Be 'complete'
        $result.response_text | Should Be 'Synthetic manual response.'
    }
}