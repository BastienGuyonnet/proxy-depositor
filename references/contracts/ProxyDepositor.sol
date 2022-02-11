pragma solidity 0.8.9;


	/**
	 * The purpose of smolVex is to streamline the deployment of a cvx like system
	 * for the sole purpose of maximizing LP rewards. Governance is turned to an afterthought
	 * most users do not care and most protocols do not use built in token governance but instead
	 * something like snapshot. That being said, perhaps leaving it open for voting ability is not a bad thing
	 * 
	 * Initially this project was not going to include handling for multitoken distro like with full crv gauges
	 * however with the impending release of solidly i think it warrants circulation
	 * 
	 * */


contract proxyDepositor {
	/**
	 * the proxy depositor has 2 major-overarching functions
	 * 1) Deposit and lock up the dex token into the ve-esque lockup
	 * 2) deposit LP tokens and keep track of the rewards emitted for each pool
	 * */

	address public immutable dexToken;
	address public wrapperToken; //perhaps this should be a proxy

	mapping (address => registeredStrategy) gaugeToStrategy;
	mapping (address => address) tokenToGauge;
	mapping (address => Rewards[]) gaugeToRewards;

	struct rewards{
		address rewardToken;
		uint entitlement;
	}

	struct registeredStrategy {
		address strategy;
		address wantToken;
		bool active;
	}

	function lockDexToken(uint amt) external returns (bool){
		require(msg.sender == wrapperToken, "!wrapper");
		_lockDexToken(amt)

	}

	function registerGauge(address _gauge, address _token, address[] rewards) external {

	}

	function updateGaugeRewards(address _gauge, address[] _rewards) external {
		require(msg.sender == maintainer || owner, "!authorized")


	}

	function deposit(uint amt, address token) external {

	}

	function withdrawFromGauge(uint amt, address gauge) external {
		require(msg.sender == gaugeToStrategy[gauge].strategy, "!strategy")
	}

	function _withdrawFromGauge(uint amt, address gauge) internal{

	}

	function retrieveRewards(address gauge, address ) public{

	}

	function getGaugeAndStrategyForToken(address token) public view returns (address gauge, address strategy){
		gauge = tokenToGauge[token];
		if(gaugeToStrategy[gauge].registeredStrategy.active == true){
			strategy = gaugeToStrategy[gauge];
		}else{
			strategy = address(0);
		}
	}
}