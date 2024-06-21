// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library LRTConstants {
    //stETH token
    bytes32 public constant ST_ETH_TOKEN = keccak256("ST_ETH_TOKEN");

    //contracts
    bytes32 public constant LRT_DEPOSIT_POOL = keccak256("LRT_DEPOSIT_POOL");
    bytes32 public constant EIGEN_STRATEGY_MANAGER = keccak256("EIGEN_STRATEGY_MANAGER");

    //Roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant EIGEN_POD_MANAGER = keccak256("EIGEN_POD_MANAGER");

    // Operator Role
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
}
