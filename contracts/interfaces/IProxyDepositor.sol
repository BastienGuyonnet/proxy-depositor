// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IProxyDepositor {
    /////////////// TO USE ///////////////

    // user wants to lock the tokens
    // deposit governance token (ex: HND) for proxy token and lock
    function depositToLock(uint256 amount, address user) external;
}