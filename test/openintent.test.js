const { expect } = require("chai");
const { ethers } = require("hardhat");

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

describe("OpenIntentBook demo", function () {
  it("posts intent, escrows tokenIn, accepts bids, finalizes winner", async function () {
    const [maker, solver1, solver2] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockERC20.deploy("Mock Token A", "TKA");
    await tokenA.waitForDeployment();
    const tokenB = await MockERC20.deploy("Mock Token B", "TKB");
    await tokenB.waitForDeployment();

    const OpenIntentBook = await ethers.getContractFactory("OpenIntentBook");
    const book = await OpenIntentBook.deploy();
    await book.waitForDeployment();

    const amountIn = ethers.parseUnits("10", 18);
    const minOut = ethers.parseUnits("9", 18);

    // mint
    await tokenA.mint(maker.address, amountIn);
    await tokenB.mint(solver1.address, ethers.parseUnits("100", 18));
    await tokenB.mint(solver2.address, ethers.parseUnits("100", 18));

    const chainId = (await ethers.provider.getNetwork()).chainId;
    const tokenAAddr = await tokenA.getAddress();
    const tokenBAddr = await tokenB.getAddress();
    const bookAddr = await book.getAddress();

    const intent = {
      maker: maker.address,
      tokenIn: tokenAAddr,
      tokenOut: tokenBAddr,
      amountIn,
      minAmountOut: minOut,
      deadline: BigInt(nowSeconds() + 60),
      nonce: 1n,
    };

    const domain = {
      name: "OpenIntent Protocol",
      version: "0.1",
      chainId,
      verifyingContract: bookAddr,
    };

    const types = {
      Intent: [
        { name: "maker", type: "address" },
        { name: "tokenIn", type: "address" },
        { name: "tokenOut", type: "address" },
        { name: "amountIn", type: "uint256" },
        { name: "minAmountOut", type: "uint256" },
        { name: "deadline", type: "uint64" },
        { name: "nonce", type: "uint256" },
      ],
    };

    const sig = await maker.signTypedData(domain, types, intent);

    await book.postIntent(intent, sig);

    // escrow
    await tokenA.connect(maker).approve(bookAddr, amountIn);
    await book.connect(maker).escrow(intent);

    // bids
    await tokenB.connect(solver1).approve(bookAddr, ethers.parseUnits("100", 18));
    await tokenB.connect(solver2).approve(bookAddr, ethers.parseUnits("100", 18));

    await book
      .connect(solver1)
      .submitBid(intent, ethers.parseUnits("9.5", 18), { value: ethers.parseEther("0.01") });
    await book
      .connect(solver2)
      .submitBid(intent, ethers.parseUnits("10.0", 18), { value: ethers.parseEther("0.02") });

    // fast-forward after deadline
    await ethers.provider.send("evm_increaseTime", [70]);
    await ethers.provider.send("evm_mine", []);

    const makerB0 = await tokenB.balanceOf(maker.address);
    const solver2A0 = await tokenA.balanceOf(solver2.address);

    await book.finalize(intent);

    const makerB1 = await tokenB.balanceOf(maker.address);
    const solver2A1 = await tokenA.balanceOf(solver2.address);

    expect(makerB1 - makerB0).to.equal(ethers.parseUnits("10.0", 18));
    expect(solver2A1 - solver2A0).to.equal(amountIn);
  });
});
