import hre, { ethers, upgrades } from "hardhat";
const amountToWithdraw = ethers.parseEther("0.1");

async function main() {
  const [owner1, owner2, staker] = await ethers.getSigners();
  const operatorAddress = "0x4cd2086e1d708e65db5d4f5712a9ca46ed4bbd0a";
  const multisigAddress = process.env.ADMIN_MULTISIG_ADDRESS ?? "";
  const multisig = await ethers.getContractAt("MultiSigWallet", multisigAddress);

  const lrtConfigAddress = process.env.LRT_CONFIG_ADDRESS ?? "";
  const config = await ethers.getContractAt("LRTConfig", lrtConfigAddress);

  const ST_ETH_TOKEN = ethers.keccak256(ethers.toUtf8Bytes("ST_ETH_TOKEN"));
  const stEthAddress = await config.tokenMap(ST_ETH_TOKEN);
  const stEth = await ethers.getContractAt("IstETH", stEthAddress);

  const rsETHAddr = await config.rsETH();
  const MyRSETH = await ethers.getContractAt("MyRSETH", rsETHAddr);

  const LRT_DEPOSIT_POOL = ethers.keccak256(ethers.toUtf8Bytes("LRT_DEPOSIT_POOL"));
  const LRTDepositPoolAddress = await config.getContract(LRT_DEPOSIT_POOL);
  const LRTDepositPool = await ethers.getContractAt("LRTDepositPool", LRTDepositPoolAddress);

  console.log("initiating withdrawal");
  console.log("MyRSETH balance before withdraw init is ", await MyRSETH.balanceOf(staker.address));
  await LRTDepositPool.connect(staker).initiateWithdrawal(stEth.target, amountToWithdraw);
  console.log("withdrawal initiated");
  console.log("MyRSETH balance after withdraw init is ", await MyRSETH.balanceOf(staker.address));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
