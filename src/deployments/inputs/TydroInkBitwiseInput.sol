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

    roles.marketOwner = EXECUTOR;
    roles.poolAdmin = EXECUTOR;
    roles.emergencyAdmin = GUARDIAN;

    config.marketId = 'Aave V3 Ink Whitelabel Bitwise Market';
    config.providerId = 1;
    config.oracleDecimals = 8;
    config.flashLoanPremium = 0.0005e4; // 5 bps, same as Tydro mainnet
    config.wrappedNativeToken = 0x4200000000000000000000000000000000000006;
    // no ETH/USD feed: reuse Tydro's UiPoolDataProviderV3 0xc851…2763

    flags.l2 = true;

    return (roles, config, flags, deployedContracts);
  }
}
