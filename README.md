# Introduction

This repository contains the code for the test Daoism assignment.

The repository is based on [KelpDAO](https://kelpdao.xyz/) and its [rsETH](https://github.com/Kelp-DAO/LRT-rsETH), which originally pursued the aim of implementing a liquid restaking token.

It was cleaned; some of the contracts/functions have been removed. However, a considerable part of the code is still present. Also, the names of variables might reflect the original version, though their usage is intended to be correct (e.g., `rsEth` instead of `MyRSETH`).

## Install and usage

The initial repository used Foundry for development, as the authors needed it for test fuzzing. Thus, the deploy scripts
are written for Forge, and it's used even after added modifications.

However, the deliverables are intended to be JS scripts; therefore, Hardhat is used.

Build:
```
forge b
npm i
```


### Run

A fork of the mainnet (before a rebase transaction of Lido protocol) is used during the local run. Using Hardhat for its fixtures, and during tests, it proved to be faster.

Start node (localhost network):
```
npx hardhat run
```

Deploy the contracts locally:
```
make deploy-lrt-local-test
```

Run tests:
```
npx hardhat test --network localhost
```

### Actions

User actions:
- Make a deposit of stETH and receive MyRSETH token in return.
- Initiate (and complete) withdrawals (when their MyRSETH is burned).

Admin actions:
- Move assets to the EigenLayer.
- Delegate to an EigenLayer operator (details below).
- Undelegate from an EigenLayer operator.

The admin role is given to a MultiSigWallet contract, which needs two confirmations from both owners to execute transactions.

To run an action, first, it's necessary to set environment variables (addresses of `LRTConfig` and `MultiSigWallet` contracts).
```
. ./.env
```

To invoke an action:
```
npx hardhat run script/hardhat-scripts/userWithdraw.ts --network localhost
```

And similarly for the rest of the actions.

## Overview

This LRT primarily consists of three contracts: 
- `LRTDepositPool`, with which users interact.
- `NodeDelegator`, which makes calls to the EigenLayer.
- `MyRSETH`, the token itself.

During deposit or withdrawal, users interact with the `LRTDepositPool` contract. The `LRTDepositPool` has a single
`NodeDelegator` associated with it. In the original repository, it had several NodeDelegators, with the purpose of
restaking various assets and delegating to various EL operators. But for the sake of simplicity, only one is left.

After the assets have been deposited to the `LRTDepositPool` by a user, the ecosystem manager may transfer them to the
NodeDelegator and then delegate to an operator and transfer to the associated strategy.

Next, the user may initiate a withdrawal. After waiting for the EL-based waiting period, the user may complete the withdrawal.

It's up to the user to calculate the right withdrawal root to complete their withdrawal.

Tests are provided to cover all the basic scenarios.

### MyRSETH token and rewards

The `MyRSETH` token is minted for a user when they make a deposit of stETH token. It is a rebasing token, which tracks the rewards gained from the Lido protocol. As it is a rebasing token (i.e., it tracks the number of shares of something), it is susceptible to rounding errors, and the balances might have slight fluctuations.

Only rewards from Lido staking are shown as the increase in MyRSETH token balances.

Also, the transfer (and allowance) functions are expected to accept shares, not tokens. Thus, it is up to the user to calculate the right amount in case of using these functions. Though `totalSupply` and `balanceOf` represent the amount in stETH with rewards. No other rewards (e.g., EigenLayer) are combined in users' balances.

When a withdraw is initiated, the tokens are burnt.

### Admin

The admin of the system is the multisignature wallet (adapted to a proxy pattern, as it does not allow a change of its owners). The owner of the proxy admin is the multisig itself.

The MultiSig contract itself is based on an old Gav Wood contract and can now be found
[here](https://solidity-by-example.org/app/multi-sig-wallet/) with a minor addition for usability purposes (public
variable of transactions length).

### Assumptions

EigenLayer contracts are secure and work fine.
The Lido protocol is secure and works fine.
Operators and managers are not malicious.

## Problems

### Vault inflation / arithmetics

To address the known problem of inflation of shares, during the initialization of the contract, a minimum deposit is made. These funds (and corresponding shares) are meant to rest in the system forever to prevent the manipulation of the shares/asset ratio.

### Delegation

Interaction of withdrawals and undelegation: if the admin undelegates from an EL operator, the rewards can no longer be withdrawn by the user for two reasons:

1) The information about the deposit is stored in EL and this information gets lost on undelegation.
2) During the waiting period for withdrawal, TVL is effectively decreased, which means the user can receive a smaller amount of tokens for their share in LRT.

The right solution would be to store (a part of) the withdrawal info in LRT and try to withdraw from the LRT ecosystem if it has enough tokens; otherwise, pass the withdrawal to the EigenLayer.

A workaround for this issue is to forbid withdrawals when the NodeDelegator is not delegated. If undelegation is done when user assets were present, it will lock them. To unlock, the manager has to redelegate again. Currently this workaround is used.

Another workaround, such as forbidding undelegation if LRT has any shares in EL, is more problematic, as it allows an attacker to freeze the manager from undelegating. Even if the manager is allowed to withdraw on behalf of a user, it's possible for an attacker to spread the tokens among many addresses, and the admin-forced withdrawal will cost too much. Another potential problem with this is that translation of shares into tokens might might work in a way that it's impossible to withdraw precisely all tokens.

### Nota Bene

It's a showcase code, so it might be vulnerable to attacks and behave badly. Only local usage is intended.

No gas optimizations were done.
