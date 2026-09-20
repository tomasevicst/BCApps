Set-StrictMode -Version 3.0

$script:SchemaVersion = '1.0'

function Resolve-EvalPath {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $BasePath,
        [switch] $AllowMissing
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $BasePath $Path }
    $fullPath = [System.IO.Path]::GetFullPath($candidate)
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "Path does not exist: $fullPath"
    }
    return $fullPath
}

function Read-EvalJson {
    param([Parameter(Mandatory = $true)] [string] $Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    } catch {
        throw "Invalid JSON in '$Path': $($_.Exception.Message)"
    }
}

function Assert-SchemaVersion {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $ArtifactName
    )

    if (-not $Object.PSObject.Properties['schema_version']) {
        throw "$ArtifactName is missing schema_version."
    }
    $major = ([string]$Object.schema_version).Split('.')[0]
    if ($major -ne $script:SchemaVersion.Split('.')[0]) {
        throw "$ArtifactName uses unsupported schema version '$($Object.schema_version)'."
    }
}

function Get-RepositoryRoot {
    param([Parameter(Mandatory = $true)] [string] $StartPath)

    $result = & git -C $StartPath rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($result)) {
        throw "Cannot resolve a Git repository from '$StartPath'."
    }
    return [System.IO.Path]::GetFullPath($result.Trim())
}

function Read-EvalQuestions {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $questions = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $question = $line | ConvertFrom-Json -Depth 100
        } catch {
            throw "Invalid JSONL at '$Path' line ${lineNumber}: $($_.Exception.Message)"
        }
        Assert-SchemaVersion -Object $question -ArtifactName "Question at line $lineNumber"
        if (-not $question.question_id -or -not $question.question) {
            throw "Question at line $lineNumber requires question_id and question."
        }
        if ($question.question_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "Question at line $lineNumber has an invalid question_id."
        }
        $questions.Add($question)
    }
    if ($questions.Count -eq 0) { throw 'At least one question is required.' }
    $duplicates = $questions | Group-Object question_id | Where-Object Count -gt 1
    if ($duplicates) { throw "Duplicate question IDs: $($duplicates.Name -join ', ')" }
    return $questions.ToArray()
}

