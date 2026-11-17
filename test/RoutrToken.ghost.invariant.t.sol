// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @dev Drives every ERC-20 entry point with unbounded amounts, including ones that must fail, and
/// keeps an independent ghost ledger of balances and allowances. Calls are made with a low-level call
/// so a revert is an observed outcome, checked against what the ghost ledger says must happen.
contract GhostLedgerHandler is Test {
    RoutrToken public immutable token;
    address[6] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public unexpectedOutcomes;
    uint256 public successfulMoves;
    uint256 public rejectedMoves;

    constructor(RoutrToken token_, address seedHolder) {
        token = token_;
        actors = [
            seedHolder,
            makeAddr("ghost-1"),
            makeAddr("ghost-2"),
            makeAddr("ghost-3"),
            makeAddr("ghost-4"),
            makeAddr("ghost-5")
        ];
        ghostBalance[seedHolder] = token_.totalSupply();
    }

    function actorCount() external pure returns (uint256) {
        return 6;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Amount near a balance edge most of the time, arbitrary otherwise.
    function _amount(uint256 raw, uint256 edge) private pure returns (uint256) {
        uint256 mode = raw % 4;
        if (mode == 0) return edge;
        if (mode == 1) return edge + 1;
        if (mode == 2) return edge == 0 ? 0 : (raw >> 2) % (edge + 1);
        return raw;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(rawAmount, ghostBalance[from]);
        bool shouldSucceed = amount <= ghostBalance[from];

        vm.prank(from);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (ok != shouldSucceed) ++unexpectedOutcomes;
        if (ok) {
            if (!abi.decode(ret, (bool))) ++unexpectedOutcomes;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++successfulMoves;
        } else {
            ++rejectedMoves;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (amount % 5 == 0) amount = type(uint256).max;
        vm.prank(owner);
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        if (!ok) ++unexpectedOutcomes;
        else ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 bal = ghostBalance[owner];
        uint256 amount = _amount(rawAmount, rawAmount % 2 == 0 ? bal : (allowed < bal ? allowed : bal));
        bool shouldSucceed = amount <= allowed && amount <= bal;

        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        if (ok != shouldSucceed) ++unexpectedOutcomes;
        if (ok) {
            if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
            ghostBalance[owner] -= amount;
            ghostBalance[to] += amount;
            ++successfulMoves;
        } else {
            ++rejectedMoves;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(0), rawAmount % 2)));
        if (ok) ++unexpectedOutcomes;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.prank(_actor(ownerSeed));
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        if (ok) ++unexpectedOutcomes;
    }

    /// @dev Strangers try the admin surface an owner-controlled token would have.
    function adminProbe(uint256 callerSeed, uint256 which, uint256 amount) external {
        address caller = _actor(callerSeed);
        address victim = actors[(callerSeed % 6 + 1) % 6];
        bytes memory data;
        uint256 w = which % 5;
        if (w == 0) data = abi.encodeWithSignature("mint(address,uint256)", caller, amount);
        else if (w == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (w == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", victim, amount);
        else if (w == 3) data = abi.encodeWithSignature("pause()");
        else data = abi.encodeWithSignature("transferOwnership(address)", caller);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        if (ok) ++unexpectedOutcomes;
    }
}

contract RoutrTokenGhostInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    RoutrToken private token;
    GhostLedgerHandler private handler;

    function setUp() public {
        address seedHolder = makeAddr("ghost-0");
        vm.prank(seedHolder);
        token = new RoutrToken();
        handler = new GhostLedgerHandler(token, seedHolder);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = GhostLedgerHandler.transfer.selector;
        selectors[1] = GhostLedgerHandler.approve.selector;
        selectors[2] = GhostLedgerHandler.transferFrom.selector;
        selectors[3] = GhostLedgerHandler.transferToZero.selector;
        selectors[4] = GhostLedgerHandler.approveZeroSpender.selector;
        selectors[5] = GhostLedgerHandler.adminProbe.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_BalancesMatchGhostLedger() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actors(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a));
            sum += token.balanceOf(a);
        }
        assertEq(sum, SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_AllowancesMatchGhostLedger() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            for (uint256 j; j < handler.actorCount(); ++j) {
                address o = handler.actors(i);
                address s = handler.actors(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
        }
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_EveryCallBehavedAsTheLedgerPredicted() public view {
        assertEq(handler.unexpectedOutcomes(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_SupplyFixedAndNothingEscapesTheActorSet() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}

/// @dev Pins that the ghost handler's predictions are not vacuous: it does reach both outcomes.
contract GhostLedgerHandlerSanityTest is Test {
    function test_HandlerSeesSuccessesAndRejections() public {
        address seedHolder = makeAddr("ghost-0");
        vm.prank(seedHolder);
        RoutrToken token = new RoutrToken();
        GhostLedgerHandler handler = new GhostLedgerHandler(token, seedHolder);
        handler.transfer(0, 1, 2); // mode 2: within balance
        handler.transfer(2, 3, 1); // mode 1: balance + 1 from an empty account
        handler.approve(1, 2, 7);
        handler.transferFrom(1, 2, 4, 3); // mode 3 with raw = 3 > allowance? allowance 7: must still predict
        handler.transferFrom(1, 3, 4, 1); // no allowance, nonzero amount: rejected
        handler.transferToZero(0, 1);
        handler.approveZeroSpender(0, 1);
        handler.adminProbe(0, 0, 1);
        assertGt(handler.successfulMoves(), 0);
        assertGt(handler.rejectedMoves(), 0);
        assertEq(handler.unexpectedOutcomes(), 0);
    }
}
