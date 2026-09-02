# Minecraft CLI Launcher

A lightweight, terminal-based Minecraft Java Edition launcher for Linux with built-in version management, custom Authlib/Yggdrasil & Offline authentication, Fabric loader support, and per-instance configuration.

Built for terminal-centric Linux environments, this Bash utility automates version downloading, dependency resolution, asset management, and client execution without relying on resource-heavy Electron or graphical wrappers.

---

## Features

- **No Graphical Launcher Required:** Boots Minecraft Java Edition straight from your Linux terminal using native JVM calls.
- **Custom Authlib / Yggdrasil Support:** Native integration with `authlib-injector` to authenticate against third-party authentication servers (e.g., custom endpoints, Ely.by, Blessing Skin).
- **Session Auto-Refresh:** Automatically validates and refreshes session tokens before game launch.
- **Offline Mode:** Create and play offline profiles with deterministic UUIDs.
- **Multi-Account Manager:** Save multiple user profiles (both Authlib and Offline) and quickly switch between them.
- **Built-in Version Installer:** Download official releases directly from Mojang metadata—automatically fetches client JARs, runtime libraries, extracts Linux natives, and downloads asset objects with multi-threaded parallel downloads (`xargs -P 16`).
- **Fabric Loader & Mod Support:** Automatically detects Fabric installations, resolves inherited dependencies (`inheritsFrom`), passes `-Dfabric.gameJarPath`, and supports mods, resource packs, and shaderpacks.
- **Per-Version Instance Isolation:** If a version folder contains its own `mods/` or `resourcepacks/` directory, the launcher automatically isolates the game directory to that specific version.
- **Flexible Game Directory:** Run Minecraft from the standard `~/.minecraft` path, an isolated directory inside `~/minecraft-cli/instances`, or any custom directory.
- **Interactive TUI Configuration:** Adjust maximum RAM (`-Xmx`), minimum RAM (`-Xms`), and garbage collection / JVM flags directly from the terminal.

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

### First-Time Setup Workflow

1. **Install a Version:**
   - Select `[i]` from the main menu.
   - Choose a release from the list of recent versions or select `[c]` to enter a custom version ID (e.g., `1.21`, `1.20.4`, `1.16.5`).
   - The launcher will download the version JSON, client JAR, libraries, Linux natives, and game assets.

2. **Add an Account:**
   - Select `[u]` from the main menu to open the **Account Manager**.
   - Choose `[a]` to add an **Authlib / Yggdrasil** account:
     - Enter your Authlib API Root URL (press Enter for default `https://elethiya.com/api/yggdrasil`).
     - Enter your username/email and password.
   - Or choose `[o]` to add an **Offline** account (enter your desired username).

3. **Configure Memory & Settings (Optional):**
   - Select `[r]` from the main menu to open directory & JVM settings:
     - **[1] Game Directory:** Select between `~/.minecraft`, `~/minecraft-cli/instances`, or a custom path.
     - **[2] Max RAM (-Xmx):** Set your maximum RAM allocation (e.g., `4G`, `8G`).
     - **[3] Min RAM (-Xms):** Set your minimum RAM allocation (e.g., `2G`, `4G`).
     - **[4] Custom JVM Flags:** Configure GC flags and optimization parameters.

4. **Launch:**
   - Enter the number corresponding to your installed version from the main menu.
   - Select your profile from the account list.
   - The launcher will validate sessions, build the classpath, and boot Minecraft.

---

## Configuration & Storage Layout

Configuration files and runtime metadata are kept clean and organized:

```text
~/minecraft-cli/
├── launch.sh              # Main executable launcher script
├── settings.json          # RAM limits, JVM flags, and game directory settings
├── authlib/
│   ├── authlib-injector.jar # Auto-downloaded agent for custom auth servers
│   └── accounts.json      # Stored session profiles and tokens
└── instances/             # Optional isolated game directory
```

### `settings.json` Example

```json
{
  "game_dir": "/home/username/.minecraft",
  "max_ram": "4G",
  "min_ram": "2G",
  "jvm_args": "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"
}
```

---

## Modding & Fabric Support

The launcher supports modded instances such as Fabric Loader (installed manually or through tools like HMCL):

1. **Install Fabric:** Place your Fabric version in your configured `versions/` folder (e.g., `<game_dir>/versions/Fabric-1.21`).
2. **Per-Version Isolation:**
   - If `<game_dir>/versions/<version-name>/mods/` or `resourcepacks/` exists, `minecraft-cli` will automatically isolate the game directory to that version's folder!
   - Otherwise, mods are loaded from `<game_dir>/mods/` and shaderpacks from `<game_dir>/shaderpacks/`.
3. **Execution:** Select the Fabric instance in the launcher menu. The script automatically resolves parent vanilla dependencies (`inheritsFrom`), supplies `-Dfabric.gameJarPath`, and launches the modded client.

---

## Troubleshooting

- **`java.lang.UnsupportedClassVersionError`**:
  You are running an older Java version than required by your Minecraft version. Install and select Java 21 for Minecraft 1.20.5+ (`sudo update-alternatives --config java`).
- **Missing CLI tools**:
  Ensure `jq`, `curl`, and `unzip` are installed. The installer relies on `jq` for parsing JSON manifests.
- **Authlib Login Failure**:
  Verify your authentication server URL and credentials. The server must provide standard Yggdrasil API endpoints (`/authserver/authenticate`, `/authserver/validate`, `/authserver/refresh`).

---

## License

This project is licensed under the MIT License.
