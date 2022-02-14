// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';


contract proxyToken is ERC20 {
    using SafeERC20 for IERC20;

    address public operator; //Should be the proxy depositor, or a dedicated minter contract

    address immutable underlying;
    constructor(ERC20 _token)
        ERC20(
            // Reaper Farm Proxy Hundred
            string(abi.encodePacked("Reaper Farm Proxy ", _token.name())),
            // rfpHND
            string(abi.encodePacked("rfp",_token.symbol()))
        )
    {
        operator = msg.sender;
        underlying = address(_token);
    }

   function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    
    function mint(address _to, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        
        _burn(_from, _amount);
    }

}