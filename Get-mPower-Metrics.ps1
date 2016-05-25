<#
	.SYNOPSIS 
	Sends mPower metrics to InfluxDB
	.DESCRIPTION
	Sends mPower metrics to InfluxDB
	.PARAMETER user
	mPower Device Username
	.PARAMETER password
	mPower Device Password
	.PARAMETER mPowerHost
	mPower address
	.PARAMETER influxdbuser
	InfluxDB username
	.PARAMETER influxdbpassword
	InfluxDB password
	.PARAMETER influxdbhost
	Hostname of the InfluxDB server. The UDP listener must be enabled on the server.
	.PARAMETER influxdbport
	Port for the InfluxDB server (default 2500)
	.INPUTS
	None
	.OUTPUTS
	None
	.NOTES
	.LINK
	https://github.com/tbyehl/Get-mPower-metrics
	
	.EXAMPLE
	.\Get-mPower-metrics.ps1 -user "username" -password "password" -mPowerHost "10.0.0.1" -influxdbuser "influxdb user" -influxdbpassword "influxdb password" -influxdbhost "localhost" -influxdbport 2500
	
#>
param(
	[parameter(HelpMessage="mPower username", Mandatory=$true)] [Alias("u")] [string] $user,
	[parameter(HelpMessage="mPower account password", Mandatory=$true)] [Alias("p")] [string] $password,
	[parameter(HelpMessage="mPower address", Mandatory=$true)] [Alias("h")] [string] $mPowerHost,
	[parameter(HelpMessage="InfluxDB username", Mandatory=$true)] [Alias("iu")] [string] $influxdbuser,
	[parameter(HelpMessage="InfluxDB password", Mandatory=$true)] [Alias("ip")] [string] $influxdbpassword,
	[parameter(HelpMessage="InfluxDB host name", Mandatory=$true)] [Alias("ih")] [string] $influxdbhost,
	[parameter(HelpMessage="InfluxDB host name", Mandatory=$true)] [Alias("ihp")] [string] $influxdbport=8086,
	[parameter(HelpMessage="InfluxDB database name", Mandatory=$true)] [Alias("id")] [string] $influxdbname
	)

	$endpoint = New-Object System.Net.IPEndPoint ([ipaddress] $influxdbhost, $influxdbPort)
	$udpclient= New-Object System.Net.Sockets.UdpClient

function Send-UDP($Message) {
	$bytes=[Text.Encoding]::ASCII.GetBytes($Message)
	$bytesSent=$udpclient.Send($bytes,$bytes.length,$endpoint)
}

$postParams = @{ username=$user ; password =$password }
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-WebRequest "http://$mPowerHost/login.cgi" -Method GET -WebSession $session | Out-Null
Invoke-WebRequest "http://$mPowerHost/login.cgi" -Method Post -Body $postParams -WebSession $session | Out-Null
$cookie=$session.Cookies.GetCookies("http://$mPowerHost")[0].Value
$refjson = Invoke-WebRequest "http://$mPowerHost/sensors" -Method Get -WebSession $session | select Content | %{$_.Content} | ConvertFrom-Json
$sensorCount = $refjson.Sensors.Count

$l = [byte[]] @(,0) * 1024
$rc = New-Object System.ArraySegment[byte] -ArgumentList @(,$l)

$w = New-object System.Net.WebSockets.ClientWebSocket												
$w.Options.AddSubProtocol("mfi-protocol")
$c = New-Object System.Threading.CancellationToken

try { $t = $w.ConnectAsync("ws://$($mPowerHost):7681/?c=$cookie", $c) }
catch {$_}

	do { Start-Sleep -Milliseconds 100 }
	until ($t.IsCompleted)

$w.SendAsync([System.Text.Encoding]::ASCII.GetBytes('{ "time": 10} '), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $c) | Out-Null

$lines=""
$watts = @(0..( $sensorCount - 1 ) ) ; $watts | % { $watts[$_] = 0 }

While ( $true ) {	
	$t = $w.ReceiveAsync($rc, $c)

	do { Start-Sleep -Milliseconds 75 }
		until ( $t.IsCompleted )

	$json = ConvertFrom-Json ( ( ( [System.Text.Encoding]::ASCII.GetString($rc) -split "} ] }")[0], "} ] }" -join " " ) )

	$json.sensors | % {
		$mPowerHostname = $refjson.sensors[( $_.Port - 1 )].Label
		$sensor = $_
		$line=""

		$sensor | Get-Member -MemberType NoteProperty | ? { $_.Name -ne 'Label' } | % {
			$temp=$_

			switch ( $sensor.($temp.Name).GetType().Name ) {
				"String" { $lines +="mFi_$( $temp.Name ),hostname=""$( $mPowerHostname -replace " ", "\ " )"" value=""$( $sensor.($temp.Name) -replace " ", "\ " )"" `n" }
				default { $lines +="mFi_$( $temp.Name ),hostname=""$( $mPowerHostname -replace " ", "\ " )"" value=$( $sensor.($temp.Name) ) `n" }
			}		
		}

		$watts[($sensor.Port - 1)] = $sensor.power

		if ( $sensor.Port -eq $sensorCount ) {
			$lines += "mFi_totalpower,hostname=""$( $mPowerHost )"" value=$( ( $watts | Measure-Object -Sum ).Sum ) `n"
		}
	}

	$lines
	Send-UDP $lines
	Get-Date
	$lines=""
}
