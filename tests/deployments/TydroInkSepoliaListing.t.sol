// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolDataProvider} from '../../src/contracts/interfaces/IPoolDataProvider.sol';
import {IAaveOracle} from '../../src/contracts/interfaces/IAaveOracle.sol';
import {ICreditDelegationToken} from '../../src/contracts/interfaces/ICreditDelegationToken.sol';
import {IDefaultInterestRateStrategyV2} from '../../src/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';
import {Errors} from '../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {TydroInkSepoliaListingPayload} from '../../scripts/TydroInkSepoliaListing.s.sol';

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

interface IGateway {
  function supply(uint256 amount, address onBehalfOf, uint16 referralCode) external returns (uint256);
  function borrow(uint256 amount, uint16 referralCode, address to) external returns (uint256);
  function repay(uint256 amount, address onBehalfOf) external returns (uint256);
}

contract TydroInkSepoliaListingTest is Test {
  IPool constant POOL = IPool(0xa1176A315F64500dB4B3e0042A6181221a053882);
  IPoolDataProvider constant PDP = IPoolDataProvider(0xC34ab490C527F08F18272D1c7E64b94769b927a9);
  IAaveOracle constant ORACLE = IAaveOracle(0xf6B316b10cEEF037ff4bB976cce81F65dC706a22);
  address constant EXECUTOR = 0x7cdcA8a69B66888B0A9702960c2858A36ab39B6b;
  address constant CONTROLLER = 0xf2886b1Ef6a1A539A68A937fBfbC185026d40F35;
  address constant DEPLOYER = 0xB5D789353ff57736d67c432b994c1f73bF683F01; // mock tokens owner
  IGateway constant GATEWAY = IGateway(0xaBfd85D25377C107c3b4Ab5BfB6aacE1038711E3);

  TydroInkSepoliaListingPayload payload;
  address USDC;
  address KBTC;
  address KHYPE;
  address WUSDC1;

  address lender = makeAddr('lender');
  address btcUser = makeAddr('btcUser');
  address hypeUser = makeAddr('hypeUser');

  function setUp() public {
    // pinned before the listing was executed on-chain (block of the listing payload deployment)
    vm.createSelectFork('https://rpc-gel-sepolia.inkonchain.com', 64807329);
    payload = new TydroInkSepoliaListingPayload();
    (USDC, KBTC, KHYPE, WUSDC1) = (payload.USDC(), payload.KBTC(), payload.KHYPE(), payload.WUSDC1());

    // without the seed funds on the Executor the execution reverts
    vm.prank(CONTROLLER);
    vm.expectRevert();
    IExecutor(EXECUTOR).executeTransaction(address(payload), 0, 'execute()', '', true);

    _mint(USDC, EXECUTOR, payload.USDC_SEED_AMOUNT() + payload.WUSDC1_SEED_AMOUNT());
    _mint(KBTC, EXECUTOR, payload.KBTC_SEED_AMOUNT());
    _mint(KHYPE, EXECUTOR, payload.KHYPE_SEED_AMOUNT());

    // same path as PermissionedPayloadsController.executePayload
    vm.prank(CONTROLLER);
    IExecutor(EXECUTOR).executeTransaction(address(payload), 0, 'execute()', '', true);
  }

  function test_seed() public view {
    address dustBin = payload.DUST_BIN();
    assertEq(IERC20(POOL.getReserveAToken(USDC)).balanceOf(dustBin), payload.USDC_SEED_AMOUNT());
    assertEq(IERC20(POOL.getReserveAToken(WUSDC1)).balanceOf(dustBin), payload.WUSDC1_SEED_AMOUNT());
    assertEq(IERC20(POOL.getReserveAToken(KBTC)).balanceOf(dustBin), payload.KBTC_SEED_AMOUNT());
    assertEq(IERC20(POOL.getReserveAToken(KHYPE)).balanceOf(dustBin), payload.KHYPE_SEED_AMOUNT());
    // wrapper fully backed, nothing left on the Executor
    assertEq(IERC20(USDC).balanceOf(WUSDC1), IERC20(WUSDC1).totalSupply());
    assertEq(IERC20(USDC).balanceOf(EXECUTOR), 0);
    assertEq(IERC20(WUSDC1).balanceOf(EXECUTOR), 0);
  }

  function test_config() public view {
    assertEq(POOL.getReservesList().length, 4);

    _checkParams(USDC, 6, 0, 0, 0, 10_00, false, true);
    _checkParams(KBTC, 8, 85_00, 87_00, 105_00, 50_00, true, false);
    _checkParams(KHYPE, 18, 0, 0, 0, 50_00, false, false);
    _checkParams(WUSDC1, 6, 0, 0, 0, 10_00, false, false);

    _checkCaps(USDC, 75_000_000, 100_000_000, 0);
    _checkCaps(KBTC, 1, 1_575, 10_00);
    _checkCaps(KHYPE, 1, 124_000, 10_00);
    _checkCaps(WUSDC1, 75_000_000, 100_000_000, 0);

    _checkRates(USDC, 95_00, 6_30, 0, 0);
    _checkRates(KBTC, 45_00, 8_00, 4_00, 80_00);
    _checkRates(KHYPE, 45_00, 0, 7_00, 300_00);
    _checkRates(WUSDC1, 95_00, 6_30, 0, 0);

    assertEq(ORACLE.getAssetPrice(USDC), 1e8);
    assertEq(ORACLE.getAssetPrice(WUSDC1), 1e8);
    assertEq(ORACLE.getAssetPrice(KBTC), 80_000e8);
    assertEq(ORACLE.getAssetPrice(KHYPE), 100e8);

    assertEq(POOL.getEModeCategoryLabel(1), 'kHYPE__wUSDC1');
    assertTrue(POOL.getIsEModeCategoryIsolated(1));
    assertEq(POOL.getEModeCategoryCollateralConfig(1).ltv, 65_00);
    assertEq(POOL.getEModeCategoryCollateralConfig(1).liquidationThreshold, 72_00);
    assertEq(POOL.getEModeCategoryCollateralConfig(1).liquidationBonus, 110_00);
    assertEq(POOL.getEModeCategoryCollateralBitmap(1), 1 << POOL.getReserveData(KHYPE).id);
    assertEq(POOL.getEModeCategoryBorrowableBitmap(1), 1 << POOL.getReserveData(WUSDC1).id);
    assertEq(POOL.getEModeCategoryLabel(2), '');

    _checkAToken(KBTC, 'Aave InkSepolia kBTC', 'aInkSepkBTC');
  }

  function test_kbtcUsdcMarket() public {
    _seedLiquidity();
    _mint(KBTC, btcUser, 1e8);

    vm.startPrank(btcUser);
    IERC20(KBTC).approve(address(POOL), 1e8);
    POOL.supply(KBTC, 1e8, btcUser, 0);

    // 1 kBTC = $80k, LTV 85% -> max $68k
    vm.expectRevert(Errors.CollateralCannotCoverNewBorrow.selector);
    POOL.borrow(USDC, 68_001e6, 2, 0, btcUser);
    POOL.borrow(USDC, 50_000e6, 2, 0, btcUser);
    assertEq(IERC20(USDC).balanceOf(btcUser), 50_000e6);

    // wUSDC1 is not borrowable outside the eMode
    vm.expectRevert(Errors.BorrowingNotEnabled.selector);
    POOL.borrow(WUSDC1, 1_000e6, 2, 0, btcUser);

    // cannot enter the isolated eMode while borrowing USDC (not borrowable in it)
    vm.expectRevert();
    POOL.setUserEMode(1);
    vm.stopPrank();
  }

  function test_khypeWusdc1Market() public {
    _seedLiquidity();
    _mint(KHYPE, hypeUser, 1_000e18); // $100k

    vm.startPrank(hypeUser);
    IERC20(KHYPE).approve(address(POOL), 1_000e18);

    // outside eMode kHYPE has LT 0: no borrowing power
    POOL.supply(KHYPE, 1_000e18, hypeUser, 0);
    vm.expectRevert();
    POOL.borrow(USDC, 1_000e6, 2, 0, hypeUser);

    POOL.setUserEMode(1);
    POOL.setUserUseReserveAsCollateral(KHYPE, true);

    // USDC is not borrowable in the eMode
    vm.expectRevert(Errors.NotBorrowableInEMode.selector);
    POOL.borrow(USDC, 1_000e6, 2, 0, hypeUser);

    // LTV 65% of $100k -> max $65k of wUSDC1, borrowed through the gateway (gets plain USDC)
    address debtToken = POOL.getReserveVariableDebtToken(WUSDC1);
    ICreditDelegationToken(debtToken).approveDelegation(address(GATEWAY), type(uint256).max);
    vm.expectRevert(Errors.CollateralCannotCoverNewBorrow.selector);
    GATEWAY.borrow(65_001e6, 0, hypeUser);
    GATEWAY.borrow(60_000e6, 0, hypeUser);
    assertEq(IERC20(USDC).balanceOf(hypeUser), 60_000e6);
    assertEq(IERC20(debtToken).balanceOf(hypeUser), 60_000e6);

    // repay through the gateway with plain USDC
    IERC20(USDC).approve(address(GATEWAY), 60_000e6);
    GATEWAY.repay(60_000e6, hypeUser);
    assertEq(IERC20(debtToken).balanceOf(hypeUser), 0);
    vm.stopPrank();
  }

  function _seedLiquidity() internal {
    _mint(USDC, lender, 2_000_000e6);
    vm.startPrank(lender);
    IERC20(USDC).approve(address(POOL), 1_000_000e6);
    POOL.supply(USDC, 1_000_000e6, lender, 0);
    IERC20(USDC).approve(address(GATEWAY), 1_000_000e6);
    GATEWAY.supply(1_000_000e6, lender, 0);
    vm.stopPrank();
    assertEq(IERC20(POOL.getReserveAToken(WUSDC1)).balanceOf(lender), 1_000_000e6);
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

  function _checkAToken(address asset, string memory name, string memory symbol) internal view {
    address aToken = POOL.getReserveAToken(asset);
    (bool ok, bytes memory data) = aToken.staticcall(abi.encodeWithSignature('name()'));
    assertTrue(ok);
    assertEq(abi.decode(data, (string)), name);
    (ok, data) = aToken.staticcall(abi.encodeWithSignature('symbol()'));
    assertTrue(ok);
    assertEq(abi.decode(data, (string)), symbol);
  }
}
