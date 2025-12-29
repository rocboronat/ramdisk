# MemDisk - Windows RAM Disk Manager

A sleek Windows application for creating and managing RAM disks.

![Screenshot](docs/screenshot.png)

## Requirements

### ImDisk Toolkit
This application uses **ImDisk Toolkit** to create virtual RAM disks.

> **Note**: While ImDisk shows as "Inactive" on SourceForge, it continues to be maintained and distributed via package managers (latest version: Feb 2025).

**Installation options:**

1. **Via Winget** (recommended):
   ```powershell
   winget install ImDisk.Toolkit
   ```

2. **Via Chocolatey**:
   ```powershell
   choco install imdisk-toolkit -y
   ```

3. **Manual download**:
   - https://sourceforge.net/projects/imdisk-toolkit/

## Features

- ✨ Create 1GB RAM disk with one click
- 📁 Choose drive letter (R, Z, Y, X, W, V)
- 💾 NTFS formatted automatically
- 🎨 Modern dark UI with subtle animations
- 📦 Built-in installation helper

## Usage

1. **Start**: Click the START button to create a RAM disk
2. **Stop**: Click the STOP button to remove the RAM disk

⚠️ **Warning**: All data on the RAM disk is lost when stopped or when the computer is turned off/restarted.

## Running the Application

```bash
flutter run -d windows
```

## Building

```bash
flutter build windows
```

The executable will be in `build/windows/x64/runner/Release/`.

## How It Works

MemDisk uses the ImDisk virtual disk driver to create a RAM-based virtual disk:
- Stored entirely in RAM for maximum speed
- Formatted with NTFS file system
- Accessible as a regular Windows drive

## Use Cases

- **Temporary files**: Store temp files for ultra-fast access
- **Browser cache**: Redirect browser cache for faster browsing
- **Development**: Fast scratch space for builds and compilations
- **Gaming**: Load game assets faster

## License

MIT
