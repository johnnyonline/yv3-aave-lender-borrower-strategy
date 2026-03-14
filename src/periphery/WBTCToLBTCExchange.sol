// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchange} from "../interfaces/IExchange.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";

contract WBTCToLBTCExchange is IExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Address of SMS on Mainnet
    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

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
        LBTC.safeApprove(address(CURVE_POOL), type(uint256).max);
        WBTC.safeApprove(address(CURVE_POOL), type(uint256).max);
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    /// @notice Returns the address of the borrow token
    /// @return Address of the borrow token
    function BORROW() external pure override returns (address) {
        return address(WBTC);
    }

    /// @notice Returns the address of the collateral token
    /// @return Address of the collateral token
    function COLLATERAL() external pure override returns (address) {
        return address(LBTC);
    }

    // ============================================================================================
    // Mutative functions
    // ============================================================================================

    /// @notice Swaps between borrow token and the collateral token
    /// @param _amount Amount of tokens to swap
    /// @param _minAmount Minimum amount of tokens to receive
    /// @param _fromToken If true, swap from borrow token to collateral token, false otherwise
    /// @return Amount of tokens received
    function swap(
        uint256 _amount,
        uint256 _minAmount,
        bool _fromToken
    ) external override returns (uint256) {
        return (_fromToken ? _swapFrom(_amount, _minAmount) : _swapTo(_amount, _minAmount));
    }

    /// @notice Sweep tokens from the contract
    /// @dev This contract should never hold any tokens
    /// @param _token The token to sweep
    function sweep(
        IERC20 _token
    ) external {
        require(msg.sender == SMS, "!caller");
        uint256 _balance = _token.balanceOf(address(this));
        require(_balance > 0, "!balance");
        _token.safeTransfer(SMS, _balance);
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    /// @notice Swaps from the borrow token to the collateral token
    /// @param _amount Amount of borrow tokens to swap
    /// @param _minAmount Minimum amount of collateral tokens to receive
    /// @return Amount of collateral tokens received
    function _swapFrom(
        uint256 _amount,
        uint256 _minAmount
    ) internal returns (uint256) {
        // Pull WBTC
        WBTC.safeTransferFrom(msg.sender, address(this), _amount);

        // WBTC --> LBTC
        uint256 _amountOut = CURVE_POOL.exchange(
            WBTC_INDEX_CURVE_POOL,
            LBTC_INDEX_CURVE_POOL,
            _amount,
            0, // minAmount
            msg.sender // receiver
        );

        require(_amountOut >= _minAmount, "slippage rekt you");

        return _amountOut;
    }

    /// @notice Swaps from the collateral token to the borrow token
    /// @param _amount Amount of collateral tokens to swap
    /// @param _minAmount Minimum amount of borrow tokens to receive
    /// @return Amount of borrow tokens received
    function _swapTo(
        uint256 _amount,
        uint256 _minAmount
    ) internal returns (uint256) {
        // Pull LBTC
        LBTC.safeTransferFrom(msg.sender, address(this), _amount);

        // LBTC --> WBTC
        uint256 _amountOut = CURVE_POOL.exchange(
            LBTC_INDEX_CURVE_POOL,
            WBTC_INDEX_CURVE_POOL,
            _amount,
            0, // minAmount
            msg.sender // receiver
        );

        require(_amountOut >= _minAmount, "slippage rekt you");

        return _amountOut;
    }

}
