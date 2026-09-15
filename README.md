# dcs_packages

Monorepo of Dart and Flutter packages for **Departure Control System (DCS)** applications: common-use platforms (CUPPS/CUTE), host messaging, device utilities, IATA document parsing, and shared runtime contracts.

Repository: [github.com/MahmoodBakhshayesh/dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages)

## Packages

| Package | Description | Type |
|---------|-------------|------|
| [dcs_common](packages/dcs_common) | Shared runtime contracts, logging, status models | Dart |
| [dcs_bcbp](packages/dcs_bcbp) | IATA BCBP barcode boarding pass parsing | Dart |
| [dcs_mrz](packages/dcs_mrz) | Passport MRZ (TD3) parsing and check digits | Dart |
| [dcs_baggage](packages/dcs_baggage) | Baggage tags and BSM domain models | Dart |
| [dcs_host](packages/dcs_host) | Host messaging adapter contracts | Dart |
| [dcs_documents](packages/dcs_documents) | Boarding pass and bag tag print payloads | Dart |
| [dcs_certification](packages/dcs_certification) | Integration certification checklists | Dart |
| [dcs_simulator](packages/dcs_simulator) | In-memory device and host simulators | Dart |
| [dcs_cupps](packages/dcs_cupps) | CUPPS socket/XML platform client | Flutter |
| [dcs_cute](packages/dcs_cute) | CUTE/MATIP socket client | Flutter |
| [dcs_cute_peripherals](packages/dcs_cute_peripherals) | CUTE peripherals: ARINC TCP, SITA/RESA FFI | Flutter |
| [dcs_zebra](packages/dcs_zebra) | Zebra Link-OS printers (TCP / BT / USB) | Flutter |
| [dcs_device_util](packages/dcs_device_util) | Desktop serial/USB device management | Flutter |

The reference DCS application lives separately at [`../dcs`](../dcs) (sibling folder) and consumes these packages via git dependencies.

## Use in another project (git)

Add only the packages you need. Pub resolves sibling dependencies from the same repository automatically.

```yaml
dependencies:
  dcs_bcbp:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_bcbp
      ref: main

  dcs_cupps:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_cupps
      ref: main
```

Pin a **tag** or **commit** instead of `main` for reproducible builds:

```yaml
      ref: v1.0.0        # release tag
      # ref: abc1234     # specific commit SHA
```

Then run:

```bash
flutter pub get
# or
dart pub get
```

### All packages at once (example)

```yaml
dependencies:
  dcs_common:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_common
      ref: main
  dcs_cupps:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_cupps
      ref: main
  dcs_cute:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_cute
      ref: main
  dcs_device_util:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_device_util
      ref: main
  dcs_zebra:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_zebra
      ref: main
  dcs_bcbp:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_bcbp
      ref: main
  dcs_mrz:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_mrz
      ref: main
  dcs_baggage:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_baggage
      ref: main
  dcs_host:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_host
      ref: main
  dcs_documents:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_documents
      ref: main
  dcs_simulator:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_simulator
      ref: main
  dcs_certification:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_certification
      ref: main
```

## Develop in this monorepo

Requires [Melos](https://melos.invertase.dev/) and Dart SDK `^3.12.0`.

```bash
git clone https://github.com/MahmoodBakhshayesh/dcs_packages.git
cd dcs_packages
dart pub global activate melos
dart pub get
melos bootstrap
```

- Edit any package under `packages/`
- Run the app: `cd ../dcs && flutter run`
- Run tests: `melos run test`

`melos bootstrap` links local packages together (overrides git dependencies with local paths).

## Pull all projects from GitHub

From the monorepo:

**Windows (PowerShell — recommended):**

```powershell
cd dcs-packages
.\scripts\pull-all.ps1
```

Or run `scripts\pull-all.bat` (uses Git Bash explicitly).

**macOS / Linux / Git Bash:**

```bash
cd dcs-packages
chmod +x scripts/pull-all.sh   # once on Mac/Linux
./scripts/pull-all.sh
```

This fast-forwards **dcs-packages** and the sibling **dcs** app repository from `origin`, then runs `melos bootstrap` / `flutter pub get` when available.

## Push all projects to GitHub

From the monorepo:

**Windows (PowerShell — recommended):**

```powershell
cd dcs-packages
.\scripts\push-all.ps1 "describe your changes"
```

Or double-click / run `scripts\push-all.bat` (uses Git Bash explicitly).

**macOS / Linux / Git Bash:**

```bash
cd dcs-packages
chmod +x scripts/push-all.sh   # once on Mac/Linux
./scripts/push-all.sh "describe your changes"
```

On Windows, plain `bash scripts/push-all.sh` often fails because `bash` resolves to WSL, not Git Bash.

This commits and pushes **dcs-packages** and the sibling **dcs** app repository (if each has a `.git` folder).

## Releasing

Tag the repository when you want a stable snapshot for other machines:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Consumers then set `ref: v1.0.0` in their `pubspec.yaml`.

## License

MIT — see [LICENSE](LICENSE).
