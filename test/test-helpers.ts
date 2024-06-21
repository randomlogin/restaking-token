import { ethers } from "hardhat";

async function prepareContracts() {
  const operator = "0x4cd2086e1d708e65db5d4f5712a9ca46ed4bbd0a";

  const [staker1, staker2, staker3] = await ethers.getSigners();
  const multisigAddress = process.env.ADMIN_MULTISIG_ADDRESS ?? "";
  const multisig = await ethers.getContractAt("MultiSigWallet", multisigAddress);

  const lrtConfigAddress = process.env.LRT_CONFIG_ADDRESS ?? "";
  const config = await ethers.getContractAt("LRTConfig", lrtConfigAddress);

  const ST_ETH_TOKEN = ethers.keccak256(ethers.toUtf8Bytes("ST_ETH_TOKEN"));
  const stEthAddress = await config.tokenMap(ST_ETH_TOKEN);
  const stEth = await ethers.getContractAt("IstETH", stEthAddress);

  const LRT_DEPOSIT_POOL = ethers.keccak256(ethers.toUtf8Bytes("LRT_DEPOSIT_POOL"));
  const LRTDepositPoolAddress = await config.getContract(LRT_DEPOSIT_POOL);
  const LRTDepositPool = await ethers.getContractAt("LRTDepositPool", LRTDepositPoolAddress);

  const rsETHAddr = await config.rsETH();
  const MyRSETH = await ethers.getContractAt("MyRSETH", rsETHAddr);

  const nodeDelegatorAddress = (await LRTDepositPool.getNodeDelegatorQueue())[0];
  const nodeDelegator = await ethers.getContractAt("NodeDelegator", nodeDelegatorAddress);

  const eigenlayerStrategyManagerAddress = await config.getContract(
    ethers.keccak256(ethers.toUtf8Bytes("EIGEN_STRATEGY_MANAGER")),
  );
  const strategyManager = await ethers.getContractAt("IEigenStrategyManager", eigenlayerStrategyManagerAddress);
  const delegationManager = await ethers.getContractAt("IDelegationManager", await strategyManager.delegation());

  await stEth.approve(LRTDepositPoolAddress, ethers.MaxUint256);
  await stEth.connect(staker2).approve(LRTDepositPoolAddress, ethers.MaxUint256);

  const strategy = await ethers.getContractAt("IStrategy", await config.assetStrategy(stEthAddress));

  let currentOperator = await delegationManager.delegatedTo(nodeDelegator.target);
  if (currentOperator.toLocaleLowerCase() != operator) {
    await nodeDelegator.delegateTo(operator);
  }
  return {
    staker1,
    staker2,
    strategy,
    nodeDelegator,
    delegationManager,
    stEth,
    MyRSETH,
    strategyManager,
    LRTDepositPool,
    operator,
  };
}

async function rebase() {
  const firstRebaseTx =
    "0x02f90314018201de8402faf0808503bee3983a830bf76794852ded011285fe67063a08005c71a85690503cee80b902a4fc7377cd00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000008cbc1f00000000000000000000000000000000000000000000000000000000000563690000000000000000000000000000000000000000000000000021b4c8e4c0628000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000341637b55103263a000000000000000000000000000000000000000000000000094b776a05b11f6b5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000003c6bcf3c156ef47ddbff61e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000a23dc001a0c938227a1e62c89d0561455cc961cbaeb1fe9c6cd565245e5be1b1620b1cfa53a01f12eadd3ab4eb4c1d6f520aaf67f21c402fe0e32998235dc263b6047ca69d67";
  let broad = await ethers.provider.broadcastTransaction(firstRebaseTx);
  await broad.wait();
}

export { prepareContracts, rebase };
