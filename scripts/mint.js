const {ethers} = require("hardhat");
const {minterContractAddress, projectId} = require("./constants");

async function main() {
  // const blockNum = await ethers.provider.getBlockNumber();
  // const block = await ethers.provider.getBlock(blockNum);

  // console.log(block);

  const [owner] = await ethers.getSigners();
  const minter = await ethers.getContractAt(
    "PragmaFixedPriceV1",
    minterContractAddress,
  );

  await minter
    .connect(owner)
    .purchase(projectId, {
      value: ethers.utils.parseEther("0.01"),
    })
    .then(txn => txn.wait());

  console.log("Token has been minted");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