function Test-IsPathInside {
    param(
        [Parameter(Mandatory = $true)] [string] $Child,
        [Parameter(Mandatory = $true)] [string] $Parent
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $childFull = [System.IO.Path]::GetFullPath($Child)
    return $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-StringHash {
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-FileHashRecord {
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [string] $File
    )

    $relative = [System.IO.Path]::GetRelativePath($Root, $File).Replace('\', '/')
    $item = Get-Item -LiteralPath $File
    return [pscustomobject]@{
        path = $relative
        size = $item.Length
        sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-TreeManifest {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } |
        Sort-Object FullName
    return @($files | ForEach-Object { Get-FileHashRecord -Root $Root -File $_.FullName })
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)] [string] $Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-EvalGit {
    param(
        [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
        [Parameter(Mandatory = $true)] [string[]] $Arguments
    )

    $output = & git -C $RepositoryRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Copy-WorkingTreeSnapshot {
    param(
        [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string[]] $WorkspacePaths
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $includeAll = $WorkspacePaths -contains '.'
    $relativeFiles = Invoke-EvalGit -RepositoryRoot $RepositoryRoot -Arguments @('ls-files', '-co', '--exclude-standard')
    foreach ($relativeFile in $relativeFiles) {
        if ([string]::IsNullOrWhiteSpace($relativeFile)) { continue }
        $normalizedFile = $relativeFile.Replace('\', '/')
        $included = $includeAll
        if (-not $included) {
            foreach ($workspacePath in $WorkspacePaths) {
                $prefix = $workspacePath.TrimEnd('/') + '/'
                if ($normalizedFile -eq $workspacePath -or $normalizedFile.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $included = $true
                    break
                }
            }
        }
        if (-not $included) { continue }
        $source = Join-Path $RepositoryRoot $relativeFile
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path $Destination $relativeFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Export-CommitSnapshot {
    param(
        [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
        [Parameter(Mandatory = $true)] [string] $Commit,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string] $EvaluationRoot,
        [Parameter(Mandatory = $true)] [string[]] $WorkspacePaths
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $archivePath = Join-Path $EvaluationRoot 'source-snapshot.tar'
    try {
        $archiveArguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @('archive', '--format=tar', "--output=$archivePath", $Commit)) { $archiveArguments.Add($argument) }
        if ($WorkspacePaths -notcontains '.') {
            $archiveArguments.Add('--')
            foreach ($workspacePath in $WorkspacePaths) { $archiveArguments.Add($workspacePath) }
        }
        Invoke-EvalGit -RepositoryRoot $RepositoryRoot -Arguments $archiveArguments | Out-Null
        & tar -xf $archivePath -C $Destination
        if ($LASTEXITCODE -ne 0) { throw "Failed to extract Git archive '$archivePath'." }
    } finally {
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    }
}

function Get-WorkspaceManifestRecord {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $files = @(Get-TreeManifest -Root $Root)
    $serialized = $files | ConvertTo-Json -Depth 10 -Compress
    return [pscustomobject]@{
        schema_version = $script:SchemaVersion
        root = $Root
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        file_count = $files.Count
        tree_hash = Get-StringHash -Value $serialized
        files = $files
    }
}

function Assert-WorkspaceIsolation {
    param(
        [Parameter(Mandatory = $true)] $CodeOnlyManifest,
        [Parameter(Mandatory = $true)] $DocsAssistedManifest,
        [Parameter(Mandatory = $true)] [string[]] $DocsFiles
    )

    $docsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $DocsFiles) { [void]$docsSet.Add($file.Replace('\', '/')) }

    $codeFiles = @{}
    foreach ($file in @($CodeOnlyManifest.files)) { $codeFiles[$file.path] = $file }
    $docsFilesByPath = @{}
    foreach ($file in @($DocsAssistedManifest.files)) { $docsFilesByPath[$file.path] = $file }

    $unexpected = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $docsFilesByPath.Keys) {
        if ($docsSet.Contains($path)) {
            if ($codeFiles.ContainsKey($path)) { $unexpected.Add("Documentation file still exists in code-only workspace: $path") }
            continue
        }
        if (-not $codeFiles.ContainsKey($path)) {
            $unexpected.Add("Non-documentation file missing from code-only workspace: $path")
            continue
        }
        if ($codeFiles[$path].size -ne $docsFilesByPath[$path].size -or $codeFiles[$path].sha256 -ne $docsFilesByPath[$path].sha256) {
            $unexpected.Add("Non-documentation file differs between workspaces: $path")
        }
    }
    foreach ($path in $codeFiles.Keys) {
        if (-not $docsFilesByPath.ContainsKey($path)) { $unexpected.Add("Extra file in code-only workspace: $path") }
    }
    foreach ($path in $docsSet) {
        if (-not $docsFilesByPath.ContainsKey($path)) { $unexpected.Add("Documentation intervention file is absent from docs-assisted workspace: $path") }
    }

    if ($unexpected.Count -gt 0) {
        throw "Workspace isolation failed:$([Environment]::NewLine)$($unexpected -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{
        status = 'verified'
        checked_at = [DateTimeOffset]::UtcNow.ToString('o')
        intervention_file_count = $docsSet.Count
        unexpected_difference_count = 0
    }
}

function Get-EvaluationArms {
    param([Parameter(Mandatory = $true)] $Context)

    $arms = [System.Collections.Generic.List[object]]::new()
    $arms.Add([pscustomobject]@{ id = 'C0'; model = $Context.config.answer_model; workspace = 'code-only'; docs = $false })
    $arms.Add([pscustomobject]@{ id = 'C1'; model = $Context.config.answer_model; workspace = 'docs-assisted'; docs = $true })
    if ($Context.config.PSObject.Properties['economical_model'] -and $Context.config.economical_model) {
        $arms.Add([pscustomobject]@{ id = 'E0'; model = $Context.config.economical_model; workspace = 'code-only'; docs = $false })
        $arms.Add([pscustomobject]@{ id = 'E1'; model = $Context.config.economical_model; workspace = 'docs-assisted'; docs = $true })
    }
    return $arms.ToArray()
}

function Get-PreparedEvaluationManifest {
    param([Parameter(Mandatory = $true)] $Context)

    $path = Join-Path $Context.evaluation_root 'evaluation-manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Evaluation is not prepared. Run prepare first: $path"
    }
    $manifest = Read-EvalJson -Path $path
    Assert-SchemaVersion -Object $manifest -ArtifactName 'Evaluation manifest'
    if ($manifest.evaluation_id -ne $Context.config.evaluation_id) { throw 'Prepared evaluation ID does not match the config.' }
    $configHash = (Get-FileHash -LiteralPath $Context.config_path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifest.config_hash -ne $configHash) { throw 'Evaluation config changed after preparation. Rerun prepare with -Force.' }
    if ($manifest.workspace_isolation.status -ne 'verified') { throw 'Prepared workspace isolation is not verified.' }
    return $manifest
}

function Get-QuestionContext {
    param([Parameter(Mandatory = $true)] $Question)

    if ($Question.PSObject.Properties['context'] -and $null -ne $Question.context) { return [string]$Question.context }
    return ''
}

function Get-AnswerPrompt {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Question
    )

    $template = Get-Content -LiteralPath $Context.prompt_template_path -Raw -Encoding UTF8
    return $template.Replace('{{APP_PATH}}', $Context.app_relative_path).
        Replace('{{QUESTION}}', [string]$Question.question).
        Replace('{{CONTEXT}}', (Get-QuestionContext -Question $Question))
}

function Get-AnswerRunDescriptors {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $EvaluationManifest
    )

    $descriptors = [System.Collections.Generic.List[object]]::new()
    foreach ($question in $Context.questions) {
        foreach ($arm in @($EvaluationManifest.arms)) {
            for ($repeat = 1; $repeat -le $Context.repeats; $repeat++) {
                $workspace = if ($arm.workspace -eq 'code-only') { $EvaluationManifest.workspaces.code_only } else { $EvaluationManifest.workspaces.docs_assisted }
                $runId = '{0}--{1}--r{2:d3}' -f $question.question_id, $arm.id, $repeat
                $prompt = Get-AnswerPrompt -Context $Context -Question $question
                $descriptors.Add([pscustomobject]@{
                    run_id = $runId
                    question = $question
                    arm = $arm
                    repeat = $repeat
                    prompt = $prompt
                    prompt_hash = Get-StringHash -Value $prompt
                    workspace_path = $workspace.path
                    workspace_hash = $workspace.tree_hash
                })
            }
        }
    }
    return $descriptors.ToArray()
}

function Get-RunPackRecord {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Descriptor
    )

    $copilotCommand = if ($Context.config.PSObject.Properties['copilot_command']) { [string]$Context.config.copilot_command } else { 'copilot' }

    return [pscustomobject]@{
        schema_version = $script:SchemaVersion
        run_id = $Descriptor.run_id
        question_id = $Descriptor.question.question_id
        arm = $Descriptor.arm.id
        model = $Descriptor.arm.model
        repeat = $Descriptor.repeat
        prompt = $Descriptor.prompt
        prompt_hash = $Descriptor.prompt_hash
        workspace_path = $Descriptor.workspace_path
        workspace_hash = $Descriptor.workspace_hash
        docs_assisted = $Descriptor.arm.docs
        command = [pscustomobject]@{
            executable = $copilotCommand
            arguments = @(Get-CopilotArguments -Context $Context -Descriptor $Descriptor)
            working_directory = $Descriptor.workspace_path
        }
        generated_by = 'manual'
        capture_method = 'run_pack'
        response_text = $null
        execution = [pscustomobject]@{
            status = 'pending'
            exit_code = $null
            wall_time_seconds = $null
            workspace_unchanged = $null
        }
        consumption = [pscustomobject]@{
            status = 'unavailable'
            source = $null
        }
    }
}

function Get-WorkspaceTreeHash {
    param([Parameter(Mandatory = $true)] [string] $Path)
    return (Get-WorkspaceManifestRecord -Root $Path).tree_hash
}

function Invoke-EvalProcess {
    param(
        [Parameter(Mandatory = $true)] [string] $FileName,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $WorkingDirectory,
        [Parameter(Mandatory = $true)] [int] $TimeoutSeconds
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.CreateNoWindow = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) { throw "Failed to start '$FileName'." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $stopwatch.Stop()

    return [pscustomobject]@{
        exit_code = if ($completed) { $process.ExitCode } else { $null }
        timed_out = -not $completed
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
        wall_time_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    }
}

function Invoke-CopilotMetricsAdapter {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] [ValidateSet('snapshot', 'collect')] [string] $Mode,
        [long] $SinceId = 0,
        [string] $WorkspacePath
    )

    $toolRoot = Split-Path $PSScriptRoot -Parent
    $adapterPath = Join-Path $toolRoot 'Read-CopilotMetrics.py'
    $pythonCommand = if ($Context.config.PSObject.Properties['python_command']) { [string]$Context.config.python_command } else { 'python' }
    $databasePath = if ($Context.config.PSObject.Properties['metrics_db_path'] -and $Context.config.metrics_db_path) {
        [string]$Context.config.metrics_db_path
    } else {
        Join-Path $HOME '.copilot/session-store.db'
    }
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @($adapterPath, $Mode, '--database', $databasePath)) { $arguments.Add([string]$argument) }
    if ($Mode -eq 'collect') {
        $arguments.Add('--since-id')
        $arguments.Add([string]$SinceId)
        $arguments.Add('--workspace')
        $arguments.Add($WorkspacePath)
    }

    try {
        $result = Invoke-EvalProcess -FileName $pythonCommand -Arguments $arguments.ToArray() -WorkingDirectory $Context.repository_root -TimeoutSeconds 30
        if ($result.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($result.stdout)) {
            return [pscustomobject]@{ status = 'unavailable'; reason = "Metrics adapter failed: $($result.stderr.Trim())"; max_usage_event_id = $SinceId }
        }
        return $result.stdout | ConvertFrom-Json -Depth 100
    } catch {
        return [pscustomobject]@{ status = 'unavailable'; reason = $_.Exception.Message; max_usage_event_id = $SinceId }
    }
}

function New-MetricValue {
    param(
        $Value,
        [Parameter(Mandatory = $true)] [ValidateSet('measured', 'partial', 'unavailable')] [string] $Status,
        [Parameter(Mandatory = $true)] [string] $Source
    )
    return [pscustomobject]@{ value = $Value; status = $Status; source = $Source }
}

function Get-CopilotArguments {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Descriptor
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    if ($Context.config.PSObject.Properties['copilot_arguments_prefix']) {
        foreach ($argument in @($Context.config.copilot_arguments_prefix)) {
            $expanded = ([string]$argument).Replace('{{REPOSITORY_ROOT}}', $Context.repository_root)
            $arguments.Add($expanded)
        }
    }
    foreach ($argument in @('--silent', '--stream', 'off', '--no-color', '--no-ask-user', '-p', $Descriptor.prompt, '--model', $Descriptor.arm.model, '-C', $Descriptor.workspace_path, '--output-format', 'text')) {
        $arguments.Add([string]$argument)
    }
    $availableTools = if ($Context.config.PSObject.Properties['available_tools']) { @($Context.config.available_tools) } else { @('view', 'grep', 'glob') }
    if ($availableTools.Count -eq 0) { throw 'available_tools must contain at least one read-only tool.' }
    $arguments.Add('--available-tools')
    foreach ($tool in $availableTools) { $arguments.Add([string]$tool) }
    return $arguments.ToArray()
}

function New-RunResult {
    param(
        [Parameter(Mandatory = $true)] $Descriptor,
        [Parameter(Mandatory = $true)] $ProcessResult,
        [Parameter(Mandatory = $true)] [bool] $WorkspaceUnchanged,
        $Metrics
    )

    $status = if ($ProcessResult.timed_out -or $ProcessResult.exit_code -ne 0) { 'failed' } elseif (-not $WorkspaceUnchanged) { 'invalid' } else { 'complete' }
    $response = if ([string]::IsNullOrWhiteSpace($ProcessResult.stdout)) { $null } else { $ProcessResult.stdout.Trim() }
    $metricsAvailable = $null -ne $Metrics -and $Metrics.status -in @('measured', 'partial')
    $metricStatus = if ($metricsAvailable) { [string]$Metrics.status } else { 'unavailable' }
    $metricSource = if ($metricsAvailable) { 'copilot_session_store' } else { 'copilot_session_store_unavailable' }
    return [pscustomobject]@{
        schema_version = $script:SchemaVersion
        run_id = $Descriptor.run_id
        question_id = $Descriptor.question.question_id
        arm = $Descriptor.arm.id
        model = $Descriptor.arm.model
        repeat = $Descriptor.repeat
        prompt_hash = $Descriptor.prompt_hash
        workspace_hash = $Descriptor.workspace_hash
        generated_by = 'copilot_cli'
        capture_method = 'automatic'
        response_text = $response
        execution = [pscustomobject]@{
            status = $status
            exit_code = $ProcessResult.exit_code
            wall_time_seconds = $ProcessResult.wall_time_seconds
            timed_out = $ProcessResult.timed_out
            workspace_unchanged = $WorkspaceUnchanged
            stderr = $ProcessResult.stderr
        }
        consumption = [pscustomobject]@{
            status = if ($metricsAvailable -and $Metrics.status -eq 'measured') { 'measured' } else { 'partial' }
            wall_time_seconds = New-MetricValue -Value $ProcessResult.wall_time_seconds -Status 'measured' -Source 'process_stopwatch'
            output_bytes = New-MetricValue -Value $(if ($null -eq $response) { 0 } else { [System.Text.Encoding]::UTF8.GetByteCount($response) }) -Status 'measured' -Source 'captured_stdout'
            output_tokens_estimate = New-MetricValue -Value $(if ($null -eq $response) { 0 } else { [Math]::Ceiling($response.Length / 4.0) }) -Status 'partial' -Source 'character_heuristic'
            input_tokens = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.input_tokens } else { $null }) -Status $metricStatus -Source $metricSource
            output_tokens = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.output_tokens } else { $null }) -Status $metricStatus -Source $metricSource
            cache_read_tokens = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.cache_read_tokens } else { $null }) -Status $metricStatus -Source $metricSource
            cache_write_tokens = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.cache_write_tokens } else { $null }) -Status $metricStatus -Source $metricSource
            reasoning_tokens = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.reasoning_tokens } else { $null }) -Status $metricStatus -Source $metricSource
            total_nano_aiu = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.total_nano_aiu } else { $null }) -Status $metricStatus -Source $metricSource
            request_multiplier_sum = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.request_multiplier_sum } else { $null }) -Status $metricStatus -Source $metricSource
            credits = New-MetricValue -Value $null -Status 'unavailable' -Source 'not_exposed_by_cli_store'
            tool_activity = New-MetricValue -Value $(if ($metricsAvailable) { $Metrics.tool_activity } else { $null }) -Status $metricStatus -Source $metricSource
            attribution = if ($null -ne $Metrics) { $Metrics } else { [pscustomobject]@{ status = 'unavailable'; reason = 'Metrics adapter did not return a result.' } }
        }
    }
}

