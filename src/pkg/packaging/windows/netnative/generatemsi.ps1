# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

param(
    [Parameter(Mandatory=$true)][string]$DotnetNativeMSIOutput,
    [Parameter(Mandatory=$true)][string]$WixRoot,
    [Parameter(Mandatory=$true)][string]$PackageSourceFolder,
    [Parameter(Mandatory=$true)][string]$WixObjRoot,
    [Parameter(Mandatory=$true)][string]$UWPPackageVersion,
    [Parameter(Mandatory=$true)][string]$DotnetToolCommand
)

$RepoRoot = Convert-Path "$PSScriptRoot\..\..\..\..\.."
$CommonScript = "$RepoRoot\tools-local\scripts\common\_common.ps1"
if(-Not (Test-Path "$CommonScript"))
{
    Exit -1
} 
. "$CommonScript"

$PackagingRoot = Join-Path $RepoRoot "src\pkg\packaging"
$PackagesWxs = Join-Path $WixObjRoot "packages.wxs"
$FrameworkWxs = Join-Path $WixObjRoot "framework.wxs"

function RestorePackages
{
    Write-Host Restoring packages for meta-package

    $RS3Project = Join-Path $WixObjRoot "RS3.csproj"
    (Get-Content "$PSScriptRoot\RS3.csproj").replace('[UWPPackageVersion]', $UWPPackageVersion) | Set-Content $RS3Project
    
    $RS2Project = Join-Path $WixObjRoot "RS2.csproj"
    (Get-Content "$PSScriptRoot\RS2.csproj").replace('[UWPPackageVersion]', $UWPPackageVersion) | Set-Content $RS2Project
    
    $NetNative1Dot4Project = Join-Path $WixObjRoot "1.4.csproj"
    (Get-Content "$PSScriptRoot\1.4.csproj") | Set-Content $NetNative1Dot4Project

    Write-Host "$DotnetToolCommand restore $RS3Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages"
    & $DotnetToolCommand restore $RS3Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages | Out-Host
    
    if($LastExitCode -ne 0)
    {
        Write-Host "Failed to restore packages for $RS3Project. Error code $LastExitCode."
        return $false
    }

    Write-Host "$DotnetToolCommand restore $RS2Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages"
    & $DotnetToolCommand restore $RS2Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages | Out-Host
    
    if($LastExitCode -ne 0)
    {
        Write-Host "Failed to restore packages for $RS2Project. Error code $LastExitCode."
        return $false
    }

    Write-Host "$DotnetToolCommand restore $NetNative1Dot4Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages"
    & $DotnetToolCommand restore $NetNative1Dot4Project --no-cache --source $PackageSourceFolder --source https://dotnet.myget.org/F/dotnet-core/api/v3/index.json --packages $WixObjRoot\packages | Out-Host
    
    if($LastExitCode -ne 0)
    {
        Write-Host "Failed to restore packages for $NetNative1Dot4Project. Error code $LastExitCode."
        return $false
    }

    return $true
}

function RunHeat
{
    $result = $true
    
    pushd "$WixRoot"

    Write-Host "Running heat.. $WixRoot\heat.exe dir $WixObjRoot\packages -out $PackagesWxs -ag -cg CG_NETCoreUWP -dr NuGetPackages -sreg -srd -scom -var var.PackageRestoreDir"
    .\heat.exe dir $WixObjRoot\packages -out $PackagesWxs -ag -cg CG_NETCoreUWP -dr NuGetPackages -sreg -srd -scom -var var.PackageRestoreDir | Out-Host

    if ($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Heat failed with exit code $LastExitCode."
    }


    Write-Host "Running heat.. $WixRoot\heat.exe dir $PSScriptRoot\NetCoreFramework -out $FrameworkWxs -ag -cg CG_NETCoreFramework -dr RefAssmsMsFxNetCore5 -sreg -srd -scom -var var.FrameworkSourceDir"
    .\heat.exe dir $PSScriptRoot\NetCoreFramework -out $FrameworkWxs -ag -cg CG_NETCoreFramework -dr RefAssmsMsFxNetCore5 -sreg -srd -scom -var var.FrameworkSourceDir | Out-Host

    if ($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Heat failed with exit code $LastExitCode."
    }


    popd
    return $result
}

function RunCandle
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running candle..
    $AuthWsxRoot =  Join-Path $PackagingRoot "windows\netnative"

    .\candle.exe -nologo `
        -dPackageRestoreDir="$WixObjRoot\packages" `
        -dFrameworkSourceDir="$PSScriptRoot\NetCoreFramework" `
        -dNugetConfigSourceDir="$AuthWsxRoot\NugetPackageRegistration" `
        -out "$WixObjRoot\" `
        -ext WixDependencyExtension.dll `
        -ext WixUtilExtension.dll `
        "$AuthWsxRoot\product.wxs" `
        "$AuthWsxRoot\registrykeys.wxs" `
        "$AuthWsxRoot\provider.wxs" `
        "$AuthWsxRoot\NugetPackageRegistration\NuGetPackageRegistration.wxs" `
        "$FrameworkWxs" `
        "$PackagesWxs" | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Candle failed with exit code $LastExitCode."
    }

    popd
    return $result
}

function RunLight
{
    $result = $true
    pushd "$WixRoot"

    Write-Host Running light..

    .\light.exe -nologo `
        -ext WixUIExtension.dll `
        -ext WixDependencyExtension.dll `
        -ext WixUtilExtension.dll `
        -cultures:en-us `
        "$WixObjRoot\product.wixobj" `
        "$WixObjRoot\registrykeys.wixobj" `
        "$WixObjRoot\packages.wixobj" `
        "$WixObjRoot\framework.wixobj" `
        "$WixObjRoot\provider.wixobj" `
        "$WixObjRoot\NuGetPackageRegistration.wixobj" `
        -out $DotnetNativeMSIOutput | Out-Host

    if($LastExitCode -ne 0)
    {
        $result = $false
        Write-Host "Light failed with exit code $LastExitCode."
    }

    popd
    return $result
}

if(!(Test-Path $WixObjRoot))
{
    throw "$WixObjRoot not found"
}

Write-Host "Creating .NET Native MSI at $DotnetNativeMSIOutput"

if([string]::IsNullOrEmpty($WixRoot))
{
    Exit -1
}

if (-Not (RestorePackages))
{
    Exit -1
}

if (-Not (RunHeat))
{
    Exit -1
}

Write-Host "Package.wxs generated at $PackagesWxs"

if(-Not (RunCandle))
{
    Exit -1
}

if(-Not (RunLight))
{
    Exit -1
}

if(!(Test-Path $DotnetNativeMSIOutput))
{
    throw "Unable to create the shared host msi."
    Exit -1
}

Write-Host -ForegroundColor Green "Successfully created shared host MSI - $DotnetNativeMSIOutput"

exit $LastExitCode
