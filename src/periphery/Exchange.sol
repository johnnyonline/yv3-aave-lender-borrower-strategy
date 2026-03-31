// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {CurveSwapper} from "@periphery/swappers/CurveSwapper.sol";

import {IExchange} from "../interfaces/IExchange.sol";

contract Exchange is IExchange, CurveSwapper, Ownable2Step {

    using SafeERC20 for IERC20;

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor(
        address _owner
    ) {
        _transferOwnership(_owner);
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

    /// @notice Swaps between two tokens
    /// @param _from The input token address
    /// @param _to The output token address
    /// @param _amountIn Amount of input tokens
    /// @param _amountOutMin Minimum amount of output tokens
    /// @return _amountOut Amount of output tokens received
    function exchange(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) external override returns (uint256 _amountOut) {
        // Pull input token from caller
        IERC20(_from).safeTransferFrom(msg.sender, address(this), _amountIn);

        // Execute the swap
        _amountOut = _curveSwapFrom(_from, _to, _amountIn, 0);

        // Slippage check
        require(_amountOut >= _amountOutMin, "slippage rekt you");

        // Transfer output to caller
        IERC20(_to).safeTransfer(msg.sender, _amountOut);
    }

}
