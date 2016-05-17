<#
	.SYNOPSIS 
	Sends mPower Stats to InfluxDB
	.DESCRIPTION
	Sends mPower Stats to InfluxDB
	.PARAMETER user
	mPower Device Username
	.PARAMETER password
	mPower Device Password
    .PARAMETER mPowerHost
    mPower address
    .PARAMETER interval
    Minimum interval in milliseconds to send stats to InfluxDB. Stats received in between intervals will be discarded. Defaults to 1000.
	.PARAMETER influxdbuser
	InfluxDB username
	.PARAMETER influxdbpassword
	InfluxDB password
	.PARAMETER influxdbhost
	Hostname of the InfluxDB server
	.PARAMETER influxdbport
	Port for the InfluxDB server (default 8086)
	.PARAMETER influxdbname
	InfluxDB database name
	.INPUTS
	None
	.OUTPUTS
	None
	.NOTES
	.LINK
	https://github.com/tbyehl/Get-mPower-Stats
	
	.EXAMPLE
	.\Get-mPower-Stats.ps1 -user "username" -password "password" -mPowerHost "10.0.0.1" -influxdbuser "influxdb user" -influxdbpassword "influxdb password" -influxdbname "influx-database" -influxdbhost "localhost" -influxdbport 8086
	
#>
param(
    [parameter(HelpMessage="mPower username", Mandatory=$true)] [Alias("u")] [string] $user,
    [parameter(HelpMessage="mPower account password", Mandatory=$true)] [Alias("p")] [string] $password,
    [parameter(HelpMessage="mPower address", Mandatory=$true)] [Alias("h")] [string] $mPowerHost,
    [parameter(HelpMessage="Time in milliseconds between posting stats to InfluxDB", Mandatory=$false)] [Alias("i")] [int] $interval=1000,
    [parameter(HelpMessage="InfluxDB username", Mandatory=$true)] [Alias("iu")] [string] $influxdbuser,
    [parameter(HelpMessage="InfluxDB password", Mandatory=$true)] [Alias("ip")] [string] $influxdbpassword,
    [parameter(HelpMessage="InfluxDB host name", Mandatory=$true)] [Alias("ih")] [string] $influxdbhost,
    [parameter(HelpMessage="InfluxDB host name", Mandatory=$true)] [Alias("ihp")] [string] $influxdbport=8086,
    [parameter(HelpMessage="InfluxDB database name", Mandatory=$true)] [Alias("id")] [string] $influxdbname
    )
   

$postParams = @{ username=$user ; password =$password }
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-WebRequest "http://$mPowerHost/login.cgi" -Method GET -WebSession $session | Out-Null
Invoke-WebRequest "http://$mPowerHost/login.cgi" -Method Post -Body $postParams -WebSession $session | Out-Null
$cookie=$session.Cookies.GetCookies("http://$mPowerHost")[0].Value
$refjson = Invoke-WebRequest "http://$mPowerHost/sensors" -Method Get -WebSession $session | select Content | %{$_.Content} | ConvertFrom-Json


$l = [byte[]] @(,0) * 1024
$rc = New-Object System.ArraySegment[byte]  -ArgumentList @(,$l)

$w = New-object System.Net.WebSockets.ClientWebSocket                                                
$w.Options.AddSubProtocol("mfi-protocol")
$c = New-Object System.Threading.CancellationToken                                                   

try { $t = $w.ConnectAsync("ws://$($mPowerHost):7681/?c=$cookie", $c) }
catch {$_}

    do { Start-Sleep -Milliseconds 100 }
    until ($t.IsCompleted)

$w.SendAsync([System.Text.Encoding]::ASCII.GetBytes('{ "time": 10} '), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $c) | Out-Null

$lines=""
$count=0
$totalPower = 0
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()

While ($true) {    
    $t = $w.ReceiveAsync($rc, $c)
    do { Start-Sleep -Milliseconds 10 }
    until ($t.IsCompleted)

    $json = ConvertFrom-Json ( ([System.Text.Encoding]::ASCII.GetString($rc) -split "} ] }")[0] + "} ] }" )

    $json.sensors | % {
        $count += 1
        $mPowerHostname = $refjson.sensors[($_.Port - 1)].Label
        $sensor = $_
        $line=""

        $sensor | Get-Member -MemberType NoteProperty | ? {$_.Name -ne 'Label' } | % {
            $temp=$_

            switch ( $sensor.($temp.Name).GetType().Name ) {
                "String" { $lines +="mFi_$($temp.Name),hostname=""$($mPowerHostname -replace " ", "\ ")"" value=""$($sensor.($temp.Name) -replace " ", "\ ")"" `n" }
                default { $lines +="mFi_$($temp.Name),hostname=""$($mPowerHostname -replace " ", "\ ")"" value=$($sensor.($temp.Name)) `n" }
            }        
        }
        $totalPower += $sensor.power
    }

    if ($count -ge 8) {
        if  ($elapsed.ElapsedMilliseconds -ge $interval) {
            $lines += "mFi_TotalPower,hostname=""mPower-1"" value=$totalPower"
            $lines 

            $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

            $authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes("$($influxdbuser):$($influxdbpassword)")))
            $uri = "http://$($influxdbhost):$($influxdbport)/write?db=$influxdbname"
            Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $lines

            Write-Host (Get-Date)
        }

        $lines=""
        $count=0
        $totalPower = 0
    }
}