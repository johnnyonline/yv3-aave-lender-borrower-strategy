// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurveTricrypto} from "../interfaces/ICurveTricrypto.sol";

import {BaseExchange} from "./BaseExchange.sol";

contract WETHToUSDCExchange is BaseExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Tricrypto Curve Pool
    uint256 private constant USDC_INDEX_USDC_WETH_POOL = 0;
    uint256 private constant WETH_INDEX_USDC_WETH_POOL = 2;
    ICurveTricrypto private constant TRICRYPTO = ICurveTricrypto(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    /// @notice Token addresses
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor() {
        USDC.forceApprove(address(TRICRYPTO), type(uint256).max);
        WETH.forceApprove(address(TRICRYPTO), type(uint256).max);
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
        return address(WETH);
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    /// @inheritdoc BaseExchange
    function _swapFrom(
        uint256 _amount
    ) internal override returns (uint256) {
        // USDC --> WETH
        return TRICRYPTO.exchange(
            USDC_INDEX_USDC_WETH_POOL,
            WETH_INDEX_USDC_WETH_POOL,
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
        // WETH --> USDC
        return TRICRYPTO.exchange(
            WETH_INDEX_USDC_WETH_POOL,
            USDC_INDEX_USDC_WETH_POOL,
            _amount,
            0, // minAmount
            false, // use_eth
            msg.sender // receiver
        );
    }

}
