<#
    This PowerShell script is designed to monitor the network connection status 
    by periodically checking the ping status to a specified target computer or IP address. 
    It employs a loop structure to continuously monitor the network status in real-time.

    If packet loss is detected, the script responds in the following manner:
    - After 30 seconds of continuous packet loss, it switches to a Wi-Fi connection 
      using the SwitchToWifi function.
    - If packet loss persists for 2 minutes while on Wi-Fi, it switches back to 
      the Ethernet connection using the SwitchToEthernet function.

    The script ensures that the ping tests are performed specifically on the 
    Ethernet interface to maintain consistent network monitoring. The CheckPingStatus 
    function uses the Test-Connection cmdlet with the -InterfaceAlias parameter 
    to target the Ethernet interface explicitly.

    This script is intended to provide automated network failover capabilities 
    in scenarios where network reliability is critical. It can be customized 
    and integrated into various network management systems or used as a standalone 
    solution for managing network connections.

    Copyright 2024 Christian de Linde Sønderskov
    Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0
#>


# Fetch current user
$username = $env:USERNAME


# Computer name variable
$computername = $env:COMPUTERNAME


# Generate log file name with prefix "user_computername"
$logFileName = "networkmonitor_$username_$computername.log"


# Define target address
$pingTarget = "8.8.8.8"


# Define log path
$logFilePath = "C:\Path\To\Log\$logFileName"


# Define WiFi Name and SSID
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


# Function to switch to an allowed WiFi SSID, if running different SSID's for different computers
# It will only connect to an allowed SSID's from the array $wifiNameToSSID and match with known SSID's
#function SwitchToWifi {
#    try {
#        # Define a hashtable to link Wi-Fi names with their SSIDs
#        $wifiNameToSSID = @{
#            "WiFiName1" = "SSID1"
#            "WiFiName2" = "SSID2"
#            # Add more Wi-Fi names and their corresponding SSIDs as needed
#        }
#
#        # Get the list of known Wi-Fi networks and their SSIDs
#        $wifiNetworks = netsh wlan show networks mode=Bssid | Select-String -Pattern "SSID [0-9]+:" | ForEach-Object { $_ -replace "SSID [0-9]+: ", "" }
#
#        # Check if any of the known Wi-Fi names match the allowed Wi-Fi names
#        $allowedWiFiNames = $wifiNameToSSID.Keys
#        $matchingWiFiName = $allowedWiFiNames | Where-Object { $wifiNetworks -contains $_ }
#
#        if ($matchingWiFiName) {
#            $matchingSSID = $wifiNameToSSID[$matchingWiFiName]
#
#            # Connect to the Wi-Fi network with the matching SSID
#            netsh wlan connect name="$matchingSSID" ssid="$matchingSSID"
#            Log "Connected to Wi-Fi network: $matchingWiFiName (SSID: $matchingSSID)"
#        } else {
#            Log "No allowed Wi-Fi network found."
#        }
#    } catch {
#        Log "Error switching to Wi-Fi: $_" -Type "Error"
#    }
#}


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
$ethernetUpDuration = [TimeSpan]::Zero
$switchedToWifiTime = [DateTime]::MinValue

while ($true) {
    $pingResult = CheckPingStatus
    if ($pingResult) {
        # Increment Ethernet uptime duration by 10 seconds
        $ethernetUpDuration += [TimeSpan]::FromSeconds(10)

        # If Ethernet uptime duration exceeds 2 minutes and currently on Wi-Fi, switch back to Ethernet
        if ($ethernetUpDuration -ge [TimeSpan]::FromMinutes(2) -and $switchedToWifiTime -ne [DateTime]::MinValue) {
            SwitchToEthernet
            Log "Switched back to Ethernet after 2 minutes of successful ping responses"
            $ethernetUpDuration = [TimeSpan]::Zero
            $switchedToWifiTime = [DateTime]::MinValue
        }
    } else {
        # Reset Ethernet uptime duration
        $ethernetUpDuration = [TimeSpan]::Zero

        # If switched to Wi-Fi earlier and now back to Ethernet, reset the time
        if ($switchedToWifiTime -ne [DateTime]::MinValue) {
            $switchedToWifiTime = [DateTime]::MinValue
        }
    }

    # Wait for 10 seconds before checking ping status again
    Start-Sleep -Seconds 10
}