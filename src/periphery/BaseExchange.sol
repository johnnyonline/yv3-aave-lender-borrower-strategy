// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchange} from "../interfaces/IExchange.sol";

abstract contract BaseExchange is IExchange {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Address of SMS on Mainnet
    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    // ============================================================================================
    // View functions
    // ============================================================================================

    /// @notice Returns the address of the borrow token
    function BORROW() public pure virtual override returns (address);

    /// @notice Returns the address of the collateral token
    function COLLATERAL() public pure virtual override returns (address);

    // ============================================================================================
    // Mutative functions
    // ============================================================================================

    /// @notice Swaps between borrow token and the collateral token
    /// @param _amount Amount of tokens to swap
    /// @param _minAmount Minimum amount of tokens to receive
    /// @param _fromBorrow If true, swap from borrow token to collateral token, false otherwise
    /// @return Amount of tokens received
    function swap(
        uint256 _amount,
        uint256 _minAmount,
        bool _fromBorrow
    ) external override returns (uint256) {
        // Pull input token from caller
        IERC20(_fromBorrow ? BORROW() : COLLATERAL()).safeTransferFrom(msg.sender, address(this), _amount);

        // Execute the swap
        uint256 _amountOut = _fromBorrow ? _swapFrom(_amount) : _swapTo(_amount);

        // Slippage check
        require(_amountOut >= _minAmount, "slippage rekt you");

        return _amountOut;
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
    /// @dev Input token is already pulled. Only perform the raw swap.
    /// @param _amount Amount of borrow tokens to swap
    /// @return Amount of collateral tokens received
    function _swapFrom(
        uint256 _amount
    ) internal virtual returns (uint256);

    /// @notice Swaps from the collateral token to the borrow token
    /// @dev Input token is already pulled. Only perform the raw swap.
    /// @param _amount Amount of collateral tokens to swap
    /// @return Amount of borrow tokens received
    function _swapTo(
        uint256 _amount
    ) internal virtual returns (uint256);

}
