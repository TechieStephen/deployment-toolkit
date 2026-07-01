function Read-AppSettings {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (!(Test-Path $Path)) {
        throw "appsettings.json not found: $Path"
    }

    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Save-AppSettings {
    param(
        [Parameter(Mandatory)]
        $AppSettings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $json = $AppSettings | ConvertTo-Json -Depth 100

    $object = [System.Text.Json.JsonDocument]::Parse($json)

    $options = [System.Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $true

    $formatted = [System.Text.Json.JsonSerializer]::Serialize($object.RootElement, $options)

    Set-Content -Path $Path -Value $formatted -Encoding UTF8
}

function Set-ConfigValue {
    param(
        [Parameter(Mandatory)]
        $Object,

        [Parameter(Mandatory)]
        [string]$Path,

        $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-WarningLog "Config value for '$Path' is null or empty. Skipping update."
        return $false
    }

    Write-Info ("Mapping -> : '{0}' : {1}" -f $Path, $Value)

    $parts = $Path.Split(':')
    $current = $Object

    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $key = $parts[$i]

        if ($null -eq $current.$key -or $current.$key -eq "") {
            $current.$key = [PSCustomObject]@{}
        }

        $current = $current.$key
    }

    $finalKey = $parts[-1]

    if ($current -is [System.Management.Automation.PSCustomObject]) {
        $current | Add-Member `
            -MemberType NoteProperty `
            -Name $finalKey `
            -Value $Value `
            -Force
    }
    else {
        $current.$finalKey = $Value
    }

    return $true
}