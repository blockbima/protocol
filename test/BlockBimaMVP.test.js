const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BlockBimaMVP", function () {
  let StableMock, stable, BlockBima, blockbima;
  let admin, lp1, lp2, user1;
  const initialSupply = ethers.utils.parseUnits("1000000", 18);

  beforeEach(async () => {
    [admin, lp1, lp2, user1, other] = await ethers.getSigners();
    // Deploy mock ERC20
    StableMock = await ethers.getContractFactory("ERC20Mock");
    stable = await StableMock.deploy("StableCoin", "STBL", admin.address, initialSupply);
    await stable.deployed();

    // Distribute tokens
    await stable.connect(admin).mint(lp1.address, ethers.utils.parseUnits("1000", 18));
    await stable.connect(admin).mint(lp2.address, ethers.utils.parseUnits("1000", 18));
    await stable.connect(admin).mint(user1.address, ethers.utils.parseUnits("500", 18));

    // Deploy BlockBimaMVP
    BlockBima = await ethers.getContractFactory("BlockBimaMVP");
    blockbima = await BlockBima.deploy(stable.address, admin.address);
    await blockbima.deployed();
  });

  it("initial state is correct", async () => {
    expect(await blockbima.capitalPool()).to.equal(0);
    expect(await blockbima.totalLPTokens()).to.equal(0);
    expect(await blockbima.paused()).to.equal(false);
    expect(await blockbima.nextPolicyId()).to.equal(1);
  });

  describe("LP deposits", () => {
    beforeEach(async () => {
      await stable.connect(lp1).approve(blockbima.address, ethers.utils.parseUnits("100", 18));
      await blockbima.connect(lp1).depositLP(ethers.utils.parseUnits("100", 18));
    });
    it("should update pool and mint tokens on first deposit", async () => {
      expect(await blockbima.capitalPool()).to.equal(ethers.utils.parseUnits("100", 18));
      expect(await blockbima.lpBalances(lp1.address)).to.equal(ethers.utils.parseUnits("100", 18));
      expect(await blockbima.totalLPTokens()).to.equal(ethers.utils.parseUnits("100", 18));
    });
    it("should mint proportional tokens on second deposit", async () => {
      await stable.connect(lp2).approve(blockbima.address, ethers.utils.parseUnits("50", 18));
      await blockbima.connect(lp2).depositLP(ethers.utils.parseUnits("50", 18));
      // Pool=150, totalLPTokens=150
      expect(await blockbima.capitalPool()).to.equal(ethers.utils.parseUnits("150", 18));
      expect(await blockbima.lpBalances(lp2.address)).to.equal(ethers.utils.parseUnits("50", 18));
      expect(await blockbima.totalLPTokens()).to.equal(ethers.utils.parseUnits("150", 18));
    });
  });

  describe("Policy creation and settlement flow", () => {
    beforeEach(async () => {
      // deposit funds so pool has capital
      await stable.connect(lp1).approve(blockbima.address, ethers.utils.parseUnits("200", 18));
      await blockbima.connect(lp1).depositLP(ethers.utils.parseUnits("200", 18));
      // approve policyholder
      await stable.connect(user1).approve(blockbima.address, ethers.utils.parseUnits("50", 18));
      // create a policy: premium 50, maxPayout 100, duration 1 second
      await blockbima.connect(user1).createPolicy(
        ethers.utils.parseUnits("50", 18),
        ethers.utils.parseUnits("100", 18),
        1,
        "TestRegion"
      );
    });

    it("policy stored correctly", async () => {
      const p = await blockbima.policies(1);
      expect(p.user).to.equal(user1.address);
      expect(p.premium).to.equal(ethers.utils.parseUnits("50", 18));
      expect(p.maxPayout).to.equal(ethers.utils.parseUnits("100", 18));
      expect(p.claimed).to.equal(false);
    });

    it("settlePolicies pays out correct amount and marks claimed", async () => {
      // increase time
      await ethers.provider.send("evm_increaseTime", [2]);
      await ethers.provider.send("evm_mine");
      // settle with 50% ratio
      await blockbima.connect(admin).settlePolicies([1], 5000);
      const p = await blockbima.policies(1);
      expect(p.claimed).to.equal(true);
      const expectedPayout = ethers.utils.parseUnits("100", 18).mul(5000).div(10000);
      expect(await stable.balanceOf(user1.address)).to.equal(expectedPayout);
    });
  });

  describe("Liquidity buffer and withdrawal", () => {
    beforeEach(async () => {
      await stable.connect(lp1).approve(blockbima.address, ethers.utils.parseUnits("100", 18));
      await blockbima.connect(lp1).depositLP(ethers.utils.parseUnits("100", 18));
      // reserveRatioBps = 3000 => reserved=30, available=70
    });
    it("withdraws only available liquidity", async () => {
      // withdraw full LP tokens
      await blockbima.connect(lp1).withdrawLP(ethers.utils.parseUnits("100", 18));
      // user should get 70
      expect(await stable.balanceOf(lp1.address)).to.equal(ethers.utils.parseUnits("1070", 18));
    });
    it("reverts if withdraw amount exceeds available", async () => {
      // try to withdraw more than available by depositing then modifying reserve
      await blockbima.connect(admin).setReserveRatio(10000);
      await expect(
        blockbima.connect(lp1).withdrawLP(ethers.utils.parseUnits("100", 18))
      ).to.be.revertedWith("Withdraw amount zero or exceeds available liquidity");
    });
  });

  describe("Pause functionality", () => {
    it("blocks operations when paused", async () => {
      await blockbima.connect(admin).pause();
      await expect(
        blockbima.connect(lp1).depositLP(1)
      ).to.be.revertedWith("Contract is paused");
      await blockbima.connect(admin).unpause();
      await stable.connect(lp1).approve(blockbima.address, 1);
      await blockbima.connect(lp1).depositLP(1);
    });
  });
});
