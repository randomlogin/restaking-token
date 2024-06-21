// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IstETH is IERC20 {
    function submit(address) external payable;

    function getTotalShares() external view returns (uint256);

    function getTotalPooledEther() external view returns (uint256);
}
