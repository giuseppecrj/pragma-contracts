const {ethers, run, network} = require("hardhat");
const fs = require("fs");

const {
  hubContractAddress,
  minterContractAddress,
  dutchMinterContractAddress,
  randomizerAddress,
  name,
  symbol,
} = require("./constants");

async function main() {
  if (
    (network.config.chainId === 80001 || network.config.chainId === 137) &&
    process.env.POLYGONSCAN_API_KEY
  ) {
    console.log("Waiting for block confirmations");
    // await verify(randomizerAddress, []);
    // await verify(minterContractAddress, [hubContractAddress]);
    // await verify(dutchMinterContractAddress, [hubContractAddress]);
    // await verify(hubContractAddress, [name, symbol, randomizerAddress]);
  }
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
