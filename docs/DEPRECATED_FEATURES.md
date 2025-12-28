# Deprecated Features - Audio Analysis

## Status: Graceful Degradation Implemented

As of November 27, 2024, Spotify deprecated the Audio Features API for new apps.

## Affected Features

The following sorting columns will show empty/N/A values:

| Column | API Field | Description |
|--------|-----------|-------------|
| **BPM** | `tempo` | Beats per minute |
| **Energy** | `energy` | 0-100, how energetic |
| **Dance** | `danceability` | 0-100, how danceable |
| **Loud** | `loudness` | dB level |
| **Valence** | `valence` | 0-100, musical positiveness |
| **Acoustic** | `acousticness` | 0-100, how acoustic |

## Still Working

| Column | Source | Description |
|--------|--------|-------------|
| **#** | Track order | Original position |
| **Title** | Track metadata | Song name |
| **Artist** | Track metadata | Artist name |
| **Release** | Album metadata | Release date |
| **Length** | Track metadata | Duration |
| **Pop.** | Track metadata | Popularity score |
| **A.Sep** | Calculated | Artist separation |
| **Rnd** | Generated | Random shuffle |

## Potential Alternatives to Restore Features

### Option 1: Third-Party APIs
- **GetSongBPM** - https://getsongbpm.com/api
- **Musicstax** - Has BPM data
- **AcousticBrainz** (archived but data available)

### Option 2: Use Legacy Spotify App
If you have access to a Spotify Developer app created before November 27, 2024, use those credentials instead.

### Option 3: Community Databases
- Tunebat.com has BPM/key data
- Could potentially scrape or use their API if available

## Implementation Notes

The app now catches the 403 error from `/v1/audio-features` and continues loading playlists with empty audio data. Tracks will display but BPM/Energy/etc columns will be blank.
