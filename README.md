ATM SP Starter — Phase 1

Modular C++ framework for ATM/POS Service Providers (SPs) aligned with CEN/XFS concepts. Phase 1 focuses on a solid core (logging, events, sessions, errors), mock SPs (Card Reader, PIN Pad), config-driven runtime, CLI overrides, and a stubbed XFS adapter for Day-3 integration work.

Contents

Features (Phase 1 Day 1–2)

Quick Start (Windows / VS 2022)

Build (Cross-platform notes)

Run the Demo

CLI Flags

Configuration (config/devices.json)

Project Layout

Unit Tests

Logging & Security

Mock Failure Injection

XFS Adapter (Stub)

Sigma / XFS Smoke Checklist

Troubleshooting

Roadmap

Features (Phase 1 Day 1–2)

Core

Structured logging (console + rotating file) with spdlog

Event model + EventBus (publish/subscribe)

Session lifecycle (start/end) and error model

Mocks

Card Reader mock: emits CardInserted → Track2Read → CardRemoved

PIN Pad mock: publishes PinRequested, returns PinEntered

Config & CLI

Loads config/devices.json at startup (log level, device logicals, timeouts, flags)

CLI: --config, --fail-rate, --pin-error

Tests

Unit tests for EventBus, Session, Mocks, and basic config load

XFS Prep

Stub adapter compiles; ready to map real WFS* calls in Phase 1 Day 3

Quick Start (Windows / VS 2022)

If cmake/ctest aren’t found on your PATH, use Option A (bundled CMake) or Option B (install).

Option A — Use Visual Studio’s bundled CMake (fast)

Open PowerShell in the repo root and run:

$cmake = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022' -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -Match '\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake\.exe$' |
  Select-Object -First 1 -ExpandProperty FullName
$ctest = Join-Path (Split-Path $cmake) 'ctest.exe'

& $cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTS=ON -DUSE_REAL_XFS=OFF
& $cmake --build build --config Release
& $ctest --test-dir build --output-on-failure -C Release

New-Item -ItemType Directory -Force -Path .\logs | Out-Null
.\build\Release\atmsp_demo.exe

Option B — Install CMake (and Git)
winget install --id Kitware.CMake -e
winget install --id Git.Git -e
# reopen PowerShell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTS=ON -DUSE_REAL_XFS=OFF
cmake --build build --config Release
ctest --test-dir build --output-on-failure -C Release
mkdir logs -Force
build\Release\atmsp_demo.exe

Build (Cross-platform notes)

Windows (MSVC/VS 2022):

Generator: -G "Visual Studio 17 2022" -A x64

-DBUILD_TESTS=ON will fetch googletest (requires Git + network)

Linux/macOS (GCC/Clang):

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=ON -DUSE_REAL_XFS=OFF
cmake --build build --config Release -- -j
ctest --test-dir build --output-on-failure
./build/atmsp_demo


The project uses C++20 and FetchContent to pull spdlog, nlohmann_json, and (tests) googletest.

Run the Demo

Happy path:

mkdir logs -Force
build\Release\atmsp_demo.exe


You’ll see in console/log:

SessionStarted ... 
[MockCardReader] opened 'CARDREADER1'
[MockPinPad] opened 'PINPAD1'
CardInserted
Track2Read PAN=541333******2345
PinRequested ...  PinEntered masked=****
CardRemoved

CLI Flags
atmsp_demo [--config <path>|--config=<path>] [--fail-rate <0-100>|--fail-rate=NN] [--pin-error] [--help]


--config Path to devices.json (default: config/devices.json)

--fail-rate Percent (0..100) chance to drop Track2Read in Card Reader mock

--pin-error Force next RequestPin to fail with "KeypadFailure"

--help Print usage

Examples

build\Release\atmsp_demo.exe --config config\devices.json
build\Release\atmsp_demo.exe --fail-rate=50 --pin-error

Configuration (config/devices.json)
{
  "logging": {
    "maskPan": true,
    "level": "info",
    "file": "logs/atmsp.log",
    "rotateMB": 5,
    "rotateFiles": 3
  },
  "devices": {
    "CARDREADER1": {
      "type": "card_reader",
      "timeouts": { "openMs": 5000, "executeMs": 10000 },
      "features": { "emv": true, "contactless": false }
    },
    "PINPAD1": {
      "type": "pin_pad",
      "timeouts": { "openMs": 5000, "executeMs": 15000 },
      "features": { "bypassAllowed": false }
    },
    "PRINTER1": {
      "type": "printer",
      "timeouts": { "openMs": 5000, "executeMs": 10000 }
    },
    "SENSORS1": {
      "type": "sensors",
      "timeouts": { "openMs": 3000, "executeMs": 5000 }
    }
  }
}


