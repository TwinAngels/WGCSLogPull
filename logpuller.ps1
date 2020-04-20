Param (
    [Parameter(Mandatory=$false)][string]$CustomerID,
    [Parameter(Mandatory=$false)][string]$Username,
    [Parameter(Mandatory=$false)][int]$Interval,
    [Parameter(Mandatory=$false)][int]$Minutes,
    [Parameter(Mandatory=$false)][int]$Hours,
    [Parameter(Mandatory=$false)][int]$Days,
    [Parameter(Mandatory=$false)][switch]$IgnoreCerts,
    [Parameter(Mandatory=$false)][switch]$Service,
    [Parameter(Mandatory=$false)][switch]$Help
)
<#
	Parameters MUST be at the top of the powershell script.
#>

#$global:Password = 'PasswordHereIfYoureLazy'

# In what time increments should we collect logs?
$global:Interval = 600;
# How far back should we collect log logs?
$global:Duration = 3600;

#############################################
# Web Gateway Cloud Service Log Puller Script v0.6 (mod)
# -- Modification by SvdB, April/2020
# -- new API version 5
# -- enforced en-US locales culture
# -- removed Update check
# -- added PW storage capability
#
# Collect logs from Web Gateway Cloud Service (last 4 hours):
#    .\CloudLogPullerLatest.ps1 -CustomerID XXXXXXXXXX -User EPO_CLOUD_USER -Hours 4 -IgnoreCerts
#
# Collect logs from Web Gateway Cloud Service (last 7 days in chunks of 5 minutes):
#    .\CloudLogPullerLatest.ps1 -CustomerID XXXXXXXXXX -User EPO_CLOUD_USER -Days 7 -Interval 300 -IgnoreCerts
#
#############################################
$global:ScriptVersion = '0.6 (mod)';

$global:CustomerID = $CustomerID;
$global:Username = $Username;
$global:UserInterval = $Interval;
$global:Duration = $Duration;
$global:Minutes = $Minutes;
$global:Hours = $Hours;
$global:Days = $Days;
$global:IgnoreCerts = $IgnoreCerts;
$global:Service = $Service
$global:Help = $Help;
Clear-Variable -name CustomerID
Clear-Variable -name Username
Clear-Variable -name Interval
Clear-Variable -name Duration
Clear-Variable -name Minutes
Clear-Variable -name Hours
Clear-Variable -name Days
Clear-Variable -name IgnoreCerts
Clear-Variable -name Service
Clear-Variable -name Help

# In what time increments should we collect logs?
$global:Interval = 600;
# How far back should we collect log logs?
$global:Duration = 3600;
# Set en-US culture for decimal numbers
[System.Threading.Thread]::CurrentThread.CurrentCulture = "en-US"

Function MFE-Startup
{
	clear
	
	If ($global:Help.IsPresent)
	{
		MFE-ShowHelp;
	}
	
	$global:CloudApiVersion = '5';
	$global:FatalError = $false;
	$global:Server = 'msg.mcafeesaas.com';
	$global:ScriptPath = $PSScriptRoot;
	$global:MfeLogFile = -Join($global:ScriptPath, '\CloudLogPuller.log');
	$global:MfeIniFile = -Join($global:ScriptPath, '\CloudLogPuller.ini');
    $global:DownloadDirectory = -Join($global:ScriptPath, '\Logs');
    $global:DownloadDirectory = "C:\MWGLogs";
	If (!(Test-Path $global:DownloadDirectory))
	{
		$r = New-Item -ItemType Directory -Force -Path $global:DownloadDirectory
	}
	
Write-Host @"

*************************************************
*                                               *
*    Cloud Log Puller $global:ScriptVersion                       *
*                                               *
*    (This script will download Web Gateway     *
*    Cloud Service Logs)                        *
*                                               *
*************************************************


"@

	MFE-GetAccountCredentials;
	If ($global:IgnoreCerts.IsPresent)
	{
		MFE-IgnoreCertWarnings;
	}
	MFE-DownloadLogs;
	MFE-DeleteEmptyFiles;
	MFE-Cleanup;
}

