// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {CurveSwapper} from "@periphery/swappers/CurveSwapper.sol";

import {IExchange} from "../interfaces/IExchange.sol";

contract Exchange is IExchange, CurveSwapper, Ownable2Step {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Address of the borrow token
    address public immutable BORROW;

    /// @notice Address of the collateral token
    address public immutable COLLATERAL;

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor(
        address _owner,
        address _borrow,
        address _collateral
    ) {
        _transferOwnership(_owner);

        BORROW = _borrow;
        COLLATERAL = _collateral;
    }

    // ===============================================================
    // Owner functions
    // ===============================================================

    /// @notice Set the Curve route for a token pair
    /// @param _from The input token
    /// @param _to The output token
    /// @param _route The route array [token_in, pool, token_out, pool, ...]
    /// @param _swapParams The swap params array [i, j, swap_type, pool_type, n_coins] per step
    /// @param _pools Pool addresses (only needed for swap_type 3)
    function setCurveRoute(
        address _from,
        address _to,
        address[11] memory _route,
        uint256[5][5] memory _swapParams,
        address[5] memory _pools
    ) external onlyOwner {
        _setCurveRoute(_from, _to, _route, _swapParams, _pools);
    }

    /// @notice Set the Curve Router address
    /// @param _router The new Curve Router address
    function setCurveRouter(
        address _router
    ) external onlyOwner {
        curveRouter = _router;
    }

    /// @notice Set the minimum amount to sell in a swap
    /// @param _minAmountToSell Minimum amount of tokens needed to execute a swap
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyOwner {
        _setMinAmountToSell(_minAmountToSell);
    }

    /// @notice Sweep tokens from the contract
    /// @dev This contract should never hold any tokens
    /// @param _token The token to sweep
    function sweep(
        IERC20 _token
    ) external onlyOwner {
        uint256 _balance = _token.balanceOf(address(this));
        require(_balance > 0, "!balance");
        _token.safeTransfer(owner(), _balance);
    }

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
        IERC20(_fromBorrow ? BORROW : COLLATERAL).safeTransferFrom(msg.sender, address(this), _amount);

        // Execute the swap
        uint256 _amountOut = _fromBorrow ? _swapFrom(_amount) : _swapTo(_amount);

        // Slippage check
        require(_amountOut >= _minAmount, "slippage rekt you");

        // Transfer output to caller
        IERC20(_fromBorrow ? COLLATERAL : BORROW).safeTransfer(msg.sender, _amountOut);

        return _amountOut;
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
    ) internal virtual returns (uint256) {
        return _curveSwapFrom(BORROW, COLLATERAL, _amount, 0);
    }

    /// @notice Swaps from the collateral token to the borrow token
    /// @dev Input token is already pulled. Only perform the raw swap.
    /// @param _amount Amount of collateral tokens to swap
    /// @return Amount of borrow tokens received
    function _swapTo(
        uint256 _amount
    ) internal virtual returns (uint256) {
        return _curveSwapFrom(COLLATERAL, BORROW, _amount, 0);
    }

}
