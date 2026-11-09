// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DeployAaveV3MarketBatchedBase} from './misc/DeployAaveV3MarketBatchedBase.sol';

import {DefaultMarketInput} from '../src/deployments/inputs/DefaultMarketInput.sol';
import {TydroInkSepoliaInput} from '../src/deployments/inputs/TydroInkSepoliaInput.sol';
import {TydroInkSepoliaBitwiseInput} from '../src/deployments/inputs/TydroInkSepoliaBitwiseInput.sol';

contract Default is DeployAaveV3MarketBatchedBase, DefaultMarketInput {}

contract TydroInkSepolia is DeployAaveV3MarketBatchedBase, TydroInkSepoliaInput {}

contract TydroInkSepoliaBitwise is DeployAaveV3MarketBatchedBase, TydroInkSepoliaBitwiseInput {}