Function MFE-GetAccountCredentials
{
    # Try to read credentials from Config File
    If (Test-Path $global:MfeIniFile -PathType leaf)
    {
        $ini = (Get-Content $global:MfeIniFile)
        # Read CustomerID
        $global:CustomerID = $ini[0]
        # Read Username
        $global:Username = $ini[1]
        # Read Password
        $SecurePassword = ConvertTo-SecureString $ini[2]
        $SecString = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
		$global:Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($SecString)
    }

	# Prompt for credentials if they are not set
	If($global:CustomerID -eq $null -Or $global:CustomerID -eq '')
	{
		$global:CustomerID = Read-Host -Prompt 'Customer ID'
	}
	Else
	{
		echo "Customer ID: $global:CustomerID"
	}	
	
	If($global:Username -eq $null -Or $global:Username -eq '')
	{
		$global:Username = Read-Host -Prompt 'Username'
	}
	Else
	{
		echo "Username: $global:Username"
	}
	
	If($global:Password -eq $null -Or $global:Password -eq '')
	{
	    $SecurePassword = Read-Host -Prompt "Password" -AsSecureString
        $SecString = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
		$global:Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($SecString)
	}
	Else
	{
		echo "Password: [Using Password from Script]"
	}

    # Write data to file if it does not exist yet
    If (-Not(Test-Path $global:MfeIniFile -PathType leaf) -And $global:Service.IsPresent)
    {
        Add-Content $global:MfeIniFile -Value ($global:CustomerID)
        Add-Content $global:MfeIniFile -Value ($global:Username)
        Add-Content $global:MfeIniFile -Value (ConvertFrom-SecureString $SecurePassword)
    }
	
	If ($global:Days -ne $null -And $global:Days -ne '')
	{
		$global:Duration = [int]$global:Days * 86400;
		echo "Collection Duration: $global:Days days ($global:Duration seconds)"
	}
	ElseIf ($global:Hours -ne $null -And $global:Hours -ne '')
	{
		$global:Duration = [int]$global:Hours * 3600;
		echo "Collection Duration: $global:Hours hours ($global:Duration seconds)"
	}
	ElseIf ($global:Minutes -ne $null -And $global:Minutes -ne '')
	{
		$global:Duration = [int]$global:Minutes * 60;
		echo "Collection Duration: $global:Minutes minutes ($global:Duration seconds)"
	}
	
	If ($global:UserInterval -ne $null -And $global:UserInterval -ne '')
	{
		$global:Interval = $global:UserInterval;
	}
	echo "Collection Interval: $global:Interval seconds"
	echo "`n";
	
	MFE-Logger -Message "INFO: Starting up Cloud Log Puller version $global:ScriptVersion" -Func 'MFE-Startup'
	MFE-Logger -Message "INFO: Customer ID: $($global:CustomerID)" -Func $MyInvocation.MyCommand
	MFE-Logger -Message "INFO: Username: $($global:Username)" -Func $MyInvocation.MyCommand
	MFE-Logger -Message "INFO: Duration: $($global:Duration)" -Func $MyInvocation.MyCommand
	MFE-Logger -Message "INFO: Interval: $($global:Interval)" -Func $MyInvocation.MyCommand
	
	
	$global:base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:Username,$global:Password)))
	Clear-Variable -name Password -Scope Global
	Clear-Variable -name Username -Scope Global
}

