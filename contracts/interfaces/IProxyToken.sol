// // SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IProxyToken {
     function underlying() external returns (address);
     function setOperator(address _operator) external;
     function mint(address _to, uint256 _amount) external;
     function burn(address _from, uint256 _amount) external;
     function deposit(uint256 _amount) external;
     function claim() external;
     function updateRewards(uint256 rewards) external;
}