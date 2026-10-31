param(
    [Parameter(Mandatory = $true)][ValidateRange(5554, 5682)][int]$Port,
    [Parameter(Mandatory = $true)][string]$ExpectedAvd,
    [switch]$Shutdown
)

# EMULATOR_CONSOLE: use the Windows loopback console when WSL adb emu is unreliable.
# Authenticate in process; never print or include the token in command arguments.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$client = [System.Net.Sockets.TcpClient]::new()

function Read-ConsoleResponse([bool]$AllowDisconnect = $false) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($true) {
        $remaining = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { throw 'Emulator console response timed out.' }
        $stream.ReadTimeout = $remaining
        try {
            $line = $reader.ReadLine()
        } catch [System.IO.IOException] {
            if ($AllowDisconnect) { return $lines.ToArray() }
            throw
        }
        if ($null -eq $line) {
            if ($AllowDisconnect) { return $lines.ToArray() }
            throw 'Emulator console disconnected before acknowledging the command.'
        }
        if ($line.StartsWith('KO:')) { throw 'Emulator console rejected the command.' }
        if ($line -eq 'OK' -or $line.StartsWith('OK:')) { return $lines.ToArray() }
        $lines.Add($line)
    }
}

try {
    if (-not $client.ConnectAsync('127.0.0.1', $Port).Wait(5000)) {
        throw 'Cannot connect to the Windows emulator console.'
    }
    $stream = $client.GetStream()
    $stream.WriteTimeout = 5000
    $reader = [System.IO.StreamReader]::new($stream)
    $writer = [System.IO.StreamWriter]::new($stream)
    $writer.NewLine = "`r`n"
    $writer.AutoFlush = $true
    $greeting = @(Read-ConsoleResponse)
    if (($greeting -join "`n") -match 'Authentication required') {
        try {
            $tokenPath = Join-Path $env:USERPROFILE '.emulator_console_auth_token'
            $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
            if ([string]::IsNullOrWhiteSpace($token) -or $token -match '[\r\n]') {
                throw 'Invalid console authentication.'
            }
            $writer.WriteLine('auth ' + $token)
            $null = @(Read-ConsoleResponse)
        } catch {
            throw 'Cannot authenticate to the Windows emulator console; no device was closed.'
        } finally {
            $token = $null
        }
    }
    $writer.WriteLine('avd name')
    $names = @(Read-ConsoleResponse | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($names.Count -ne 1 -or $names[0].Trim() -cne $ExpectedAvd) {
        throw 'Emulator console AVD does not match the confirmed target; no device was closed.'
    }
    if ($Shutdown) {
        $writer.WriteLine('kill')
        $null = @(Read-ConsoleResponse $true)
        # The caller must still observe ADB disappearance and Windows process exit.
        Write-Output "Console shutdown requested: $ExpectedAvd (port $Port)."
    } else {
        Write-Output $names[0].Trim()
    }
} finally {
    $client.Dispose()
}
