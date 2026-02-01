# Changelog

## Unreleased

* Use max part target duration of all renditions to calculate part hold back.
* Add ci GitHub action 
* Bump ex_m3u8 dependency.
* Improve fragments (moof/mdat) generation in low latency HLS.
* Set correctly independent flag in `EXT-X-PART`.

## v0.5.0 - 2025-12-24

* Add server control option to writer.
* Add rendition reports to media playlists for LL-HLS.

## v0.4.0 - 2025-12-14

* Add support for AV1 codec.

## v0.3.0 - 2025-12-05

* Add discontinuity.

## v0.2.0 - 2025-12-03

* Add low latency HLS support.
* Delete storage behavior and store segments/playlists directly to the filesystem.
* Generate #EXT-X-PROGRAM-DATE-TIME for live playlists.
* Add options to provide segment and part duration.
* Add callbacks for segment and part creation.
* Bump mpeg_ts dependency
