// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC20-shaped contract that reverts for transfer/approve calls.
/// @dev Useful for testing that state changes don't persist when token transfers fail.
contract RevertingERC20 {
    string public constant name = "Reverting";
    string public constant symbol = "REVERT";
    uint8 public constant decimals = 18;

    // Keep as a public variable so the compiler generates totalSupply() getter.
    uint256 public totalSupply = 1;

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        revert("REVERT");
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("REVERT");
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("REVERT");
    }
}
