const {expect} = require("chai");
const {ethers} = require("hardhat");
const fs = require("fs");

async function mineNBlocks(n) {
  for (let index = 0; index < n; index++) {
    await ethers.provider.send("evm_mine");
  }
}

function getBalance(_address) {
  return ethers.provider.getBalance(_address);
}

describe("PragmaHub", function () {
  const name = "Non-Fungible Token";
  const symbol = "NFT";
  const pricePerTokenInWei = ethers.utils.parseEther("0.01");
  const data = {};
  let projectId;

  beforeEach(async () => {
    const [owner, newOwner, artist, additional, g] = await ethers.getSigners();
    data.accounts = {owner, newOwner, artist, additional, g};

    const Randomizer = await ethers.getContractFactory("BasicRandomizer");
    data.randomizer = await Randomizer.deploy();

    const PragmaHub = await ethers.getContractFactory("PragmaHub");
    data.hub = await PragmaHub.connect(g).deploy(
      name,
      symbol,
      data.randomizer.address,
    );

    const PragmaFixedPriceV1 = await ethers.getContractFactory(
      "PragmaFixedPriceV1",
    );
    data.minter = await PragmaFixedPriceV1.connect(g).deploy(data.hub.address);

    const script = await fs
      .readFileSync(`${__dirname}/../scripts/libs/main.min.js`)
      .toString();

    /**
     * Minter
     */
    await data.hub.connect(g).addMintWhitelisted(data.minter.address);

    /**
     * Create Test Project
     */

    // get project id
    projectId = await data.hub
      .connect(g)
      .nextProjectId()
      .then(t => t.toString());

    // create test project
    await data.hub
      .connect(g)
      .addProject(`Test Project ${projectId}`, artist.address)
      .then(tx => tx.wait());

    // publish project
    await data.hub
      .connect(g)
      .publish(
        projectId,
        "This is the project description",
        "Giuseppe Rodriguez",
        "https://giuseppecrj.com",
        "CC BY-NC 4.0",
        "https://token.pragma.art/",
      );

    // update the max mints of a project
    await data.hub.connect(artist).updateProjectMaxMints(projectId, 15);

    // unpause project
    await data.hub.connect(artist).toggleProjectIsPaused(projectId);

    // add js
    await data.hub.connect(artist).addProjectScript(projectId, script);

    // update minter max mints
    await data.minter.connect(g).setProjectMaxMints(projectId);

    // set the price
    await data.minter
      .connect(artist)
      .updatePricePerTokenInWei(projectId, pricePerTokenInWei);
  });

  it("Should return a random value", async () => {
    expect(1).to.equal(1);
    await mineNBlocks(4);
    expect(await data.randomizer.value()).to.equal(
      await data.randomizer.value(),
    );
  });

  it("should purchase a token", async () => {
    await data.minter.connect(data.accounts.newOwner).purchase(projectId, {
      value: pricePerTokenInWei,
    });

    const receipt = await data.minter
      .connect(data.accounts.newOwner)
      .purchase(projectId, {
        value: pricePerTokenInWei,
      })
      .then(txn => txn.wait());

    const tokenId = parseInt(receipt.logs[0].topics[3]);
    const balance = await data.hub
      .balanceOf(data.accounts.newOwner.address)
      .then(txn => txn.toString());

    expect(+balance).to.equal(2);
    expect(tokenId).to.equal(1);
  });

  it("reverts if max mints are reached", async () => {
    let bal1 = await getBalance(data.accounts.newOwner.address);

    for (let i = 0; i < 15; i++) {
      await data.minter.connect(data.accounts.newOwner).purchase(projectId, {
        value: pricePerTokenInWei,
      });
    }

    let bal2 = await getBalance(data.accounts.newOwner.address);

    await expect(bal2.lt(bal1)).to.be.true;

    await expect(
      data.minter.connect(data.accounts.newOwner).purchase(projectId, {
        value: pricePerTokenInWei,
      }),
    ).to.be.revertedWith("MaxMintsReached()");
  });

  it("should return project information", async () => {
    console.log(await data.hub.projectDetails(projectId));
  });

  it("should set a new token uri", async () => {
    await data.minter.connect(data.accounts.owner).purchase(projectId, {
      value: pricePerTokenInWei,
    });

    const receipt = await data.minter
      .connect(data.accounts.owner)
      .purchase(projectId, {
        value: pricePerTokenInWei,
      })
      .then(v => v.wait());

    const tokenId = parseInt(receipt.logs[0].topics[3]);

    await data.hub
      .connect(data.accounts.g)
      .updateProjectBaseURI(projectId, "https://cdn.com/");

    await data.hub
      .connect(data.accounts.artist)
      .updateProjectTokenURI(projectId, tokenId, "ipfs://hash");

    expect(await data.hub.tokenURI(0)).to.equal("https://cdn.com/0");
    expect(await data.hub.tokenURI(tokenId)).to.equal("ipfs://hash");
  });
});
