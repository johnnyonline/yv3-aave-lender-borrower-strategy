// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurveTricrypto} from "../interfaces/ICurveTricrypto.sol";

import {BaseExchange} from "./BaseExchange.sol";

contract WBTCToUSDCExchange is BaseExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Tricrypto Curve Pool
    uint256 private constant USDC_INDEX_USDC_WETH_POOL = 0;
    uint256 private constant WBTC_INDEX_USDC_WETH_POOL = 1;
    ICurveTricrypto private constant TRICRYPTO = ICurveTricrypto(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    /// @notice Token addresses
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor() {
        USDC.forceApprove(address(TRICRYPTO), type(uint256).max);
        WBTC.forceApprove(address(TRICRYPTO), type(uint256).max);
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    /// @notice Returns the address of the borrow token
    /// @return Address of the borrow token
    function BORROW() public pure override returns (address) {
        return address(USDC);
    }

    /// @notice Returns the address of the collateral token
    /// @return Address of the collateral token
    function COLLATERAL() public pure override returns (address) {
        return address(WBTC);
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    /// @inheritdoc BaseExchange
    function _swapFrom(
        uint256 _amount
    ) internal override returns (uint256) {
        // USDC --> WBTC
        return TRICRYPTO.exchange(
            USDC_INDEX_USDC_WETH_POOL,
            WBTC_INDEX_USDC_WETH_POOL,
            _amount,
            0, // minAmount
            false, // use_eth
            msg.sender // receiver
        );
    }

    /// @inheritdoc BaseExchange
    function _swapTo(
        uint256 _amount
    ) internal override returns (uint256) {
        // WBTC --> USDC
        return TRICRYPTO.exchange(
            WBTC_INDEX_USDC_WETH_POOL,
            USDC_INDEX_USDC_WETH_POOL,
            _amount,
            0, // minAmount
            false, // use_eth
            msg.sender // receiver
        );
    }

}
