param(
    [Parameter(Mandatory = $true)]
    [string] $ProjectPath,

    [Parameter(Mandatory = $true)]
    [string] $ModelBimPath,

    [Parameter(Mandatory = $true)]
    [string] $BaselinePbitPath,

    [Parameter(Mandatory = $true)]
    [string] $OutputPbitPath
)

$ErrorActionPreference = 'Stop'

function Read-Json([string] $Path) {
    Get-Content -Raw -Encoding utf8 $Path | ConvertFrom-Json
}

function Compress-JsonFile([string] $Path) {
    (Get-Content -Raw -Encoding utf8 $Path).Trim()
}

Add-Type -AssemblyName System.IO.Compression

function Read-ZipText([string] $PackagePath, [string] $EntryName, [Text.Encoding] $Encoding) {
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.GetEntry($EntryName)
        if ($null -eq $entry) {
            throw "Package entry '$EntryName' was not found in $PackagePath"
        }
        $reader = [IO.StreamReader]::new($entry.Open(), $Encoding, $true)
        try {
            $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("arc-sql-pbit-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $baselineLayoutPath = Join-Path $tempRoot 'BaselineLayout'
    $layoutPath = Join-Path $tempRoot 'Layout'
    $modelPath = Join-Path $tempRoot 'DataModelSchema'
    $baselineLayout = Read-ZipText $BaselinePbitPath 'Report/Layout' ([Text.Encoding]::Unicode)
    $modelJson = Get-Content -Raw -Encoding utf8 $ModelBimPath

    [IO.File]::WriteAllText($baselineLayoutPath, $baselineLayout, [Text.Encoding]::Unicode)
    & node (Join-Path $PSScriptRoot 'build-layout.mjs') $baselineLayoutPath $layoutPath $ProjectPath
    if ($LASTEXITCODE -ne 0) {
        throw "Layout generation failed with exit code $LASTEXITCODE"
    }
    [IO.File]::WriteAllText($modelPath, $modelJson, [Text.Encoding]::Unicode)

    Copy-Item $BaselinePbitPath $OutputPbitPath -Force
    $stream = [IO.File]::Open($OutputPbitPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    try {
        $archive = [IO.Compression.ZipArchive]::new(
            $stream,
            [IO.Compression.ZipArchiveMode]::Update,
            $false
        )
        try {
            foreach ($replacement in @(
                @{ Entry = 'DataModelSchema'; File = $modelPath },
                @{ Entry = 'Report/Layout'; File = $layoutPath }
            )) {
                $existing = $archive.GetEntry($replacement.Entry)
                if ($null -ne $existing) {
                    $existing.Delete()
                }

                $entry = $archive.CreateEntry(
                    $replacement.Entry,
                    [IO.Compression.CompressionLevel]::Optimal
                )
                $entryStream = $entry.Open()
                try {
                    $fileStream = [IO.File]::OpenRead($replacement.File)
                    try {
                        $fileStream.CopyTo($entryStream)
                    }
                    finally {
                        $fileStream.Dispose()
                    }
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}
finally {
    Remove-Item $tempRoot -Recurse -Force
}

Write-Output "Built $OutputPbitPath"
