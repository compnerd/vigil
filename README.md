# vigil

A Windows command-line tool that prevents your computer from going to sleep or turning off the display. Perfect for long-running tasks, presentations, or keeping your system active.

## What does vigil do?

vigil temporarily overrides Windows power management settings to keep your computer awake. It offers three ways to prevent sleep:

- **`vigil start`** — Start sleep prevention that runs until you manually stop it
- **`vigil end`** — Stop a running vigil session
- **`vigil stand`** — Prevent sleep while running a specific command

## Installation

Build from source using Swift Package Manager:

```powershell
swift build --configuration release
```

The executable will be available at `.build/release/vigil.exe`.

## Basic Usage

### Keep system awake indefinitely

```powershell
# Prevent computer from sleeping due to inactivity
vigil start --idle

# Also keep the display on
vigil start --idle --display

# Stop when done
vigil end
```

### Keep system awake for a specific duration

```powershell
# Prevent sleep for 2 hours (7200 seconds)
vigil start --idle --timeout 7200
```

### Prevent sleep while running a command

```powershell
# Keep system awake while running a backup
vigil stand --idle -- robocopy C:\Important D:\Backup /MIR

# Keep display on during a video conversion
vigil stand --display -- ffmpeg -i input.mp4 output.mkv
```

## Command Options

### Sleep Prevention Modes

- `--idle` / `-i` — Prevent the computer from sleeping due to inactivity
- `--display` / `-d` — Prevent the display from turning off
- `--system` / `-s` — Prevent sleep only when running on AC power (not battery)

### Additional Options

- `--timeout <seconds>` / `-t` — Automatically stop after specified seconds (only with `start`)

## Common Scenarios

**Long download or upload:**
```powershell
vigil start --idle
# Run your download/upload
vigil end
```

**Presentation or demo:**
```powershell
vigil start --display --idle
# Give your presentation
vigil end
```

**Overnight batch job:**
```powershell
vigil stand --idle -- python my_long_script.py
```

**Video call or streaming:**
```powershell
vigil start --display --system  # Only when plugged in
```

## How It Works

vigil uses Windows power management APIs to temporarily change execution state:
- Requests that Windows keep the system and/or display active
- Automatically restores normal power settings when stopped
- Uses named events for communication between `start` and `end` commands

## Troubleshooting

**vigil end doesn't work:**
- Make sure you're running as the same user who ran `vigil start`
- Only one `vigil start` session can run at a time

**Computer still goes to sleep:**
- Check if other power policies (group policy, manufacturer tools) are overriding settings
- Try combining `--idle` and `--display` flags
- Verify you're using the correct flags for your scenario

**--system flag has no effect:**
- This flag only prevents sleep when on AC power
- Check your power status in Windows settings
