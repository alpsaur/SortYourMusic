$port = 8000
$webRoot = Join-Path $PSScriptRoot "web"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()

Write-Host "Server running at http://127.0.0.1:$port/"
Write-Host "Press Ctrl+C or close this window to stop."
Write-Host ""

$mimeTypes = @{
    ".html" = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".ttf"  = "font/ttf"
}

# Read API key from config.js
$configPath = Join-Path $webRoot "config.js"
$configContent = Get-Content $configPath -Raw
if ($configContent -match "GETSONGBPM_API_KEY\s*=\s*'([^']+)'") {
    $apiKey = $matches[1]
    Write-Host "GetSongBPM API key loaded"
} else {
    Write-Host "Warning: GetSongBPM API key not found in config.js"
    $apiKey = ""
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $localPath = $request.Url.LocalPath

        # Proxy for GetSongBPM API (to avoid CORS issues)
        if ($localPath -eq "/api/bpm/search") {
            # Search for song by artist and title
            $query = $request.Url.Query
            $params = [System.Web.HttpUtility]::ParseQueryString($query)
            $artist = $params["artist"]
            $title = $params["title"]

            if ($artist -and $title -and $apiKey) {
                try {
                    $searchQuery = [System.Uri]::EscapeDataString("$artist $title")
                    $apiUrl = "https://api.getsong.co/search/?api_key=$apiKey&type=song&lookup=$searchQuery"

                    $webClient = New-Object System.Net.WebClient
                    $webClient.Encoding = [System.Text.Encoding]::UTF8
                    $apiResponse = $webClient.DownloadString($apiUrl)

                    $response.ContentType = "application/json"
                    $response.Headers.Add("Access-Control-Allow-Origin", "*")
                    $content = [System.Text.Encoding]::UTF8.GetBytes($apiResponse)
                    $response.ContentLength64 = $content.Length
                    $response.OutputStream.Write($content, 0, $content.Length)
                    Write-Host "API /api/bpm/search?artist=$artist&title=$title - 200"
                } catch {
                    $response.StatusCode = 500
                    $errMsg = @{ error = $_.Exception.Message } | ConvertTo-Json
                    $content = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $content.Length
                    $response.OutputStream.Write($content, 0, $content.Length)
                    Write-Host "API /api/bpm/search - 500: $($_.Exception.Message)"
                }
            } else {
                $response.StatusCode = 400
                $errMsg = @{ error = "Missing artist, title, or API key" } | ConvertTo-Json
                $content = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $content.Length
                $response.OutputStream.Write($content, 0, $content.Length)
                Write-Host "API /api/bpm/search - 400: Missing params"
            }
            $response.Close()
            continue
        }

        # Serve static files
        if ($localPath -eq "/") { $localPath = "/index.html" }

        $filePath = Join-Path $webRoot $localPath.TrimStart("/")

        if (Test-Path $filePath -PathType Leaf) {
            $content = [System.IO.File]::ReadAllBytes($filePath)
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $response.ContentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
            $response.ContentLength64 = $content.Length
            $response.OutputStream.Write($content, 0, $content.Length)
        } else {
            $response.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
            $response.OutputStream.Write($msg, 0, $msg.Length)
        }

        $response.Close()
        Write-Host "$($request.HttpMethod) $($request.Url.LocalPath) - $($response.StatusCode)"
    }
} finally {
    $listener.Stop()
}
