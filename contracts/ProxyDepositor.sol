// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "hardhat/console.sol";

import "./interfaces/IVoteEscrow.sol";
import "./interfaces/IProxyToken.sol";
import "./interfaces/ITokenMinter.sol";
import "./interfaces/ILiquidityGauge.sol";
import "./interfaces/CErc20I.sol";
import "./interfaces/IComptroller.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract ProxyDepositor is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    address public protocolToken; //protocol token that can be locked in exchange for voting power
    address public veProtocolToken; //voteEscrow version of the protocol token
    address public proxyToken; //interest bearing wrapper token
    address[] public stakedTokens; //tokens that can be staked / supplied
    address public locker; //contract used to lock token
    address public tokenMinter;

    //todo Though the voting part of the protocol should be the same accross the board,
    // the staking, lending of assets may differ. Hundred uses a compound style system,
    // whereas spirit uses sushi style masterchef, each with their own functions
    // Solve this by delegating this responsibility to another contract?
    address public masterChef; //contract handling pools and distributing rewards
    address public comptroller; //comptroller contract

    /// @notice Error messages
    string constant ACCESS_DENIED = "ACCESS DENIED";
    string constant WRONG_TOKEN = "WRONG TOKEN";
    string constant AMOUNT_EQUAL_ZERO = "AMOUNT = 0";
    string constant REDEEM_ERROR = "REDEEM ERROR";

    /// @notice Helpful constants
    uint256 constant MAX_LOCK_TIME = 4 * 365 * 24 * 3600; // 4 years

    /// @notice Roles
    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

    ///@notice informational mappings
    /// {registeredStrategies} - strategies that use the proxy depositor
    /// {strategyToReward} - returns the rewards associated to a strategy
    /// {tokenToPool} - returns the contract where token can be supplied and boosted
    /// {tokenToGauge} - returns the contract where cToken can be staked
    mapping (address => strategyInfo) registeredStrategies;
    mapping (address => rewards[]) strategyToReward;
    mapping (address => address) tokenToPool;
    mapping (address => address) tokenToGauge;

    ///@notice Relevant information about the strategy
    struct strategyInfo {
        address strategy;// yeah, that's weird
        address wantToken;
        address gauge;
    }

    ///@notice reward model for a strategy
    struct rewards {
        address rewardToken;
        uint256 percentage;
    }

    /**
     * @param _proxyToken token given in exchange to the protocol token (ex: Reaper Farm Proxy HND)
     * @param _locker contract to interact with to lock the protocol token (ex: veHND => 0x376020c5b0ba3fd603d7722381faa06da8078d8a)
     * @param _masterChef contract to interact with to stake tokens in pools and get rewards ()
     */
    constructor(address _proxyToken, address _locker, address _masterChef, address _tokenMinter) {
        proxyToken = _proxyToken;
        locker = _locker;
        masterChef = _masterChef;
        tokenMinter = _tokenMinter;
        protocolToken = IProxyToken(proxyToken).underlying();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGIST, msg.sender);
        console.log(msg.sender);
    }

    // strategy wants to deposit tokens in rewarding pools, boosted
    // assumes the tokens have been transferred to this contracts, otherwise fetch them
    function depositToStake(address _token) public {
        _onlyRegisteredStrategies();

        // Get pool and gauge for token
        address pool = tokenToPool[_token];
        address gauge = tokenToGauge[_token];
        require(pool != address(0) && gauge != address(0), WRONG_TOKEN);

        // Enter market, mint cToken
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeIncreaseAllowance(pool, tokenBalance);
        CErc20I(pool).mint(tokenBalance);

        // Stake cToken into gauge
        uint256 cTokenBalance = IERC20(pool).balanceOf(address(this));
        IERC20(pool).safeIncreaseAllowance(gauge, cTokenBalance);
        ILiquidityGauge(gauge).deposit(cTokenBalance, address(this), false);
    }

    // user wants to lock the tokens
    // assumes protocol tokens are transferred to this contract beforehand
    // deposit governance token (ex: HND) for proxy token and lock
    function depositToLock(uint256 _amount) public {
        require(_amount != 0, AMOUNT_EQUAL_ZERO);
        uint256 protocolTokenBal = IERC20(protocolToken).balanceOf(address(this));
        uint256 unlockTime = block.timestamp + MAX_LOCK_TIME;
        IERC20(locker).safeIncreaseAllowance(locker, protocolTokenBal);
        // If no protocol token is locked yet, a new lock needs to be created
        if(IVoteEscrow(locker).locked(address(this)).amount == 0) {
            _createLock(protocolTokenBal, unlockTime);
        } else {
            _increaseLock(protocolTokenBal, unlockTime);
        }
    }

    function _createLock(uint256 _amount, uint256 _unlockTime) internal {
        IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
        IVoteEscrow(locker).create_lock(_amount, _unlockTime);
    }

    function _increaseLock(uint256 _amount, uint256 _unlockTime) internal {
        IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
        IVoteEscrow(locker).increase_amount(_amount);
        IVoteEscrow(locker).increase_unlock_time(_unlockTime);
    }

    //todo current amount passed is expressend in gaugeToken
    //todo should I rework this so that a token amount is passed in 
    function withdrawFromStake(address _token, uint256 amount) external {
        _onlyRegisteredStrategies();

        // Get pool and gauge for token
        address pool = tokenToPool[_token];
        address gauge = tokenToGauge[_token];
        require(pool != address(0) && gauge != address(0), WRONG_TOKEN);

        // use gToken to get cToken
        uint256 amountToWithdraw = Math.min(ILiquidityGauge(gauge).balanceOf(address(this)),amount);
        ILiquidityGauge(gauge).withdraw(amountToWithdraw, true);

        // use cToken to get token
        uint256 poolTokenAmountToWithdraw = IERC20(pool).balanceOf(address(this));
        uint256 poolExchangeRate = CTokenI(pool).exchangeRateCurrent();
        uint256 tokenAmountToWithdraw = poolExchangeRate * poolTokenAmountToWithdraw;
        uint256 balanceOfUnderlying = CTokenI(pool).balanceOfUnderlying(address(this));
        tokenAmountToWithdraw = Math.min(tokenAmountToWithdraw, balanceOfUnderlying);
        require(CErc20I(pool).redeemUnderlying(tokenAmountToWithdraw) == 0, REDEEM_ERROR);

        // send all token of the depositor to the strategy
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        console.log("tokenBal :", tokenBal);
        IERC20(_token).safeTransfer(msg.sender, tokenBal);
    }

    // user wants to retrieve his tokens
    function withdrawFromLock() public {
        //todo implement this or remove if we consider locked token to be eternally locked
        return;
    }

    // strategy comes to get the rewards
    // on HND, this means getting the HND rewards, sending only a strategies'
    // share back to it, and up to aa certain bonus
    function retrieveRewards() public {
        _onlyRegisteredStrategies();
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] = CErc20I(registeredStrategies[msg.sender].wantToken);
        ITokenMinter(tokenMinter).mint(registeredStrategies[msg.sender].gauge);

        // Split and send to strat and voters
    }

    function voteForGaugeWeight(address _gauge_addr, uint256 _user_weight) external {
        //todo decide how to implement this
        //  users may choose
        //  or, we do
    }

    function _onlyRegisteredStrategies() internal {
        require(registeredStrategies[msg.sender].strategy == msg.sender, ACCESS_DENIED);
    }

    function addStrategy(address _strategy, address _wantToken, address _gauge) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), ACCESS_DENIED);
        strategyInfo memory strategy = strategyInfo(_strategy, _wantToken, _gauge);
        registeredStrategies[_strategy] = strategy;
    }

    function setTokenToGauge(address _token, address _gauge) external {
        require(hasRole(STRATEGIST, msg.sender), ACCESS_DENIED);
        tokenToGauge[_token] = _gauge;
    }

    function setTokenToPool(address _token, address _pool) external {
        require(hasRole(STRATEGIST, msg.sender), ACCESS_DENIED);
        tokenToPool[_token] = _pool;
    }
}