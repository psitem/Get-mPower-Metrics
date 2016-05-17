# Get-mPower-Metrics
Script to retrieve metrics from Ubiquit mPower and send to InfluxDB. Script uses the WebSockets API, which puts much less load on the device than using the REST API.

Right now this script is barely tested and has no error handling. Don't complain to me if it kicks your dog or runs off with your spouse.

Props to brianddk for writing the code that showed me how to use WebSockets from PowerShell.  https://github.com/brianddk/ripple-ps-websocket

# Usage

     .\Get-mPower-metrics.ps1 -user "username" -password "password" -mPowerHost "10.0.0.1" -influxdbuser "influxdb user" -influxdbpassword "influxdb password" -influxdbname "influx-database" -influxdbhost "localhost" -influxdbport 8086


![](http://i.imgur.com/1TT14yJ.png)
