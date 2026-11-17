# Routr Network (ROUTR)

A fixed-supply ERC-20 token built with Solidity 0.8.26 and the vendored
OpenZeppelin Contracts v5.1.0 ERC20 implementation.

| Parameter | Value |
| --- | --- |
| Deployment artifact | `src/RoutrToken.sol:RoutrToken` |
| Name | `Routr Network` |
| Symbol | `ROUTR` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | The constructor's `msg.sender` |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | None |

`INITIAL_SUPPLY` is the named constant for the full supply in base units. The
constructor mints it once and emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`.
There is no subsequent minting or burning entry point and no owner, administrator,
pause, blacklist, fee, rebase, initializer, proxy, or upgrade mechanism.

## Build and test

Run from this repository's root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xabf257515de22b574a72285d8fe7b90b962a889b3a156ad030687fa16e980408 forge test
forge fmt --check
sha256sum --check DEPENDENCIES.sha256
```

All Solidity dependencies and their licenses are included as ordinary files in
`lib/`. There are no package installation steps, submodules, fork tests, RPC
dependencies, environment reads in tests, FFI, or filesystem cheatcode permissions.
Dependency versions, source archives, and checksums are in `DEPENDENCIES.md`.

The tests cover metadata, the constructor mint and its event, direct and factory
deployment, exact transfers, full-balance and one-unit transfers, zero and self
transfers, approvals, revocation, finite and unlimited allowances, delegated
transfers, and atomic rollback on failure. Failure cases include insufficient
balance or allowance, zero addresses, unauthorized spending, nonexistent admin
and mint functions, unknown selectors, and direct ETH sends. Six fuzz tests run
1,024 cases each. Three stateful invariants run 128 sequences of 64 calls each,
checking the fixed supply, conservation of all balances in a closed set of
holders, and unchanged metadata across transfers and approval changes.

The provided launch checks were read for compatibility. They require their
separate factory/Uniswap harness and launch environment, and are not part of this
standalone project's local test suite.

## Deployment and assumptions

Deploy the `RoutrToken` creation bytecode directly with no arguments and no ETH.
There are no linked external libraries, contract dependencies, initialization
calls, or chain-specific constructor settings. The intended launch chain is
Ethereum (chain id 1), as supplied in the assignment; local tests use an isolated
EVM and send no transactions to a live network.

The deployer means the address executing `CREATE` or `CREATE2`. For the IdentityMD
launch, that address is the launch factory, which receives **100%** of the supply.
It is not `tx.origin`, the wallet invoking the factory, or a separate recipient
argument. The factory performs subsequent launch allocations and pool operations.
This token does not allocate supply to application contracts or implement a pool
or distributor. The launch workflow supplies its own deployment manifest.

The release operator is responsible for the launch transaction, chain selection,
factory distribution, validating the deployed bytecode and constructor mint, and
publishing/verifying the source. Confirm `name`, `symbol`, `decimals`, `totalSupply`,
and the full initial balance at the deploying address before distribution. Only
the token contract belongs in the deployment list; contracts under `test/` are
local fixtures and test harnesses.

## After launch

No owner-settable values, administrative keys, keepers, or maintenance calls are
required. Holders control their balances; approved spenders can transfer only
within the allowance a holder grants them. The deploying address retains no
special token privileges after receiving the initial balance.

Successful transfers deliver the exact requested number of base units. Standard
ERC-20 zero-value transfers to a nonzero address succeed and emit `Transfer`;
transfers to the zero address revert. Self-transfers preserve the balance but
still require sufficient funds. `approve` replaces the existing allowance and
emits `Approval`. Finite allowances decrease on `transferFrom`; a `uint256` maximum
allowance remains unchanged. OpenZeppelin v5 does not emit an additional `Approval`
event when `transferFrom` consumes an allowance. Integrations should query
`allowance` for its current value. Even a holder needs a self-allowance if using
`transferFrom` instead of `transfer`.

Holders are responsible for recipient selection, custody, and approvals. Prefer
exact allowances and revoke unused approvals. When changing a live nonzero
allowance, first revoke it and wait for confirmation before granting a new one;
a spender may consume an existing approval before the replacement is confirmed.

Transfers do not call recipient hooks or check whether a recipient can recover
tokens. Tokens sent to the token contract or another contract without a recovery
method can be permanently inaccessible. There is no privileged recovery method
for ROUTR, other ERC-20 tokens, or forcibly delivered ETH. Direct ETH transfers
revert.

## Security review and validation

The supplied security reference was used as a review checklist. The token adds
only a constructor and a supply constant to the unmodified ERC-20 implementation.
Its runtime makes no external calls, uses no oracles, signatures, randomness, or
dynamic fee logic, and introduces no custom unchecked arithmetic. Public spending
is restricted to the caller's own balance or a holder-granted allowance.

Local validation consists of compilation, unit tests, fuzz tests, stateful
invariants, formatting, and dependency checksum verification. Slither, Mythril,
the separate protected launch harness, and live deployment verification were not
run here. These checks do not constitute an independent security audit; release
review and explorer verification remain the release operator's responsibility.
