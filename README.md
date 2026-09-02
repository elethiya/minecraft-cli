# minecraft-cli


Markdown

# Minecraft CLI Launcher

A Minecraft launcher that runs directly from the Linux terminal instead of using a GUI-based launcher. This launcher also supports Authlib.

Built for terminal-centric Linux environments, this lightweight Bash utility automates version downloading, dependency resolution, asset management, and execution without relying on resource-heavy Electron or graphical wrappers.

---

## Features

- **No Graphical Launcher Required:** Boots Minecraft Java Edition straight from your terminal using native JVM calls.
- **Custom Authlib / Yggdrasil Support:** Native integration with `authlib-injector` to authenticate against third-party authentication servers (e.g., custom endpoints, Ely.by, Blessing Skin).
- **Multi-Account Manager:** Store multiple profiles (both Authlib and Offline) with persistent session tokens and token auto-refresh.
- **Built-in Version Installer:** Download official Minecraft releases, client JARs, runtime libraries, Linux natives, and asset objects directly from Mojang metadata.
- **Fabric Loader & Mod Support:** Automatically detects Fabric installations, resolves inherited dependencies, and runs Fabric mods, Iris shaders, and resource packs.
- **Flexible Game Directory:** Run Minecraft from the standard `~/.minecraft` path, an isolated directory inside `~/minecraft-cli/instances`, or any custom path.
- **Interactive TUI Configuration:** Adjust maximum RAM (`-Xmx`), minimum RAM (`-Xms`), and garbage collection flags directly from the terminal.

---

## Requirements

Ensure you have the required CLI utilities and an appropriate Java runtime installed (Java 21 is required for Minecraft 1.20.5+):

### Debian / Ubuntu
```bash
sudo apt update
sudo apt install -y openjdk-21-jdk curl jq unzip

Arch Linux
Bash

sudo pacman -Syu --needed jdk21-openjdk curl jq unzip

Installation

    Clone or download the repository to your local machine:
    Bash

git clone [https://github.com/your-username/minecraft-cli.git](https://github.com/your-username/minecraft-cli.git) ~/minecraft-cli
cd ~/minecraft-cli

Make the launcher script executable:
Bash

    chmod +x launch.sh

Quick Start

Launch the interactive interface:
Bash

./launch.sh

First-Time Setup Workflow:

    Install a Version: Select [i] from the menu to download your preferred Minecraft release (e.g., 1.21).

    Add an Account: Select [u] to register an account:

        Choose [a] for Authlib (enter your Yggdrasil API URL, username, and password).

        Choose [o] for Offline mode.

    Configure Memory (Optional): Select [r] to configure -Xmx (Max RAM) and -Xms (Min RAM).

    Launch: Enter the number corresponding to your installed version, select your profile, and the game will start.

Configuration & Storage Layout

Configuration files and runtime metadata are kept clean and organized:
Plaintext

~/minecraft-cli/
├── launch.sh              # Main executable script
├── settings.json          # RAM limits, JVM flags, and game directory settings
├── authlib/
│   ├── authlib-injector.jar # Downloaded agent for custom auth servers
│   └── accounts.json      # Stored session profiles and tokens
└── instances/             # Optional isolated game directory

Modding & Fabric Support

The launcher supports Fabric Loader instances created manually or managed through tools like HMCL:

    Place your Fabric version in your configured versions/ folder (e.g., versions/Fabric-1.21).

    Add your mods to <gameDir>/mods/ and shaderpacks to <gameDir>/shaderpacks/.

    Select the Fabric instance in the launcher menu. The script resolves the parent vanilla dependencies, passes -Dfabric.gameJarPath, and initializes the modded client.

License

This project is licensed under the MIT License.
