// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

/* ─────────────────────────  cheat-code interface  ─────────────────────── */
interface Vm {
    function startBroadcast() external;
    function startBroadcast(address origin) external;
    function stopBroadcast() external;

    function startPrank(address) external;
    function startPrank(address,address) external;
    function stopPrank() external;

    function store(address target, bytes32 slot, bytes32 value) external;
    function etch(address target, bytes calldata code) external;
    function getCode(string calldata path) external returns (bytes memory);
}

/* ──────────────────────────────  imports  ─────────────────────────────── */
import "../contracts/Unitroller.sol";
import "../contracts/Comptroller.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/CEther.sol";
import "../contracts/PriceOracle.sol";

import "../contracts/WhitePaperInterestRateModel.sol";
import "../contracts/CErc20Delegate.sol";
import "../contracts/CErc20Delegator.sol";
import "../contracts/EIP20Interface.sol";

import "./FuseAdminStub.sol";

/* ───────────────────────────  mock ERC-20  ────────────────────────────── */
contract DemoUSD is EIP20Interface {
    string  public name = "Demo USD";
    string  public symbol = "DUSD";
    uint8   public decimals = 18;
    uint    public totalSupply = 1_000_000e18;
    mapping(address => uint)                      public balances;
    mapping(address => mapping(address => uint))  public allowances;

    constructor() public { balances[msg.sender] = totalSupply; }

    function transfer(address to, uint amt) external returns (bool) {
        balances[msg.sender] -= amt; balances[to] += amt; return true;
    }
    function approve(address s, uint a) external returns (bool) {
        allowances[msg.sender][s] = a; return true;
    }
    function transferFrom(address f,address t,uint a) external returns (bool){
        allowances[f][msg.sender] -= a;
        balances[f] -= a; balances[t] += a; return true;
    }
    function balanceOf(address a) external view returns (uint) { return balances[a]; }
    function allowance(address o,address s) external view returns (uint) { return allowances[o][s]; }
}

/* ─────────────────────────  IRM stub (unchanged)  ─────────────────────── */
contract IRMStub {
    function isInterestRateModel() external pure returns (bool) { return true; }
    function checkpointInterest() external pure {}
    function checkpointInterest(uint256) external pure {}
    function resetInterestCheckpoints() external pure {}
    function interestFeeRate() external pure returns (uint) { return 0; }
}

/* ─────────────────────────  deployment script  ────────────────────────── */
contract DeployRariCore {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address constant FUSE_ADMIN =
        0xa731585ab05fC9f83555cf9Bff8F58ee94e18F85;   // from UnitrollerAdminStorage

    function run() public {

        /************ 1️⃣  core contracts + storage patch (one broadcast) **/
        vm.startBroadcast();

        FuseAdminStub      stub   = new FuseAdminStub();
        Unitroller         unit   = new Unitroller();
        Comptroller        impl   = new Comptroller();
        SimplePriceOracle  oracle = new SimplePriceOracle();
        IRMStub            irm    = new IRMStub();

        bytes memory stubCode = type(FuseAdminStub).runtimeCode;
        vm.etch(FUSE_ADMIN, stubCode);                           // whitelist stub
        // Set Unitroller admin to the broadcast EOA so upgrades are authorized

        // ── storage patch -------------------------------------------------
        // slot 4 : fuseAdmin address
        // slot 5 : fuseAdminHasRights = true
        // slot 6 : adminHasRights     = true
        vm.store(address(unit), bytes32(uint256(4)), bytes32(uint256(uint160(FUSE_ADMIN))));
        vm.store(address(unit), bytes32(uint256(5)), bytes32(uint256(1)));
        vm.store(address(unit), bytes32(uint256(6)), bytes32(uint256(1)));

        // slot 3 : pendingComptrollerImplementation → impl
        vm.store(address(unit), bytes32(uint256(3)), bytes32(uint256(uint160(address(impl)))));

        vm.stopBroadcast(); // finish the first Fuse‑admin batch before the self‑call
        // Comptroller must call _become, which will move impl from slot 3 → slot 2
        // Call _become as the Unitroller admin (Fuse‑admin) so the brains change is authorised
        vm.startPrank(FUSE_ADMIN);
        impl._become(unit);
        vm.stopPrank();

        // Resume as Fuse‑admin for the remaining pool setup
        vm.startBroadcast();   // broadcast as Unitroller admin

        Comptroller proxy = Comptroller(address(unit));
        proxy._setPriceOracle(PriceOracle(address(oracle)));
        proxy._setCloseFactor(0.5e18);
        proxy._setLiquidationIncentive(1e18);

        CEther cEth = new CEther();
        vm.stopBroadcast();      // end pool-admin batch

        /************ 2️⃣  initialise cETH as Fuse admin *******************/
        vm.startPrank(FUSE_ADMIN);
        vm.etch(FUSE_ADMIN, stubCode);                            // ensure stub
        require(FuseAdminStub(FUSE_ADMIN).interestFeeRate() == 0,"stub fail");

        cEth.initialize(
            ComptrollerInterface(address(proxy)),
            InterestRateModel(address(irm)),
            1e18,
            "Compound Ether",
            "cETH",
            8,
            0,
            0
        );
        vm.stopPrank();

        /************ 3️⃣  deploy DemoUSD market (cDUSD) and list it *****/
        // We must execute the deployment *as* the Fuse admin, because
        // CErc20Delegate::initialize() checks `msg.sender == fuseAdmin`.
        // We wrap the whole sequence in a single broadcast so all state
        // changes are mined in one transaction.
        // Broadcast the following transactions *as* the Fuse admin
        vm.startPrank(FUSE_ADMIN);  // no broadcast; impersonate Fuse‑admin only

        // Keep the stub code at the Fuse‑admin address so the whitelist
        // and fee checks still pass
        vm.etch(FUSE_ADMIN, stubCode);

        // ── deploy underlying, IRM and delegate implementation ──
        DemoUSD dusd = new DemoUSD();
        WhitePaperInterestRateModel irmD = new WhitePaperInterestRateModel(
            0,          // baseRatePerYear
            0.20e18     // multiplierPerYear (20 % at full utilisation)
        );
        CErc20Delegate cErcImpl = new CErc20Delegate();

        // ── deploy the delegator proxy (9‑arg constructor) ──
        CErc20Delegator cDUSD = new CErc20Delegator(
            address(dusd),                          // underlying ERC‑20
            ComptrollerInterface(address(proxy)),   // pool comptroller
            InterestRateModel(address(irmD)),       // IRM
            "Compound Demo USD",                    // cToken name
            "cDUSD",                                // cToken symbol
            address(cErcImpl),                      // delegate implementation
            "",                                     // becomeImplementationData
            0,                                      // reserveFactorMantissa
            0                                       // adminFeeMantissa
        );


        // ── list the market & set parameters (still inside broadcast) ──
        proxy._supportMarket(CToken(address(cDUSD)));
        proxy._setCollateralFactor(CToken(address(cDUSD)), 0.75e18);

        // price: 1 DUSD = 1 USD = 1e18 in ETH‑scaled oracle
        oracle.setUnderlyingPrice(CToken(address(cDUSD)), 1e18);
        vm.stopPrank();
    }
}