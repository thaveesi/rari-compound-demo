// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

interface Vm {
    /* ───── broadcast helpers ───── */
    function startBroadcast() external;
    function startBroadcast(address origin) external;
    function stopBroadcast() external;

    /* ───── prank / impersonation ───── */
    function startPrank(address) external;           // ← add
    function startPrank(address, address) external;  //    (2-arg variant, optional but handy)
    function stopPrank() external;                   // ← add

    /* ───── storage & byte-code cheats ───── */
    function store(address target, bytes32 slot, bytes32 value) external;
    function etch(address target, bytes calldata code) external;
    function getCode(string calldata path) external returns (bytes memory);
}

import "../contracts/Unitroller.sol";
import "../contracts/Comptroller.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/CEther.sol";
import "../contracts/PriceOracle.sol";
//import "../contracts/WhitePaperInterestRateModel.sol";  // no longer needed
import "./FuseAdminStub.sol";

// ── IRM stub to bypass checkpointInterest reverts
contract IRMStub {
    function isInterestRateModel() external pure returns (bool) { return true; }
    function checkpointInterest() external pure {}
    function checkpointInterest(uint256) external pure {}
    function resetInterestCheckpoints() external pure {}
    /// @dev pretend Fuse admin wants 0% fee
    function interestFeeRate() external pure returns (uint) {
        return 0;
    }
}

contract DeployRariCore {
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/*  NEW ▶  the real constant Fuse admin address from UnitrollerAdminStorage  */
address constant FUSE_ADMIN =
    0xa731585ab05fC9f83555cf9Bff8F58ee94e18F85;

function run() public {
    /******************************************************************
     * 1️⃣  Deploy everything and patch storage in *one* broadcast     *
     ******************************************************************/
    vm.startBroadcast();

    // ––– deployments ––––––––––––––––––––––––––––––––––––––––––––––––
    FuseAdminStub              stub   = new FuseAdminStub();
    Unitroller                 unit   = new Unitroller();
    Comptroller                impl   = new Comptroller();
    SimplePriceOracle          oracle = new SimplePriceOracle();
    //WhitePaperInterestRateModel irm   = new WhitePaperInterestRateModel(0, 0);
    IRMStub                   irm   = new IRMStub();

    /* ================================================================
       1-A.  Impersonate the **real** FuseFeeDistributor whitelist
             --------------------------------------------------------
       We overwrite the code that already (or not) lives at
       0xa73158… with our stub’s bytecode so that
       `comptrollerImplementationWhitelist()` always returns true.
    ================================================================= */
    // Grab the **runtime** byte-code of FuseAdminStub (not creation code!)
    bytes memory stubCode = type(FuseAdminStub).runtimeCode;
    vm.etch(FUSE_ADMIN, stubCode);                       // overwrite at constant

    /* ================================================================
       1-B.  Direct storage writes on Unitroller
             --------------------------------------------------------
             slot 2 : bool fuseAdminHasRights
             slot 3 : bool adminHasRights
       NOTE:  slot 0 (admin) is **already** msg.sender (your EOA) because
              the constructor sets it, so we leave it untouched.
    ================================================================= */
    vm.store(address(unit), bytes32(uint256(2)), bytes32(uint256(1))); // fuseAdminHasRights = true
    vm.store(address(unit), bytes32(uint256(3)), bytes32(uint256(1))); // adminHasRights     = true
    vm.store(address(unit), bytes32(uint256(4)), bytes32(uint256(address(irm))));

    /******************************************************************
     * 2️⃣  Wire proxy ⇆ implementation and finish pool set-up        *
     ******************************************************************/
    require(
        unit._setPendingImplementation(address(impl)) == 0,
        "setPendingImpl failed"
    );
    impl._become(unit);  // calls _acceptImplementation internally

    Comptroller proxy = Comptroller(address(unit));
    proxy._setPriceOracle(PriceOracle(address(oracle)));
    proxy._setCloseFactor(0.5e18);
    proxy._setLiquidationIncentive(1e18);

    /******************************************************************
     * 3️⃣  Deploy the cETH market and list it                         *
     ******************************************************************/
    CEther cEth = new CEther();

    // ── Phase‑1  (EOA) ── deploy contracts & prepare proxy ─────────
    // (this phase already ran; we are right after deploying cEth)
    vm.stopBroadcast();                       // close pool‑admin batch

    // ── Phase‑2  (FUSE_ADMIN) ── initialise cETH ───────────────────
    vm.startPrank(FUSE_ADMIN);                // impersonate without a key
    // Ensure FuseAdminStub (already contains interestFeeRate()==0) is in place
    vm.etch(FUSE_ADMIN, stubCode);
    // optional sanity-check — can be removed for prod
    require(FuseAdminStub(FUSE_ADMIN).interestFeeRate() == 0,
        "FuseAdminStub not etched");
     
    // Overwrite FUSE_ADMIdN with our IRMStub so interestFeeRate() is zero
    // 1) real comptroller proxy
    // 2) our IRMStub
    // 3) initialExchangeRate = 1e18
    // 4) name/symbol/decimals
    // 5) reserveFactor = 0, adminFee = 0
    cEth.initialize(
        ComptrollerInterface(address(proxy)),
        InterestRateModel(address(irm)),
        1e18,                  // initialExchangeRateMantissa_
        "Compound Ether",      // name_
        "cETH",                // symbol_
        8,                     // decimals_
        0,                     // reserveFactorMantissa_
        0                      // adminFeeMantissa_
    );
    vm.stopPrank();              // done as Fuse admin                      // done as Fuse admin

    // ── Phase‑3  (EOA) ── list the market & tune parameters ───────
    vm.startBroadcast();         // back to pool-admin EOA                        // back to pool admin
    proxy._supportMarket(cEth);
    proxy._setCollateralFactor(cEth, 0.75e18); // 75 % LTV for demo
    vm.stopBroadcast();                       // final close
}

}