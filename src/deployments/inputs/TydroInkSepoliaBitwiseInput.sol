// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import './MarketInput.sol';

contract TydroInkSepoliaBitwiseInput is MarketInput {
  // PermissionedPayloadsController executor (owner = controller, 1h delay, proposer = Super Admin Safe)
  address constant EXECUTOR = 0x3A540F759Ca7c16bf2E2682698ce3278BF14f5CB;
  // Guardian Safe, 1/3 (Bitwise, Martin)
  address constant GUARDIAN = 0xaD8438252239E871367d05130760514F1937D258;

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
    roles.marketOwner = EXECUTOR;
    roles.poolAdmin = EXECUTOR;
    roles.emergencyAdmin = GUARDIAN;

    config.marketId = 'Tydro Ink Sepolia Bitwise Market';
    config.providerId = 1;
    config.oracleDecimals = 8;
    config.flashLoanPremium = 0.0005e4; // 5 bps, same as Tydro mainnet
    config.wrappedNativeToken = 0x4200000000000000000000000000000000000006;
    // no ETH/USD feed: reuse the mainnet-version UiPoolDataProviderV3 0x292E…aff8

    flags.l2 = true;

    return (roles, config, flags, deployedContracts);
  }
}
