// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IPriceOracle} from "@aave-v3/interfaces/IPriceOracle.sol";

import {ICentralAprOracle} from "../interfaces/ICentralAprOracle.sol";
import {IStrategyInterface as IStrategy} from "../interfaces/IStrategyInterface.sol";

contract StrategyAprOracle is AprOracleBase {

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice The WAD
    uint256 private constant WAD = 1e18;

    /// @notice The RAY constant
    uint256 private constant RAY = 1e27;

    /// @notice The maximum basis points
    uint256 private constant MAX_BPS = 10_000;

    /// @notice The central APR oracle contract. Used to get the lender vault's APR
    ICentralAprOracle public constant CENTRAL_APR_ORACLE =
        ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor() AprOracleBase("Aave v3 Lender Borrower Strategy APR Oracle", address(0)) {}

    // ===============================================================
    // View functions
    // ===============================================================

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        // Cast the strategy address to its interface
        IStrategy strategy_ = IStrategy(_strategy);

        // Get tokens and oracle from the strategy
        ERC20 _borrowToken = ERC20(strategy_.borrowToken());
        ERC20 _asset = ERC20(strategy_.asset());
        IPriceOracle _oracle = IPriceOracle(strategy_.PRICE_ORACLE());

        // Convert the delta from `asset` to `borrowToken` via USD (oracle prices are in USD with 8 decimals)
        int256 _deltaInUsd = _delta * int256(_oracle.getAssetPrice(address(_asset))) / int256(10 ** _asset.decimals());
        int256 _deltaInBorrowToken =
            _deltaInUsd * int256(10 ** _borrowToken.decimals()) / int256(_oracle.getAssetPrice(address(_borrowToken)));

        // Get the current borrow APR and reward APR
        uint256 _borrowApr =
            IPool(strategy_.POOL()).getReserveData(address(_borrowToken)).currentVariableBorrowRate / (RAY / WAD);
        uint256 _rewardApr = CENTRAL_APR_ORACLE.getStrategyApr(strategy_.lenderVault(), _deltaInBorrowToken);

        // Return 0 if the borrow APR is greater than or equal to the reward APR
        if (_borrowApr >= _rewardApr) return 0;

        // Net spread scaled by the target leverage
        uint256 _targetLTV = (strategy_.getLiquidateCollateralFactor() * strategy_.targetLTVMultiplier()) / MAX_BPS;
        return (_rewardApr - _borrowApr) * _targetLTV / WAD;
    }

}
