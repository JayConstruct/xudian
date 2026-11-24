param(
    [Parameter(Mandatory = $true)][string]$EmulatorPath,
    [Parameter(Mandatory = $true)][string[]]$EmulatorArguments,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
)

# The emulator prefers an IPv6 modem listener even when Windows allows the
# bind but rejects connections to ::1. In that case reserve only the IPv6
# endpoint until the modem has bound its built-in IPv4 fallback.
function Get-ModemPortReservation {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $listener = $null
        $client = $null
        $ipv4 = $null
        $keepListener = $false
        try {
            $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback, 0)
            $listener.Server.DualMode = $false
            $listener.ExclusiveAddressUse = $true
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
            $client = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetworkV6)
            try {
                $pending = $client.ConnectAsync([Net.IPAddress]::IPv6Loopback, $port)
                $null = $pending.Wait(1000)
                return
            } catch {
                $cause = $_.Exception.GetBaseException()
                if ($cause -isnot [Net.Sockets.SocketException] -or
                    $cause.SocketErrorCode -ne [Net.Sockets.SocketError]::AccessDenied) { return }
            }
            $ipv4 = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
            $ipv4.ExclusiveAddressUse = $true
            $ipv4.Start()
            $keepListener = $true
            return $listener
        } catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -isnot [Net.Sockets.SocketException] -or
                $cause.SocketErrorCode -ne [Net.Sockets.SocketError]::AddressAlreadyInUse) { return }
        } finally {
            if ($client) { $client.Dispose() }
            if ($ipv4) { $ipv4.Stop() }
            if ($listener -and !$keepListener) { $listener.Stop() }
        }
    }
}

$reservation = Get-ModemPortReservation
try {
    if ($reservation) {
        $port = $reservation.LocalEndpoint.Port
        $EmulatorArguments += @('-modem-simulator-port', [string]$port)
    }
    $exe = Get-Item -LiteralPath $EmulatorPath
    $process = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -ArgumentList $EmulatorArguments -PassThru
    Write-Output "Emulator started, PID: $($process.Id)"
    if ($reservation) {
        $deadline = [DateTime]::UtcNow.AddSeconds([math]::Min(45, $TimeoutSeconds))
        do {
            $endpoints = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
            if ($endpoints | Where-Object { $_.Port -eq $port -and $_.Address.Equals([Net.IPAddress]::Loopback) }) {
                Write-Output "Modem listening on IPv4 loopback 127.0.0.1:$port."
                return
            }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline -and !$process.HasExited)
        Write-Warning "Could not confirm the IPv4 modem listener on port $port."
    }
} finally {
    if ($reservation) { $reservation.Stop() }
}
