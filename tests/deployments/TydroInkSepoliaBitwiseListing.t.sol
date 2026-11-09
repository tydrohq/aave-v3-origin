// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolDataProvider} from '../../src/contracts/interfaces/IPoolDataProvider.sol';
import {IAaveOracle} from '../../src/contracts/interfaces/IAaveOracle.sol';
import {IDefaultInterestRateStrategyV2} from '../../src/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';
import {Errors} from '../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {TydroInkSepoliaBitwiseListingPayload} from '../../scripts/TydroInkSepoliaBitwiseListing.s.sol';

interface IExecutor {
  function executeTransaction(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    bool withDelegatecall
  ) external payable returns (bytes memory);
}

interface IMintable {
  function mint(address account, uint256 value) external returns (bool);
}

contract TydroInkSepoliaBitwiseListingTest is Test {
  IPool constant POOL = IPool(0x2a0b4f94F2C2D1d9Eb7dB6A28305e26ED7B648A1);
  IPoolDataProvider constant PDP = IPoolDataProvider(0x8fD0AeC736f4b045d2C2ce97458FC5b74F22EE19);
  IAaveOracle constant ORACLE = IAaveOracle(0x99871a07Db6185356756Ce18FCEEA19A6569Ee47);
  address constant EXECUTOR = 0x3A540F759Ca7c16bf2E2682698ce3278BF14f5CB;
  address constant CONTROLLER = 0x640512d97A67844b398e7EF2E87c3B02Cfe6e5e5;
  address constant DEPLOYER = 0xB5D789353ff57736d67c432b994c1f73bF683F01; // mocks owner, holds faucet EURC

  TydroInkSepoliaBitwiseListingPayload payload;
  address EURC;
  address SUSDAI;
  address HUMA;

  address lender = makeAddr('lender');
  address user = makeAddr('user');

  function setUp() public {
    // pinned before the listing was executed on-chain (block of the listing payload deployment)
    vm.createSelectFork('https://rpc-gel-sepolia.inkonchain.com', 64899400);
    payload = new TydroInkSepoliaBitwiseListingPayload();
    (EURC, SUSDAI, HUMA) = (payload.EURC(), payload.SUSDAI(), payload.HUMA());

    // without the seed funds on the Executor the execution reverts
    vm.prank(CONTROLLER);
    vm.expectRevert();
    IExecutor(EXECUTOR).executeTransaction(address(payload), 0, 'execute()', '', true);

    // same funding as on-chain: faucet EURC sent by Martin, mocks minted
    uint256 eurcSeed = payload.EURC_SEED_AMOUNT();
    vm.prank(DEPLOYER);
    IERC20(EURC).transfer(EXECUTOR, eurcSeed);
    _mint(SUSDAI, EXECUTOR, payload.SUSDAI_SEED_AMOUNT());
    _mint(HUMA, EXECUTOR, payload.HUMA_SEED_AMOUNT());

    // same path as PermissionedPayloadsController.executePayload
    vm.prank(CONTROLLER);
    IExecutor(EXECUTOR).executeTransaction(address(payload), 0, 'execute()', '', true);
  }

  function test_seed() public view {
    address dustBin = payload.DUST_BIN();
    assertEq(IERC20(POOL.getReserveAToken(EURC)).balanceOf(dustBin), payload.EURC_SEED_AMOUNT());
    assertEq(IERC20(POOL.getReserveAToken(SUSDAI)).balanceOf(dustBin), payload.SUSDAI_SEED_AMOUNT());
    assertEq(IERC20(POOL.getReserveAToken(HUMA)).balanceOf(dustBin), payload.HUMA_SEED_AMOUNT());
    assertEq(IERC20(EURC).balanceOf(EXECUTOR), 0);
  }

  function test_config() public view {
    assertEq(POOL.getReservesList().length, 3);

    _checkParams(EURC, 6, 0, 0, 0, 10_00, false, true);
    _checkParams(SUSDAI, 18, 80_00, 85_00, 105_00, 20_00, true, false);
    _checkParams(HUMA, 18, 50_00, 60_00, 110_00, 20_00, true, false);

    _checkCaps(EURC, 8_000_000, 10_000_000, 0);
    _checkCaps(SUSDAI, 1, 10_000_000, 10_00);
    _checkCaps(HUMA, 1, 100_000_000, 10_00);

    _checkRates(EURC, 95_00, 6_30, 0, 0);

    assertEq(ORACLE.getAssetPrice(EURC), 1.12e8);
    assertEq(ORACLE.getAssetPrice(SUSDAI), 1.12e8);
    assertEq(ORACLE.getAssetPrice(HUMA), 0.015e8);

    assertEq(POOL.getEModeCategoryLabel(1), '');

    _checkToken(POOL.getReserveAToken(EURC), 'Aave InkSepoliaBitwise EURC', 'aInkSepBitEURC');
    _checkToken(POOL.getReserveVariableDebtToken(EURC), 'Aave InkSepoliaBitwise Variable Debt EURC', 'variableDebtInkSepBitEURC');
  }

  function test_borrowAgainstSusdai() public {
    _seedLiquidity();
    _mint(SUSDAI, user, 1_000e18); // $1,120

    vm.startPrank(user);
    IERC20(SUSDAI).approve(address(POOL), 1_000e18);
    POOL.supply(SUSDAI, 1_000e18, user, 0);

    // LTV 80% -> $896 = 800 EURC at $1.12
    vm.expectRevert(Errors.CollateralCannotCoverNewBorrow.selector);
    POOL.borrow(EURC, 800.01e6, 2, 0, user);
    POOL.borrow(EURC, 790e6, 2, 0, user);
    assertEq(IERC20(EURC).balanceOf(user), 790e6);

    // collaterals are not borrowable
    vm.expectRevert(Errors.BorrowingNotEnabled.selector);
    POOL.borrow(HUMA, 1e18, 2, 0, user);
    vm.stopPrank();
  }

  function test_borrowAgainstHuma() public {
    _seedLiquidity();
    _mint(HUMA, user, 100_000e18); // $1,500

    vm.startPrank(user);
    IERC20(HUMA).approve(address(POOL), 100_000e18);
    POOL.supply(HUMA, 100_000e18, user, 0);

    // LTV 50% -> $750 = 669.64 EURC at $1.12
    vm.expectRevert(Errors.CollateralCannotCoverNewBorrow.selector);
    POOL.borrow(EURC, 670e6, 2, 0, user);
    POOL.borrow(EURC, 660e6, 2, 0, user);
    assertEq(IERC20(EURC).balanceOf(user), 660e6);
    vm.stopPrank();
  }

  // EURC is a Circle token we can't mint: deal() is test-only
  function _seedLiquidity() internal {
    deal(EURC, lender, 10_000e6);
    vm.startPrank(lender);
    IERC20(EURC).approve(address(POOL), 10_000e6);
    POOL.supply(EURC, 10_000e6, lender, 0);
    vm.stopPrank();
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(DEPLOYER);
    IMintable(token).mint(to, amount);
  }

  function _checkParams(
    address asset,
    uint256 decimals,
    uint256 ltv,
    uint256 lt,
    uint256 lb,
    uint256 rf,
    bool collateral,
    bool borrowable
  ) internal view {
    uint256[] memory got = new uint256[](7);
    (got[0], got[1], got[2], got[3], got[4], , , , , ) = PDP.getReserveConfigurationData(asset);
    assertEq(got[0], decimals);
    assertEq(got[1], ltv);
    assertEq(got[2], lt);
    assertEq(got[3], lb);
    assertEq(got[4], rf);
    (, , , , , bool collateral_, bool borrowable_, , , ) = PDP.getReserveConfigurationData(asset);
    assertEq(collateral_, collateral);
    assertEq(borrowable_, borrowable);
  }

  function _checkCaps(address asset, uint256 borrowCap, uint256 supplyCap, uint256 liqFee) internal view {
    (uint256 bc, uint256 sc) = PDP.getReserveCaps(asset);
    assertEq(bc, borrowCap);
    assertEq(sc, supplyCap);
    assertEq(PDP.getLiquidationProtocolFee(asset), liqFee);
    assertTrue(PDP.getFlashLoanEnabled(asset));
    assertEq(PDP.getDebtCeiling(asset), 0);
    assertFalse(PDP.getPaused(asset));
    (, , , , , , , , bool active, bool frozen) = PDP.getReserveConfigurationData(asset);
    assertTrue(active);
    assertFalse(frozen);
  }

  function _checkRates(address asset, uint256 optimal, uint256 base, uint256 s1, uint256 s2) internal view {
    IDefaultInterestRateStrategyV2.InterestRateDataRay memory r = IDefaultInterestRateStrategyV2(
      PDP.getInterestRateStrategyAddress(asset)
    ).getInterestRateData(asset);
    assertEq(r.optimalUsageRatio, optimal * 1e23);
    assertEq(r.baseVariableBorrowRate, base * 1e23);
    assertEq(r.variableRateSlope1, s1 * 1e23);
    assertEq(r.variableRateSlope2, s2 * 1e23);
  }

  function _checkToken(address token, string memory name, string memory symbol) internal view {
    (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature('name()'));
    assertTrue(ok);
    assertEq(abi.decode(data, (string)), name);
    (ok, data) = token.staticcall(abi.encodeWithSignature('symbol()'));
    assertTrue(ok);
    assertEq(abi.decode(data, (string)), symbol);
  }
}
