# MemoryShield

<img width="1080" height="768" alt="Screenshot 2026-06-05 at 21 02 53" src="https://github.com/user-attachments/assets/fd217e9e-181b-4e35-b9de-675f66c0ce1e" />


A lightweight macOS menu-bar utility that watches running processes and reclaims memory before your Mac starts swapping. MemoryShield samples per-process RSS, plots history, and can automatically terminate user apps that stay above a configurable threshold for a sustained duration.

## Features

- Live per-process memory usage with icons, uptime, and percentage of total RAM
- Configurable memory threshold (MB) and sustain duration (seconds) before action
- Optional auto-kill of user apps that exceed the threshold
- Rolling history chart per process
- Activity log of terminations
- Native SwiftUI app, no background daemons, no telemetry

## Requirements

- macOS 14 or later
- Xcode 15+ (for building from source)

## Install

### From source

```sh
make build      # unsigned Release build into ./build
make run        # build and launch
make install    # copy MemoryShield.app to /Applications
```

### Fastlane

```sh
bundle install
make fastlane-run
make fastlane-install
```

## Usage

1. Launch **MemoryShield**.
2. Set the **Threshold (MB)** above which a process is considered a memory hog.
3. Set the **Sustain (s)** window — how long a process must stay above the threshold before it is eligible to be killed.
4. Toggle **Auto-kill** to let MemoryShield terminate offenders automatically, or leave it off to just monitor.

System processes are filtered out — only user apps are eligible for termination.

## Project layout

```
MemoryShield/
├── MemoryShield/            # SwiftUI sources
│   ├── MemoryShieldApp.swift
│   ├── ContentView.swift
│   └── ProcessMonitor.swift
├── MemoryShield.xcodeproj/
├── fastlane/
├── Makefile
└── Gemfile
```

## Contributing

Issues and PRs are welcome. Please read [SECURITY.md](SECURITY.md) before reporting anything that looks like a vulnerability.

## License

[MIT](LICENSE) © Matheus Gois
