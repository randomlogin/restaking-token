import hre, { ethers, upgrades } from "hardhat";

async function main() {
  const [owner1, owner2] = await ethers.getSigners();
  const operatorAddress = "0x4cd2086e1d708e65db5d4f5712a9ca46ed4bbd0a";
  const multisigAddress = process.env.ADMIN_MULTISIG_ADDRESS ?? "";
  const multisig = await ethers.getContractAt("MultiSigWallet", multisigAddress);

  const lrtConfigAddress = process.env.LRT_CONFIG_ADDRESS ?? "";
  const config = await ethers.getContractAt("LRTConfig", lrtConfigAddress);

  const ST_ETH_TOKEN = ethers.keccak256(ethers.toUtf8Bytes("ST_ETH_TOKEN"));
  const stEthAddress = await config.tokenMap(ST_ETH_TOKEN);
  const stEth = await ethers.getContractAt("IERC20", stEthAddress);

  const LRT_DEPOSIT_POOL = ethers.keccak256(ethers.toUtf8Bytes("LRT_DEPOSIT_POOL"));
  const LRTDepositPoolAddress = await config.getContract(LRT_DEPOSIT_POOL);
  const LRTDepositPool = await ethers.getContractAt("LRTDepositPool", LRTDepositPoolAddress);

  let nodeDelegatorAddress = (await LRTDepositPool.getNodeDelegatorQueue())[0];
  let nodeDelegator = await ethers.getContractAt("NodeDelegator", nodeDelegatorAddress);

  const eigenlayerStrategyManagerAddress = await config.getContract(
    ethers.keccak256(ethers.toUtf8Bytes("EIGEN_STRATEGY_MANAGER")),
  );
  const strategyManager = await ethers.getContractAt("IEigenStrategyManager", eigenlayerStrategyManagerAddress);
  const delegationManager = await ethers.getContractAt("IDelegationManager", await strategyManager.delegation());

  let currentOperator = await delegationManager.delegatedTo(nodeDelegator.target);

  console.log("current operator is", currentOperator);
  console.log("delegating to", operatorAddress);
  const delegateCalldata = nodeDelegator.interface.encodeFunctionData("delegateTo", [operatorAddress]);
  await multisig.submitTransaction(nodeDelegatorAddress, 0, delegateCalldata);
  let txLen = await multisig.transactionsLength();
  let tx = await multisig.confirmTransaction(txLen - 1n);
  await tx.wait();
  tx = await multisig.connect(owner2).confirmTransaction(txLen - 1n);
  await tx.wait();
  tx = await multisig.executeTransaction(txLen - 1n);
  await tx.wait();

  currentOperator = await delegationManager.delegatedTo(nodeDelegator.target);
  console.log("current operator is", currentOperator);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