Log Level: "debug" | "info" | "warn" | "error"

Devices: Logical names used by the app; timeouts are placeholders for future wiring.

Project Layout
.
├─ CMakeLists.txt
├─ include/
│  └─ atmsp/
│     ├─ logging.h
│     ├─ events.h
│     ├─ event_bus.h
│     ├─ errors.h
│     ├─ session.h
│     ├─ sp_interface.h
│     ├─ card_reader_sp.h
│     ├─ pin_pad_sp.h
│     ├─ config.h
│     └─ xfs/
│        └─ adapter.h          # XFS adapter (stub)
├─ src/
│  ├─ logging.cpp
│  ├─ session.cpp
│  ├─ mock_card_reader.cpp
│  ├─ mock_pin_pad.cpp
│  ├─ config.cpp
│  └─ xfs_adapter.cpp          # XFS adapter (stub)
├─ tests/
│  ├─ test_event_bus.cpp
│  ├─ test_session.cpp
│  ├─ test_mocks.cpp
│  └─ test_config.cpp
├─ config/
│  └─ devices.json
├─ docs/
│  └─ SIGMA_XFS_CHECKLIST.md
└─ logs/                       # runtime logs (gitignored)

Unit Tests

Build with tests:

cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --output-on-failure -C Release


EventBus.PublishesEvents

Session.Lifecycle

Mocks.CardReaderEmitsEvents

Config.LoadsDevices

If network blocks fetching googletest, reconfigure with -DBUILD_TESTS=OFF.

Logging & Security

Console and rotating file sink (logs/atmsp.log)

PAN is masked in logs: first 6 + ****** + last 4
Example: 541333******2345

No full track data is written to disk (demo emits a raw string internally, but we log only masked PAN).

Note: This repo is a dev scaffold. For production ATM/POS:

Enforce PCI DSS (log redaction, key handling, secure storage)

EMV L2 flows & kernel integration

Key management (DUKPT/RKL, secure modules)

Mock Failure Injection

Card Reader

Command: SetFailureRate { "pct": 0..100 }

Behavior: randomly drops Track2Read and logs WARN.

Example via CLI:

build\Release\atmsp_demo.exe --fail-rate=50


Or programmatically:

(void)card->execute("SetFailureRate", {{"pct", 50}});


PIN Pad

Command: InjectPinError {}

Behavior: next RequestPin fails, returns {"ok":false,"error":"KeypadFailure"}

Example via CLI:

build\Release\atmsp_demo.exe --pin-error


Or programmatically:

(void)pin->execute("InjectPinError", {});

XFS Adapter (Stub)

File: include/atmsp/xfs/adapter.h, src/xfs_adapter.cpp
Currently logs and returns {ok:true} for startup/open/execute/close.
In Day 3, this will map to real WFSStartUp/WFSCleanUp/WFSOpen/WFSClose/WFSExecute and bridge unsolicited events into our EventBus.

Toggle real integration later with:

-DUSE_REAL_XFS=ON


…and add vendor SDK include/lib paths in CMakeLists.txt.

Sigma / XFS Smoke Checklist

See docs/SIGMA_XFS_CHECKLIST.md:

WFSStartUp / WFSCleanUp

WFSOpen / WFSClose for CARDREADER1, PINPAD1

Execute NOOP/STATUS (or vendor diag)

Event mapping:

Card insert/remove → CardInserted/CardRemoved

PIN request/entered → PinRequested/PinEntered

Capture Sigma tool screenshots (open, status OK, basic exec)

Troubleshooting

cmake / ctest not found

Use the bundled VS CMake (Option A above), or

Install via winget install Kitware.CMake, reopen PowerShell

Dependency fetch fails (no Git / blocked network)

Install Git: winget install Git.Git

Or build with tests disabled: -DBUILD_TESTS=OFF

Build errors about C++ standard

Ensure VS 2022 C++ workload is installed (MSVC v143+) and CMake ≥ 3.21

No logs appear

Ensure logs/ exists (the app creates/uses it); check write permissions

Roadmap

Day 3: XFS adapter → real WFS* calls; event bridging; Sigma smoke

Phase 1 later: Printer & dispenser mocks; scripted flow runner; richer error taxonomy

Phase 2: Real SPs; EMV/PIN flows; ISO 8583 or host integration; RKL/DUKPT

Phase 3: AI modules (fraud/compliance/predictive) + real-time monitoring