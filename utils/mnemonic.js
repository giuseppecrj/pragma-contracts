const fs = require("fs");

function mnemonic(defaultNetwork) {
  try {
    return fs.readFileSync("./mnemonic.txt").toString().trim();
  } catch (e) {
    if (defaultNetwork !== "localhost") {
      console.log(
        "☢️ WARNING: No mnemonic file created for a deploy account. Try `yarn run generate` and then `yarn run account`.",
      );
    }
  }
  return "";
}

async function account({ethers}, DEBUG = false) {
  const {hdkey} = require("ethereumjs-wallet");
  const bip39 = require("bip39");
  try {
    const mnemonic = fs.readFileSync("./mnemonic.txt").toString().trim();
    if (DEBUG) console.log("mnemonic", mnemonic);
    const seed = await bip39.mnemonicToSeed(mnemonic);
    if (DEBUG) console.log("seed", seed);
    const hdwallet = hdkey.fromMasterSeed(seed);
    const wallet_hdpath = "m/44'/60'/0'/0/";
    const account_index = 0;
    const fullPath = wallet_hdpath + account_index;
    if (DEBUG) console.log("fullPath", fullPath);
    const wallet = hdwallet.derivePath(fullPath).getWallet();
    const privateKey = "0x" + wallet.privateKey.toString("hex");
    if (DEBUG) console.log("privateKey", privateKey);
    const EthUtil = require("ethereumjs-util");
    const address =
      "0x" + EthUtil.privateToAddress(wallet.privateKey).toString("hex");

    const qrcode = require("qrcode-terminal");
    qrcode.generate(address);
    console.log("‍📬 Deployer Account is " + address);
    for (const n in config.networks) {
      try {
        const provider = new ethers.providers.JsonRpcProvider(
          config.networks[n].url,
        );
        const balance = await provider.getBalance(address);
        console.log(" -- " + n + " --  -- -- 📡 ");
        console.log("   balance: " + ethers.utils.formatEther(balance));
        console.log(
          "   nonce: " + (await provider.getTransactionCount(address)),
        );
      } catch (e) {
        if (DEBUG) {
          console.log(e);
        }
      }
    }
  } catch (err) {
    console.log(err);
    console.log(`--- Looks like there is no mnemonic file created yet.`);
    console.log(
      `--- Please run ${chalk.greenBright("yarn generate")} to create one`,
    );
  }
}

async function createBurner(DEBUG = false) {
  const bip39 = require("bip39");
  const {hdkey} = require("ethereumjs-wallet");

  const mnemonic = bip39.generateMnemonic();
  DEBUG && console.log("mnemonic", mnemonic);

  const seed = await bip39.mnemonicToSeed(mnemonic);
  DEBUG && console.log("seed", seed);

  const hdwallet = hdkey.fromMasterSeed(seed);
  const walletHdPath = "m/44'/60'/0'/0/";

  const accountIndex = 0;

  const fullPath = walletHdPath + accountIndex;
  DEBUG && console.log("fullPath", fullPath);

  const wallet = hdwallet.derivePath(fullPath).getWallet();
  const privateKey = "0x" + wallet.privateKey.toString("hex");

  DEBUG && console.log("privateKey", privateKey);

  const EthUtil = require("ethereumjs-util");
  const address =
    "0x" + EthUtil.privateToAddress(wallet.privateKey).toString("hex");

  console.log(
    "🔐 Account Generated as " + address + " and set as mnemonic in root",
  );

  console.log(
    "💬 Use 'yarn run account' to get more information about the deployment account.",
  );

  fs.writeFileSync(
    "./" + address + ".txt",
    `${mnemonic.toString()}\n${privateKey}`,
  );
  fs.writeFileSync("./mnemonic.txt", mnemonic.toString());
}

module.exports = {
  mnemonic,
  createBurner,
  account,
};
