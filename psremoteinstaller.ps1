# Local path to the App installer file
$LocalAppInstaller = "C:\Users\usernameexample\Documents\Skype-8.122.0.205.exe"
$RemoteInstallerPath = "C:\Temp\AppSetup.exe"

# Reading the list of computers
$computers = Get-Content -Path "C:\Users\usernameexample\Documents\computers.txt"

# Command to install App
$taskName = "InstallApp"
$installCommand = "$RemoteInstallerPath /VERYSILENT /NORESTART"

# Prompt for credentials once
$cred = Get-Credential

# Function to install App on a remote computer
function Install-App {
    param (
        [string] $ComputerName,
        $credential
    )

    # Check if the computer is accessible
    if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
        Write-Host "Connecting to $ComputerName..."

        try {
            # Create a session
            $session = New-PSSession -ComputerName $ComputerName -Credential $credential

            # Create the directory on the remote computer, if it does not exist
            Invoke-Command -Session $session -ScriptBlock {
                param ($RemoteInstallerPath)
                $folderPath = [System.IO.Path]::GetDirectoryName($RemoteInstallerPath)
                if (-Not (Test-Path -Path $folderPath)) {
                    New-Item -Path $folderPath -ItemType Directory | Out-Null
                }
            } -ArgumentList $RemoteInstallerPath

            # Copy the installer file to the remote computer
            Copy-Item -Path $LocalAppInstaller -Destination $RemoteInstallerPath -ToSession $session -Force

            # Create a scheduled task on the remote computer to install App
            $scriptBlock = {
                param ($installCommand, $taskName, $RemoteInstallerPath)

                # Command to create the scheduled task
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $installCommand"
                $trigger = New-ScheduledTaskTrigger -AtStartup
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName $taskName

                # Start the scheduled task
                Start-ScheduledTask -TaskName $taskName
                Write-Host "Scheduled task for App installation created and started on $ComputerName"

                # Wait for the task to complete
                while ((Get-ScheduledTask $taskName).State -eq 'Running') {
                    Start-Sleep -Seconds 5
                }

                # Remove the temporary folder
                $folderPath = [System.IO.Path]::GetDirectoryName($RemoteInstallerPath)
                Remove-Item -Path $folderPath -Recurse -Force
                Write-Host "Temp folder removed on $ComputerName"
            }

            # Execute the command on the remote computer
            Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $installCommand, $taskName, $RemoteInstallerPath

            # Close the session
            Remove-PSSession -Session $session
        }
        catch {
            Write-Error "Failed to copy installer or connect to $ComputerName. Error: $_"
        }
    } else {
        Write-Host "$ComputerName is not accessible."
    }
}

# Iterate over all computers and install App
foreach ($computer in $computers) {
    Write-Host "Updating App on $computer"
    Install-App -ComputerName $computer -credential $cred
}