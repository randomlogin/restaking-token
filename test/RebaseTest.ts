const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
import { prepareContracts, rebase } from "./test-helpers.ts";
import hre, { ethers, upgrades } from "hardhat";
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const stEthDepositAmount = ethers.parseEther("2");
const MyRSETHDepositAmount = ethers.parseEther("0.5");

describe("Rebasing:", function () {
  it("After rebase the totalSupply and user balances should increase", async function () {
    const { staker1, staker2, stEth, MyRSETH, LRTDepositPool } = await loadFixture(prepareContracts);
    const snapshotId = await hre.network.provider.request({ method: "evm_snapshot" });
    let receipt = await stEth.submit(staker1.address, { value: stEthDepositAmount });
    await receipt.wait();
    receipt = await stEth.connect(staker2).submit(staker2.address, { value: 2n * stEthDepositAmount });
    await receipt.wait();

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    let depositTx = await LRTDepositPool.depositAsset(
      stEth.target,
      MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );
    await depositTx.wait();

    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, 2n * MyRSETHDepositAmount);
    depositTx = await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      2n * MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );
    await depositTx.wait();

    let balance1Old = await MyRSETH.balanceOf(staker1.address);
    let balance2Old = await MyRSETH.balanceOf(staker2.address);
    let totalSupplyOld = await MyRSETH.totalSupply();

    await rebase();
    expect(await MyRSETH.balanceOf(staker1.address)).to.be.above(balance1Old);
    expect(await MyRSETH.balanceOf(staker2.address)).to.be.above(balance2Old);
    expect(await MyRSETH.totalSupply()).to.be.above(totalSupplyOld);
    await hre.network.provider.request({ method: "evm_revert", params: [snapshotId] });
  });
});
