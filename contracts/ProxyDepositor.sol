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
    string constant WRONG_INPUT = "WRONG INPUT";
    string constant ACCESS_DENIED = "ACCESS DENIED";
    string constant WRONG_TOKEN = "WRONG TOKEN";
    string constant AMOUNT_EQUAL_ZERO = "AMOUNT = 0";
    string constant REDEEM_ERROR = "REDEEM ERROR";

    /// @notice Helpful constants
    uint256 constant MAX_LOCK_TIME = 4 * 365 * 24 * 3600; // 4 years
    uint256 constant WEEK = 7 * 24 * 3600;

    /// Time until tokens can be unlocked
    uint256 unlockTimeWeek;
    uint256 balanceToLock;

    /// @notice Roles
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

    /// @notice Variables used to split the rewards
    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public veProviderSplit = 1000;
    uint256 public permanentLockSplit = 500;
    uint256 public strategySplit = 8500;

    ///@notice informational mappings
    /// {registeredStrategies} - strategies that use the proxy depositor
    /// {strategyToReward} - returns the rewards associated to a strategy
    mapping (address => strategyInfo) public registeredStrategies;
    address[] public strategies;

    ///@notice Relevant information about the strategy
    struct strategyInfo {
        uint256 id;
        address wantToken;
        address pool;
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

    /// @notice Strategies will use this to deposit the tokens and get yield
    /// 
    function depositToStake(address _token) public returns (uint256) {
        _onlyRegisteredStrategies();

        // Get strategy info
        strategyInfo memory strategy = registeredStrategies[msg.sender]; 

        // Get pool and gauge for token
        address pool = strategy.pool;
        address gauge = strategy.gauge;

        // Enter market, mint cToken
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeIncreaseAllowance(pool, tokenBalance);
        CErc20I(pool).mint(tokenBalance);

        // Stake cToken into gauge
        uint256 cTokenBalance = IERC20(pool).balanceOf(address(this));
        IERC20(pool).safeIncreaseAllowance(gauge, cTokenBalance);
        ILiquidityGauge(gauge).deposit(cTokenBalance, address(this), false);

        return ILiquidityGauge(gauge).balanceOf(address(this));
    }

    // user wants to lock the tokens
    // deposit governance token (ex: HND) for proxy token and lock
    function depositToLock(uint256 amount, address user) public {
        IERC20(protocolToken).safeTransferFrom(proxyToken, address(this), amount);

        uint256 newUnlockTime = block.timestamp + MAX_LOCK_TIME;
        uint256 newUnlockTimeWeek = (newUnlockTime / WEEK) * WEEK;

        uint256 protocolTokenBal = IERC20(protocolToken).balanceOf(address(this));
        IERC20(locker).safeIncreaseAllowance(locker, protocolTokenBal);

        // If no protocol token is locked yet, a new lock needs to be created
        if(IVoteEscrow(locker).locked(address(this)).amount == 0) {
            _createLock(protocolTokenBal, newUnlockTimeWeek);
        } else {
            _increaseLock(protocolTokenBal, newUnlockTimeWeek);
        }

        // mint the proxy token, send to user
        // proxyToken to protocolToken is 1:1
        IProxyToken(proxyToken).mint(user, amount);
    }

    function _createLock(uint256 _amount, uint256 _unlockTimeWeek) internal {
        IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
        IVoteEscrow(locker).create_lock(_amount, _unlockTimeWeek);
        unlockTimeWeek = _unlockTimeWeek;
    }

    function _increaseLock(uint256 _amount, uint256 _unlockTimeWeek) internal {
        // Making sure the lock can be increased to this unlockTimeWeek
        // because the voteEscrow will revert if the previous lock ends the same week
        if(_unlockTimeWeek > unlockTimeWeek) {
            IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
            IVoteEscrow(locker).increase_amount(_amount);
            IVoteEscrow(locker).increase_unlock_time(_unlockTimeWeek);
            unlockTimeWeek = _unlockTimeWeek;
            balanceToLock = 0;
        } else {
            // This balance needs to stay in the contract
            // instead of being sent as reward
            balanceToLock += _amount;
        }
    }

    //todo current amount passed is expressed in gaugeToken
    function withdrawFromStake(address _token, uint256 amount) external {
        _onlyRegisteredStrategies();

        // Get strategy info
        strategyInfo memory strategy = registeredStrategies[msg.sender]; 

        // Get pool and gauge for token
        address pool = strategy.pool;
        address gauge = strategy.gauge;

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
        IERC20(_token).safeTransfer(msg.sender, tokenBal);
    }

    // strategy comes to get the rewards
    // on HND, this means getting the HND rewards, sending only a strategies'
    // share back to it, and up to a certain bonus
    function retrieveRewards() public {
        _onlyRegisteredStrategies();
        ITokenMinter(tokenMinter).mint(registeredStrategies[msg.sender].gauge);

        // Split and send to strat and voters, ignore balance that is meant to be locked
        uint256 protocolTokenBalance = IERC20(protocolToken).balanceOf(address(this)) - balanceToLock;
        uint256 providerRewards = protocolTokenBalance * veProviderSplit / PERCENT_DIVISOR;
        uint256 permanentLockRewards = protocolTokenBalance * permanentLockSplit / PERCENT_DIVISOR;
        uint256 strategyRewards = protocolTokenBalance * strategySplit / PERCENT_DIVISOR;

        IERC20(protocolToken).safeTransfer(msg.sender, strategyRewards);
        IERC20(protocolToken).safeTransfer(proxyToken, providerRewards); // assuming proxyToken manages handing out thos rewards to users
        _increaseLock(permanentLockRewards, MAX_LOCK_TIME);

        IProxyToken(proxyToken).updateRewards(providerRewards);
    }

    /// @notice change the voting allocation
    /// Both arrays need to be of same length
    /// Total of weights should add up to 100
    function setVoteForGaugeWeightsManually(address[] calldata _gauge_addrs, uint256[] calldata _user_weights) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), ACCESS_DENIED);
        require(_gauge_addrs.length == _user_weights.length, WRONG_INPUT);
        require(_gauge_addrs.length == strategies.length, WRONG_INPUT);

        uint256 total;
        for (uint256 i; i < _gauge_addrs.length; i++) {
            total = total + _user_weights[i];
            //set the vote
        }

        require(total == 100, WRONG_INPUT);
    }

    function _onlyRegisteredStrategies() internal view {
        require(registeredStrategies[msg.sender].wantToken != address(0), ACCESS_DENIED);
    }

    /// @notice register a new strategy if possible
    function addStrategy(address _strategy, address _wantToken, address _gauge, address _pool) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), ACCESS_DENIED);
        require(registeredStrategies[_strategy].wantToken == address(0), WRONG_INPUT);
        strategyInfo memory strategy = strategyInfo(strategies.length, _wantToken, _gauge, _pool);
        registeredStrategies[_strategy] = strategy;
        strategies.push(_strategy);
    }

    /// @notice Check that the address is a strategy, remove it from the strategies array
    /// assumes the strategy will check it has retrieved its funds
    function removeStrategy(address _strategy) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), ACCESS_DENIED);
        require(registeredStrategies[_strategy].wantToken != address(0), WRONG_INPUT);
        strategies[registeredStrategies[_strategy].id] = strategies[strategies.length - 1];
        strategies.pop();
        delete registeredStrategies[_strategy];
    }

    /// @notice How to allocate rewards
    function setRewardSplit(uint256 _veProviderSplit, uint256 _permanentLockSplit, uint256 _strategySplit) external {
        require(hasRole(STRATEGIST, msg.sender), ACCESS_DENIED);
        require(_veProviderSplit + _permanentLockSplit + _strategySplit == PERCENT_DIVISOR, WRONG_INPUT);
        veProviderSplit = _veProviderSplit;
        permanentLockSplit = _permanentLockSplit;
        strategySplit = _strategySplit;
    }
}