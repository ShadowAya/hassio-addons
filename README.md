# FileBot Home Assistant Add-on Repository

This repository contains a Home Assistant community add-on that watches for new media files and organizes them with FileBot.

## Add-ons

- [filebot](./filebot) - Watches a folder, renames media using FileBot CLI, and moves/copies/links files to an output folder.

## Quick Start

1. In Home Assistant, go to **Settings -> Add-ons -> Add-on Store -> Repositories**.
2. Add this repository URL.
3. Install the **FileBot** add-on.

## Notes

- FileBot is downloaded at container startup into `/data/filebot/`.
- The FileBot bundle is intentionally not stored in this repository or baked into the image.
- Review FileBot license terms before use: https://www.filebot.net/forums/viewtopic.php?t=5
