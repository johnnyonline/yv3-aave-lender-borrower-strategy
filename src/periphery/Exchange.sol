// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchange} from "../interfaces/IExchange.sol";
import {ICurveTricrypto} from "../interfaces/ICurveTricrypto.sol";

contract WETHToUSDCExchange is IExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Address of SMS on Mainnet
    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    /// @notice WETH/USDC Curve Pool
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
        USDC.safeApprove(address(TRICRYPTO), type(uint256).max);
        WETH.safeApprove(address(TRICRYPTO), type(uint256).max);
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    /// @notice Returns the address of the `token`
    /// @return Address of the token
    function TOKEN() external pure override returns (address) {
        return address(USDC);
    }

    /// @notice Returns the address of the paired token
    /// @return Address of the paired token
    function PAIRED_WITH() external pure override returns (address) {
        return address(WETH);
    }

    // ============================================================================================
    // Mutative functions
    // ============================================================================================

    /// @notice Swaps between token and the paired with token
    /// @param _amount Amount of tokens to swap
    /// @param _minAmount Minimum amount of tokens to receive
    /// @param _fromToken If true, swap from token to the paired token, false otherwise
    /// @return Amount of tokens received
    function swap(uint256 _amount, uint256 _minAmount, bool _fromToken) external override returns (uint256) {
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

    /// @notice Swaps from the borrow token to the paired token
    /// @param _amount Amount of borrow tokens to swap
    /// @param _minAmount Minimum amount of paired tokens to receive
    /// @return Amount of paired tokens received
    function _swapFrom(uint256 _amount, uint256 _minAmount) internal returns (uint256) {
        // Pull USDC
        USDC.safeTransferFrom(msg.sender, address(this), _amount);

        // USDC --> WETH
        uint256 _amountOut = TRICRYPTO.exchange(
            USDC_INDEX_USDC_WETH_POOL,
            WETH_INDEX_USDC_WETH_POOL,
            _amount,
            0, // minAmount
            false, // use_eth
            msg.sender // receiver
        );

        require(_amountOut >= _minAmount, "slippage rekt you");

        return _amountOut;
    }

    /// @notice Swaps from the paired token to the borrow token
    /// @param _amount Amount of paired tokens to swap
    /// @param _minAmount Minimum amount of borrow tokens to receive
    /// @return Amount of borrow tokens received
    function _swapTo(uint256 _amount, uint256 _minAmount) internal returns (uint256) {
        // Pull WETH
        WETH.safeTransferFrom(msg.sender, address(this), _amount);

        // WETH --> USDC
        uint256 _amountOut = TRICRYPTO.exchange(
            WETH_INDEX_USDC_WETH_POOL,
            USDC_INDEX_USDC_WETH_POOL,
            _amount,
            0, // minAmount
            false, // use_eth
            msg.sender // receiver
        );

        require(_amountOut >= _minAmount, "slippage rekt you");

        return _amountOut;
    }

}
