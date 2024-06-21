const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
import hre, { ethers, upgrades } from "hardhat";
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
import { prepareContracts, rebase } from "./test-helpers";

const operator = "0x4cd2086e1d708e65db5d4f5712a9ca46ed4bbd0a";
const amountToWithdraw = 25000000n;
const accuracyDelta = 100n;
const stEthDepositAmount = ethers.parseEther("2");
const MyRSETHDepositAmount = ethers.parseEther("0.5");

describe("Deposits:", function () {
  it("Should deposit and withdraw", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    await stEth.submit(staker1.address, { value: 10n * stEthDepositAmount });
    await stEth.connect(staker2).submit(staker2.address, { value: 10n * stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    await LRTDepositPool.depositAsset(stEth.target, MyRSETHDepositAmount, minimumAmountOfRSETHForDeposit, "");

    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, 2n * MyRSETHDepositAmount);
    await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      2n * MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );

    let stEthBalanceBefore = await stEth.balanceOf(staker1.address);
    let rsEthBalanceBefore = await MyRSETH.balanceOf(staker1.address);

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);
    let shares = await strategy.underlyingToSharesView(amountToWithdraw);

    let nonce = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);
    let receipt = await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    await receipt.wait();
    let withdrawalBlock = receipt.blockNumber;

    await LRTDepositPool.connect(staker2).initiateWithdrawal.staticCall(stEth.target, amountToWithdraw);

    let stEthBalanceAfter = await stEth.balanceOf(staker1.address);
    let rsEthBalanceAfter = await MyRSETH.balanceOf(staker1.address);

    expect(stEthBalanceAfter - stEthBalanceAfter).to.be.below(accuracyDelta);
    expect(rsEthBalanceAfter - rsEthBalanceBefore + amountToWithdraw).to.be.below(accuracyDelta);

    const blocksToMine = await delegationManager.getWithdrawalDelay([strategy]);
    await mine(blocksToMine);

    await LRTDepositPool.completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce, withdrawalBlock, [strategy], [shares]],
      stEth.target,
    );
    stEthBalanceAfter = await stEth.balanceOf(staker1.address);
    rsEthBalanceAfter = await MyRSETH.balanceOf(staker1.address);
    expect(stEthBalanceAfter - stEthBalanceBefore - amountToWithdraw).to.be.below(accuracyDelta);
    expect(rsEthBalanceAfter - rsEthBalanceBefore).to.be.below(accuracyDelta);
  });

  it("Balance of a user should not change when the other user withdraws", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    await stEth.submit(staker1.address, { value: stEthDepositAmount });
    await stEth.connect(staker2).submit(staker2.address, { value: 2n * stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    await LRTDepositPool.depositAsset(stEth.target, MyRSETHDepositAmount, minimumAmountOfRSETHForDeposit, "");

    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, 2n * MyRSETHDepositAmount);
    await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      2n * MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );

    let balance1Old = await MyRSETH.balanceOf(staker1.address);
    let balance2Old = await MyRSETH.balanceOf(staker2.address);
    let totalSupplyOld = await MyRSETH.totalSupply();

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);

    let bal1 = await MyRSETH.balanceOf(staker1.address);
    let bal2 = await MyRSETH.balanceOf(staker2.address);
    let tot = await MyRSETH.totalSupply();

    await LRTDepositPool.connect(staker2).initiateWithdrawal(stEth.target, amountToWithdraw);

    let bal1new = await MyRSETH.balanceOf(staker1.address);
    let bal2new = await MyRSETH.balanceOf(staker2.address);
    let totnew = await MyRSETH.totalSupply();

    expect(bal1new - bal1).to.be.below(accuracyDelta);
    expect(bal2new - bal2 + amountToWithdraw).to.be.below(accuracyDelta);
    expect(totnew - tot + amountToWithdraw).to.be.below(accuracyDelta);
  });
  it("After rebase, deposits and withdraws should mint and burn correct values", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    const snapshotId = await hre.network.provider.request({ method: "evm_snapshot" });

    await stEth.submit(staker1.address, { value: stEthDepositAmount });
    await stEth.connect(staker2).submit(staker2.address, { value: 2n * stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    let depositTx = await LRTDepositPool.depositAsset(
      stEth.target,
      MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );
    await depositTx.wait();

    let balance1Old = await MyRSETH.balanceOf(staker1.address);
    let totalSupplyOld = await MyRSETH.totalSupply();

    await rebase();
    expect(await MyRSETH.balanceOf(staker1.address)).to.be.above(balance1Old);

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);
    await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    depositTx = await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );
    await depositTx.wait();

    let balance1New = await MyRSETH.balanceOf(staker1.address);
    let totalSupplyNew = await MyRSETH.totalSupply();
    await hre.network.provider.request({ method: "evm_revert", params: [snapshotId] });
    expect(balance1New).to.be.above(balance1Old);
    expect(totalSupplyNew).to.be.above(totalSupplyOld);
  });

  it("Should not complete the same withdraw", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    let receipt = await stEth.submit(staker1.address, { value: stEthDepositAmount });
    await receipt.wait();
    receipt = await stEth.connect(staker2).submit(staker2.address, { value: 2n * stEthDepositAmount });
    await receipt.wait();

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    let nonce = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);
    await LRTDepositPool.depositAsset(stEth.target, MyRSETHDepositAmount, minimumAmountOfRSETHForDeposit, "");
    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);

    receipt = await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    await receipt.wait();

    const blocksToMine = await delegationManager.getWithdrawalDelay([strategy]);
    await mine(blocksToMine);

    let shares = await strategy.underlyingToSharesView(amountToWithdraw);
    receipt = await LRTDepositPool.completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce, receipt.blockNumber, [strategy], [shares]],
      stEth.target,
    );
    await receipt.wait();

    receipt = await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    await receipt.wait();

    await mine(blocksToMine);

    await expect(
      LRTDepositPool.completeWithdrawal(
        [nodeDelegator.target, operator, nodeDelegator.target, nonce, receipt.blockNumber, [strategy], [shares]],
        stEth.target,
      ),
    ).to.be.reverted;
  });
  it("Should deposit rebase and withdraw", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    const snapshotId = await hre.network.provider.request({ method: "evm_snapshot" });
    await stEth.submit(staker1.address, { value: stEthDepositAmount });
    await stEth.connect(staker2).submit(staker2.address, { value: 2n * stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    await LRTDepositPool.depositAsset(stEth.target, MyRSETHDepositAmount, minimumAmountOfRSETHForDeposit, "");

    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, 2n * MyRSETHDepositAmount);
    await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      2n * MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );

    let stEthBalanceBefore = await stEth.balanceOf(staker1.address);
    let rsEthBalanceBefore = await MyRSETH.balanceOf(staker1.address);

    let stEthBalanceBefore2 = await stEth.balanceOf(staker2.address);
    let rsEthBalanceBefore2 = await MyRSETH.balanceOf(staker2.address);

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);
    let shares = await strategy.underlyingToSharesView(amountToWithdraw);

    let nonce1 = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);
    let receipt = await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    await receipt.wait();
    let withdrawalBlock = receipt.blockNumber;

    // await LRTDepositPool.connect(staker2).initiateWithdrawal.staticCall(stEth.target, amountToWithdraw);
    let secondAmountToWithdraw = amountToWithdraw;
    let nonce2 = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);
    let shares2 = await strategy.underlyingToSharesView(secondAmountToWithdraw);
    // delegationManager.on("WithdrawalQueued", (event,x) => console.log(event,x));
    receipt = await LRTDepositPool.connect(staker2).initiateWithdrawal(stEth.target, secondAmountToWithdraw);
    await receipt.wait();
    let withdrawalBlock2 = receipt.blockNumber;
    // delegationManager.removeAllListeners("WithdrawalQueued");

    let stEthBalanceAfter = await stEth.balanceOf(staker1.address);
    let rsEthBalanceAfter = await MyRSETH.balanceOf(staker1.address);
    let stEthBalanceAfter2 = await stEth.balanceOf(staker2.address);
    let rsEthBalanceAfter2 = await MyRSETH.balanceOf(staker2.address);

    expect(stEthBalanceAfter - stEthBalanceAfter).to.be.below(accuracyDelta);
    expect(rsEthBalanceAfter - rsEthBalanceBefore + amountToWithdraw).to.be.below(accuracyDelta);

    const blocksToMine = await delegationManager.getWithdrawalDelay([strategy]);
    await mine(blocksToMine);

    await LRTDepositPool.completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce1, withdrawalBlock, [strategy], [shares]],
      stEth.target,
    );
    await rebase();
    // console.log("calling complete withdrawal with", [nodeDelegator.target, operator, nodeDelegator.target, nonce2, withdrawalBlock2, [strategy], [shares2]], stEth.target);
    await LRTDepositPool.connect(staker2).completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce2, withdrawalBlock2, [strategy], [shares2]],
      stEth.target,
    );
    stEthBalanceAfter = await stEth.balanceOf(staker1.address);
    rsEthBalanceAfter = await MyRSETH.balanceOf(staker1.address);
    stEthBalanceAfter2 = await stEth.balanceOf(staker2.address);
    rsEthBalanceAfter2 = await MyRSETH.balanceOf(staker2.address);

    await hre.network.provider.request({ method: "evm_revert", params: [snapshotId] });
    expect(stEthBalanceAfter - stEthBalanceBefore - amountToWithdraw).to.be.above(accuracyDelta);
    expect(rsEthBalanceAfter - rsEthBalanceBefore + amountToWithdraw).to.be.above(accuracyDelta);
    expect(stEthBalanceAfter2 - stEthBalanceBefore2 - secondAmountToWithdraw).to.be.above(accuracyDelta);
    expect(rsEthBalanceAfter2 - rsEthBalanceBefore2 - amountToWithdraw).to.be.above(accuracyDelta);
  });

  it("Withdrawal should be possible only from its initiator", async function () {
    const { staker1, staker2, strategy, nodeDelegator, delegationManager, stEth, MyRSETH, LRTDepositPool } =
      await loadFixture(prepareContracts);
    await stEth.submit(staker1.address, { value: 10n * stEthDepositAmount });
    await stEth.connect(staker2).submit(staker2.address, { value: 10n * stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    await LRTDepositPool.depositAsset(stEth.target, MyRSETHDepositAmount, minimumAmountOfRSETHForDeposit, "");

    minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, 2n * MyRSETHDepositAmount);
    await LRTDepositPool.connect(staker2).depositAsset(
      stEth.target,
      2n * MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);

    let shares = await strategy.underlyingToSharesView(amountToWithdraw);

    let nonce = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);
    let receipt = await LRTDepositPool.initiateWithdrawal(stEth.target, amountToWithdraw);
    await receipt.wait();
    let withdrawalBlock = receipt.blockNumber;

    await LRTDepositPool.connect(staker2).initiateWithdrawal.staticCall(stEth.target, amountToWithdraw);

    let stEthBalanceAfter = await stEth.balanceOf(staker1.address);
    let rsEthBalanceAfter = await MyRSETH.balanceOf(staker1.address);

    const blocksToMine = await delegationManager.getWithdrawalDelay([strategy]);
    await mine(blocksToMine);

    await LRTDepositPool.completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce, withdrawalBlock, [strategy], [shares]],
      stEth.target,
    );
    await expect(
      LRTDepositPool.connect(staker2).completeWithdrawal(
        [nodeDelegator.target, operator, nodeDelegator.target, nonce, withdrawalBlock, [strategy], [shares]],
        stEth.target,
      ),
    ).to.be.reverted;
  });
});
