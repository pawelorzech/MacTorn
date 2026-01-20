# Installation

This guide covers how to install MacTorn on your Mac.

## System Requirements

| Requirement | Details |
|-------------|---------|
| **macOS Version** | 13.0 (Ventura) or later |
| **Architecture** | Universal Binary - Intel (x86_64) and Apple Silicon (arm64) |
| **Storage** | ~10 MB |
| **Network** | Internet connection for Torn API |

## Download

1. Visit the [Releases page](https://github.com/pawelorzech/MacTorn/releases)
2. Download the latest `MacTorn.zip` file
3. Unzip the downloaded file

## Install

1. Drag `MacTorn.app` to your **Applications** folder
2. Open MacTorn from Applications (or Spotlight search)

## Gatekeeper Warning (Unsigned App)

Since MacTorn is not signed with an Apple Developer certificate, macOS Gatekeeper will block it on first launch. Here's how to bypass this:

### Method 1: Right-Click Open

1. **Right-click** (or Control-click) on `MacTorn.app`
2. Select **Open** from the context menu
3. Click **Open** in the dialog that appears

### Method 2: System Settings

1. Try to open MacTorn normally (it will be blocked)
2. Open **System Settings** (or System Preferences on older macOS)
3. Go to **Privacy & Security**
4. Scroll down to the Security section
5. You'll see a message about MacTorn being blocked
6. Click **Open Anyway**
7. Enter your password if prompted
8. Click **Open** in the confirmation dialog

## First Launch

After successfully opening MacTorn:

1. The app will appear as a bolt icon in your menu bar
2. Click the icon to open the MacTorn window
3. Navigate to the **Settings** tab
4. Enter your Torn API Key (see [[API-Setup]])
5. Click **Save & Connect**

## Updating MacTorn

MacTorn automatically checks for updates. When a new version is available:

1. A notification appears in the Settings tab
2. Click **Download Update** to open the releases page
3. Download and replace the old version with the new one

Alternatively, manually check [GitHub Releases](https://github.com/pawelorzech/MacTorn/releases) for new versions.

## Uninstalling

To remove MacTorn:

1. Quit MacTorn if running (right-click menu bar icon)
2. Delete `MacTorn.app` from Applications
3. (Optional) Remove preferences: delete `~/Library/Preferences/com.bombel.MacTorn.plist`

---

**Next:** [[Getting-Started]] - Configure your API key
