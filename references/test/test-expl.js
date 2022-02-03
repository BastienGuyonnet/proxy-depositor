const hre = require("hardhat");
const chai = require("chai");
const { solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;
const wantAbi = require("../abi/bpt-a-late-quartet.json");

const moveTimeForward = async (seconds) => {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
}

describe("Vaults", () => {
    const wantAddress = "0xf3A602d30dcB723A74a0198313a7551FEacA7DAc"; // bpToken - A Late Quartet
    const rewardAddress = "0x10b620b2dbAC4Faa7D7FFD71Da486f5D44cd86f9"; // Liquid
    const wantHolderAddress = "0xf335947Fd2BB811cEa6fBce43847fcEff8Ad2e62"; // pray you don't have to change that, or buy some yourself
    const paymentRouterAddress = "0x603e60D22af05ff77FDCf05c063f582C40e55aae";
    const strategistAddress = "0x1E71AEE6081f62053123140aacC7a06021D77348";

    //Underlying tokens addresses
    const usdcAddress = "0x04068DA6C83AFCFA0e13ba15A6696662335D5B75";
    const wftmAddress = "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83";
    const wbtcAddress = "0x321162Cd933E2Be498Cd2267a90534A804051b11";
    const wethAddress = "0x74b23882a30290451A17c44f4F05243b6b58C76d";

    //Benefactors
    const rewardHolderAddress = "0x078E88E465f2a430399E319d57543A7A76E97668";

    // Masterchef and tools to get pending rewards
    const masterChefAddress = "0x6e2ad6527901c9664f016466b8DA1357a004db0f";
    const poolId = 31;

    let Vault;
    let Strategy;
    let Treasury;
    let Want;
    let PaymentRouter;
    let MasterChef;

    let vault;
    let strategy;
    let treasury;
    let paymentRouter;
    let masterChef;

    let want;
    let self;
    let selfAddress;
    let owner;
    let strategist;
    let rewardHolder;

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
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [strategistAddress],
        });
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [rewardHolderAddress],
        });
        self = await ethers.provider.getSigner(wantHolderAddress);
        strategist = await ethers.provider.getSigner(strategistAddress);
        rewardHolder = await ethers.provider.getSigner(rewardHolderAddress);
        selfAddress = await self.getAddress();

        // get artifacts
        Strategy = await ethers.getContractFactory("ReaperAutoCompound_LiquidV2_Beethoven");
        Vault = await ethers.getContractFactory("ReaperVaultv1_3");
        Treasury = await ethers.getContractFactory("ReaperTreasury");
        Want = await ethers.getContractFactory("Usdc");
        PaymentRouter = await ethers.getContractFactory("PaymentRouter");

        //deploy contracts
        treasury = await Treasury.deploy();
        // want = new ethers.Contract(wantAddress, wantAbi, self);
        want = await Want.attach(wantAddress);
        reward = await Want.attach(rewardAddress);
        paymentRouter = await PaymentRouter.attach(paymentRouterAddress);
        vault = await Vault.deploy(
            wantAddress,
            "A Late Quartet Beethoven-Liquid Crypt",
            "rf-LQUARTET",
            0,
            0,
            ethers.constants.MaxUint256
        );
        masterChef = await ethers.getContractAt("IMasterChefv2",masterChefAddress);

        // IMPORTANT : routes must be provided in the pool's own token order
        strategy = await Strategy.deploy(
            vault.address,
            [treasury.address, paymentRouterAddress],
            [strategistAddress],
            wantAddress,
            poolId
        );
        await strategy.deployed();
        await vault.initialize(strategy.address);
        await paymentRouter
            .connect(strategist)
            .addStrategy(strategy.address, [strategistAddress], [100]);
        
        await want
            .connect(self)
            .approve(vault.address, ethers.constants.MaxUint256);
    });

    describe("Deploying the vault and strategy", () => {
        it("should initiate a vault with a 0 balance", async () => {
            const totalBalance = await vault.balance();
            const availableBalance = await vault.available();
            const pricePerFullShare = await vault.getPricePerFullShare();

            expect(totalBalance).to.equal(ethers.constants.Zero);
            expect(availableBalance).to.equal(ethers.constants.Zero);
            expect(pricePerFullShare).to.equal(ethers.utils.parseEther("1"));
        });
    });

    describe("Vault Tests", () => {
        it("should allow deposits and account for them correctly", async () => {
            const userBalance = await want.balanceOf(selfAddress);
            const initialVaultBalance = await vault.balance();
            const depositAmount = userBalance.div(2);

            await vault.connect(self).deposit(depositAmount);
            const newVaultBalance = await vault.balance();
            const newUserBalance = await want.balanceOf(selfAddress);
            const deductedAmount = userBalance.sub(newUserBalance);

            console.log(`initialVaultBalance ${initialVaultBalance.toString()} = ethers.constants.Zero ${ethers.constants.Zero}`);
            console.log(`newVaultBalance ${newVaultBalance.toString()} = depositAmount ${depositAmount}`);
            console.log(`deductedAmount ${deductedAmount.toString()} = depositAmount ${depositAmount.toString()}`);
            expect(initialVaultBalance).to.equal(ethers.constants.Zero);
            expect(newVaultBalance).to.equal(depositAmount);
            expect(deductedAmount).to.equal(depositAmount);
        });

        it("should allow withdrawals", async () => {
            const userBalance = await want.balanceOf(selfAddress);
            const depositAmount = userBalance.div(2);
            await vault.connect(self).deposit(depositAmount);
      
            const withdrawAmount = depositAmount; // .div(4);
            await vault.connect(self).withdraw(withdrawAmount);
      
            const actualUserBalanceAfterWithdraw = await want.balanceOf(selfAddress);
            const expectedUserBalanceAfterWithdraw = userBalance
              .sub(depositAmount)
              .add(withdrawAmount);
            
            console.log(
                `actualUserBalanceAfterWithdraw ${actualUserBalanceAfterWithdraw} > expectedUserBalanceAfterWithdraw.mul(9950).div(10000) ${expectedUserBalanceAfterWithdraw.mul(9950).div(10000)}`
            );
            expect(actualUserBalanceAfterWithdraw).to.be.gte(
              expectedUserBalanceAfterWithdraw.mul(9950).div(10000)
            );
            console.log(
              `Withdraw fees paid is ${userBalance
                .sub(depositAmount)
                .add(withdrawAmount)
                .sub(actualUserBalanceAfterWithdraw)
                .mul(10000)
                .div(withdrawAmount)} basis points.`
            );
        });

        it("should provide yield", async () => {
            const timeToSkip = 60 * 60;
            const initialUserBalance = await want.balanceOf(selfAddress);
            const depositAmount = initialUserBalance;

            await vault.connect(self).deposit(depositAmount);
            const initialVaultBalance = await vault.balance();
      
            await strategy
              .connect(strategist)
              .updateHarvestLogCadence(timeToSkip / 2);
      
            const numHarvests = 5;
            // const benefactorRewardBalance = await reward.balanceOf(rewardHolderAddress);
            for (let i = 0; i < numHarvests; i++) {
              await moveTimeForward(timeToSkip);
              // await reward.connect(rewardHolder).transfer(strategy.address ,benefactorRewardBalance.div(6));
              console.log(`pending lqdr reward: ${await masterChef.pendingLqdr(poolId, strategy.address)}`);
              await strategy.harvest();
            }

            const finalVaultBalance = await vault.balance();
            expect(finalVaultBalance).to.be.gt(initialVaultBalance);
      
            const averageAPR = await strategy.averageAPRAcrossLastNHarvests(
              numHarvests - 1
            );
            console.log(
              `Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`
            );
        });

        it("should allow updating the strategy", async () => {
            const newStrategy = await Strategy.deploy(
                vault.address,
                [treasury.address, paymentRouterAddress],
                [strategistAddress],
                wantAddress,
                poolId
            );

            await vault.proposeStrat(newStrategy.address);
            await vault.upgradeStrat();

            const newVaultStrategyAddress = await vault.strategy();
            console.log(`newStrategy.address ${newStrategy.address} == newVaultStrategyAddress ${newVaultStrategyAddress}`);
            expect(newStrategy.address).to.be.equal(newVaultStrategyAddress);
            
        });
    });

    describe("Strategy Tests", () => {
        it("should be able to pause and then unpause", async () => {
            const userBalance = await want.balanceOf(selfAddress);
            const depositAmount = userBalance.div(4);
            await strategy.pause();
            await expect(vault.connect(self).deposit(depositAmount)).to.be.reverted;
            await strategy.unpause();
            await expect(vault.connect(self).deposit(depositAmount)).to.not.be.reverted;
        });

        it("should be able to panic", async () => {
            const userBalance = await want.balanceOf(selfAddress);
            const depositAmount = userBalance.div(4);
            await vault.connect(self).deposit(depositAmount);
            await expect(strategy.panic()).to.not.be.reverted;
            const vaultBalance = await vault.balance();
            const strategyBalance = await strategy.balanceOf();
            expect(vaultBalance).to.equal(strategyBalance);
        });
    });
});