// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {AaveV3Payload} from '../src/contracts/extensions/v3-config-engine/AaveV3Payload.sol';
import {IAaveV3ConfigEngine as IEngine} from '../src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {EngineFlags} from '../src/contracts/extensions/v3-config-engine/EngineFlags.sol';
import {IPool} from '../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

interface IERC20Wrapper {
  function depositFor(address account, uint256 value) external returns (bool);
}

/**
 * @notice Tydro Ink Sepolia test listing, same params as Tydro Ink mainnet:
 *  - kBTC <> USDC in the global market (kBTC collateral, USDC borrowable)
 *  - kHYPE <> wUSDC1 in an isolated eMode only (kHYPE LT 0 and wUSDC1 not borrowable outside of it)
 * Executed by the Executor (POOL_ADMIN) via delegatecall to `execute()`.
 * The Executor must hold the seed amounts (USDC_SEED_AMOUNT + WUSDC1_SEED_AMOUNT of USDC, kBTC, kHYPE)
 * before execution: like the aave-proposals-v3 listings, each new reserve is seeded to the DustBin.
 */
contract TydroInkSepoliaListingPayload is AaveV3Payload {
  using SafeERC20 for IERC20;

  IPool public constant POOL = IPool(0xa1176A315F64500dB4B3e0042A6181221a053882);
  address public constant DUST_BIN = 0xAdbA104090aC3e88904Cc2c6e5Be0A54bB82757c;

  address public constant USDC = 0xba31A80B7bE22cFddbdFAfBeB67F41c20Eb620f1;
  address public constant KBTC = 0x064aF7ee546Ea9c73Bab710E2a89A5b402493e54;
  address public constant KHYPE = 0xc01f088b7359ca765FB4B2A33fc98641Ac1E6326;
  address public constant WUSDC1 = 0xda29A6c8ABa99b444ff4F70a72b896fe9f81ef54;

  address public constant USDC_FEED = 0x4F0F228256D26AE4029e228dbfa060E159697669; // also wUSDC1 (1:1)
  address public constant KBTC_FEED = 0x0ced0b87C4A93F14E13e080168469cd633c3E649;
  address public constant KHYPE_FEED = 0xbaEFeb7706119d6658706DEDfE4A0cC2D4AD31cB;

  uint256 public constant USDC_SEED_AMOUNT = 10e6;
  uint256 public constant WUSDC1_SEED_AMOUNT = 10e6; // wrapped from the Executor's USDC
  uint256 public constant KBTC_SEED_AMOUNT = 0.00025e8;
  uint256 public constant KHYPE_SEED_AMOUNT = 1e18;

  constructor() AaveV3Payload(IEngine(0x098bB207463E2DC21c10254D1097AFecDEA7B99A)) {}

  function _postExecute() internal override {
    _seed(USDC, USDC_SEED_AMOUNT);
    _seed(KBTC, KBTC_SEED_AMOUNT);
    _seed(KHYPE, KHYPE_SEED_AMOUNT);

    IERC20(USDC).forceApprove(WUSDC1, WUSDC1_SEED_AMOUNT);
    IERC20Wrapper(WUSDC1).depositFor(address(this), WUSDC1_SEED_AMOUNT);
    _seed(WUSDC1, WUSDC1_SEED_AMOUNT);
  }

  function _seed(address asset, uint256 amount) internal {
    IERC20(asset).forceApprove(address(POOL), amount);
    POOL.supply(asset, amount, DUST_BIN, 0);
  }

  function newListings() public pure override returns (IEngine.Listing[] memory) {
    IEngine.Listing[] memory listings = new IEngine.Listing[](4);

    listings[0] = IEngine.Listing({
      asset: USDC,
      assetSymbol: 'USDC',
      priceFeed: USDC_FEED,
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
      supplyCap: 100_000_000,
      borrowCap: 75_000_000,
      liqProtocolFee: 0
    });

    listings[1] = IEngine.Listing({
      asset: KBTC,
      assetSymbol: 'kBTC',
      priceFeed: KBTC_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 8_00,
        variableRateSlope1: 4_00,
        variableRateSlope2: 80_00
      }),
      enabledToBorrow: EngineFlags.DISABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 85_00,
      liqThreshold: 87_00,
      liqBonus: 5_00,
      reserveFactor: 50_00,
      supplyCap: 1_575,
      borrowCap: 1,
      liqProtocolFee: 10_00
    });

    // collateral only inside the kHYPE__wUSDC1 eMode
    listings[2] = IEngine.Listing({
      asset: KHYPE,
      assetSymbol: 'kHYPE',
      priceFeed: KHYPE_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 7_00,
        variableRateSlope2: 300_00
      }),
      enabledToBorrow: EngineFlags.DISABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 0,
      liqThreshold: 0,
      liqBonus: 0,
      reserveFactor: 50_00,
      supplyCap: 124_000,
      borrowCap: 1,
      liqProtocolFee: 10_00
    });

    // USDC params, but borrowable only inside the kHYPE__wUSDC1 eMode
    listings[3] = IEngine.Listing({
      asset: WUSDC1,
      assetSymbol: 'wUSDC1',
      priceFeed: USDC_FEED,
      rateStrategyParams: IEngine.InterestRateInputData({
        optimalUsageRatio: 95_00,
        baseVariableBorrowRate: 6_30,
        variableRateSlope1: 0,
        variableRateSlope2: 0
      }),
      enabledToBorrow: EngineFlags.DISABLED,
      flashloanable: EngineFlags.ENABLED,
      ltv: 0,
      liqThreshold: 0,
      liqBonus: 0,
      reserveFactor: 10_00,
      supplyCap: 100_000_000,
      borrowCap: 75_000_000,
      liqProtocolFee: 0
    });

    return listings;
  }

  function eModeCategoryCreations()
    public
    pure
    override
    returns (IEngine.EModeCategoryCreation[] memory)
  {
    address[] memory collaterals = new address[](1);
    collaterals[0] = KHYPE;

    address[] memory borrowables = new address[](1);
    borrowables[0] = WUSDC1;

    IEngine.EModeCategoryCreation[] memory creations = new IEngine.EModeCategoryCreation[](1);
    creations[0] = IEngine.EModeCategoryCreation({
      ltv: 65_00,
      liqThreshold: 72_00,
      liqBonus: 10_00,
      label: 'kHYPE__wUSDC1',
      borrowables: borrowables,
      collaterals: collaterals,
      isolated: true
    });

    return creations;
  }

  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'InkSepolia', networkAbbreviation: 'InkSep'});
  }
}

contract DeployTydroInkSepoliaListing is Script {
  function run() external returns (TydroInkSepoliaListingPayload payload) {
    require(block.chainid == 763373, 'wrong chain');

    vm.startBroadcast();
    payload = new TydroInkSepoliaListingPayload();
    vm.stopBroadcast();
  }
}