function Initialize-BcAiKnowledgeEvaluation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string] $ConfigPath)

    $configFull = Resolve-EvalPath -Path $ConfigPath -BasePath (Get-Location).Path
    $config = Read-EvalJson -Path $configFull
    Assert-SchemaVersion -Object $config -ArtifactName 'Evaluation config'

    foreach ($required in @('evaluation_id', 'app_path', 'questions_file', 'docs_manifest', 'output_root', 'answer_model')) {
        if (-not $config.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$config.$required)) {
            throw "Evaluation config requires '$required'."
        }
    }

    if ($config.evaluation_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw 'evaluation_id must contain only letters, numbers, dot, underscore, and hyphen.'
    }

    $repositoryRoot = Get-RepositoryRoot -StartPath $PSScriptRoot
    $configDirectory = Split-Path -Parent $configFull
    $appPath = Resolve-EvalPath -Path $config.app_path -BasePath $repositoryRoot
    $questionsPath = Resolve-EvalPath -Path $config.questions_file -BasePath $configDirectory
    $manifestPath = Resolve-EvalPath -Path $config.docs_manifest -BasePath $configDirectory
    $outputRoot = Resolve-EvalPath -Path $config.output_root -BasePath $configDirectory -AllowMissing

    if (-not (Test-IsPathInside -Child $appPath -Parent $repositoryRoot)) { throw 'app_path must be inside the repository.' }
    if (Test-IsPathInside -Child $outputRoot -Parent $repositoryRoot) { throw 'output_root must be outside the repository.' }
    if (-not (Test-Path -LiteralPath (Join-Path $appPath 'app.json') -PathType Leaf)) { throw "app_path must contain app.json: $appPath" }

    $questions = @(Read-EvalQuestions -Path $questionsPath)
    $docsManifest = Read-EvalJson -Path $manifestPath
    Assert-SchemaVersion -Object $docsManifest -ArtifactName 'Docs manifest'
    if (-not $docsManifest.PSObject.Properties['files'] -or @($docsManifest.files).Count -eq 0) {
        throw 'Docs manifest requires at least one file.'
    }

    $manifestFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @($docsManifest.files)) {
        if ([System.IO.Path]::IsPathRooted([string]$file)) { throw "Docs manifest path must be relative: $file" }
        $resolved = Resolve-EvalPath -Path ([string]$file) -BasePath $repositoryRoot
        if (-not (Test-IsPathInside -Child $resolved -Parent $appPath)) { throw "Docs manifest path must be inside app_path: $file" }
        if ([System.IO.Path]::GetExtension($resolved) -ne '.md') { throw "Docs manifest path must be Markdown: $file" }
        $manifestFiles.Add([System.IO.Path]::GetRelativePath($repositoryRoot, $resolved).Replace('\', '/'))
    }
    if (@($manifestFiles | Sort-Object -Unique).Count -ne $manifestFiles.Count) { throw 'Docs manifest contains duplicate paths.' }

    $workspacePaths = [System.Collections.Generic.List[string]]::new()
    $configuredWorkspacePaths = if ($config.PSObject.Properties['workspace_paths'] -and @($config.workspace_paths).Count -gt 0) { @($config.workspace_paths) } else { @('.') }
    foreach ($workspacePath in $configuredWorkspacePaths) {
        if ([System.IO.Path]::IsPathRooted([string]$workspacePath)) { throw "workspace_paths entries must be repository-relative: $workspacePath" }
        $resolvedWorkspacePath = Resolve-EvalPath -Path ([string]$workspacePath) -BasePath $repositoryRoot
        if (-not (Test-IsPathInside -Child $resolvedWorkspacePath -Parent $repositoryRoot) -and $resolvedWorkspacePath -ne $repositoryRoot) {
            throw "workspace_paths entry escapes the repository: $workspacePath"
        }
        $workspacePaths.Add([System.IO.Path]::GetRelativePath($repositoryRoot, $resolvedWorkspacePath).Replace('\', '/'))
    }
    if (@($workspacePaths | Sort-Object -Unique).Count -ne $workspacePaths.Count) { throw 'workspace_paths contains duplicate paths.' }

    $appJson = Read-EvalJson -Path (Join-Path $appPath 'app.json')
    $evaluationRoot = Join-Path $outputRoot $config.evaluation_id
    $repeats = if ($config.PSObject.Properties['repeats']) { [int]$config.repeats } else { 1 }
    if ($repeats -lt 1) { throw 'repeats must be at least 1.' }

    return [pscustomobject]@{
        schema_version = $script:SchemaVersion
        config_path = $configFull
        config = $config
        repository_root = $repositoryRoot
        app_path = $appPath
        app_relative_path = [System.IO.Path]::GetRelativePath($repositoryRoot, $appPath).Replace('\', '/')
        app_metadata = $appJson
        questions = $questions
        docs_manifest = $docsManifest
        docs_files = $manifestFiles
        workspace_paths = $workspacePaths
        output_root = $outputRoot
        evaluation_root = $evaluationRoot
        repeats = $repeats
        prompt_template_path = Join-Path (Split-Path $PSScriptRoot -Parent) 'templates/answer-prompt.md'
    }
}

function Write-BcAiKnowledgeEvalValidationSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Context)

    $arms = @('C0', 'C1')
    if ($Context.config.PSObject.Properties['economical_model'] -and $Context.config.economical_model) { $arms += @('E0', 'E1') }
    [pscustomobject]@{
        evaluation_id = $Context.config.evaluation_id
        repository_root = $Context.repository_root
        app_path = $Context.app_relative_path
        app_name = $Context.app_metadata.name
        question_count = $Context.questions.Count
        docs_file_count = $Context.docs_files.Count
        arms = $arms
        repeats = $Context.repeats
        output_root = $Context.output_root
        status = 'valid'
    } | Format-List
}

function Assert-BcAiKnowledgeEvalPaidRunApproval {
    [CmdletBinding()]
    param([switch] $Confirmed)

    if (-not $Confirmed) { throw 'Paid model execution requires -ConfirmPaidRuns.' }
}

function New-BcAiKnowledgeEvalWorkspaces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    $evaluationRoot = $Context.evaluation_root
    $workspaceRoot = Join-Path $evaluationRoot 'workspaces'
    $codeOnlyRoot = Join-Path $workspaceRoot 'code-only'
    $docsAssistedRoot = Join-Path $workspaceRoot 'docs-assisted'
    $manifestRoot = Join-Path $evaluationRoot 'workspace-manifests'
    $evaluationManifestPath = Join-Path $evaluationRoot 'evaluation-manifest.json'

    if (Test-Path -LiteralPath $evaluationManifestPath -PathType Leaf) {
        if (-not $Force) {
            $existing = Read-EvalJson -Path $evaluationManifestPath
            if ($existing.workspace_isolation.status -eq 'verified' -and (Test-Path -LiteralPath $codeOnlyRoot) -and (Test-Path -LiteralPath $docsAssistedRoot)) {
                Write-Output "Prepared workspaces already exist: $workspaceRoot"
                return $existing
            }
            throw "Existing evaluation is incomplete or invalid. Use -Force to recreate it: $evaluationRoot"
        }
    }
    if ($Force) {
        foreach ($path in @($workspaceRoot, $manifestRoot, (Join-Path $evaluationRoot 'run-packs'), (Join-Path $evaluationRoot 'runs'), (Join-Path $evaluationRoot 'judge-packs'), (Join-Path $evaluationRoot 'judge-pass-runs'), (Join-Path $evaluationRoot 'judge-pass-failures'), (Join-Path $evaluationRoot 'judgments'), (Join-Path $evaluationRoot 'reports'), (Join-Path $evaluationRoot 'calibration'))) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $evaluationManifestPath -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $evaluationRoot -Force | Out-Null
    $sourceMode = if ($Context.config.PSObject.Properties['source_mode']) { [string]$Context.config.source_mode } else { 'commit' }
    if ($sourceMode -notin @('commit', 'working-tree')) { throw "Unsupported source_mode '$sourceMode'." }
    $headCommit = @(Invoke-EvalGit -RepositoryRoot $Context.repository_root -Arguments @('rev-parse', 'HEAD'))[0].Trim()
    $sourceCommit = if ($Context.config.PSObject.Properties['source_commit'] -and $Context.config.source_commit) { [string]$Context.config.source_commit } else { $headCommit }

    if ($sourceMode -eq 'commit') {
        Export-CommitSnapshot -RepositoryRoot $Context.repository_root -Commit $sourceCommit -Destination $docsAssistedRoot -EvaluationRoot $evaluationRoot -WorkspacePaths $Context.workspace_paths
        $dirtyFiles = @()
        $reproducible = $true
    } else {
        Copy-WorkingTreeSnapshot -RepositoryRoot $Context.repository_root -Destination $docsAssistedRoot -WorkspacePaths $Context.workspace_paths
        $dirtyFiles = @(Invoke-EvalGit -RepositoryRoot $Context.repository_root -Arguments @('status', '--short', '--untracked-files=all'))
        $reproducible = $dirtyFiles.Count -eq 0
    }

    Copy-Item -LiteralPath $docsAssistedRoot -Destination $codeOnlyRoot -Recurse -Force
    foreach ($relativeDoc in $Context.docs_files) {
        $baselineDoc = Join-Path $codeOnlyRoot $relativeDoc
        if (-not (Test-Path -LiteralPath $baselineDoc -PathType Leaf)) {
            throw "Documentation intervention file is absent from source snapshot: $relativeDoc"
        }
        Remove-Item -LiteralPath $baselineDoc -Force
    }

    $codeOnlyManifest = Get-WorkspaceManifestRecord -Root $codeOnlyRoot
    $docsAssistedManifest = Get-WorkspaceManifestRecord -Root $docsAssistedRoot
    $isolation = Assert-WorkspaceIsolation -CodeOnlyManifest $codeOnlyManifest -DocsAssistedManifest $docsAssistedManifest -DocsFiles $Context.docs_files

    New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
    Write-JsonFile -Value $codeOnlyManifest -Path (Join-Path $manifestRoot 'code-only.json')
    Write-JsonFile -Value $docsAssistedManifest -Path (Join-Path $manifestRoot 'docs-assisted.json')

    $questionRecords = @($Context.questions | ForEach-Object {
        [pscustomobject]@{
            question_id = $_.question_id
            question = $_.question
            context = Get-QuestionContext -Question $_
            content_hash = Get-StringHash -Value ($_.question | ConvertTo-Json -Compress)
        }
    })
    $evaluationManifest = [pscustomobject]@{
        schema_version = $script:SchemaVersion
        evaluation_id = $Context.config.evaluation_id
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
        repository_root = $Context.repository_root
        app_path = $Context.app_relative_path
        source = [pscustomobject]@{
            mode = $sourceMode
            commit = $sourceCommit
            head_commit = $headCommit
            reproducible = $reproducible
            workspace_paths = @($Context.workspace_paths)
            dirty_file_count = $dirtyFiles.Count
            dirty_files = $dirtyFiles
        }
        config_hash = (Get-FileHash -LiteralPath $Context.config_path -Algorithm SHA256).Hash.ToLowerInvariant()
        questions = $questionRecords
        docs_files = @($Context.docs_files)
        arms = @(Get-EvaluationArms -Context $Context)
        repeats = $Context.repeats
        workspaces = [pscustomobject]@{
            code_only = [pscustomobject]@{ path = $codeOnlyRoot; tree_hash = $codeOnlyManifest.tree_hash }
            docs_assisted = [pscustomobject]@{ path = $docsAssistedRoot; tree_hash = $docsAssistedManifest.tree_hash }
        }
        workspace_isolation = $isolation
    }
    Write-JsonFile -Value $evaluationManifest -Path $evaluationManifestPath

    Write-Output "Prepared and verified workspaces: $workspaceRoot"
    return $evaluationManifest
}

function Invoke-NotImplementedEvalStage {
    param([Parameter(Mandatory = $true)] [string] $Stage)
    throw "Evaluation stage '$Stage' is not implemented yet. Use dry-run to validate inputs."
}

function Export-BcAiKnowledgeEvalRunPacks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    $evaluationManifest = Get-PreparedEvaluationManifest -Context $Context
    $packRoot = Join-Path $Context.evaluation_root 'run-packs'
    if ($Force) { Remove-Item -LiteralPath $packRoot -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $packRoot -Force | Out-Null
    $count = 0
    foreach ($descriptor in Get-AnswerRunDescriptors -Context $Context -EvaluationManifest $evaluationManifest) {
        $packPath = Join-Path $packRoot "$($descriptor.run_id).json"
        if ((Test-Path -LiteralPath $packPath) -and -not $Force) { continue }
        Write-JsonFile -Value (Get-RunPackRecord -Context $Context -Descriptor $descriptor) -Path $packPath
        $count++
    }
    Write-Output "Exported $count run pack(s) to $packRoot"
}

function Invoke-BcAiKnowledgeEvalAnswerRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    $evaluationManifest = Get-PreparedEvaluationManifest -Context $Context
    $runRoot = Join-Path $Context.evaluation_root 'runs'
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $timeoutSeconds = if ($Context.config.PSObject.Properties['timeout_seconds']) { [int]$Context.config.timeout_seconds } else { 900 }
    $copilotCommand = if ($Context.config.PSObject.Properties['copilot_command']) { [string]$Context.config.copilot_command } else { 'copilot' }
    $failures = [System.Collections.Generic.List[string]]::new()
    $calibrationPath = Join-Path $Context.evaluation_root 'calibration/result.json'
    if (-not (Test-Path -LiteralPath $calibrationPath -PathType Leaf)) {
        throw 'Calibration is required before automatic answer runs. Run calibrate first.'
    }

    foreach ($descriptor in Get-AnswerRunDescriptors -Context $Context -EvaluationManifest $evaluationManifest) {
        $runPath = Join-Path $runRoot "$($descriptor.run_id).json"
        if ((Test-Path -LiteralPath $runPath) -and -not $Force) {
            $existing = Read-EvalJson -Path $runPath
            if ($existing.execution.status -eq 'complete') { continue }
        }

        $beforeHash = Get-WorkspaceTreeHash -Path $descriptor.workspace_path
        if ($beforeHash -ne $descriptor.workspace_hash) { throw "Workspace changed before run '$($descriptor.run_id)'. Rerun prepare with -Force." }
        $arguments = @(Get-CopilotArguments -Context $Context -Descriptor $descriptor)
        $metricsSnapshot = Invoke-CopilotMetricsAdapter -Context $Context -Mode snapshot
        $processResult = Invoke-EvalProcess -FileName $copilotCommand -Arguments $arguments -WorkingDirectory $descriptor.workspace_path -TimeoutSeconds $timeoutSeconds
        $metrics = Invoke-CopilotMetricsAdapter -Context $Context -Mode collect -SinceId $metricsSnapshot.max_usage_event_id -WorkspacePath $descriptor.workspace_path
        $afterHash = Get-WorkspaceTreeHash -Path $descriptor.workspace_path
        $result = New-RunResult -Descriptor $descriptor -ProcessResult $processResult -WorkspaceUnchanged ($beforeHash -eq $afterHash) -Metrics $metrics
        Write-JsonFile -Value $result -Path $runPath
        if ($result.execution.status -ne 'complete') { $failures.Add($descriptor.run_id) }
    }

    if ($failures.Count -gt 0) { throw "Answer run failures: $($failures -join ', ')" }
    Write-Output "Answer runs are complete: $runRoot"
}

function Import-BcAiKnowledgeEvalResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] [string] $ImportPath,
        [string] $RunId,
        [switch] $Force
    )

    $evaluationManifest = Get-PreparedEvaluationManifest -Context $Context
    $importFull = Resolve-EvalPath -Path $ImportPath -BasePath (Get-Location).Path
    $descriptors = @(Get-AnswerRunDescriptors -Context $Context -EvaluationManifest $evaluationManifest)
    $runRoot = Join-Path $Context.evaluation_root 'runs'
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

    if ([System.IO.Path]::GetExtension($importFull) -eq '.json') {
        $result = Read-EvalJson -Path $importFull
        Assert-SchemaVersion -Object $result -ArtifactName 'Imported response'
        $RunId = [string]$result.run_id
    } else {
        if ([string]::IsNullOrWhiteSpace($RunId)) { throw '-RunId is required when importing a plain-text response.' }
        $descriptor = $descriptors | Where-Object run_id -eq $RunId | Select-Object -First 1
        if (-not $descriptor) { throw "Unknown run ID '$RunId'." }
        $response = Get-Content -LiteralPath $importFull -Raw -Encoding UTF8
        $result = Get-RunPackRecord -Context $Context -Descriptor $descriptor
        $result.generated_by = 'manual'
        $result.capture_method = 'plain_text_import'
        $result.response_text = $response.Trim()
        $result.execution.status = 'complete'
        $result.execution.workspace_unchanged = $true
    }

    $knownDescriptor = $descriptors | Where-Object run_id -eq $RunId | Select-Object -First 1
    if (-not $knownDescriptor) { throw "Imported response has unknown run ID '$RunId'." }
    if ($result.prompt_hash -ne $knownDescriptor.prompt_hash -or $result.workspace_hash -ne $knownDescriptor.workspace_hash) {
        throw 'Imported response provenance does not match the prepared run descriptor.'
    }
    $target = Join-Path $runRoot "$RunId.json"
    if ((Test-Path -LiteralPath $target) -and -not $Force) { throw "Run result already exists: $target" }
    Write-JsonFile -Value $result -Path $target
    Write-Output "Imported response: $target"
}

