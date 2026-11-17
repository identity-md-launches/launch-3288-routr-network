// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Routr Network (ROUTR)
/// @notice A fixed-supply ERC-20 with all tokens minted once to the deploying address.
/// @dev Has no owner, external mint or burn functions, transfer fees, or upgrade mechanism.
contract RoutrToken is ERC20 {
    /// @notice The entire supply, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev When deployed by a factory, the factory receives the entire supply.
    constructor() ERC20("Routr Network", "ROUTR") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
