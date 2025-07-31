# This script finds disconnected Azure Arc-enabled servers and attempts to reconnect them.
# Requires Az.ConnectedMachine PowerShell module.

# Check if Az.ConnectedMachine module is installed, install if missing
if (-not (Get-Module -ListAvailable -Name Az.ConnectedMachine)) {
    Write-Host "Az.ConnectedMachine module is not installed. Installing..."
    try {
        Install-Module -Name Az.ConnectedMachine -Force -Scope CurrentUser -AllowClobber
    } catch {
        Write-Error "Failed to install Az.ConnectedMachine module. $_"
        return
    }
}

# Import the module if not already imported
if (-not (Get-Module -Name Az.ConnectedMachine)) {
    Import-Module Az.ConnectedMachine
}

#Connect to Azure Account
Connect-AzAccount -UseDeviceAuthentication

# Get all Arc-enabled servers in the current subscription
$arcServers = Get-AzConnectedMachine

# Filter servers that are disconnected
$disconnectedServers = $arcServers | Where-Object { $_.Status -ne "Connected" }

if ($disconnectedServers.Count -eq 0) {
    Write-Host "No disconnected Arc-enabled servers found."
    return
}

Write-Host "Found $($disconnectedServers.Count) disconnected Arc-enabled server(s):"
$disconnectedServers | ForEach-Object { Write-Host $_.Name }

# Prompt for credentials to use for remote sessions
$cred = Get-Credential -Message "Enter credentials for remote servers"

# Attempt to reconnect each disconnected server
foreach ($server in $disconnectedServers) {
    Write-Host "Attempting to reconnect server: $($server.Name)"
    try {
        # Attempt to create a remote session
        $session = New-PSSession -ComputerName $server.Name -Credential $cred -ErrorAction Stop

        # Run the onboarding command remotely
        Invoke-Command -Session $session -ScriptBlock {
            param($resourceId)
            Write-Host "Running: azcmagent disconnect"
            azcmagent disconnect
            Write-Host "Running: azcmagent connect --resource-id $resourceId"
            azcmagent connect --resource-id $resourceId
        } -ArgumentList $server.Id

        Write-Host "Reconnection command sent to $($server.Name)."
        Remove-PSSession $session
    } catch {
        Write-Warning "Failed to process $($server.Name): $_"
        if ($session) { Remove-PSSession $session }
    }
}

Write-Host "Script completed."