function Get-JudgeModel {
    param([Parameter(Mandatory = $true)] $Context)
    if (-not $Context.config.PSObject.Properties['judge_model'] -or [string]::IsNullOrWhiteSpace([string]$Context.config.judge_model)) {
        throw 'judge_model is required for automatic judging.'
    }
    return [string]$Context.config.judge_model
}

function Get-CompletedRunResults {
    param([Parameter(Mandatory = $true)] $Context)

    $runRoot = Join-Path $Context.evaluation_root 'runs'
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) { throw 'No answer runs exist.' }
    $results = @{}
    foreach ($file in Get-ChildItem -LiteralPath $runRoot -Filter '*.json' -File) {
        $run = Read-EvalJson -Path $file.FullName
        Assert-SchemaVersion -Object $run -ArtifactName "Run '$($file.Name)'"
        if ($run.execution.status -eq 'complete') { $results[$run.run_id] = $run }
    }
    return $results
}

function Get-ComparisonDescriptors {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $RunResults
    )

    $pairs = [System.Collections.Generic.List[object]]::new()
    $pairs.Add(@('C0', 'C1'))
    if ($Context.config.PSObject.Properties['economical_model'] -and $Context.config.economical_model) { $pairs.Add(@('E0', 'E1')) }
    $descriptors = [System.Collections.Generic.List[object]]::new()
    $seed = if ($Context.config.PSObject.Properties['random_seed']) { [int]$Context.config.random_seed } else { 20260920 }

    foreach ($question in $Context.questions) {
        for ($pairIndex = 0; $pairIndex -lt $pairs.Count; $pairIndex++) {
            $pair = $pairs[$pairIndex]
            for ($repeat = 1; $repeat -le $Context.repeats; $repeat++) {
                $leftId = '{0}--{1}--r{2:d3}' -f $question.question_id, $pair[0], $repeat
                $rightId = '{0}--{1}--r{2:d3}' -f $question.question_id, $pair[1], $repeat
                if (-not $RunResults.ContainsKey($leftId) -or -not $RunResults.ContainsKey($rightId)) {
                    throw "Complete paired runs are required: $leftId and $rightId"
                }
                for ($judgeIndex = 1; $judgeIndex -le 3; $judgeIndex++) {
                    $comparison = "$($pair[0])_vs_$($pair[1])"
                    $judgmentId = '{0}--pair{1:d3}--r{2:d3}--j{3:d3}' -f $question.question_id, ($pairIndex + 1), $repeat, $judgeIndex
                    $swapHash = Get-StringHash -Value "$seed|$judgmentId"
                    $swap = ([Convert]::ToInt32($swapHash.Substring(0, 2), 16) % 2) -eq 1
                    $answerA = if ($swap) { $RunResults[$rightId] } else { $RunResults[$leftId] }
                    $answerB = if ($swap) { $RunResults[$leftId] } else { $RunResults[$rightId] }
                    $descriptors.Add([pscustomobject]@{
                        judgment_id = $judgmentId
                        question = $question
                        comparison = $comparison
                        repeat = $repeat
                        judge_index = $judgeIndex
                        answer_a = $answerA
                        answer_b = $answerB
                        mapping = [pscustomobject]@{ A = $answerA.arm; B = $answerB.arm }
                    })
                }
            }
        }
    }
    return $descriptors.ToArray()
}