Function MFE-DownloadLogs
{
	<#
		Download Logs from Web Gateway Cloud Service
	#>
	$TimeTo = MFE-GetEpoch;
    $TimeTo = $TimeTo - ($TimeTo % 1800)
	$TimeFrom = $TimeTo - $global:Duration;
	$CycleFrom = $TimeFrom;
	$CycleTo = $CycleFrom + $global:Interval;
	
	MFE-Logger -Message "WARN: Start collect $(EpochToTimestamp -UnixTime $TimeFrom) to $(EpochToTimestamp -UnixTime $TimeTo)" -Func $MyInvocation.MyCommand -Level 'warn'
	
	$HttpHeaders = @{
		'Authorization' = ("Basic {0}" -f $global:base64AuthInfo)
		'Accept' = "text/csv"
		'User-Agent' = "Cloud Log Puller v$($global:ScriptVersion)"
		'X-MFE-DownloadFileName' = "Forensic Report.csv"
		'X-MFE-CSVRowXPath' = "//request"
		'X-MWG-API-Version' = "$global:CloudApiVersion"
	}
	
	Do
	{
		MFE-Logger -Message "INFO: Collecting logs $(EpochToTimestamp -UnixTime $CycleFrom) to $(EpochToTimestamp -UnixTime $CycleTo)" -Func $MyInvocation.MyCommand -Level 'info'
		$uri = "https://$($global:Server):443/mwg/api/reporting/forensic/$($global:CustomerID)?filter.requestTimestampFrom=$($CycleFrom)&filter.requestTimestampTo=$($CycleTo)&order.0.requestTimestamp=asc";
		$response = try {
			Invoke-RestMethod -Headers $HttpHeaders -TimeoutSec 60 -Uri $uri -OutFile "$($global:DownloadDirectory)\CloudLog_$($CycleFrom).csv"
		}
		catch {
			$StatusCode = $_.Exception.Response.StatusCode.value__ ;
			$StatusDescription = $_.Exception.Response.StatusDescription
			$WebException = $_.Exception
			MFE-CheckForHttpError -StatusCode $StatusCode -WebException $WebException -Func $MyInvocation.MyCommand -UrlHost $global:Server
		}
		
		$CycleFrom = $CycleTo + 1;
		$CycleTo = $CycleTo + $global:Interval;
	} While (!$global:FatalError -And $TimeTo -gt $CycleTo)
	
	If (!$global:FatalError)
	{
		MFE-Logger -Message "INFO: Collecting logs $(EpochToTimestamp -UnixTime $CycleFrom) to $(EpochToTimestamp -UnixTime $TimeTo)" -Func $MyInvocation.MyCommand -Level 'info'
		$uri = "https://$($global:Server):443/mwg/api/reporting/forensic/$($global:CustomerID)?filter.requestTimestampFrom=$($CycleFrom)&filter.requestTimestampTo=$($TimeTo)&order.0.requestTimestamp=asc";
		$response = try {
			Invoke-RestMethod -Headers $HttpHeaders -TimeoutSec 60 -Uri $uri -OutFile "$($global:DownloadDirectory)\CloudLog_$($CycleFrom).csv"
		}
		catch {
			$StatusCode = $_.Exception.Response.StatusCode.value__ ;
			$StatusDescription = $_.Exception.Response.StatusDescription
			$WebException = $_.Exception
			MFE-CheckForHttpError -StatusCode $StatusCode -WebException $WebException -Func $MyInvocation.MyCommand -UrlHost $global:Server
		}
	}
	
	MFE-Logger -Message "WARN: Finished collecting logs" -Func $MyInvocation.MyCommand -Level 'warn'
}

Function EpochToTimestamp ([long]$UnixTime)
{
    $epoch = New-Object System.DateTime (1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc);
	$time = $epoch.AddSeconds($UnixTime);
	#$timestamp = "[{0:dd/MMM/yy} {0:HH:mm:ss} -0000]" -f ($time)
	$timestamp = "{0:dd/MMM/yy} {0:HH:mm:ss} -0000" -f ($time)
    write $timestamp
    return $timestamp;
}

Function MFE-DeleteEmptyFiles
{
	MFE-Logger -Message "WARN: Deleting Empty Log Files" -Func $MyInvocation.MyCommand -Level 'warn'
	#Get-ChildItem $global:DownloadDirectory -Filter CloudLog_*.csv -recurse |?{$_.PSIsContainer -eq $false -and $_.length -lt 5}|?{Remove-Item $_.fullname -WhatIf}
	Get-ChildItem $global:DownloadDirectory -Filter CloudLog_*.csv -recurse |?{$_.PSIsContainer -eq $false -and $_.length -lt 5}|?{Remove-Item $_.fullname}
}

Function MFE-CallApi
{
	Param ( [string]$uri, [string]$Func, [string]$Method, [string]$Body, [string]$ContentType  )
	
	$response = try {
		If($Method -ne $null -And $Method -ne '')
		{
			Invoke-RestMethod -Headers @{Authorization=("Basic {0}" -f $global:base64AuthInfo)} -TimeoutSec 5 -Uri $uri -Method $Method -Body $Body -ContentType $ContentType
		}
		Else
		{
			Invoke-RestMethod -Headers @{Authorization=("Basic {0}" -f $global:base64AuthInfo)} -TimeoutSec 5 -Uri $uri
		}
	}
	catch {
		$StatusCode = $_.Exception.Response.StatusCode.value__ ;
		$StatusDescription = $_.Exception.Response.StatusDescription
		$WebException = $_.Exception
		MFE-CheckForHttpError -StatusCode $StatusCode -WebException $WebException -Func $Func -UrlHost $global:Server
	}
}

