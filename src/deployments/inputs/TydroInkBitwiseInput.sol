// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import './MarketInput.sol';

contract TydroInkBitwiseInput is MarketInput {
  // TODO: PermissionedPayloadsController executor (owner = controller, 24h delay, proposer = Bitwise Super Admin Safe)
  address constant EXECUTOR = address(0);
  // TODO: Guardian Safe, 1/2 (nested Bitwise + Tydro Safes)
  address constant GUARDIAN = address(0);

  function _getMarketInput(
    address
  )
    internal
    pure
    override
    returns (
      Roles memory roles,
      MarketConfig memory config,
      DeployFlags memory flags,
      MarketReport memory deployedContracts
    )
  {
    require(EXECUTOR != address(0) && GUARDIAN != address(0), 'placeholder role');

    roles.marketOwner = EXECUTOR; // owns the PoolAddressesProvider (upgrades)
    roles.poolAdmin = EXECUTOR; // ACL admin + POOL_ADMIN (listings, params)
    roles.emergencyAdmin = GUARDIAN; // pause, freeze, LTV to zero

    config.marketId = 'Aave V3 Ink Whitelabel Bitwise Market';
    config.providerId = 1; // id in this instance's own registry
    config.oracleDecimals = 8;
    config.flashLoanPremium = 0.0005e4; // 5 bps (100% = 1e4), same as Tydro mainnet
    config.wrappedNativeToken = 0x4200000000000000000000000000000000000006;
    // No ETH/USD feed: only used to deploy a UiPoolDataProvider. We reuse Tydro's (0xc851…2763),
    // which takes the PoolAddressesProvider as argument. Asset feeds are set at listing.

    flags.l2 = true;

    return (roles, config, flags, deployedContracts);
  }
}
