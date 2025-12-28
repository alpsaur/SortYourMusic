# PKCE Implementation Plan for SortYourMusic

## Problem Statement

Spotify deprecated the Implicit Grant OAuth flow for apps created after April 9, 2025. The current app uses `response_type=token` (implicit grant), which is now rejected by Spotify with an authorization error.

## Solution

Implement **Authorization Code flow with PKCE** (Proof Key for Code Exchange). This is Spotify's recommended flow for browser-based applications.

**Reference:** https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow

---

## Current Flow (Broken)

```
1. User clicks "Login with Spotify"
2. authorizeUser() redirects to:
   https://accounts.spotify.com/authorize?
     client_id=XXX
     &response_type=token          <-- BLOCKED
     &scope=...
     &redirect_uri=http://127.0.0.1:8000/

3. Spotify redirects back with token in hash:
   http://127.0.0.1:8000/#access_token=...

4. parseArgs() extracts token from location.hash
5. App uses token
```

## New Flow (PKCE)

```
1. User clicks "Login with Spotify"

2. Generate PKCE values:
   - code_verifier: random 64-character string
   - code_challenge: base64url(sha256(code_verifier))
   - Store code_verifier in localStorage

3. authorizeUser() redirects to:
   https://accounts.spotify.com/authorize?
     client_id=XXX
     &response_type=code            <-- NEW
     &scope=...
     &redirect_uri=http://127.0.0.1:8000/
     &code_challenge_method=S256    <-- NEW
     &code_challenge=...            <-- NEW

4. User authorizes on Spotify

5. Spotify redirects back with code in query string:
   http://127.0.0.1:8000/?code=...   <-- Query string, not hash

6. Exchange code for token (POST to Spotify):
   POST https://accounts.spotify.com/api/token
   Body:
     grant_type=authorization_code
     code=...
     redirect_uri=http://127.0.0.1:8000/
     client_id=XXX
     code_verifier=...              <-- From localStorage

7. Receive access_token in JSON response

8. App uses token (same as before)
```

---

## Implementation Steps

### Step 1: Add PKCE Helper Functions

Add **before** the existing `authorizeUser()` function. Based on Spotify's official documentation.

**Spotify Requirements:**
- Code verifier: 43-128 characters, high-entropy random string
- Allowed characters: letters, digits, underscores, periods, hyphens, tildes
- Code challenge: base64url(sha256(code_verifier))

```javascript
// PKCE Helpers (from Spotify docs, adapted for ES5 compatibility)
function generateCodeVerifier() {
    // Spotify: "cryptographic random string between 43-128 characters"
    var possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    var array = new Uint8Array(64);
    window.crypto.getRandomValues(array);
    var verifier = '';
    for (var i = 0; i < array.length; i++) {
        verifier += possible.charAt(array[i] % possible.length);
    }
    return verifier;
}

function sha256(plain) {
    var encoder = new TextEncoder();
    var data = encoder.encode(plain);
    return window.crypto.subtle.digest('SHA-256', data);
}

function base64urlencode(buffer) {
    var bytes = new Uint8Array(buffer);
    var binary = '';
    for (var i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    // Spotify: base64 with URL-safe characters, no padding
    return btoa(binary)
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}
```

**Note:** Spotify's example uses `replace(/=/g, '')` first, then the other replacements. Order matters for consistency.

### Step 2: Modify authorizeUser()

Replace the existing function. Use Promise `.then()` instead of async/await for jQuery compatibility.

**Spotify Required Parameters:**
| Parameter | Value |
|-----------|-------|
| `client_id` | App's Client ID |
| `response_type` | `code` (not `token`) |
| `redirect_uri` | Must exactly match registered URI |
| `code_challenge_method` | `S256` |
| `code_challenge` | Generated challenge |
| `scope` | Space-separated permissions |

```javascript
function authorizeUser() {
    var codeVerifier = generateCodeVerifier();
    localStorage.setItem('spotify_code_verifier', codeVerifier);

    sha256(codeVerifier).then(function(hashed) {
        var codeChallenge = base64urlencode(hashed);
        var scopes = 'playlist-read-private playlist-modify-private playlist-modify-public';

        var url = 'https://accounts.spotify.com/authorize' +
            '?client_id=' + SPOTIFY_CLIENT_ID +
            '&response_type=code' +
            '&scope=' + encodeURIComponent(scopes) +
            '&redirect_uri=' + encodeURIComponent(SPOTIFY_REDIRECT_URI) +
            '&code_challenge_method=S256' +
            '&code_challenge=' + codeChallenge;

        window.location.href = url;
    });
}
```

**Key change:** `response_type=code` instead of `response_type=token`

### Step 3: Add Token Exchange Function

Add new function to exchange authorization code for access token.

**Spotify Token Endpoint:** `POST https://accounts.spotify.com/api/token`

**Required Parameters (form-urlencoded):**
| Parameter | Value |
|-----------|-------|
| `grant_type` | `authorization_code` |
| `code` | Authorization code from redirect |
| `redirect_uri` | Must match original request exactly |
| `client_id` | App's Client ID |
| `code_verifier` | The verifier stored earlier |

**Required Header:** `Content-Type: application/x-www-form-urlencoded`

