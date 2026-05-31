# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Li-native static HTTP server (`src/lib.li`): epoll loop, keep-alive, pipeline drain via runtime `httpd_drain_slot_i`, cached index fast path.

### Changed

- Build `lic build packages/li-net-httpd/src/lib.li -o li-httpd` (no C sources in package).

## [0.1.0] - 2026-05-16

### Added

- Initial scaffold via `scripts/li-new-package` (PKG-li-httpd).
