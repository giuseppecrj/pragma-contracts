const {ethers, run, network} = require("hardhat");
const {name, symbol} = require("./constants");

async function main() {
  const [deployer] = await ethers.getSigners();

  /** Randomizer */
  const RandomizerFactory = await ethers.getContractFactory("BasicRandomizer");
  console.log("Deploying BasicRandomizer contract...");
  const randomizer = await RandomizerFactory.deploy();
  await randomizer.deployed();
  console.log("BasicRandomizer deployed to:", randomizer.address);

  /** Hub */
  const HubFactory = await ethers.getContractFactory("PragmaHub");
  console.log("Deploying PragmaHub contract...");
  const hub = await HubFactory.deploy(name, symbol, randomizer.address);
  await hub.deployed();
  console.log("PragmaHub deployed to:", hub.address);

  /** Minter */
  const Minter = await ethers.getContractFactory("PragmaFixedPriceV1");
  console.log("Deploying Minter contract...");
  const minter = await Minter.deploy(hub.address);
  console.log("PragmaHub deployed to:", minter.address);

  if (
    (network.config.chainId === 80001 || network.config.chainId === 137) &&
    process.env.POLYGONSCAN_API_KEY
  ) {
    console.log("Waiting for block confirmations");
    await hub.deployTransaction.wait(6);
    await verify(randomizer.address, []);
    await verify(hub.address, [name, symbol, randomizer.address]);
  }

  await hub
    .connect(deployer)
    .addMintWhitelisted(minter.address)
    .then(tx => tx.wait());
  console.log("Minter added to Hub whitelist");

  console.log(`
    Hub address: ${hub.address}
    Minter address: ${minter.address}
    Randomizer address: ${randomizer.address}
  `);
}

async function verify(contractAddress, args) {
  console.log("Verifying contract...");
  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: args,
    });
  } catch (error) {
    if (error.message.toLowerCase().includes("already verified")) {
      console.log("Already Verified");
    } else {
      console.log(error);
    }
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
