<#
.SYNOPSIS
Monitors an Azure DevOps build and sends email alerts whenever a job has failed.

.PARAMETER Account
Name of the Azure DevOps account to connect to.

.PARAMETER Project
Name of the Azure DevOps project to connect to.

.PARAMETER BuildId
ID of the build to monitor.

.PARAMETER AlertEmail
Email address where alerts will be sent.

.PARAMETER SmtpServer
SMTP server host to send emails through.

.PARAMETER SmtpPort
Port number to connect to the SMTP server.

.PARAMETER FromEmail
Email address to use as the sender of the alert. Defaults to the SMTP account credentials that are prompted for.
#>

[cmdletbinding()]
param(
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][int]$BuildId,
    [Parameter(Mandatory = $true)][string]$AlertEmail,
    [string]$SmtpServer = "smtp.office365.com",
    [int]$SmtpPort = 587,
    [string]$FromEmail
)

if (-Not (Get-Module -ListAvailable -Name Microsoft.ADAL.PowerShell))
{
    Install-Module -Name Microsoft.ADAL.PowerShell
}

Write-Host "Authenticating to Azure DevOps..."
$token = Get-ADALAccessToken -AuthorityName "common" -ClientId "872cd9fa-d31f-45e0-9eab-6e460a02d1f1" -ResourceId "499b84ac-1321-427f-aa17-267ca6975798" -RedirectUri "urn:ietf:wg:oauth:2.0:oob"

$creds = $host.UI.PromptForCredential("Enter credentials", "Enter SMTP account credentials", "", "")
if (-not $FromEmail)
{
    $FromEmail = $creds.UserName
}

function SendAlert {
    param(
        [string]$Message
    )
    
    Write-Host $Message

    Send-MailMessage -To $AlertEmail -From $FromEmail -SmtpServer $SmtpServer -Port $SmtpPort -UseSSL -Credential $creds -Subject "Build Alert: $BuildId" -Body $Message
}

$header = @{Authorization = "Bearer $token"}

$failedJobs = @{}

$buildUrl = "https://dev.azure.com/$Account/$Project/_apis/build/builds/$BuildId/?api-version=5.1"
$timelineUrl = "https://dev.azure.com/$Account/$Project/_apis/build/builds/$BuildId/timeline?api-version=5.1"

$build = Invoke-RestMethod -Uri $buildUrl -Method Get -ContentType "application/json" -Headers $header

if ($build)
{
    while ($build.status -ne "completed") {
        $timeline = Invoke-RestMethod -Uri $timelineUrl -Method Get -ContentType "application/json" -Headers $header
        foreach ($record in $timeline.records) {
            if ($record.type -eq "Job" -and $record.state -eq "completed" -and $record.result -eq "failed" -and -not $failedJobs[$record.id]) {
                $failedJobs.Add($record.id, $record)
                SendAlert("Job failed: $($record.name)")
            }
        }

        $build = Invoke-RestMethod -Uri $buildUrl -Method Get -ContentType "application/json" -Headers $header

        Start-Sleep -Seconds 10
    }

    SendAlert("Build completed")
}