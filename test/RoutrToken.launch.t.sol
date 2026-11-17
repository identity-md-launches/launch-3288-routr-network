// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @dev Stands in for the launch factory: deploys the token in one call (CREATE2, as the factory does)
/// and forwards the swarm share, the pool share and the remainder from the minted supply.
contract LaunchFactoryFixture {
    RoutrToken public token;

    function launch(bytes32 salt, address distributor, address pool, uint256 poolBps, address remainderTo)
        external
        returns (RoutrToken t)
    {
        t = new RoutrToken{salt: salt}();
        token = t;
        uint256 supply = t.totalSupply();
        uint256 swarm = (supply * 1_000) / 10_000;
        uint256 seed = (supply * poolBps) / 10_000;
        require(t.transfer(distributor, swarm), "swarm");
        require(t.transfer(pool, seed), "seed");
        require(t.transfer(remainderTo, t.balanceOf(address(this))), "remainder");
    }

    function forward(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract RoutrTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private distributor = makeAddr("distributor");
    address private pool = makeAddr("pool-manager");
    address private requester = makeAddr("requester");

    function test_CreatedCodeIsDeterministicAndHasNoConstructorArgs() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        bytes32 salt = bytes32(uint256(7));
        address predicted = vm.computeCreate2Address(salt, keccak256(type(RoutrToken).creationCode), address(factory));
        RoutrToken t = factory.launch(salt, distributor, pool, 5_000, requester);
        assertEq(address(t), predicted);
    }

    function test_LaunchFlowsArriveExactly() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken t = factory.launch(bytes32(0), distributor, pool, 5_000, requester);
        assertEq(t.balanceOf(distributor), 100_000_000 ether);
        assertEq(t.balanceOf(pool), 500_000_000 ether);
        assertEq(t.balanceOf(requester), 400_000_000 ether);
        assertEq(t.balanceOf(address(factory)), 0);
        assertEq(t.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_LaunchFlowsConserveSupply(uint256 rawPoolBps) public {
        uint256 poolBps = bound(rawPoolBps, 0, 9_000);
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken t = factory.launch(bytes32(0), distributor, pool, poolBps, requester);
        uint256 swarm = SUPPLY / 10;
        uint256 seed = (SUPPLY * poolBps) / 10_000;
        assertEq(t.balanceOf(distributor), swarm);
        assertEq(t.balanceOf(pool), seed);
        assertEq(t.balanceOf(requester), SUPPLY - swarm - seed);
        assertEq(t.balanceOf(distributor) + t.balanceOf(pool) + t.balanceOf(requester), SUPPLY);
    }

    /// @dev The distributor pays out the swarm share in equal claims; every claim arrives whole and the
    /// only thing left behind is the integer-division dust, never more.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_DistributorClaimsArriveWhole(uint8 rawClaimants) public {
        uint256 claimants = bound(rawClaimants, 1, 40);
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken t = factory.launch(bytes32(0), distributor, pool, 5_000, requester);
        uint256 share = t.balanceOf(distributor) / claimants;
        for (uint256 i; i < claimants; ++i) {
            address claimant = address(uint160(0xC1A1_0000 + i));
            vm.prank(distributor);
            assertTrue(t.transfer(claimant, share));
            assertEq(t.balanceOf(claimant), share);
        }
        assertEq(t.balanceOf(distributor), SUPPLY / 10 - share * claimants);
        assertLt(t.balanceOf(distributor), claimants);
        assertEq(t.totalSupply(), SUPPLY);
    }

    function test_PoolCanSellAndBuyBackWithoutLoss() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken t = factory.launch(bytes32(0), distributor, pool, 5_000, requester);
        address trader = makeAddr("trader");
        vm.prank(pool);
        assertTrue(t.transfer(trader, 12_345 ether));
        assertEq(t.balanceOf(trader), 12_345 ether);
        vm.prank(trader);
        assertTrue(t.transfer(pool, 12_345 ether));
        assertEq(t.balanceOf(trader), 0);
        assertEq(t.balanceOf(pool), 500_000_000 ether);
    }

    function test_FactoryKeepsNoPowerAfterDistributing() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken t = factory.launch(bytes32(0), distributor, pool, 5_000, requester);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(factory), 0, 1));
        factory.forward(requester, 1);

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        t.transferFrom(requester, address(factory), 1);
        assertEq(t.balanceOf(requester), 400_000_000 ether);
    }

    function test_SecondLaunchIsIndependent() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        RoutrToken a = factory.launch(bytes32(uint256(1)), distributor, pool, 5_000, requester);
        RoutrToken b = factory.launch(bytes32(uint256(2)), distributor, pool, 2_000, requester);
        assertTrue(address(a) != address(b));
        assertEq(a.totalSupply(), SUPPLY);
        assertEq(b.totalSupply(), SUPPLY);
        assertEq(a.balanceOf(pool), 500_000_000 ether);
        assertEq(b.balanceOf(pool), 200_000_000 ether);
    }

    function test_RedeployAtSameSaltReverts() public {
        LaunchFactoryFixture factory = new LaunchFactoryFixture();
        factory.launch(bytes32(uint256(3)), distributor, pool, 5_000, requester);
        vm.expectRevert();
        factory.launch(bytes32(uint256(3)), distributor, pool, 5_000, requester);
    }

    function test_RuntimeHasNoDelegatecallOrSelfdestruct() public {
        RoutrToken t = new RoutrToken();
        bytes memory code = address(t).code;
        bool reachable = true;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function test_LegacyAllowanceHelpersAreAbsent() public {
        RoutrToken t = new RoutrToken();
        (bool ok,) = address(t).call(abi.encodeWithSignature("increaseAllowance(address,uint256)", requester, 1));
        assertFalse(ok);
        (ok,) = address(t).call(abi.encodeWithSignature("decreaseAllowance(address,uint256)", requester, 1));
        assertFalse(ok);
        (ok,) = address(t)
            .call(
                abi.encodeWithSignature(
                    "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                    address(this),
                    requester,
                    1,
                    type(uint256).max,
                    uint8(27),
                    bytes32(0),
                    bytes32(0)
                )
            );
        assertFalse(ok);
        assertEq(t.allowance(address(this), requester), 0);
    }
}
