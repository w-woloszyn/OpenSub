// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Mintable ERC20 that attempts to re-enter OpenSub during transferFrom.
/// @dev Used to test R1 (reentrancy) from THREAT_MODEL.md.
contract ReentrantERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // Reentrancy configuration
    address public target;      // OpenSub contract
    uint256 public planId;
    address public subscriber;

    bool public reentryAttempted;
    bool public reentrySucceeded;
    uint256 public reentryAttempts;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function setReentryConfig(address target_, uint256 planId_, address subscriber_) external {
        target = target_;
        planId = planId_;
        subscriber = subscriber_;
    }

    function mint(address to, uint256 amount) external {
        require(to != address(0), "TO0");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // Attempt a re-entrant call into OpenSub.collect(subscriptionId).
        if (target != address(0) && planId != 0 && subscriber != address(0)) {
            reentryAttempted = true;
            reentryAttempts += 1;

            // Query the currently-active subscriptionId for the configured (planId, subscriber).
            (bool okSubId, bytes memory ret) = target.staticcall(
                abi.encodeWithSignature("activeSubscriptionOf(uint256,address)", planId, subscriber)
            );
            if (okSubId && ret.length >= 32) {
                uint256 subscriptionId;
                assembly {
                    subscriptionId := mload(add(ret, 32))
                }
                // Try to re-enter collect(). We expect this to fail due to nonReentrant.
                (bool ok, ) = target.call(abi.encodeWithSignature("collect(uint256)", subscriptionId));
                reentrySucceeded = reentrySucceeded || ok;
            }
        }

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOW");
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "TO0");
        uint256 bal = balanceOf[from];
        require(bal >= amount, "BAL");
        unchecked {
            balanceOf[from] = bal - amount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
