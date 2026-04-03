const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  const tokenA = await MockERC20.deploy("Mock Token A", "TKA");
  await tokenA.waitForDeployment();

  const tokenB = await MockERC20.deploy("Mock Token B", "TKB");
  await tokenB.waitForDeployment();

  const OpenIntentBook = await hre.ethers.getContractFactory("OpenIntentBook");
  const book = await OpenIntentBook.deploy();
  await book.waitForDeployment();

  console.log("tokenA:", await tokenA.getAddress());
  console.log("tokenB:", await tokenB.getAddress());
  console.log("intentBook:", await book.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
