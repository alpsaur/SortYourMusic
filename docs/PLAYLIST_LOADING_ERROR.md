# Playlist Loading Error & Session Persistence

## Problem Statement

After successfully implementing PKCE authentication, two issues remain:

### Issue 1: No Session Persistence
- User logs in successfully
- Playlists are displayed
- **Refreshing the page requires logging in again**
- Token is not persisted between page loads

### Issue 2: Playlist Loading Fails
- Clicking on a playlist results in: `Error while loading playlist: error`

## Current Status

- ✅ PKCE authentication works
- ✅ User can log in via Spotify
- ✅ Playlists are listed on first load
- ❌ Refreshing page loses session
- ❌ Clicking a playlist fails to load tracks

---

## Fix Plan: Issue 1 - Session Persistence

### Root Cause

The access token is stored only in the JavaScript variable `accessToken`. When the page refreshes, this variable is lost.

### Solution

Store the token in `localStorage` and check for it on page load.

**Changes needed:**

1. **After successful token exchange** - Save token to localStorage:
```javascript
localStorage.setItem('spotify_access_token', token);
```

2. **On page load** - Check for existing token:
```javascript
var storedToken = localStorage.getItem('spotify_access_token');
if (storedToken) {
    accessToken = storedToken;
    // load playlists...
}
```

3. **Handle token expiration** - Spotify tokens expire after 1 hour. Options:
   - Store expiration time, check on load
   - Catch 401 errors and prompt re-login
   - Use refresh tokens (more complex)

### Implementation

Add to initialization logic:
```javascript
} else if (localStorage.getItem('spotify_access_token')) {
    // Restore session from localStorage
    accessToken = localStorage.getItem('spotify_access_token');
    $(".worker").hide();
    fetchCurrentUserProfile(function(user) {
        if (user) {
            curUserID = user.id;
            $("#who").text(user.id);
            loadPlaylists(user.id);
        } else {
            // Token expired or invalid - clear and show login
            localStorage.removeItem('spotify_access_token');
            $("#go").show();
            $("#go").on('click', function() {
                authorizeUser();
            });
        }
    });
}
```

---

## Issue 2: Playlist Loading - ROOT CAUSE FOUND

### The Error

```
GET https://api.spotify.com/v1/audio-features?ids=... 403 (Forbidden)
```

### Root Cause: Spotify Deprecated Audio Features API

**Spotify deprecated the `/v1/audio-features` endpoint for new apps after November 27, 2024.**

From [Spotify Community](https://community.spotify.com/t5/Spotify-for-Developers/403-Forbidden-on-v1-audio-features-using-both-user-and-client/td-p/7200198):
> "This endpoint is returning 403 because it is deprecated. Only apps that had a quota extension before November 27, 2024 can still use it."

Since your Spotify Developer app was created in **December 2024**, it cannot access:
- `/v1/audio-features` (BPM, energy, danceability, valence, etc.)
- `/v1/audio-analysis`

**This is NOT a scope or authentication issue - the endpoint is simply blocked for new apps.**

### Impact

The core functionality of SortYourMusic depends on audio features:
- ❌ BPM (tempo)
- ❌ Energy
- ❌ Danceability
- ❌ Loudness
- ❌ Valence
- ❌ Acousticness

### Options

| Option | Pros | Cons |
|--------|------|------|
| **A. Graceful degradation** | App still works for basic sorting (title, artist, popularity) | Loses main feature |
| **B. Use old app** | Full functionality | Need access to pre-Nov 2024 app credentials |
| **C. Third-party API** | Could restore functionality | Costs money, adds complexity |
| **D. Accept limitation** | No code changes | App is essentially broken |

### Recommended: Option A - Graceful Degradation

Modify the app to:
1. Catch the 403 error from audio-features
2. Continue loading playlist without audio data
3. Show basic columns (Title, Artist, Album, Popularity)
4. Disable BPM/Energy/Danceability columns or show "N/A"

---

## Previous Investigation (for reference)

### Step 1: Identify the Error Source

The error message "Error while loading playlist: error" comes from `fetchSinglePlaylist()` which calls `fetchPlaylistTracks()`.

Looking at the code:
```javascript
fetchPlaylistTracks(playlist)
.then(function() {
    saveState();
    enableSaveButtonWhenNeeded();
})
.catch(function(msg) {
    console.log('msg', msg);
    error("Error while loading playlist: " + msg);
});
```

The error is being caught but only shows "error" - need to identify what's failing.

### Step 2: Possible Causes

1. **API endpoint issue** - The Spotify API endpoint for fetching playlist tracks may have changed
2. **Token scope issue** - Missing required permissions (unlikely - we have `playlist-read-private`)
3. **CORS issue** - Cross-origin request being blocked
4. **API response format change** - Spotify changed their response structure
5. **Rate limiting** - Too many requests

### Step 3: Debug Approach

1. Check browser console (F12) for detailed error messages
2. Check Network tab for failed API requests
3. Look at the specific API call being made in `fetchPlaylistTracks()`

---

## Code Analysis

### fetchPlaylistTracks() function

Located around line 700+ in index.html. Key API call:

```javascript
var startUrl = "https://api.spotify.com/v1/users/" + playlist.owner.id +
    "/playlists/" + playlist.id + "/tracks?limit=50";
```

**Potential Issue:** This uses the old API format. Spotify's current API may prefer:
```
https://api.spotify.com/v1/playlists/{playlist_id}/tracks
```

### API Endpoints to Check

| Old Format | New Format |
|------------|------------|
| `/v1/users/{user_id}/playlists/{playlist_id}/tracks` | `/v1/playlists/{playlist_id}/tracks` |

---

## Code Analysis (Detailed)

The playlist loading involves 3 API calls in sequence:

```
1. GET /v1/users/{owner_id}/playlists/{playlist_id}/tracks
   → Returns track list

2. GET /v1/albums?ids={album_ids}
   → Returns album details (for release dates)

3. GET /v1/audio-features?ids={track_ids}
   → Returns BPM, energy, danceability, etc.
```

At line 735, these run in parallel:
```javascript
return Q.all([fetchAllAlbums(aids), fetchAudioFeatures(ids)]);
```

If **any** of these fail, the whole promise rejects with "error".

### Most Likely Culprit: Audio Features API

Spotify deprecated some Echo Nest APIs. The `/v1/audio-features` endpoint may have restrictions or require additional scopes.

**Current scopes:** `playlist-read-private playlist-modify-private playlist-modify-public`

**Potentially missing:** The audio-features endpoint might work, but let's verify.

---

## Next Steps

1. [ ] **Check browser console (F12)** - Look for the actual HTTP error (401, 403, 404?)
2. [ ] **Check Network tab** - Which API call is failing?
3. [ ] Test if it's a specific playlist or all playlists
4. [ ] Verify audio-features API still works with current token

---

## References

- Spotify Web API: https://developer.spotify.com/documentation/web-api
- Get Playlist Tracks: https://developer.spotify.com/documentation/web-api/reference/get-playlists-tracks