function Get-JudgePrompt {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Descriptor,
        [Parameter(Mandatory = $true)] [ValidateSet('content', 'evidence')] [string] $Pass
    )

    $templateName = if ($Pass -eq 'content') { 'judge-content-prompt.md' } else { 'judge-evidence-prompt.md' }
    $template = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) "templates/$templateName") -Raw -Encoding UTF8
    return $template.Replace('{{QUESTION}}', [string]$Descriptor.question.question).
        Replace('{{ANSWER_A}}', [string]$Descriptor.answer_a.response_text).
        Replace('{{ANSWER_B}}', [string]$Descriptor.answer_b.response_text)
}

function Get-JudgeRetryPrompt {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Descriptor,
        [Parameter(Mandatory = $true)] [ValidateSet('content', 'evidence')] [string] $Pass
    )

    $templateName = "judge-$Pass-retry-prompt.md"
    $template = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) "templates/$templateName") -Raw -Encoding UTF8
    return $template.Replace('{{QUESTION}}', [string]$Descriptor.question.question).
        Replace('{{ANSWER_A}}', [string]$Descriptor.answer_a.response_text).
        Replace('{{ANSWER_B}}', [string]$Descriptor.answer_b.response_text)
}

function Get-JudgePackRecord {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] $Descriptor
    )

    return [pscustomobject]@{
        schema_version = $script:SchemaVersion
        judgment_id = $Descriptor.judgment_id
        question_id = $Descriptor.question.question_id
        comparison = 'blind_pair'
        repeat = $Descriptor.repeat
        judge_index = $Descriptor.judge_index
        question = $Descriptor.question.question
        answer_a = $Descriptor.answer_a.response_text
        answer_b = $Descriptor.answer_b.response_text
        content_prompt = Get-JudgePrompt -Context $Context -Descriptor $Descriptor -Pass content
        evidence_prompt = Get-JudgePrompt -Context $Context -Descriptor $Descriptor -Pass evidence
        content_retry_prompt = Get-JudgeRetryPrompt -Context $Context -Descriptor $Descriptor -Pass content
        evidence_retry_prompt = Get-JudgeRetryPrompt -Context $Context -Descriptor $Descriptor -Pass evidence
        generated_by = 'manual'
        review_status = 'unreviewed'
    }
}

