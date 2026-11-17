// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @dev Demonstrates that a contract deployer receives the supply, rather than tx.origin.
contract TokenFactoryFixture {
    function deploy() external returns (RoutrToken) {
        return new RoutrToken();
    }

    function forward(RoutrToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract RoutrTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private spender = makeAddr("spender");
    RoutrToken private token;

    function setUp() public {
        token = new RoutrToken();
    }

    function test_MetadataAndExactInitialSupply() public view {
        assertEq(token.name(), "Routr Network");
        assertEq(token.symbol(), "ROUTR");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new RoutrToken();
    }

    function test_FactoryReceivesAndCanDistributeEntireSupply() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice);
        RoutrToken launched = factory.deploy();

        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertTrue(factory.forward(launched, alice, SUPPLY));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(alice), SUPPLY);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));

        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_TransferOneBaseUnit() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenEmptyAccountTransfers() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_RevertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_RevertWhenTransferTargetsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenZeroTransferTargetsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_ApproveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        token.approve(spender, 100 ether);
        token.approve(spender, 3 ether);
        assertEq(token.allowance(address(this), spender), 3 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_ApprovalMayExceedBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenApprovingZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromUsesOnlyCallersAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromEmitsTransferAndDecrementsAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 3 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 3 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertEq(token.balanceOf(alice), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromCanConsumeExactAllowance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_TransferFromPreservesUnlimitedAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 3 ether));
        assertTrue(token.transferFrom(address(this), bob, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 3 ether);
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function test_TransferFromToSelfStillConsumesAllowance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_HolderNeedsAllowanceWhenUsingTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromExceedsAllowance() public {
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenTransferFromExceedsBalancePreservesAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromTargetsZeroPreservesAllowance() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenZeroTransferFromUsesZeroSender() public {
        // Allowance validation runs before the transfer's sender validation.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_DeployerCannotTakeHolderTokensWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_CommonMintBurnAndAdminSelectorsRevertForEveryone() public {
        token.transfer(alice, 10 ether);
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("initialize(address)", bob);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("unpause()");
        calls[8] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[9] = abi.encodeWithSignature("freeze(address)", alice);
        calls[10] = abi.encodeWithSignature("seize(address)", alice);
        calls[11] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[13] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[14] = abi.encodeWithSignature("owner()");
        calls[15] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_DirectEtherAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool acceptedEther,) = address(token).call{value: 1 ether}("");
        assertFalse(acceptedEther);
        (bool acceptedUnknownCall,) = address(token).call(hex"ffffffff");
        assertFalse(acceptedUnknownCall);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferBeyondBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_DelegatedTransferConservesSupplyAndConsumesAllowance(uint256 rawApproval, uint256 rawAmount)
        public
    {
        uint256 approved = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverAllowanceCannotMoveTokens(uint256 rawApproval, uint256 rawExcess) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawExcess, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_ApprovalIsIsolatedToOwnerAndSpender(uint256 amount) public {
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferChangesNeitherBalanceNorSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
