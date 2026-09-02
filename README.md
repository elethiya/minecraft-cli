# Minecraft CLI Launcher

A lightweight, terminal-based Minecraft Java Edition launcher for Linux with built-in version management, mod loader installers (**Fabric, NeoForge, Forge, Quilt**), custom **Authlib/Yggdrasil & Offline** authentication, **Offline Skins & Capes**, and per-instance configuration.

Built for terminal-centric Linux environments, this Bash utility automates version downloading, dependency resolution, asset management, and client execution without relying on resource-heavy Electron or graphical wrappers.

---

## Features

- **No Graphical Launcher Required:** Boots Minecraft Java Edition straight from your Linux terminal using native JVM calls.
- **Mod Loader Support & Built-in Installers:**
  - **Fabric Loader:** Automated installation and dependency resolution.
  - **NeoForge Loader:** Full support for modern NeoForge versions with native module-path (`-p`) and JVM argument expansion.
  - **Minecraft Forge:** Installer support for classic and modern Forge versions.
  - **Quilt Loader:** Seamless Quilt installer integration.
  - **Snapshots & Pre-releases:** Easy testing builds installation from Mojang manifests.
  - **Dynamic Badges in Version List:** Clearly labels installed versions as `(Vanilla)`, `(Fabric)`, `(NeoForge)`, `(Forge)`, `(Quilt)`, `(OptiFine)`, or `(Snapshot)`.
- **Offline Skins & Capes Manager (`[s]`):**
  - **Skin & Cape Management:** Configure custom `.png` image files or direct image URLs for offline player profiles.
  - **Custom Skin / Auth Server:** Attach custom Yggdrasil / authlib endpoints to offline sessions.
- **Custom Authlib / Yggdrasil Support:** Native integration with `authlib-injector` to authenticate against third-party servers (e.g. custom endpoints, Blessing Skin).
- **Session Auto-Refresh:** Automatically validates and refreshes session tokens before game launch.
- **Multi-Account Manager:** Save multiple user profiles (both Authlib and Offline) and switch between them effortlessly.
- **Built-in Fast Version Downloader:** Multi-threaded parallel asset downloads (`xargs -P 16`), library resolution, and Linux native extraction.
- **Per-Version Instance Isolation:** If a version folder contains its own `mods/` or `resourcepacks/` directory, the launcher automatically isolates the game directory to that specific version.
- **Flexible Game Directory:** Run Minecraft from the standard `~/.minecraft` path, an isolated directory inside `~/minecraft-cli/instances`, or any custom directory.
- **Interactive TUI Configuration:** Adjust maximum RAM (`-Xmx`), minimum RAM (`-Xms`), and JVM flags directly from the terminal.

---

## Requirements

Ensure you have the required CLI utilities and an appropriate Java runtime installed.

### Java Version Matrix

| Minecraft Version | Required Java Version |
| :--- | :--- |
| **1.20.5+** (including 1.21+) | Java 21+ |
| **1.17 – 1.20.4** | Java 17 |
| **1.16.5 and older** | Java 8 |

### Installing Dependencies

#### Debian / Ubuntu / Linux Mint / Pop!_OS
```bash
sudo apt update
sudo apt install -y openjdk-21-jdk curl jq unzip
```

#### Arch Linux / Manjaro
```bash
sudo pacman -Syu --needed jdk21-openjdk curl jq unzip
```

#### Fedora / RHEL
```bash
sudo dnf install -y java-21-openjdk curl jq unzip
```

---

## Installation

1. Clone the repository to your home directory:
   ```bash
   git clone https://github.com/elethiya/minecraft-cli.git ~/minecraft-cli
   cd ~/minecraft-cli
   ```

2. Make the launcher script executable:
   ```bash
   chmod +x launch.sh
   ```

> [!NOTE]
> The launcher defaults to operating from `~/minecraft-cli`. If cloned to a different path, ensure you update `CLI_DIR` in `launch.sh` or create a symlink.

---

## Quick Start

Launch the interactive interface:

```bash
./launch.sh
```

### Main Menu Overview

```text
==============================================
             MINECRAFT CLI LAUNCHER           
==============================================
  Game Path:  /home/username/.minecraft
  RAM:        -Xms2G / -Xmx4G
----------------------------------------------
Installed Game Versions:
  [1] 1.21.1                         (Vanilla)
  [2] fabric-loader-0.16.9-1.21.1    (Fabric)
  [3] neoforge-21.1.249              (NeoForge)
  [4] 1.20.1-forge-47.4.10           (Forge)

Commands & Tools:
  [i] Install Version / Mod Loader (Vanilla, Fabric, NeoForge, Forge, Quilt)
  [s] Offline Skins & Capes Manager
  [r] Configure Directory, RAM & JVM Flags
  [u] Manage Accounts (Authlib / Offline)
  [q] Quit
----------------------------------------------
```