function ConvertFrom-JudgeLineProtocol {
    param(
        [Parameter(Mandatory = $true)] [string] $Text,
        [Parameter(Mandatory = $true)] [ValidateSet('content', 'evidence')] [string] $Pass
    )

    $lines = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('```') })
    if ($Pass -eq 'content') {
        $dimensions = @('correctness', 'completeness_actionability', 'scope_fit', 'uncertainty_safety')
        $scores = @{ A = @{}; B = @{} }
        $winners = @{}
        $overall = $null
        $confidence = $null
        foreach ($line in $lines) {
            $parts = @($line -split '\|')
            if ($parts.Count -eq 4 -and $parts[0] -eq 'SCORE' -and $parts[1] -in @('A', 'B') -and $parts[2] -in $dimensions -and $parts[3] -match '^[0-3]$') {
                $scores[$parts[1]][$parts[2]] = [int]$parts[3]
            } elseif ($parts.Count -eq 3 -and $parts[0] -eq 'WINNER' -and $parts[1] -in $dimensions -and $parts[2] -in @('A', 'B', 'tie', 'unsure')) {
                $winners[$parts[1]] = $parts[2]
            } elseif ($parts.Count -eq 2 -and $parts[0] -eq 'OVERALL' -and $parts[1] -in @('A', 'B', 'tie', 'unsure')) {
                $overall = $parts[1]
            } elseif ($parts.Count -eq 2 -and $parts[0] -eq 'CONFIDENCE' -and $parts[1] -in @('high', 'medium', 'low')) {
                $confidence = $parts[1]
            }
        }
        foreach ($answer in @('A', 'B')) {
            foreach ($dimension in $dimensions) {
                if (-not $scores[$answer].ContainsKey($dimension)) { throw "Content line protocol is missing SCORE|$answer|$dimension." }
            }
        }
        foreach ($dimension in $dimensions) {
            if (-not $winners.ContainsKey($dimension)) { throw "Content line protocol is missing WINNER|$dimension." }
        }
        if (-not $overall) { throw 'Content line protocol is missing OVERALL.' }
        if (-not $confidence) { throw 'Content line protocol is missing CONFIDENCE.' }
        return [pscustomobject]@{
            scores = [pscustomobject]@{ A = [pscustomobject]$scores.A; B = [pscustomobject]$scores.B }
            dimension_winners = [pscustomobject]$winners
            overall_winner = $overall
            confidence = $confidence
            reason = 'Structured retry omitted free-text reasoning.'
        }
    }

    $grounding = @{}
    $claims = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        $parts = @($line -split '\|', 6)
        if ($parts.Count -eq 3 -and $parts[0] -eq 'GROUNDING' -and $parts[1] -in @('A', 'B') -and $parts[2] -match '^[0-3]$') {
            $grounding[$parts[1]] = [int]$parts[2]
        } elseif ($parts.Count -eq 6 -and $parts[0] -eq 'CLAIM' -and $parts[1] -in @('A', 'B') -and $parts[2] -in @('verified', 'unsupported', 'contradicted', 'unresolved') -and $parts[3] -in @('true', 'false')) {
            $claims.Add([pscustomobject]@{
                answer = $parts[1]
                claim = $parts[5]
                status = $parts[2]
                evidence = @($parts[4] -split ';' | Where-Object { $_ })
                material_error = $parts[3] -eq 'true'
            })
        }
    }
    foreach ($answer in @('A', 'B')) {
        if (-not $grounding.ContainsKey($answer)) { $grounding[$answer] = 0 }
        if (-not @($claims | Where-Object answer -eq $answer).Count) {
            $grounding[$answer] = 0
            $claims.Add([pscustomobject]@{
                answer = $answer
                claim = 'The judge returned no structured critical claim for this answer.'
                status = 'unresolved'
                evidence = @()
                material_error = $false
            })
        }
    }
    $claimArray = $claims.ToArray()
    return [pscustomobject]@{
        claims = $claimArray
        evidence_grounding = [pscustomobject]@{ A = $grounding.A; B = $grounding.B }
        material_errors = @($claimArray | Where-Object material_error)
    }
}

function ConvertFrom-JudgeJson {
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $Pass
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Pass judge returned an empty response." }
    $trimmed = $Text.Trim().TrimStart([char]0xFEFF)
    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($trimmed)

    $fenced = [regex]::Match($trimmed, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
    if ($fenced.Success) { $candidates.Add($fenced.Groups[1].Value) }

    $firstBrace = $trimmed.IndexOf('{')
    $lastBrace = $trimmed.LastIndexOf('}')
    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
        $candidates.Add($trimmed.Substring($firstBrace, $lastBrace - $firstBrace + 1))
    }

    $lastError = $null
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        try {
            return $candidate | ConvertFrom-Json -Depth 100
        } catch {
            $lastError = $_.Exception.Message
        }
    }
    try {
        return ConvertFrom-JudgeLineProtocol -Text $trimmed -Pass $Pass
    } catch {
        $lastError = "$lastError Line protocol: $($_.Exception.Message)"
    }
    throw "$Pass judge did not return valid JSON: $lastError"
}

