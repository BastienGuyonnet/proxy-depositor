const deployVault = async () => {
  const Vault = await ethers.getContractFactory("ReaperVaultv1_3");

  const wantAddress = "0xf3A602d30dcB723A74a0198313a7551FEacA7DAc";
  const vaultTokenName = "A Late Quartet Beethoven-Liquid Crypt";
  const vaultTokenSymbol = "rf-LQUARTET";
  const approvalDelay = 0;
  const depositFee = 0;
  const tvlCap = ethers.utils.parseEther("20000");

  const vault = await Vault.deploy(
    wantAddress,
    vaultTokenName,
    vaultTokenSymbol,
    approvalDelay,
    depositFee,
    tvlCap
  );

  await vault.deployed();
  console.log("Vault deployed to:", vault.address);
  return vault.address;
}

const deployStrategy = async (vaultAddress) => {
  const Strategy = await ethers.getContractFactory("ReaperAutoCompound_LiquidV2_Beethoven");
  const treasuryAddress = "0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b";
  const paymentSplitterAddress = "0x63cbd4134c2253041F370472c130e92daE4Ff174";
  const strategists = ["0x1E71AEE6081f62053123140aacC7a06021D77348","0x81876677843D00a7D792E1617459aC2E93202576","0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4"];
  const wantAddress = "0xf3A602d30dcB723A74a0198313a7551FEacA7DAc";
  const poolId = 31;

  const strategy = await Strategy.deploy(
    vaultAddress,
    [treasuryAddress,paymentSplitterAddress],
    strategists,
    wantAddress,
    poolId
  );
  await strategy.deployed();
  console.log("Strategy deployed to:", strategy.address);
  return strategy.address;
}

const initializeVault = async (vaultAddress, strategyAddress) => {
  const Vault = await ethers.getContractFactory("ReaperVaultv1_3");
  const vault = await Vault.attach(vaultAddress);
  await vault.initialize(strategyAddress);
  console.log("Vault initialized");
}

async function main() {
  const vaultAddress = await deployVault();
  // const strategyAddress = await deployStrategy(vaultAddress);
  // await initializeVault(vaultAddress, strategyAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