---

## Version & Mod Loader Installation (`[i]`)

Select `[i]` from the main menu to open the installer:

1. **[1] Official Vanilla Releases:** Install official Minecraft releases (1.21.1, 1.20.4, 1.16.5, etc.).
2. **[2] Official Snapshots & Pre-releases:** Install upcoming testing builds and snapshots (e.g. `24w34a`).
3. **[3] Fabric Loader:** Select an installed or target Minecraft version. The script automatically installs Fabric Loader and configures inherited libraries.
4. **[4] NeoForge Loader:** Install modern NeoForge for Minecraft 1.20.2+ (e.g. 1.21.1, 1.20.4). Automatically fetches the matching release from Maven and runs client setup.
5. **[5] Minecraft Forge:** Install Forge for versions like 1.20.1, 1.19.2, 1.16.5, or 1.12.2 via Forge promotions metadata.
6. **[6] Quilt Loader:** Install the Quilt mod loader.
7. **[c] Custom Mojang Version ID:** Manually specify any version manifest ID.

---

## Offline Skins & Capes Manager (`[s]`)

Manage custom skins, capes, and custom authlib skin servers for offline profiles:

```text
==============================================
         OFFLINE SKINS & CAPES MANAGER        
==============================================
  Account:        my_username (Offline)
  Skin File:      /home/.../skins/my_username.png
  Cape File:      /home/.../capes/my_username.png
  Skin Server:    None
----------------------------------------------
  [1] Set Skin Image (.png file or image URL)
  [2] Set Cape Image (.png file or image URL)
  [3] Set Custom Authlib / Skin Server URL
  [4] Clear Skin & Cape
  [b] Back to Main Menu
----------------------------------------------
```

### Skin Options Explained

- **Option [1] Set Skin Image:**
  - Provide a path to a local `.png` file (`/home/user/skin.png`).
  - Or enter a direct image URL (`https://.../skin.png`).
- **Option [2] Set Cape Image:**
  - Set a local cape PNG file or direct image URL.
- **Option [3] Set Custom Authlib / Skin Server URL:**
  - Connect your offline profile to a custom Yggdrasil / skin API server (e.g. `https://elethiya.com/api/yggdrasil` or a custom endpoint).
  - When configured, `-javaagent:$AUTHLIB_JAR=<server_url>` is attached at startup.
- **Option [4] Clear Skin & Cape:**
  - Resets custom skin and cape textures for the profile.

---

## Configuration & Storage Layout

```text
~/minecraft-cli/
├── launch.sh              # Main executable launcher script
├── settings.json          # RAM limits, JVM flags, and game directory settings
├── authlib/
│   ├── authlib-injector.jar # Auto-downloaded agent for custom auth & skin servers
│   └── accounts.json      # Stored session profiles and tokens
├── skins/                 # Cached local offline skin images
├── capes/                 # Cached local offline cape images
└── instances/             # Optional isolated game directory
```

### `settings.json` Example

```json
{
  "game_dir": "/home/username/.minecraft",
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M --enable-native-access=ALL-UNNAMED"
}
```

---

## Modding & Directory Isolation

- **Per-Version Isolation:**
  If `<game_dir>/versions/<version-name>/mods/` or `resourcepacks/` exists, `minecraft-cli` will automatically isolate the game directory to that version's folder.
- **Global Mod Directory:**
  Otherwise, mods are loaded from `<game_dir>/mods/` and shaderpacks from `<game_dir>/shaderpacks/`.

---

## Troubleshooting

- **`java.lang.UnsupportedClassVersionError`**:
  You are running an older Java version than required by your Minecraft version. Install and select Java 21 for Minecraft 1.20.5+ (`sudo update-alternatives --config java`).
- **Java 21 Unsafe/Native Access Warnings**:
  Add `--enable-native-access=ALL-UNNAMED` to `jvm_args` in `settings.json` (configured by default).
- **Missing CLI tools**:
  Ensure `jq`, `curl`, and `unzip` are installed. The installer relies on `jq` for parsing JSON manifests.
- **Custom Authlib Endpoint Issues**:
  Verify your server URL. The server must provide standard Yggdrasil API endpoints (`/authserver/authenticate`, `/authserver/validate`, `/authserver/refresh`).

---

## License

This project is licensed under the MIT License.