Function MFE-CheckForHttpError
{
	Param ( [string]$StatusCode, [string]$WebException, [string]$Func, [string]$UrlHost )
	#Write-Host $StatusCode;
	#Write-Host $WebException;
	
	If ($StatusCode -eq '401')
	{
		MFE-Logger -Message "ERROR: Unauthorized, check username/password (Status Code: 401)" -Func $Func -Level 'error'
		$global:FatalError = $true;
	}
	ElseIf ($StatusCode -eq '403')
	{
		MFE-Logger -Message "ERROR: Request Blocked (Status Code: 403)" -Func $Func -Level 'error'
	}
	ElseIf ($StatusCode -like '40x')
	{
		MFE-Logger -Message "ERROR: Other failure (Status Code: $($StatusCode))" -Func $Func -Level 'error'
	}
	ElseIf ($WebException -like "*File unavailable*")
	{
		MFE-Logger -Message "ERROR: File not found" -Func $Func -Level 'error'
	}
	ElseIf ($WebException -like "*The remote name could not be resolved*")
	{
		MFE-Logger -Message "ERROR: DNS Failure ($UrlHost)" -Func $Func -Level 'error'
	}
	ElseIf ($WebException -like "*The handshake failed due to an unexpected packet format*")
	{
		MFE-Logger -Message "ERROR: Handshake Failure" -Func $Func -Level 'error'
	}
	ElseIf ($WebException -like "*Unable to connect to the remote server*" -Or $WebException -like "*The operation has timed out*")
	{
		MFE-Logger -Message "ERROR: Gave up waiting, server not reachable (SYN, SYN, SYN)" -Func $Func -Level 'error'
	}
	Else
	{
		MFE-Logger -Message "ERROR: Not sure what happened here..." -Func $Func -Level 'error'
		Write-Host $WebException -ForegroundColor "Red"
	}
}

Function MFE-IgnoreCertWarnings
{
	MFE-Logger -Message "Ignoring certificate warnings" -Func $MyInvocation.MyCommand

Add-Type @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            ServicePointManager.ServerCertificateValidationCallback += 
                delegate
                (
                    Object obj, 
                    X509Certificate certificate, 
                    X509Chain chain, 
                    SslPolicyErrors errors
                )
                {
                    return true;
                };
        }
    }
"@
	
	# Only use TLS1.2
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	
	[ServerCertificateValidationCallback]::Ignore();
}

Function MFE-Logger
{
	Param ( [string]$Message, [string]$Func, [string]$Level )
	# Timestamp format = [31/Jul/17 12:00:00 -0500]
	$timezone = "{0:zzz}" -f (Get-Date)
	$timezone = ($timezone -replace ":", '')
	$timestamp = "[{0:dd/MMM/yy} {0:HH:mm:ss} $timezone]" -f (Get-Date)
	Add-Content $global:MfeLogFile -Value "$($timestamp) $($Func): $($Message)"
	
	If ($Level.ToLower() -eq 'error')
	{
		Write-Host "$($timestamp) $($Func): $($Message)" -ForegroundColor "Red"
	}
	ElseIf ($Level.ToLower() -eq 'warn')
	{
		Write-Host "$($timestamp) $($Func): $($Message)" -ForegroundColor "Yellow"
	}
	ElseIf ($Level.ToLower() -eq 'info')
	{
		Write-Host "$($timestamp) $($Func): $($Message)" -ForegroundColor "Cyan"
	}
	ElseIf ($Level.ToLower() -eq 'success' -Or $Level.ToLower() -eq 'ok')
	{
		Write-Host "$($timestamp) $($Func): $($Message)" -ForegroundColor "Green"
	}
	Else
	{
		Write-Host "$($timestamp) $($Func): $($Message)"
	}
}

Function MFE-GetEpoch
{
	$ED=[Math]::Floor([long](Get-Date(Get-Date).ToUniversalTime() -UFormat %s))
    return $ED
}

Function MFE-Cleanup
{
	# Cleanup Variables
	Clear-Variable -name base64AuthInfo -Scope Global
}

MFE-Startup;