function Invoke-JudgeModelPass {
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] [string] $JudgmentId,
        [Parameter(Mandatory = $true)] [string] $Prompt,
        [Parameter(Mandatory = $true)] [string] $RetryPrompt,
        [Parameter(Mandatory = $true)] [string] $WorkspacePath,
        [Parameter(Mandatory = $true)] [string] $WorkspaceHash,
        [Parameter(Mandatory = $true)] [string] $Model,
        [Parameter(Mandatory = $true)] [string] $Pass,
        [switch] $Force
    )

    $descriptor = [pscustomobject]@{
        run_id = "$JudgmentId--$Pass"
        question = [pscustomobject]@{ question_id = $JudgmentId }
        arm = [pscustomobject]@{ id = 'judge'; model = $Model }
        repeat = 1
        prompt = $Prompt
        prompt_hash = Get-StringHash -Value $Prompt
        workspace_path = $WorkspacePath
        workspace_hash = $WorkspaceHash
    }
    $passRoot = Join-Path $Context.evaluation_root 'judge-pass-runs'
    $failureRoot = Join-Path $Context.evaluation_root 'judge-pass-failures'
    $passPath = Join-Path $passRoot "$JudgmentId--$Pass.json"
    $primaryPromptHash = $descriptor.prompt_hash
    $retryPromptHash = Get-StringHash -Value $RetryPrompt
    $cachedResponseInvalid = $false
    if ((Test-Path -LiteralPath $passPath -PathType Leaf) -and -not $Force) {
        $existing = Read-EvalJson -Path $passPath
        $validProvenance = $existing.run_id -eq $descriptor.run_id -and
            $existing.model -eq $Model -and
            $existing.prompt_hash -in @($primaryPromptHash, $retryPromptHash) -and
            $existing.workspace_hash -eq $WorkspaceHash -and
            $existing.execution.status -eq 'complete' -and
            $existing.execution.workspace_unchanged -eq $true
        if ($validProvenance) {
            try {
                $parsed = ConvertFrom-JudgeJson -Text $existing.response_text -Pass $Pass
                return [pscustomobject]@{
                    response = $parsed
                    response_hash = Get-StringHash -Value $existing.response_text
                    execution = $existing.execution
                    consumption = $existing.consumption
                }
            } catch {
                $cachedResponseInvalid = $true
            }
        }
    }

    $prompts = if ($cachedResponseInvalid) { @($RetryPrompt) } else { @($Prompt, $RetryPrompt) }
    $lastError = $null
    $attempt = 0
    foreach ($effectivePrompt in @($prompts | Select-Object -Unique)) {
        $attempt++
        $descriptor.prompt = $effectivePrompt
        $descriptor.prompt_hash = Get-StringHash -Value $effectivePrompt
        $timeoutSeconds = if ($Context.config.PSObject.Properties['timeout_seconds']) { [int]$Context.config.timeout_seconds } else { 900 }
        $copilotCommand = if ($Context.config.PSObject.Properties['copilot_command']) { [string]$Context.config.copilot_command } else { 'copilot' }
        $beforeHash = Get-WorkspaceTreeHash -Path $WorkspacePath
        if ($beforeHash -ne $WorkspaceHash) { throw "Judge workspace changed before '$($descriptor.run_id)'." }
        $metricsSnapshot = Invoke-CopilotMetricsAdapter -Context $Context -Mode snapshot
        $processResult = Invoke-EvalProcess -FileName $copilotCommand -Arguments @(Get-CopilotArguments -Context $Context -Descriptor $descriptor) -WorkingDirectory $WorkspacePath -TimeoutSeconds $timeoutSeconds
        $metrics = Invoke-CopilotMetricsAdapter -Context $Context -Mode collect -SinceId $metricsSnapshot.max_usage_event_id -WorkspacePath $WorkspacePath
        $afterHash = Get-WorkspaceTreeHash -Path $WorkspacePath
        $runResult = New-RunResult -Descriptor $descriptor -ProcessResult $processResult -WorkspaceUnchanged ($beforeHash -eq $afterHash) -Metrics $metrics
        Write-JsonFile -Value $runResult -Path $passPath
        if ($runResult.execution.status -ne 'complete') { throw "$Pass judge process failed for '$JudgmentId'." }
        try {
            $parsed = ConvertFrom-JudgeJson -Text $runResult.response_text -Pass $Pass
            return [pscustomobject]@{
                response = $parsed
                response_hash = Get-StringHash -Value $runResult.response_text
                execution = $runResult.execution
                consumption = $runResult.consumption
            }
        } catch {
            $lastError = $_.Exception.Message
            Write-JsonFile -Value $runResult -Path (Join-Path $failureRoot "$JudgmentId--$Pass--attempt$attempt.json")
        }
    }
    throw $lastError
}
function Invoke-BcAiKnowledgeEvalCalibration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    $evaluationManifest = Get-PreparedEvaluationManifest -Context $Context
    $calibrationRoot = Join-Path $Context.evaluation_root 'calibration'
    $resultPath = Join-Path $calibrationRoot 'result.json'
    if ((Test-Path -LiteralPath $resultPath) -and -not $Force) {
        Write-Output "Calibration already exists: $resultPath"
        return
    }
    New-Item -ItemType Directory -Path $calibrationRoot -Force | Out-Null
    $workspace = $evaluationManifest.workspaces.code_only
    $arm = $evaluationManifest.arms | Where-Object id -eq 'C0' | Select-Object -First 1
    $prompt = 'Reply with exactly BC_AI_KNOWLEDGE_EVAL_CALIBRATION. Do not use tools or modify files.'
    $descriptor = [pscustomobject]@{
        run_id = 'calibration--C0--r001'
        question = [pscustomobject]@{ question_id = 'calibration' }
        arm = $arm
        repeat = 1
        prompt = $prompt
        prompt_hash = Get-StringHash -Value $prompt
        workspace_path = $workspace.path
        workspace_hash = $workspace.tree_hash
    }
    $timeoutSeconds = if ($Context.config.PSObject.Properties['timeout_seconds']) { [int]$Context.config.timeout_seconds } else { 900 }
    $copilotCommand = if ($Context.config.PSObject.Properties['copilot_command']) { [string]$Context.config.copilot_command } else { 'copilot' }
    $beforeHash = Get-WorkspaceTreeHash -Path $descriptor.workspace_path
    $metricsSnapshot = Invoke-CopilotMetricsAdapter -Context $Context -Mode snapshot
    $processResult = Invoke-EvalProcess -FileName $copilotCommand -Arguments @(Get-CopilotArguments -Context $Context -Descriptor $descriptor) -WorkingDirectory $descriptor.workspace_path -TimeoutSeconds $timeoutSeconds
    $metrics = Invoke-CopilotMetricsAdapter -Context $Context -Mode collect -SinceId $metricsSnapshot.max_usage_event_id -WorkspacePath $descriptor.workspace_path
    $afterHash = Get-WorkspaceTreeHash -Path $descriptor.workspace_path
    $result = New-RunResult -Descriptor $descriptor -ProcessResult $processResult -WorkspaceUnchanged ($beforeHash -eq $afterHash) -Metrics $metrics
    $result | Add-Member -NotePropertyName calibration -NotePropertyValue ([pscustomobject]@{
        token_measurement_available = $metrics.status -in @('measured', 'partial')
        metrics_adapter_status = $metrics.status
        metrics_adapter_reason = if ($metrics.PSObject.Properties['reason']) { $metrics.reason } else { $null }
    })
    Write-JsonFile -Value $result -Path $resultPath
    if ($result.execution.status -ne 'complete') { throw "Calibration failed. See $resultPath" }
    Write-Output "Calibration complete: $($metrics.status) metrics attribution"
}
function Export-BcAiKnowledgeEvalJudgePacks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    Get-PreparedEvaluationManifest -Context $Context | Out-Null
    $runResults = Get-CompletedRunResults -Context $Context
    $packRoot = Join-Path $Context.evaluation_root 'judge-packs'
    $mappingRoot = Join-Path $Context.evaluation_root 'judge-mappings'
    if ($Force) {
        Remove-Item -LiteralPath $packRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $mappingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $packRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $mappingRoot -Force | Out-Null
    $count = 0
    foreach ($descriptor in Get-ComparisonDescriptors -Context $Context -RunResults $runResults) {
        $packPath = Join-Path $packRoot "$($descriptor.judgment_id).json"
        $mappingPath = Join-Path $mappingRoot "$($descriptor.judgment_id).json"
        if ((Test-Path -LiteralPath $packPath) -and -not $Force) { continue }
        Write-JsonFile -Value (Get-JudgePackRecord -Context $Context -Descriptor $descriptor) -Path $packPath
        Write-JsonFile -Value ([pscustomobject]@{
            schema_version = $script:SchemaVersion
            judgment_id = $descriptor.judgment_id
            comparison = $descriptor.comparison
            blind_mapping = $descriptor.mapping
            answer_a_run_id = $descriptor.answer_a.run_id
            answer_b_run_id = $descriptor.answer_b.run_id
        }) -Path $mappingPath
        $count++
    }
    Write-Output "Exported $count blind judge pack(s) to $packRoot"
}

