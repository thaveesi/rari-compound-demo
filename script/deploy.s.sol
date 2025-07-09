// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import "forge-std/Script.sol";

// Core contracts
import "../contracts/Comptroller.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/CEther.sol";
import "../contracts/Unitroller.sol";

// TODO: import your attacker/flashloan contract here when ready

contract DeployAndExploitRari is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Step 1: Deploy protocol admin contracts
        Comptroller comptroller = new Comptroller();
        Unitroller unitroller = new Unitroller();
        SimplePriceOracle priceOracle = new SimplePriceOracle();

        // Step 2: Deploy market contracts
        CEther cEther = new CEther();

        // --- If you want to add ERC20 markets, do it here:
        // CErc20 cDAI = new CErc20(<args>);
        // etc.

        // Step 3: Initialize protocol (pseudo-code, fill in real calls)
        // - Set comptroller/implementation
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(address(unitroller));
        // - Set price oracle, support markets, etc.
        comptroller._setPriceOracle(address(priceOracle));
        comptroller._supportMarket(address(cEther));
        // - Set collateral factors, close factors, etc. as needed

        // Step 4: Deploy/fund your attacker contract (leave as a TODO for now)
        // address attacker = deploy your Attacker contract here
        // Fund attacker, set balances, prep for flashloan

        // --- PLACEHOLDER: add your flashloan/attacker contract here ---
        // Attacker attacker = new Attacker(address(unitroller), ...);
        // attacker.attack();

        // Step 5: (Optional) Manipulate state, simulate victim/attacker interactions, or call exploit logic

        vm.stopBroadcast();
    }
}
