const {ethers} = require("hardhat");
const fs = require("fs");
const {hubContractAddress, minterContractAddress} = require("./constants");

const projectName = "Genesis";
const pricePerTokenInWei = ethers.utils.parseEther("0.01");
const data = {};

async function main() {
  const script = await fs
    .readFileSync(`${__dirname}/libs/main.min.js`)
    .toString();

  const [g] = await ethers.getSigners();
  data.accounts = {g};

  data.hub = await ethers.getContractAt("PragmaHub", hubContractAddress);
  data.minter = await ethers.getContractAt(
    "PragmaFixedPriceV1",
    minterContractAddress,
  );

  const projectId = await data.hub
    .connect(g)
    .nextProjectId()
    .then(t => t.toString());

  await data.hub
    .connect(g)
    .addProject(projectName, g.address)
    .then(tx => tx.wait());

  console.log("Project has been created");

  await data.hub
    .connect(g)
    .toggleProjectIsActive(projectId)
    .then(tx => tx.wait());

  console.log("Project has been activated");

  await data.hub
    .connect(g)
    .updateProjectMaxMints(projectId, 100)
    .then(tx => tx.wait());

  console.log("Project max mints have been updated");

  await data.hub
    .connect(g)
    .toggleProjectIsPaused(projectId)
    .then(tx => tx.wait());

  console.log("Project has been unpaused");

  await data.hub
    .connect(g)
    .addProjectScript(projectId, script)
    .then(tx => tx.wait());

  console.log("Project script has been added");

  await data.minter
    .connect(g)
    .setProjectMaxMints(projectId)
    .then(tx => tx.wait());

  console.log("Minter max mints have been set");

  await data.minter
    .connect(g)
    .updatePricePerTokenInWei(projectId, pricePerTokenInWei)
    .then(tx => tx.wait());

  console.log("Minter price has been set");

  await data.hub
    .connect(g)
    .updateProjectDescription(projectId, "This is our second collection")
    .then(tx => tx.wait());

  console.log("Project description has been updated");

  await data.hub
    .connect(g)
    .updateProjectArtistName(projectId, "0xG")
    .then(tx => tx.wait());

  console.log("Project artist has been updated");

  await data.hub
    .connect(g)
    .updateProjectWebsite(projectId, "https://pragma.art/")
    .then(tx => tx.wait());

  console.log("Project website has been updated");

  await data.hub
    .connect(g)
    .updateProjectBaseURI(projectId, "https://token.pragma.art/")
    .then(tx => tx.wait());

  console.log("Project base uri has been updated");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
