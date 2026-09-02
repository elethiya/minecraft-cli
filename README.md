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
- **Offline Skins & Capes via Mod:** Automatically provisions the universal `CustomSkinLoader` mod into your instance `mods/` directory, loading local `.png` skins and capes in-game with zero Python scripts and zero external services.
- **Per-Version Instance Isolation:** Each game version runs from its own clean, isolated directory (`~/minecraft-cli/instances/<version>/`) so worlds, settings, and mods never conflict between versions.
- **Convenient Top-Level Folders:** Unhidden `~/minecraft-cli/mods` and `~/minecraft-cli/resourcepacks` folders symlink directly to your active instance for effortless drag-and-drop.
- **Mods & Resource Packs Manager (`[m]`):** View installed mods and quickly launch your system file manager to drop in new mods.
- **Custom Authlib / Yggdrasil Support:** Native integration with `authlib-injector` to authenticate against third-party servers.
- **Session Auto-Refresh:** Automatically validates and refreshes session tokens before game launch.
- **Multi-Account Manager:** Save multiple user profiles (both Authlib and Offline) and switch between them effortlessly.
- **Built-in Fast Version Downloader:** Multi-threaded parallel asset downloads (`xargs -P 16`), library resolution, and Linux native extraction.
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

### First-Time Run Setup
On your first launch, the launcher will ask you where you want to store your game files:
```text
==============================================
         WELCOME TO MINECRAFT LAUNCHER        
==============================================
  Please select the directory where you want to
  install and store your Minecraft game files:

  [1] Standard ~/.minecraft
      (Default location: ~/.minecraft)

  [2] Inside Launcher Directory
      (Location: ~/minecraft-cli/.minecraft)

  [3] Custom Path
      (Specify any folder on your system)
----------------------------------------------
Select an option [1-3, default: 1]: 
```
Your choice is remembered in `settings.json`. You can reconfigure this at any time using option `[r]`.

### Main Menu Overview

```text
==============================================
             MINECRAFT CLI LAUNCHER           
==============================================
  Game Path:      /home/username/.minecraft
  Versions Dir:   /home/username/.minecraft/versions
  Active Mods:    ~/minecraft-cli/mods
  RAM:            -Xms2G / -Xmx4G
----------------------------------------------
Installed Game Versions:
  [1] 1.21.11                        (Vanilla)
  [2] 26.2                           (Vanilla)
  [3] fabric-loader-0.19.3-1.21.11   (Fabric)
  [4] fabric-loader-0.19.3-26.2      (Fabric)

Commands & Tools:
  [i] Install Version / Mod Loader (Vanilla, Fabric, NeoForge, Forge, Quilt)
  [m] Manage Mods & Resource Packs
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

### How Offline Skins & Capes Work
Offline player skins and capes are loaded directly into the game using the universal **CustomSkinLoader** mod (`tools/CustomSkinLoader_Universal-15.0.1.jar`).
- **No Python scripts** running in the background.
- **No third-party network services** (like `ely.by`) — textures are loaded from local folders.
- Automatically configured for any modded loader (Fabric, Forge, NeoForge, Quilt).

---

## Configuration & Storage Layout

```text
~/minecraft-cli/
├── launch.sh              # Main executable launcher script
├── settings.json          # RAM limits, game directory and JVM configuration
├── versions/              # Direct shortcuts to every installed version
│   ├── fabric-loader-0.19.5-1.21/
│   │   ├── mods/          # Shortcut to version's mods folder
│   │   ├── resourcepacks/ # Shortcut to version's resourcepacks
│   │   ├── shaderpacks/   # Shortcut to version's shaderpacks
│   │   └── saves/         # Shortcut to version's saves
│   └── 1.21/
│       ├── mods/
│       ├── resourcepacks/
│       └── shaderpacks/
├── mods/                  # Quick shortcut symlink to active version's mods directory
├── resourcepacks/         # Quick shortcut symlink to active version's resourcepacks
├── shaderpacks/           # Quick shortcut symlink to active version's shaderpacks
├── .minecraft/
│   └── versions/
│       ├── fabric-loader-0.19.5-1.21/
│       │   ├── mods/            # Dedicated mods folder for this version
│       │   ├── resourcepacks/   # Dedicated resourcepacks for this version
│       │   ├── shaderpacks/     # Dedicated shaderpacks for this version
│       │   ├── saves/           # Singleplayer worlds for this version
│       │   ├── CustomSkinLoader/# Offline skins & capes cache for this version
│       │   ├── fabric-loader-0.19.5-1.21.jar
│       │   └── fabric-loader-0.19.5-1.21.json
├── tools/
│   └── CustomSkinLoader_Universal-15.0.1.jar # Universal mod for offline skins
├── authlib/
│   ├── authlib-injector.jar # Agent for third-party Yggdrasil authentication
│   └── accounts.json      # Stored session profiles and offline accounts
├── skins/                 # Stored player skin PNGs
└── capes/                 # Stored player cape PNGs
```

### `settings.json` Example

```json
{
  "game_dir": "/home/username/minecraft-cli/.minecraft",
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M --enable-native-access=ALL-UNNAMED"
}
```

---

## Modding & Directory Isolation

- **Direct In-Version Isolation:**
  Every version has its own dedicated `mods/`, `resourcepacks/`, `shaderpacks/`, and `saves/` folders directly inside `.minecraft/versions/<version>/`.
- **Active Version Symlinks:**
  The root `~/minecraft-cli/mods` and `~/minecraft-cli/resourcepacks` folders point directly to your selected version's folder so you can easily access them from your file manager or terminal.
- **Manage Mods in Launcher (`[m]`):**
  Select `[m]` in the main launcher menu to review installed mods for each version and open any version's `mods/` folder in your system file manager.

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
