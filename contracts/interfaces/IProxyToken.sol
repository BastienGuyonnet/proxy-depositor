// // SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IProxyToken {
    function underlying() external returns (address);
}