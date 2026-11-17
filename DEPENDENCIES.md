# Vendored dependencies

All required Solidity dependencies are ordinary files under `lib/`; no install, submodule, or network access is needed to build or test once Solidity 0.8.26 is available.

Upstream source files and license texts are included unchanged. The archive SHA-256 values below identify the downloads used for this project.

- **forge-std v1.9.7**: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  - Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- **openzeppelin-contracts v5.1.0**: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
  - Archive SHA-256: `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`

OpenZeppelin includes only ERC20 and its transitive dependencies. forge-std includes its Solidity source tree for tests, plus its MIT and Apache-2.0 licenses.

`DEPENDENCIES.sha256` records the SHA-256 of every vendored file. From the project root, run `sha256sum --check DEPENDENCIES.sha256` to check that the vendored files have not changed.
