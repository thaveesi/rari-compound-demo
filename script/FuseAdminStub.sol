// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

/// @dev Minimal stub for local deployments.
///      – Always whitelists new Comptroller implementations
///      – Pretends Fuse takes a 0 % fee (interestFeeRate = 0)

contract FuseAdminStub {
    /* ---------- Comptroller-whitelist helpers ---------- */

    // Some versions call the 2-arg variant, some the 1-arg variant.
    function comptrollerImplementationWhitelist(address, address)
        external
        pure
        returns (bool)
    {
        return true;
    }

    function comptrollerImplementationWhitelist(address)
        external
        pure
        returns (bool)
    {
        return true;
    }

    /// @notice Echoes the implementation back; satisfies old Fuse checks.
    function latestComptrollerImplementation(address impl)
        external
        pure
        returns (address)
    {
        return impl;
    }

    /* ---------- Fee & limit stubs ---------- */

    /// @notice **Zero-fee** stub – critical for `_setAdminFeeFresh` bound.
    function interestFeeRate() external pure returns (uint256) {
        return 0;
    }

    /// @notice No minimum borrow in local tests.
    function minBorrowEth() external pure returns (uint256) {
        return 0;
    }
}