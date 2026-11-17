// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WalletGas} from "./properties/WalletGas.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @notice RoutrToken does not read gasleft(), forward fixed gas or catch failed calls. These checks
/// pin that every state-changing function a holder or a bot sends does the same work at the gas
/// limit a wallet would estimate as with gas to spare, so a later change that adds such logic is caught.
contract RoutrTokenWalletGasTest is WalletGas {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    RoutrToken private token;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private spender = makeAddr("spender");

    function setUp() public {
        token = new RoutrToken();
        token.transfer(alice, 1_000 ether);
    }

    function test_TransferToFreshRecipientAtWalletGas() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.transfer, (bob, 400 ether)));
    }

    function test_TransferEntireBalanceAtWalletGas() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.transfer, (bob, 1_000 ether)));
    }

    function test_TransferToExistingHolderAtWalletGas() public {
        vm.prank(alice);
        token.transfer(bob, 1);
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.transfer, (bob, 5 ether)));
    }

    function test_ZeroTransferAtWalletGas() public {
        assertSameAtWalletGas(bob, address(token), abi.encodeCall(IERC20.transfer, (alice, 0)));
    }

    function test_ApproveAtWalletGas() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.approve, (spender, 10 ether)));
    }

    function test_RevokeApprovalAtWalletGas() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.approve, (spender, 0)));
    }

    function test_TransferFromFiniteAllowanceAtWalletGas() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        assertSameAtWalletGas(spender, address(token), abi.encodeCall(IERC20.transferFrom, (alice, bob, 7 ether)));
    }

    function test_TransferFromUnlimitedAllowanceAtWalletGas() public {
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        assertSameAtWalletGas(spender, address(token), abi.encodeCall(IERC20.transferFrom, (alice, bob, 1_000 ether)));
    }

    function test_DeployerTransferOfLaunchShareAtWalletGas() public {
        assertSameAtWalletGas(
            address(this), address(token), abi.encodeCall(IERC20.transfer, (bob, (SUPPLY * 1_000) / 10_000))
        );
    }

    /// @dev The wallet-gas run must actually deliver: after the check (which leaves state unchanged)
    /// the same call at the estimated limit is executed for real and its effects are observed.
    function test_TransferAtEstimatedLimitMovesTokens() public {
        bytes memory data = abi.encodeCall(IERC20.transfer, (bob, 400 ether));
        uint256 snap = vm.snapshotState();
        uint256 lo;
        uint256 hi = GAS_TO_SPARE;
        while (lo + 1 < hi) {
            uint256 mid = (lo + hi) / 2;
            vm.revertToState(snap);
            vm.prank(alice);
            (bool ok,) = address(token).call{gas: mid}(data);
            if (ok) hi = mid;
            else lo = mid;
        }
        vm.revertToStateAndDelete(snap);
        vm.prank(alice);
        (bool success, bytes memory ret) = address(token).call{gas: hi}(data);
        assertTrue(success);
        assertTrue(abi.decode(ret, (bool)));
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token.balanceOf(alice), 600 ether);
    }
}
