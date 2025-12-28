# Sort Your Music

Sort your Spotify playlists by BPM, energy, danceability, and more.

Originally from [sortyourmusic.playlistmachinery.com](http://sortyourmusic.playlistmachinery.com/) - this fork adds local Windows support and updated authentication.

## Features

- Sort playlists by Title, Artist, Release Date, Popularity, Length
- Sort by BPM, Energy, Danceability, Acousticness (via GetSongBPM)
- Artist separation - spread out songs by the same artist
- Random shuffle
- Save reordered playlists back to Spotify

## Quick Start (Windows)

1. Double-click `SortYourMusic.bat`
2. Browser opens automatically to `http://127.0.0.1:8000`
3. Click "Login with Spotify"
4. Select a playlist and sort!

Close the command window when done.

## Setup Your Own Instance

1. Create a [Spotify Developer App](https://developer.spotify.com/dashboard)
2. Add `http://127.0.0.1:8000/` as a Redirect URI
3. Copy your Client ID to `web/config.js`

## Credits

- Original app by [Paul Lamere](https://github.com/plamere/SortYourMusic)
- BPM data provided by [GetSongBPM](https://getsongbpm.com/)

## Note on Spotify API Changes

As of November 2024, Spotify deprecated the Audio Features API for new apps. This fork uses [GetSongBPM](https://getsongbpm.com/) as an alternative data source for BPM and audio features.