function Invoke-BcAiKnowledgeEvalJudging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [switch] $Force
    )

    $evaluationManifest = Get-PreparedEvaluationManifest -Context $Context
    $calibrationPath = Join-Path $Context.evaluation_root 'calibration/result.json'
    if (-not (Test-Path -LiteralPath $calibrationPath -PathType Leaf)) { throw 'Calibration is required before automatic judging.' }
    Export-BcAiKnowledgeEvalJudgePacks -Context $Context -Force:$Force
    $judgeModel = Get-JudgeModel -Context $Context
    $judgmentRoot = Join-Path $Context.evaluation_root 'judgments'
    $sandboxRoot = Join-Path $Context.evaluation_root 'judge-sandbox'
    $passRoot = Join-Path $Context.evaluation_root 'judge-pass-runs'
    $failureRoot = Join-Path $Context.evaluation_root 'judge-pass-failures'
    if ($Force) {
        Remove-Item -LiteralPath $judgmentRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $passRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $failureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $judgmentRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
    $sandboxHash = Get-WorkspaceTreeHash -Path $sandboxRoot
    $docsWorkspace = $evaluationManifest.workspaces.docs_assisted
    $failures = [System.Collections.Generic.List[string]]::new()

    foreach ($packFile in Get-ChildItem -LiteralPath (Join-Path $Context.evaluation_root 'judge-packs') -Filter '*.json' -File) {
        $pack = Read-EvalJson -Path $packFile.FullName
        $target = Join-Path $judgmentRoot $packFile.Name
        if ((Test-Path -LiteralPath $target) -and -not $Force) { continue }
        try {
            $contentPass = Invoke-JudgeModelPass -Context $Context -JudgmentId $pack.judgment_id -Prompt $pack.content_prompt -RetryPrompt $pack.content_retry_prompt -WorkspacePath $sandboxRoot -WorkspaceHash $sandboxHash -Model $judgeModel -Pass content -Force:$Force
            $evidencePass = Invoke-JudgeModelPass -Context $Context -JudgmentId $pack.judgment_id -Prompt $pack.evidence_prompt -RetryPrompt $pack.evidence_retry_prompt -WorkspacePath $docsWorkspace.path -WorkspaceHash $docsWorkspace.tree_hash -Model $judgeModel -Pass evidence -Force:$Force
            $mapping = Read-EvalJson -Path (Join-Path (Join-Path $Context.evaluation_root 'judge-mappings') $packFile.Name)
            $winner = if ($contentPass.response.PSObject.Properties['overall_winner']) { [string]$contentPass.response.overall_winner } else { 'unsure' }
            if ($winner -notin @('A', 'B', 'tie', 'unsure')) { $winner = 'unsure' }
            $confidence = if ($contentPass.response.PSObject.Properties['confidence']) { [string]$contentPass.response.confidence } else { 'medium' }
            if ($confidence -notin @('high', 'medium', 'low')) { $confidence = 'low' }
            $judgment = [pscustomobject]@{
                schema_version = $script:SchemaVersion
                judgment_id = $pack.judgment_id
                question_id = $pack.question_id
                comparison = $mapping.comparison
                repeat = $pack.repeat
                judge_index = $pack.judge_index
                judge_model = $judgeModel
                generated_by = 'copilot_cli'
                review_status = 'unreviewed'
                blind_mapping = $mapping.blind_mapping
                winner = $winner
                confidence = $confidence
                scores = if ($contentPass.response.PSObject.Properties['scores']) { $contentPass.response.scores } else { [pscustomobject]@{} }
                content = $contentPass
                evidence = $evidencePass
                material_errors = if ($evidencePass.response.PSObject.Properties['material_errors']) { @($evidencePass.response.material_errors) } else { @() }
            }
            Write-JsonFile -Value $judgment -Path $target
        } catch {
            $failures.Add("$($pack.judgment_id): $($_.Exception.Message)")
        }
    }

    if ($failures.Count -gt 0) { throw "Judge failures:$([Environment]::NewLine)$($failures -join [Environment]::NewLine)" }
    Write-Output "Judgments are complete: $judgmentRoot"
}

function Import-BcAiKnowledgeEvalJudgment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Context,
        [Parameter(Mandatory = $true)] [string] $ImportPath,
        [switch] $Force
    )

    Get-PreparedEvaluationManifest -Context $Context | Out-Null
    $importFull = Resolve-EvalPath -Path $ImportPath -BasePath (Get-Location).Path
    $judgment = Read-EvalJson -Path $importFull
    Assert-SchemaVersion -Object $judgment -ArtifactName 'Imported judgment'
    if (-not $judgment.judgment_id) { throw 'Imported judgment requires judgment_id.' }
    $mappingPath = Join-Path (Join-Path $Context.evaluation_root 'judge-mappings') "$($judgment.judgment_id).json"
    if (-not (Test-Path -LiteralPath $mappingPath -PathType Leaf)) { throw "Unknown judgment ID '$($judgment.judgment_id)'." }
    $mapping = Read-EvalJson -Path $mappingPath
    if ($judgment.PSObject.Properties['blind_mapping']) {
        if (($judgment.blind_mapping | ConvertTo-Json -Compress) -ne ($mapping.blind_mapping | ConvertTo-Json -Compress)) {
            throw 'Imported judgment blind mapping does not match the exported pack.'
        }
    } else {
        $judgment | Add-Member -NotePropertyName blind_mapping -NotePropertyValue $mapping.blind_mapping
    }
    $targetRoot = Join-Path $Context.evaluation_root 'judgments'
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    $target = Join-Path $targetRoot "$($judgment.judgment_id).json"
    if ((Test-Path -LiteralPath $target) -and -not $Force) { throw "Judgment already exists: $target" }
    Write-JsonFile -Value $judgment -Path $target
    Write-Output "Imported judgment: $target"
}
function Invoke-BcAiKnowledgeEvalAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Context)

    Get-PreparedEvaluationManifest -Context $Context | Out-Null
    $pythonCommand = if ($Context.config.PSObject.Properties['python_command']) { [string]$Context.config.python_command } else { 'python' }
    $analyzerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Analyze-BcAiKnowledgeEval.py'
    $result = Invoke-EvalProcess -FileName $pythonCommand -Arguments @($analyzerPath, '--evaluation-root', $Context.evaluation_root) -WorkingDirectory $Context.repository_root -TimeoutSeconds 120
    if ($result.exit_code -ne 0) { throw "Report generation failed: $($result.stderr.Trim())" }
    Write-Output $result.stdout.Trim()
}

Export-ModuleMember -Function *-BcAiKnowledgeEval*, Initialize-BcAiKnowledgeEvaluation, Assert-BcAiKnowledgeEvalPaidRunApproval
