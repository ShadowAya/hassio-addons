# FileBot Home Assistant Add-on Repository

This repository contains a Home Assistant community add-on that watches for new media files and organizes them with FileBot.

## Add-ons

- [filebot](./filebot) - Watches a folder, renames media using FileBot CLI, and moves/copies/links files to an output folder.

## Quick Start

1. Publish this repository to GitHub.
2. Update `repository.yaml` with your real GitHub URL.
3. In Home Assistant, go to **Settings -> Add-ons -> Add-on Store -> Repositories**.
4. Add your repository URL.
5. Install the **FileBot Organizer** add-on.

## Notes

- FileBot is downloaded at container startup into `/data/filebot.jar`.
- The FileBot jar is intentionally not stored in this repository or baked into the image.
- Review FileBot license terms before use: https://www.filebot.net/forums/viewtopic.php?t=5
