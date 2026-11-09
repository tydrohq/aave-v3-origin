// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./MarketInput.sol";

contract TydroInkSepoliaInput is MarketInput {
    // PermissionedPayloadsController executor (owner = controller, 20 min delay)
    address constant EXECUTOR = 0x7cdcA8a69B66888B0A9702960c2858A36ab39B6b;
    // 1/3 Safe (Martin, Evan, Arun)
    address constant SAFE = 0x80b0A30Dcd4A5a0e86246FAeF38A74ed40FFC6e5;

    function _getMarketInput(address)
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
        roles.emergencyAdmin = SAFE;

        config.marketId = "Tydro Ink Sepolia Market";
        config.providerId = 1;
        config.oracleDecimals = 8;
        config.flashLoanPremium = 0.0005e4; // 5 bps, same as Tydro mainnet
        config.wrappedNativeToken = 0x4200000000000000000000000000000000000006;
        // no ETH/USD feed: UiPoolDataProviderV3 is not deployed

        flags.l2 = true;

        return (roles, config, flags, deployedContracts);
    }
}
