// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurvePool} from "../interfaces/ICurvePool.sol";

import {BaseExchange} from "./BaseExchange.sol";

contract WBTCToLBTCExchange is BaseExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice LBTC/WBTC Curve Pool
    uint256 private constant LBTC_INDEX_CURVE_POOL = 0;
    uint256 private constant WBTC_INDEX_CURVE_POOL = 1;
    ICurvePool private constant CURVE_POOL = ICurvePool(0x2f3bC4c27A4437AeCA13dE0e37cdf1028f3706F0);

    /// @notice Token addresses
    IERC20 private constant LBTC = IERC20(0x8236a87084f8B84306f72007F36F2618A5634494);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor() {
        LBTC.forceApprove(address(CURVE_POOL), type(uint256).max);
        WBTC.forceApprove(address(CURVE_POOL), type(uint256).max);
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    /// @notice Returns the address of the borrow token
    /// @return Address of the borrow token
    function BORROW() public pure override returns (address) {
        return address(WBTC);
    }

    /// @notice Returns the address of the collateral token
    /// @return Address of the collateral token
    function COLLATERAL() public pure override returns (address) {
        return address(LBTC);
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    /// @inheritdoc BaseExchange
    function _swapFrom(
        uint256 _amount
    ) internal override returns (uint256) {
        // WBTC --> LBTC
        return CURVE_POOL.exchange(
            WBTC_INDEX_CURVE_POOL,
            LBTC_INDEX_CURVE_POOL,
            _amount,
            0, // minAmount
            msg.sender // receiver
        );
    }

    /// @inheritdoc BaseExchange
    function _swapTo(
        uint256 _amount
    ) internal override returns (uint256) {
        // LBTC --> WBTC
        return CURVE_POOL.exchange(
            LBTC_INDEX_CURVE_POOL,
            WBTC_INDEX_CURVE_POOL,
            _amount,
            0, // minAmount
            msg.sender // receiver
        );
    }

}
