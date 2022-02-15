// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./interfaces/IVoteEscrow.sol";
import "./interfaces/IProxyToken.sol";
import "./interaces/CErc20I.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ProxyDepositor is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    address public protocolToken; //protocol token that can be locked in exchange for voting power
    address public veProtocolToken //voteEscrow version of the protocol token
    address public proxyToken; //interest bearing wrapper token
    address[] public stakedTokens; //tokens that can be staked / supplied
    address public locker; //contract used to lock token

    //todo Though the voting part of the protocol should be the same accross the board,
    // the staking, lending of assets may differ. Hundred uses a compound style system,
    // whereas spirit uses sushi style masterchef, each with their own functions
    // Solve this by delegating this responsibility to another contract?
    address public masterChef; //contract handling pools and distributing rewards
    address public comptroller; //comptroller contract


    /// @notice Helpful constants
    uint256 MAX_LOCK_TIME = 4 * 365 * 24 * 3600; // 4 years

    /// @notice Roles
    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

    mapping (address => registeredStrategy) registeredStrategies;
    mapping (address => Rewards[]) gaugeToRewards; 
    mapping (address => address) tokenToPool;

    ///@notice Relevant information about the strategy
    struct strategyInfo {
        address strategy;
        address wantToken;
        uint256 rewards;
    }

    /**
     * @param _proxyToken token given in exchange to the protocol token (ex: Reaper Farm Proxy HND)
     * @param _locker contract to interact with to lock the protocol token (ex: veHND => 0x376020c5b0ba3fd603d7722381faa06da8078d8a)
     * @param _masterChef contract to interact with to stake tokens in pools and get rewards ()
     */
    constructor(address _proxyToken, address _locker, address _masterChef) {
        proxyToken = _proxyToken;
        locker = _locker;
        masterChef = _masterChef;
        protocolToken = IProxyToken(proxyToken).underlying();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // strategy wants to deposit tokens in rewarding pools, boosted
    // assumes the tokens have been transferred to this contracts, otherwise fetch them
    function depositToStake(address _token) public returns(bool){
        _onlyRegisteredStrategies();
        address pool = tokenToPool[_token];
        require(pool != address(0), "UNKNOWN TOKEN");
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeIncreaseAllowance(pool, tokenBalance);
        CErc20I(pool).mint(tokenBalance);
        return true;
    }

    // user wants to lock the tokens
    // assumes protocol tokens are transferred to this contract beforehand
    // deposit governance token (ex: HND) for proxy token and lock
    function depositToLock(uint256 _amount) public returns(bool){
        require(_amount != 0, "AMOUNT EQUAL 0");
        uint256 protocolTokenBal = IERC20(protocolToken).balanceOf(address(this));
        uint256 unlockTime = block.timestamp + MAX_LOCK_TIME;
        IERC20(locker).safeIncreaseAllowance(locker, protocolTokenBal);
        // If no protocol token is locked yet, a new lock needs to be created
        if(IVoteEscrow(locker).locked(address(this)).amount == 0) {
            _createLock(protocolTokenBal, unlockTime);
        } else {
            _increaseLock(protocolTokenBal, unlockTime);
        }
        return true;
    }

    function _createLock(uint256 _amount, uint256 _unlockTime) internal returns(bool) {
        IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
        IVoteEscrow(locker).create_lock(_amount, _unlockTime);
        return true;
    }

    function _increaseLock(uint256 _amount, uint256 _unlockTime) internal returns(bool) {
        IERC20(protocolToken).safeIncreaseAllowance(locker, _amount);
        IVoteEscrow(locker).increase_amount(_amount);
        IVoteEscrow(locker).increase_unlock_time(_unlockTime);
    }

    // user wants to retrieve his tokens
    function withdrawFromLock() public {
        //todo implement this or remove if we consider locked token to be eternally locked
        return;
    }

    //strategy comes to get the rewards -> out of the entered market for this strategy
    function retrieveRewards() public returns (bool){
        _onlyRegisteredStrategies();
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] = registeredStrategies[msg.sender].wantToken;
        comptroller.claimComp(address(this), tokens);
    }

    function _onlyRegisteredStrategies() internal {
        require(hasRole(STRATEGY, msg.sender), "ACCESS DENIED");
    }

    function addStrategy(address _strategy, address _want) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {

    }
}