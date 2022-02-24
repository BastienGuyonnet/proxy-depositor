const hre = require("hardhat");
const chai = require("chai");
const { solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;

// Custom utility function

const moveTimeForward = async (seconds) => {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
}

// Registry
/// Tokens
const protocolTokenAddress = "0x10010078a54396F62c96dF8532dc2B4847d47ED3"; // HND
const veProtocolTokenAddress= "0x376020c5B0ba3Fd603d7722381fAA06DA8078d8a" // veHND
const WantTokenAddress = "0x04068DA6C83AFCFA0e13ba15A6696662335D5B75"; // usdc
const CoumpoundWantTokenAddress = "0x243e33aa7f6787154a8e59d3c27a66db3f8818ee";// hUSDC
const GaugeWantTokenAddress = "0x110614276F7b9Ae8586a1C1D9Bc079771e2CE8cF";// hUSDC gauge

/// Contracts
const comptroller = "0x0F390559F258eB8591C8e31Cf0905E97cf36ACE2";
const tokenMinter = "0x42b458056f887fd665ed6f160a59afe932e1f559";
const gaugeController = "0xb1c4426C86082D91a6c097fC588E5D5d8dD1f5a8";

/// EOA
const strategistAddress = "0x1E71AEE6081f62053123140aacC7a06021D77348";
const wantHolderAddress = "0xA9497FD9D1dD0d00DE1Bf988E0e36794848900F9";

describe('Proxy-Depositor', () => {
    // ContractFactories
    /// Tested
    let ProxyDepositor;
    let ProxyToken;

    /// Already exists
    let ProtocolToken;
    let WantToken;
    let CompoundWantToken;
    let GaugeWantToken;

    // Contracts
    /// Tested
    let proxyDepositor;
    let proxyToken;

    /// Already exists
    let protocolToken;
    let wantToken;
    let compoundWantToken;
    let gaugeWantToken;

    // Accounts and more
    let self;
    let selfAddress;
    let owner;
    
    beforeEach( async () => {
        //reset network
        await network.provider.request({
            method: "hardhat_reset",
            params: [
                {
                    forking: {
                        jsonRpcUrl: "https://late-wild-fire.fantom.quiknode.pro/",
                        // jsonRpcUrl: "https://rpc.ftm.tools/",
                    },
                },
            ],
        });

        // get signers
        [owner] = await ethers.getSigners();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [wantHolderAddress],
        });
        self = await ethers.provider.getSigner(wantHolderAddress);
        selfAddress = await self.getAddress();
        console.log("selfAddress: ", selfAddress);
        console.log("owner: ", owner.address);

        // get artifacts
        ProxyDepositor = await ethers.getContractFactory("ProxyDepositor");
        WantToken = await ethers.getContractFactory("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20");
        ProtocolToken = await ethers.getContractFactory("Hundred");
        ProxyToken = await ethers.getContractFactory("ProxyToken");

        // deploy
        proxyToken = await ProxyToken.deploy(protocolTokenAddress);
        proxyDepositor = await ProxyDepositor.deploy(proxyToken.address, veProtocolTokenAddress, gaugeController, tokenMinter);
        wantToken = await WantToken.attach(WantTokenAddress);
        compoundWantToken = await WantToken.attach(CoumpoundWantTokenAddress);
        gaugeWantToken = await WantToken.attach(GaugeWantTokenAddress);

        // authorize the user as a strategy
        await proxyDepositor.connect(owner).addStrategy(selfAddress, WantTokenAddress, GaugeWantTokenAddress);
        await proxyDepositor.connect(owner).setTokenToPool(WantTokenAddress, CoumpoundWantTokenAddress);
        await proxyDepositor.connect(owner).setTokenToGauge(WantTokenAddress, GaugeWantTokenAddress);
    });

    describe("ProxyToken and ProxyDepositor tests", () => {
        it("should allow deposits and withdraws of usdc", async () => {
            const userBalance = await wantToken.balanceOf(selfAddress);
            const depositAmount = userBalance.div(5);
            console.log("depositAmount: ", depositAmount);
            const initialProxyDepositorGBal = await gaugeWantToken.balanceOf(proxyDepositor.address);
            console.log("initialProxyDepositorGBal: ", initialProxyDepositorGBal);
            await wantToken.connect(self).transfer(proxyDepositor.address, depositAmount);
            await proxyDepositor.connect(self).depositToStake(WantTokenAddress);
            
            const finalProxyDepositorGBal = await gaugeWantToken.balanceOf(proxyDepositor.address);
            console.log("finalProxyDepositorGBal: ", finalProxyDepositorGBal);

            await proxyDepositor.connect(self).withdrawFromStake(WantTokenAddress, finalProxyDepositorGBal);
            const afterUserBalance = await wantToken.balanceOf(selfAddress);
            console.log(`userBalance: ${userBalance} and afterUserBalance: ${afterUserBalance}`);
        });
    });
});