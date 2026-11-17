// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @dev Keeps transfers inside a closed set of holders so every base unit can be accounted for.
contract RoutrTokenHandler is Test {
    RoutrToken public immutable token;
    address[4] public actors;

    constructor(RoutrToken token_) {
        token = token_;
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2"), makeAddr("holder-3")];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function moveApproved(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 amount = bound(rawAmount, 0, balance < allowanceBefore ? balance : allowanceBefore);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        uint256 expectedAllowance = allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount;
        assertEq(token.allowance(owner, spender), expectedAllowance);
    }
}

contract RoutrTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    RoutrToken private token;
    RoutrTokenHandler private handler;

    function setUp() public {
        token = new RoutrToken();
        handler = new RoutrTokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = RoutrTokenHandler.move.selector;
        selectors[1] = RoutrTokenHandler.approve.selector;
        selectors[2] = RoutrTokenHandler.moveApproved.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalSupplyStaysFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_EveryBaseUnitIsAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_MetadataStaysFixed() public view {
        assertEq(token.name(), "Routr Network");
        assertEq(token.symbol(), "ROUTR");
        assertEq(token.decimals(), 18);
    }
}
