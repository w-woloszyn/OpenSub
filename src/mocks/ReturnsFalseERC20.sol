// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC20-shaped contract that returns `false` for transfer/approve calls.
/// @dev Useful for testing that SafeERC20 reverts on `false` returns.
contract ReturnsFalseERC20 {
    string public constant name = "ReturnsFalse";
    string public constant symbol = "FALSE";
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
        return false;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}
