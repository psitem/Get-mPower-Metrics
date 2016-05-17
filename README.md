# Get-mPower-Metrics
Script to retrieve metrics from Ubiquit mPower and send to InfluxDB. Script uses the WebSockets API, which puts much less load on the device than using the REST API.

Props to brianddk for writing the code that showed me how to use WebSockets from PowerShell.  https://github.com/brianddk/ripple-ps-websocket
