const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("NFT", async function () {
  it("Should deploy the contract, mint a token, and resolve to the right URI", async () => {
    const URI = "ipfs://QmWJBNeQAm9Rh4YaW8GFRnSgwa4dN889VKm9poc2DQPBkv";
    const [account] = await ethers.getSigners();
    console.log(account.address);

    const NFT = await ethers.getContractFactory("MyNFT");
    const nft = await NFT.deploy();
    await nft.deployed();

    await nft.mint(account.address, URI);

    console.log(await nft.tokenURI(1));

    expect(await nft.tokenURI(1)).to.equal(URI);
  });
});
