// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import './interfaces/IProxyDepositor.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';


contract ProxyToken is ERC20 {
    using SafeERC20 for IERC20;

    address public operator; //Should be the proxy depositor, or a dedicated minter contract
    address public proxyDepositor; //Stored in another value, if depositor needs to be different from operator

    IERC20 public immutable underlying;
    uint256 lastUpdateTime;
    uint256 accRewardPerShare;
    uint256 stakedTotal;

    mapping (address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    event Deposit(address indexed user, uint256 amount);
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event SetOperator(address indexed newOperator, address indexed formerOperator);

    constructor(ERC20 _token)
        ERC20(
            // Reaper Farm Proxy Hundred
            string(abi.encodePacked("Reaper Farm Proxy ", _token.name())),
            // rfpHND
            string(abi.encodePacked("rfp",_token.symbol()))
        )
    {
        operator = msg.sender;
        underlying = _token;
    }

   function setOperator(address _operator) external {
        _onlyOperator();
        address formerOperator = operator;
        operator = _operator;

        emit SetOperator(operator, formerOperator);
    }

    
    function mint(address _to, uint256 _amount) external {
        _onlyOperator();
        
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        _onlyOperator();
        
        _burn(_from, _amount);
    }

    /// @notice wraps underlying tokens 
    /// tokens are then sent to proxy depositor to be locked
    function deposit(uint256 _amount) public {
        ///Pull tokens
        underlying.safeTransferFrom(msg.sender, address(this), _amount);

        /// Approve and call proxy depositor to lock
        underlying.safeIncreaseAllowance(proxyDepositor, _amount);
        IProxyDepositor(proxyDepositor).depositToLock(_amount, msg.sender);
        

        emit Deposit(msg.sender, _amount);
    }

    /// @notice user stakes his proxyToken to become eligible for rewards
    /// claims rewards first to update accounting
    function stake(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        _claim(user);

        transferFrom(msg.sender, address(this), _amount);

        user.amount += _amount;
        stakedTotal += _amount;

        emit Stake(msg.sender, _amount);
    }

    /// @notice user unstakes his proxyToken and is no longer eligible for rewards.
    function unstake(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > _amount, "unstaking too much");
        _claim(user);
        user.amount -= _amount;
        stakedTotal -= _amount;

        transfer(msg.sender, _amount);

        emit Unstake(msg.sender, _amount);
    }

    function claim() external {
        UserInfo storage user = userInfo[msg.sender];
        _claim(user);
    }

    /// @notice calculate reward for a user
    /// Transfer those to the user
    function _claim(UserInfo storage user) internal {
        uint256 pending = user.amount * accRewardPerShare - user.rewardDebt;
        user.rewardDebt += pending;
        underlying.safeTransfer(msg.sender, pending);

        emit Claim(msg.sender, pending);
    }


    function updateRewards(uint256 rewards) external {
        _onlyOperator();

        accRewardPerShare += rewards / stakedTotal;
        lastUpdateTime = block.timestamp;
    }

    function _onlyOperator() internal view {
        require(msg.sender == operator, "!auth");
    }
}