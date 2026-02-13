// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address caller) external;
    function startPrank(address caller) external;
    function stopPrank() external;

    function warp(uint256 newTimestamp) external;

    function expectRevert() external;
    function expectRevert(bytes calldata message) external;
    function expectRevert(bytes4 message) external;

    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);

    function assume(bool condition) external;

    function targetContract(address target) external;
    function startBroadcast() external;
    function stopBroadcast() external;
}
