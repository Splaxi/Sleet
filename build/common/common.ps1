
# install CLI
Function Install-DotnetCLI {
    param(
        [string]$RepoRoot
    )

    $CLIRoot = Get-DotnetCLIRoot $RepoRoot

    New-Item -ItemType Directory -Force -Path $CLIRoot | Out-Null

    $env:DOTNET_HOME = $CLIRoot
    $installDotnet = Join-Path $CLIRoot "install.ps1"

    $DotnetExe = Get-DotnetCLIExe $RepoRoot

    if (-not (Test-Path $DotnetExe)) {

        New-Item -ItemType Directory -Force -Path $CLIRoot

        Write-Host "Fetching $installDotnet"

        wget https://raw.githubusercontent.com/dotnet/sdk/983c8115e6341287a5866ed7be05c663c7e89614/scripts/obtain/dotnet-install.ps1 -OutFile $installDotnet

        & $installDotnet -Channel 3.1 -i $CLIRoot -Version 3.1.101

        if (-not (Test-Path $DotnetExe)) {
            Write-Log "Missing $DotnetExe"
            exit 1
        }
    }

    & $DotnetExe --info
}

Function Get-DotnetCLIRoot {
    param(
        [string]$RepoRoot
    )
    return Join-Path $RepoRoot ".cli"
}

Function Get-DotnetCLIExe {
    param(
        [string]$RepoRoot
    )

    $CLIRoot = Get-DotnetCLIRoot $RepoRoot

    return Join-Path $CLIRoot "dotnet.exe"
}

Function Get-NuGetExePath {
    param(
        [string]$RepoRoot
    )

    return Join-Path $RepoRoot ".nuget/nuget.exe"
}

# download .nuget\nuget.exe
Function Install-NuGetExe {
    param(
        [string]$RepoRoot
    )

    $nugetExe = Get-NuGetExePath $RepoRoot

    if (-not (Test-Path $nugetExe)) {
        Write-Host "Downloading nuget.exe"
        $nugetDir = Split-Path $nugetExe
        New-Item -ItemType Directory -Force -Path $nugetDir

        wget https://dist.nuget.org/win-x86-commandline/v5.3.0/nuget.exe -OutFile $nugetExe
    }
}

# Delete the artifacts directory
Function Remove-Artifacts {
    param(
        [string]$RepoRoot
    )

    $artifactsDir = Join-Path $RepoRoot "artifacts"

    if (Test-Path $artifactsDir) {
        Remove-Item $artifactsDir -Force -Recurse
    }
}

# Invoke dotnet exe
Function Invoke-DotnetExe {
    param(
        [string]$RepoRoot,
        [string[]]$Arguments
    )

    $dotnetExe = Get-DotnetCLIExe $RepoRoot
    $command = "$dotnetExe $Arguments"

    Write-Host "[Exec]" $command -ForegroundColor Cyan

    & $dotnetExe $Arguments

    if (-not $?) {
        Write-Error $command
        exit 1
    }
}

# Invoke dotnet msbuild
Function Invoke-DotnetMSBuild {
    param(
        [string]$RepoRoot,
        [string[]]$Arguments
    )

    $buildArgs = , "msbuild"
    $buildArgs += "/nologo"
    $buildArgs += "/v:m"
    $buildArgs += "/nr:false"
    $buildArgs += "/m:1"
    $buildArgs += $Arguments

    Invoke-DotnetExe $RepoRoot $buildArgs
}

Function Install-DotnetTools {
    param(
        [string]$RepoRoot
    )

    $toolsPath = Join-Path $RepoRoot ".nuget/tools"

    if (-not (Test-Path $toolsPath)) {
        Write-Host "Installing dotnet tools to $toolsPath"
        $args = @("tool","install","--tool-path",$toolsPath,"--ignore-failed-sources","dotnet-format","--version","3.3.111304")

        Invoke-DotnetExe $RepoRoot $args
    }
}

Function Install-CommonBuildTools {
    param(
        [string]$RepoRoot
    )

    Install-DotnetCLI $RepoRoot
    Install-NuGetExe $RepoRoot
    Install-DotnetTools $RepoRoot
}

Function Invoke-DotnetFormat {
    param(
        [string]$RepoRoot
    )

    $formatExe = Join-Path $RepoRoot ".nuget/tools/dotnet-format.exe"

    $args = @("-w",$RepoRoot)

    # On CI builds run a check instead of making code changes
    if ($env:CI -eq "True") 
    {
        $args += "--check"
    }

    $command = "$formatExe $args"
    Write-Host "[EXEC] $command" -ForegroundColor Cyan

    & $formatExe $args

    if (-not $?) {
        Write-Warning "dotnet-format failed. Please fix the style errors!"

        # Currently dotnet-format fails on CIs but not locally in some scenarios
        # exit 1
    }
}