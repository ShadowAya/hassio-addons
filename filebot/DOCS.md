# FileBot Organizer Add-on

This add-on watches a folder for new media files and runs FileBot CLI to rename and organize them.

> ⚠️ **Disclaimer**
> This add-on is a beta, I'm not an experienced hassio add-on developer. Feedback and PRs are welcomed!

## Features

- Watches for files via `inotifywait` or polling fallback
- Downloads FileBot jar at runtime into `/data/filebot.jar`
- Supports mounting local partitions like `/dev/sda1` to `/mnt/sda1`
- Supports `move`, `copy`, `hardlink`, and `symlink` actions
- Supports separate output roots for movies and TV shows
- Supports parsed path placeholders such as `<SHOWNAME>` and `<MOVIENAME>`
- Supports per-type path validation modes: `none`, `strict`, `create_last`

## Configuration

```yaml
watch_folder: /mnt/sda1/upload
movie_output_folder: /mnt/sda1/external_media/movies
show_output_folder: /mnt/sda1/external_media/shows/<SHOWNAME>
movie_path_validation: strict
show_path_validation: create_last
mounts:
  - /dev/sda1
movie_format: "{n} ({y})"
show_format: "{s00e00} - {t}"
database: TheTVDB
action: move
conflict: auto
poll_interval: 30
use_inotify: true
```

### Option Reference

- `watch_folder` (string): Source folder to watch for new files.
- `movie_output_folder` (string): Output path template for movie files.
- `show_output_folder` (string): Output path template for TV show files.
- `movie_path_validation` (enum): `none`, `strict`, `create_last`.
- `show_path_validation` (enum): `none`, `strict`, `create_last`.
- `mounts` (list): Devices or partition names to mount under `/mnt`, for example `/dev/sda1` or `sda1`.
- `movie_format` (string): FileBot format for movie files.
- `show_format` (string): FileBot format for TV show files.
- `database` (enum): `TheTVDB`, `TMDB`, `AniDB`, or `TheMovieDB`.
- `action` (enum): `move`, `copy`, `hardlink`, or `symlink`.
- `conflict` (enum): `auto`, `skip`, or `override`.
- `poll_interval` (int): Polling interval in seconds when polling mode is used.
- `use_inotify` (bool): If true, use inotify; otherwise force polling.

### Output Path Placeholders

You can use parsed placeholders inside `movie_output_folder` and `show_output_folder`:

- `<SHOWNAME>` or `<SHOW_NAME>`
- `<MOVIENAME>` or `<MOVIE_NAME>`
- `<TITLE>`
- `<YEAR>`
- `<MEDIA_TYPE>` or `<TYPE>`

Example:

```yaml
show_output_folder: /mnt/sda1/external_media/shows/<SHOWNAME>
```

For an episode matched to `The Last of Us`, this resolves to:

```text
/mnt/sda1/external_media/shows/The Last of Us
```

### Path Validation Modes

- `none`: Skip validation checks.
- `strict`: Output directory must already exist.
- `create_last`: Parent directory must already exist; the final folder is created if missing.

## Local Disk Mounting

If you use a USB disk attached directly to Home Assistant OS:

1. Add devices to `mounts`, for example `/dev/sda1`.
2. Set `watch_folder`, `movie_output_folder`, and `show_output_folder` to matching `/mnt/<partition>/...` paths.
3. The add-on mounts with `mount -t auto`.
4. On stop, the add-on attempts to unmount mounted partitions cleanly.

## Important License Note

FileBot is downloaded at startup and is not bundled in this image.
Review and comply with FileBot license terms before use:
https://www.filebot.net/forums/viewtopic.php?t=5

## Troubleshooting

- If inotify fails, the add-on automatically falls back to polling.
- Ensure chosen devices are mapped in the add-on config and physically present.
- Check add-on logs for mount or FileBot invocation errors.
