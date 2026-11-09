// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DeployAaveV3MarketBatchedBase} from './misc/DeployAaveV3MarketBatchedBase.sol';

import {DefaultMarketInput} from '../src/deployments/inputs/DefaultMarketInput.sol';
import {TydroInkBitwiseInput} from '../src/deployments/inputs/TydroInkBitwiseInput.sol';

contract Default is DeployAaveV3MarketBatchedBase, DefaultMarketInput {}

// The deployer stays owner of AaveV3SetupBatch (only setMarketReport left), like Tydro's Ink market
contract TydroInkBitwise is DeployAaveV3MarketBatchedBase, TydroInkBitwiseInput {}
