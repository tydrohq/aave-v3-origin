// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {AaveV3Payload} from '../src/contracts/extensions/v3-config-engine/AaveV3Payload.sol';
import {IAaveV3ConfigEngine as IEngine} from '../src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {EngineFlags} from '../src/contracts/extensions/v3-config-engine/EngineFlags.sol';
import {IPool} from '../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice Bitwise Ink Sepolia test listing, global market only (no eMode):
 *  - EURC (Circle testnet token) borrowable, not collateral, IRM like Tydro mainnet USDC
 *  - sUSDai and HUMA (mocks) collateral only
 * Executed by the Executor (POOL_ADMIN) via delegatecall to `execute()`.
 * The Executor must hold the seed amounts before execution: each new reserve is seeded to the DustBin.
 */
contract TydroInkSepoliaBitwiseListingPayload is AaveV3Payload {
  using SafeERC20 for IERC20;

  IPool public constant POOL = IPool(0x2a0b4f94F2C2D1d9Eb7dB6A28305e26ED7B648A1);
  address public constant DUST_BIN = 0x48Ed39C524e2211caF3f5C458014558CA411ddCC;

  address public constant EURC = 0x14e4Ae1e59676865C8C76362E2D13156880315D6;
  address public constant SUSDAI = 0x6374e3b51e4Ea9D74951A3455D52f7eF005Fc2a4;
  address public constant HUMA = 0x5bBE34F2467D7d3B67E40a689A1ecBDbEFdDf8dD;

  address public constant EURC_FEED = 0xc3534B87B147807cE8a82dFC7037bc800689D7EE; // $1.12
  address public constant SUSDAI_FEED = 0x6fda1A10014cb5e9183284dBfFF7e3DC6db17e01; // $1.12
  address public constant HUMA_FEED = 0x98a51073126A2df9d0f4451504DE1A4180314b01; // $0.015

  uint256 public constant EURC_SEED_AMOUNT = 10e6;
  uint256 public constant SUSDAI_SEED_AMOUNT = 10e18;
  uint256 public constant HUMA_SEED_AMOUNT = 1_000e18;

  constructor() AaveV3Payload(IEngine(0x166A349De589e71DF7B2cB4a2A8E4f14FE2f9E9e)) {}

  function _postExecute() internal override {
    _seed(EURC, EURC_SEED_AMOUNT);
    _seed(SUSDAI, SUSDAI_SEED_AMOUNT);
    _seed(HUMA, HUMA_SEED_AMOUNT);
  }

  function _seed(address asset, uint256 amount) internal {
    IERC20(asset).forceApprove(address(POOL), amount);
    POOL.supply(asset, amount, DUST_BIN, 0);
  }

  function newListings() public pure override returns (IEngine.Listing[] memory) {
    IEngine.Listing[] memory listings = new IEngine.Listing[](3);

    listings[0] = IEngine.Listing({
      asset: EURC,
      assetSymbol: 'EURC',
      priceFeed: EURC_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 95_00,
        baseVariableBorrowRate: 6_30,
        variableRateSlope1: 0,
        variableRateSlope2: 0
      }),
      enabledToBorrow: EngineFlags.ENABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 0,
      liqThreshold: 0,
      liqBonus: 0,
      reserveFactor: 10_00,
      supplyCap: 10_000_000,
      borrowCap: 8_000_000,
      liqProtocolFee: 0
    });

    // not borrowable: the IRM is unused
    listings[1] = IEngine.Listing({
      asset: SUSDAI,
      assetSymbol: 'sUSDai',
      priceFeed: SUSDAI_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 7_00,
        variableRateSlope2: 300_00
      }),
      enabledToBorrow: EngineFlags.DISABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 80_00,
      liqThreshold: 85_00,
      liqBonus: 5_00,
      reserveFactor: 20_00,
      supplyCap: 10_000_000,
      borrowCap: 1,
      liqProtocolFee: 10_00
    });

    listings[2] = IEngine.Listing({
      asset: HUMA,
      assetSymbol: 'HUMA',
      priceFeed: HUMA_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 7_00,
        variableRateSlope2: 300_00
      }),
      enabledToBorrow: EngineFlags.DISABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 50_00,
      liqThreshold: 60_00,
      liqBonus: 10_00,
      reserveFactor: 20_00,
      supplyCap: 100_000_000,
      borrowCap: 1,
      liqProtocolFee: 10_00
    });

    return listings;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'InkSepoliaBitwise', networkAbbreviation: 'InkSepBit'});
  }
}

contract DeployTydroInkSepoliaBitwiseListing is Script {
  function run() external returns (TydroInkSepoliaBitwiseListingPayload payload) {
    require(block.chainid == 763373, 'wrong chain');

    vm.startBroadcast();
    payload = new TydroInkSepoliaBitwiseListingPayload();
    vm.stopBroadcast();
  }
}
