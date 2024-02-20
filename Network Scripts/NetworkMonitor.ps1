<#
    Copyright 2024 @ McDoom

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
#>

# Fetch logged in user
$username = $env:USERNAME


# Computer name variable
$computername = $env:COMPUTERNAME


# Generate log file name with prefix "user - computername" and current date and time
$logFileName = "$username-$computername-$(Get-Date -Format 'dd-MM-yyyy_HH_mm').log"


# Define target address
$pingTarget = "8.8.8.8"


# Define log path
$logFilePath = "C:\Path\To\Log\$logFileName"


# Specify which WiFi network
$wifiName = ""
$wifiSSID = ""


# Get the interface index of the default Ethernet interface
try {
    $ethernetInterfaceIndex = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Ethernet*" -and $_.Status -eq "Up" } | Select-Object -ExpandProperty ifIndex
} catch {
    Write-Host "Error getting Ethernet interface index: $_"
    exit 1
}


# Log function
function Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-content -Path $logFilePath -Value $logMessage
}


# Function to switch traffic to Wi-Fi
function SwitchToWifi {
    try {
        # Connect to specific Wi-Fi network
        netsh wlan connect name=$wifiName ssid=$wifiSSID
        
        # Limit traffic on Ethernet to only ping requests
        New-NetQosPolicy -InterfaceIndex $ethernetInterfaceIndex -Name "PingOnly" -AppPathNameMatchCondition "icmp" -ThrottleRateActionBitsPerSecond 1024
    } catch {
        Log "Error switching to Wi-Fi: $_"
    }
}


# Function to switch traffic back to Ethernet
function SwitchToEthernet {
    try {
        # Disconnect from Wi-Fi
        netsh wlan disconnect
        
        # Remove traffic limitation on Ethernet
        Remove-NetQosPolicy -InterfaceIndex $ethernetInterfaceIndex -Name "PingOnly"
    } catch {
        Log "Error switching to Ethernet: $_"
    }
}


# Function to check ping status
function CheckPingStatus {
    # Testing the connection on the Ethernet interface
    return (Test-Connection -ComputerName $pingTarget -InterfaceAlias $ethernetInterfaceAlias -Quiet)
}


# Main loop
$packetLossDuration = [TimeSpan]::Zero
$switchedToWifiTime = [DateTime]::MinValue

while ($true) {
    $pingResult = CheckPingStatus
    if (-not $pingResult) {
        # Increment packet loss into 10 seconds duration
        $packetLossDuration += [TimeSpan]::FromSeconds(10)
        
        # If packet loss duration exceeds 2 minutes and currently on Wi-Fi, switch back to Ethernet
        if ($packetLossDuration -ge [TimeSpan]::FromMinutes(2) -and $switchedToWifiTime -ne [DateTime]::MinValue) {
            SwitchToEthernet
            Log "Switched back to Ethernet after 2 minutes of packet loss"
            $packetLossDuration = [TimeSpan]::Zero
            $switchedToWifiTime = [DateTime]::MinValue
        } elseif ($packetLossDuration -ge [TimeSpan]::FromSeconds(30)) {
            # If packet loss duration exceeds 30 seconds, switches to Wi-Fi
            SwitchToWifi
            $switchedToWifiTime = Get-Date
            Log "Switched to Wi-Fi due to packet loss"
        } else {
            Log "Packet loss detected"
        }
    } else {
        # Reset packet loss duration
        $packetLossDuration = [TimeSpan]::Zero

        # If switched to Wi-Fi earlier and now back to Ethernet, reset the time
        if ($switchedToWifiTime -ne [DateTime]::MinValue) {
            $switchedToWifiTime = [DateTime]::MinValue
        }
    }
    
    # Wait for 10 seconds before checking ping status again
    Start-Sleep -Seconds 10
}
