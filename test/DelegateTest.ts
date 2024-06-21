const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
import { prepareContracts } from "./test-helpers.ts";
import hre, { ethers, upgrades } from "hardhat";
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const operator = "0x4cd2086e1d708e65db5d4f5712a9ca46ed4bbd0a";
const amountToWithdraw = 1000000000n;
const accuracyDelta = 1000;
const stEthDepositAmount = ethers.parseEther("2");
const MyRSETHDepositAmount = ethers.parseEther("0.5");

describe("Delegation:", function () {
  it("Undelegating changes balances and another delegation restores them", async function () {
    const {
      staker1,
      staker2,
      strategy,
      nodeDelegator,
      delegationManager,
      stEth,
      MyRSETH,
      LRTDepositPool,
      strategyManager,
    } = await loadFixture(prepareContracts);
    let receipt = await stEth.submit(staker1.address, { value: stEthDepositAmount });

    let minimumAmountOfRSETHForDeposit = await LRTDepositPool.getRsETHAmountToMint(stEth.target, MyRSETHDepositAmount);
    let depositTx = await LRTDepositPool.depositAsset(
      stEth.target,
      MyRSETHDepositAmount,
      minimumAmountOfRSETHForDeposit,
      "",
    );

    await LRTDepositPool.transferAssetToNodeDelegator(0, stEth.target, await stEth.balanceOf(LRTDepositPool.target));
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);

    let balanceBeforeUndelegation = await MyRSETH.balanceOf(staker1);
    let shares = await strategyManager.stakerStrategyShares(nodeDelegator.target, strategy.target);
    let nonce1 = await delegationManager.cumulativeWithdrawalsQueued(nodeDelegator.target);

    let undelegationReceipt = await nodeDelegator.undelegate();
    await undelegationReceipt.wait();
    let undelegationBlock = undelegationReceipt.blockNumber;
    let balanceAfterUndelegation = await MyRSETH.balanceOf(staker1);
    expect(balanceAfterUndelegation - balanceBeforeUndelegation).to.be.below(accuracyDelta);
    const blocksToMine = await delegationManager.getWithdrawalDelay([strategy]);
    await mine(blocksToMine);

    let stEthBalanceOld = await stEth.balanceOf(nodeDelegator);
    let completeWithdrawalReceipt = await LRTDepositPool.completeWithdrawal(
      [nodeDelegator.target, operator, nodeDelegator.target, nonce1, undelegationBlock, [strategy.target], [shares]],
      stEth.target,
    );
    await completeWithdrawalReceipt.wait();
    let stEthBalanceNew = await stEth.balanceOf(nodeDelegator);
    let balanceAfterWithdrawalCompletion = await MyRSETH.balanceOf(staker1);
    expect(balanceAfterWithdrawalCompletion).to.equal(balanceBeforeUndelegation);
    expect(stEthBalanceNew).to.be.above(stEthBalanceOld);

    await nodeDelegator.delegateTo(operator);
    await nodeDelegator.depositAssetIntoStrategy(stEth.target);
    let balanceAfterRedelegation = await MyRSETH.balanceOf(staker1);
    expect(balanceAfterRedelegation - balanceBeforeUndelegation).to.be.below(accuracyDelta);
  });
});
