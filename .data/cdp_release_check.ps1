param(
    [int]$Port = 9224,
    [string]$Url = 'https://mushukistan.uz/register',
    [string]$ScreenshotPath = 'D:\Data science\mushukent\.data\cdp-release-check.png'
)

$ErrorActionPreference = 'Stop'
$targets = @(Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list")
$target = @($targets | Where-Object { $_.type -eq 'page' })[0]
if ($null -eq $target) {
    throw 'No page target is available from Chrome DevTools.'
}

$socket = New-Object System.Net.WebSockets.ClientWebSocket
$socket.Options.Proxy = [Net.GlobalProxySelection]::GetEmptyWebProxy()
$webSocketUrl = [string]$target.webSocketDebuggerUrl
$socket.ConnectAsync(
    [Uri]$webSocketUrl,
    [Threading.CancellationToken]::None
).GetAwaiter().GetResult()

$script:nextId = 0
$script:exceptions = New-Object System.Collections.Generic.List[string]
$script:logErrors = New-Object System.Collections.Generic.List[string]
$script:failedRequests = New-Object System.Collections.Generic.List[string]
$script:httpErrors = New-Object System.Collections.Generic.List[string]
$script:googleResponses = New-Object System.Collections.Generic.List[string]

function Send-CdpCommand {
    param(
        [string]$Method,
        [hashtable]$Params = @{}
    )

    $script:nextId += 1
    $payload = @{
        id = $script:nextId
        method = $Method
        params = $Params
    } | ConvertTo-Json -Compress -Depth 12
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $segment = New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
    $socket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()
    return $script:nextId
}

function Record-CdpEvent {
    param($Message)

    switch ($Message.method) {
        'Runtime.exceptionThrown' {
            $script:exceptions.Add(
                [string]$Message.params.exceptionDetails.text
            )
        }
        'Log.entryAdded' {
            if ($Message.params.entry.level -eq 'error') {
                $script:logErrors.Add([string]$Message.params.entry.text)
            }
        }
        'Network.loadingFailed' {
            $script:failedRequests.Add(
                "$($Message.params.errorText) [$($Message.params.type)]"
            )
        }
        'Network.responseReceived' {
            $response = $Message.params.response
            $uri = [Uri]$response.url
            $summary = "$([int]$response.status) $($uri.Host)$($uri.AbsolutePath)"
            if ([int]$response.status -ge 400) {
                $script:httpErrors.Add($summary)
            }
            if ($uri.Host -like '*.google.com' -or
                $uri.Host -like '*.googleusercontent.com' -or
                $uri.Host -like '*.gstatic.com') {
                $script:googleResponses.Add($summary)
            }
        }
    }
}

function Receive-CdpResponse {
    param(
        [int]$CommandId,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $buffer = New-Object byte[] 1048576
        $builder = New-Object Text.StringBuilder
        do {
            $remaining = [int][Math]::Max(
                1,
                ($deadline - [DateTime]::UtcNow).TotalMilliseconds
            )
            $cancellation = New-Object Threading.CancellationTokenSource
            $cancellation.CancelAfter($remaining)
            try {
                $segment = New-Object ArraySegment[byte] -ArgumentList @(,$buffer)
                $result = $socket.ReceiveAsync(
                    $segment,
                    $cancellation.Token
                ).GetAwaiter().GetResult()
            } finally {
                $cancellation.Dispose()
            }
            if ($result.MessageType -eq
                [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'Chrome DevTools WebSocket closed unexpectedly.'
            }
            [void]$builder.Append(
                [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            )
        } while (-not $result.EndOfMessage)

        $message = $builder.ToString() | ConvertFrom-Json
        Record-CdpEvent $message
        if ($message.id -eq $CommandId) {
            if ($null -ne $message.error) {
                throw "CDP command failed: $($message.error.message)"
            }
            return $message.result
        }
    }
    throw "Timed out waiting for CDP command $CommandId."
}

foreach ($domain in 'Page', 'Runtime', 'Network', 'Log') {
    $id = Send-CdpCommand -Method "$domain.enable"
    [void](Receive-CdpResponse -CommandId $id)
}

$id = Send-CdpCommand -Method 'Page.navigate' -Params @{ url = $Url }
[void](Receive-CdpResponse -CommandId $id)
Start-Sleep -Seconds 20

$expression = @'
JSON.stringify({
  title: document.title,
  href: location.href,
  readyState: document.readyState,
  bodyText: document.body.innerText,
  iframeCount: document.querySelectorAll('iframe').length,
  iframes: Array.from(document.querySelectorAll('iframe')).map((node) => ({
    host: (() => { try { return new URL(node.src).host; } catch (_) { return ''; } })(),
    title: node.title,
    name: node.name
  })),
  googleElementCount: document.querySelectorAll('[aria-label*="Google"], [title*="Google"], [class*="google" i], [id*="google" i]').length
})
'@
$id = Send-CdpCommand -Method 'Runtime.evaluate' -Params @{
    expression = $expression
    returnByValue = $true
}
$evaluation = Receive-CdpResponse -CommandId $id
$page = $evaluation.result.value | ConvertFrom-Json

$id = Send-CdpCommand -Method 'Page.captureScreenshot' -Params @{
    format = 'png'
    captureBeyondViewport = $true
}
$screenshot = Receive-CdpResponse -CommandId $id
[IO.File]::WriteAllBytes(
    $ScreenshotPath,
    [Convert]::FromBase64String($screenshot.data)
)

$result = [ordered]@{
    title = $page.title
    href = $page.href
    readyState = $page.readyState
    bodyText = $page.bodyText
    iframeCount = $page.iframeCount
    iframes = $page.iframes
    googleElementCount = $page.googleElementCount
    runtimeExceptions = @($script:exceptions | Select-Object -Unique)
    consoleErrors = @($script:logErrors | Select-Object -Unique)
    failedRequests = @($script:failedRequests | Select-Object -Unique)
    httpErrors = @($script:httpErrors | Select-Object -Unique)
    googleResponses = @($script:googleResponses | Select-Object -Unique)
    screenshot = $ScreenshotPath
}
$result | ConvertTo-Json -Depth 8

$socket.Dispose()