```javascript
function exchangeCodeForToken(code, callback) {
    var codeVerifier = localStorage.getItem('spotify_code_verifier');

    if (!codeVerifier) {
        callback('No code verifier found - please try logging in again', null);
        return;
    }

    $.ajax({
        url: 'https://accounts.spotify.com/api/token',
        type: 'POST',
        contentType: 'application/x-www-form-urlencoded',
        data: {
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: SPOTIFY_REDIRECT_URI,
            client_id: SPOTIFY_CLIENT_ID,
            code_verifier: codeVerifier
        },
        success: function(response) {
            localStorage.removeItem('spotify_code_verifier');
            callback(null, response.access_token);
        },
        error: function(xhr) {
            var errorMsg = 'Token exchange failed';
            try {
                var errData = JSON.parse(xhr.responseText);
                errorMsg += ': ' + (errData.error_description || errData.error);
            } catch(e) {
                errorMsg += ': ' + xhr.status;
            }
            callback(errorMsg, null);
        }
    });
}
```

**Note:** Added explicit `contentType` header and better error handling. Also validates that code_verifier exists before attempting exchange.

### Step 4: Modify parseArgs()

**Why:** Spotify's PKCE flow returns the code in the **query string** (`?code=...`), not the hash fragment. The original function only parsed the hash.

```javascript
function parseArgs() {
    var args = {};

    // Check query string first (PKCE flow returns ?code=...)
    var queryString = window.location.search.substring(1);
    if (queryString) {
        var queryPairs = queryString.split('&');
        for (var i = 0; i < queryPairs.length; i++) {
            var pair = queryPairs[i].split('=');
            if (pair[0]) {
                args[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1] || '');
            }
        }
    }

    // Also check hash (legacy implicit flow - backwards compatibility)
    var hash = location.hash.replace(/#/g, '');
    var all = hash.split('&');
    _.each(all, function(keyvalue) {
        var kv = keyvalue.split('=');
        var key = kv[0];
        var val = kv[1];
        if (key) args[key] = val;
    });

    return args;
}
```

**Change:** Added query string parsing before hash parsing. Query string takes precedence.

### Step 5: Modify Document Ready Initialization

Update the initialization logic to handle the authorization code. This is the **largest change** - replacing the conditional block inside `$(document).ready()`.

**Original logic:**
```
if error → show error, show login button
else if access_token → use token, load playlists
else → show login button
```

**New logic:**
```
if error → show error, show login button
else if code → exchange for token, then load playlists (NEW)
else if access_token → use token, load playlists (legacy)
else → show login button
```

```javascript
// In $(document).ready(), REPLACE the entire if/else block for args handling:

if ('error' in args) {
    error("Authorization error: " + (args.error_description || args.error));
    $("#go").show();
    $("#go").on('click', function() {
        authorizeUser();
    });
} else if ('code' in args) {
    // NEW: PKCE flow - exchange code for token
    info("Logging in...");
    $(".worker").hide();

    exchangeCodeForToken(args['code'], function(err, token) {
        if (err) {
            error(err);
            $("#go").show();
            $("#go").on('click', function() {
                authorizeUser();
            });
        } else {
            // Clear URL params and proceed
            window.history.replaceState({}, document.title, window.location.pathname);
            accessToken = token;

            fetchCurrentUserProfile(function(user) {
                if (user) {
                    curUserID = user.id;
                    $("#who").text(user.id);
                    loadPlaylists(user.id);
                } else {
                    error("Trouble getting the user profile");
                }
            });
        }
    });
} else if ('access_token' in args) {
    // LEGACY: Implicit flow (keep for backwards compatibility)
    accessToken = args['access_token'];
    $(".worker").hide();
    fetchCurrentUserProfile(function(user) {
        if (user) {
            curUserID = user.id;
            $("#who").text(user.id);
            loadPlaylists(user.id);
        } else {
            error("Trouble getting the user profile");
        }
    });
} else {
    // No auth params - show login button
    $("#go").show();
    $("#go").on('click', function() {
        authorizeUser();
    });
}
```

**Key points:**
- Uses callback pattern (not async/await) for jQuery compatibility
- `exchangeCodeForToken()` handles the POST to Spotify's token endpoint
- Clears URL after successful auth so refresh doesn't re-trigger exchange
- Keeps legacy `access_token` handling for backwards compatibility

---

## Key Differences from Previous Attempt

| Issue | Previous Approach | Fixed Approach |
|-------|------------------|----------------|
| async in $(document).ready() | Used `async function()` | Use callbacks/Promises |
| ES6+ syntax | Used `for...of`, arrow functions | Use traditional `for` loops, `function()` |
| Error handling | Errors silent | Explicit error callbacks |
| Testing | All changes at once | Step-by-step verification |

---

## Testing Plan

1. After Step 1: Verify page still loads (no JS errors)
2. After Step 2: Click login, verify redirect to Spotify with `response_type=code`
3. After Step 3-5: Complete login flow, verify token received and playlists load

---

## Files to Modify

- `web/index.html` - All JavaScript changes (inline script)
- `web/config.js` - Already configured correctly

## Rollback

If issues occur:
```bash
git checkout web/index.html
```
