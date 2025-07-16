// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import "../contracts/Comptroller.sol";
import "../contracts/Unitroller.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/WhitePaperInterestRateModel.sol";
import "../contracts/CEther.sol";

// Minimal cheat‑code interface for Foundry
interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract DeployRariVulnSetup {
    Vm constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function run() public {
        vm.startBroadcast();

        // 1. Deploy admin/proxy contracts
        Comptroller comptroller = new Comptroller();
        Unitroller unitroller = new Unitroller();

        // 2. Deploy price oracle
        SimplePriceOracle oracle = new SimplePriceOracle();

        // 3. Deploy interest rate model
        // Use small nonzero rates for realism, but doesn't matter for exploit
        WhitePaperInterestRateModel irm = new WhitePaperInterestRateModel(
            0, // baseRatePerBlock
            0 // multiplierPerBlock
        );

        // 4. Wire up controller proxy/logic
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(address(unitroller));

        // After this, you interact with Comptroller *through* the Unitroller proxy address
        Comptroller proxy = Comptroller(address(unitroller));
        proxy._setPriceOracle(address(oracle));
        proxy._setCloseFactor(5e16); // 5%, or set as desired
        proxy._setLiquidationIncentive(1e18); // 1x, or set as desired

        // 5. Deploy CEther market, with references to proxy and IRM
        // CEther constructor: ComptrollerInterface comptroller_, InterestRateModel interestRateModel_, uint initialExchangeRateMantissa, string memory name_, string memory symbol_, uint8 decimals_, address payable admin_
        CEther cEther = new CEther(
            address(proxy), // Comptroller (proxy address)
            address(irm), // Interest rate model
            2e18, // Initial exchange rate mantissa (e.g. 2e18)
            "Compound Ether", // Name
            "cETH", // Symbol
            8, // Decimals
            msg.sender // Admin (set to deployer)
        );

        // 6. Register CEther market with Comptroller (use public wrapper)
        proxy.supportMarket(address(cEther));

        // 7. (Optional) Set collateral factors, market params, fund cEther, etc.
        // proxy._setCollateralFactor(address(cEther), 0.8e18); // 80%, set as needed

        vm.stopBroadcast();
    }
}
