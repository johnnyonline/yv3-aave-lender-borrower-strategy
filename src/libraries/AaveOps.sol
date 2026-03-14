// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IAToken} from "@aave-v3/interfaces/IAToken.sol";
import {IPoolDataProvider} from "@aave-v3/interfaces/IPoolDataProvider.sol";
import {IPriceOracleSentinel} from "@aave-v3/interfaces/IPriceOracleSentinel.sol";
import {DataTypes} from "@aave-v3/protocol/libraries/types/DataTypes.sol";

library AaveOps {

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice The AAVE referral code, 0 means no referral
    uint16 private constant REFERRAL = 0;

    /// @notice The AAVE interest rate mode, interestRateMode 2 for Variable, 1 is deprecated on v3.2.0
    uint256 private constant INTEREST_RATE_MODE = 2;

    /// @notice The basis points denominator
    uint256 private constant MAX_BPS = 10_000;

    /// @notice The WAD constant
    uint256 private constant WAD = 1e18;

    // ===============================================================
    // View functions
    // ===============================================================

    /// @notice Checks if supplying the asset is paused
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _asset The asset address
    /// @return True if supply is paused
    function isSupplyPaused(
        IPoolDataProvider _poolDataProvider,
        address _asset
    ) external view returns (bool) {
        (,,,,,,,, bool _isActive, bool _isFrozen) = _poolDataProvider.getReserveConfigurationData(_asset);
        return !_isActive || _isFrozen || _poolDataProvider.getPaused(_asset);
    }

    /// @notice Checks if borrowing the token is paused, including PriceOracleSentinel check for L2 deployments
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _borrowToken The borrow token address
    /// @return True if borrowing is paused
    function isBorrowPaused(
        IPoolDataProvider _poolDataProvider,
        address _borrowToken
    ) external view returns (bool) {
        (,,,,,, bool _borrowingEnabled,, bool _isActive, bool _isFrozen) =
            _poolDataProvider.getReserveConfigurationData(_borrowToken);
        if (!_borrowingEnabled || !_isActive || _isFrozen || _poolDataProvider.getPaused(_borrowToken)) return true;

        address _sentinel = _poolDataProvider.ADDRESSES_PROVIDER().getPriceOracleSentinel();
        if (_sentinel == address(0)) return false;

        return !IPriceOracleSentinel(_sentinel).isBorrowAllowed();
    }

    /// @notice Checks if the caller's position is liquidatable, including PriceOracleSentinel check for L2 deployments
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _pool The AAVE pool
    /// @return True if health factor is below 1 and liquidations are allowed
    function isLiquidatable(
        IPoolDataProvider _poolDataProvider,
        IPool _pool
    ) external view returns (bool) {
        (,,,,, uint256 _healthFactor) = _pool.getUserAccountData(address(this));
        if (_healthFactor >= WAD || _healthFactor == 0) return false;

        address _sentinel = _poolDataProvider.ADDRESSES_PROVIDER().getPriceOracleSentinel();
        if (_sentinel == address(0)) return true;

        return IPriceOracleSentinel(_sentinel).isLiquidationAllowed();
    }

    /// @notice Returns the maximum amount of collateral that can be deposited
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _aToken The aToken for the asset
    /// @param _asset The collateral asset address
    /// @return The maximum deposit amount, capped by the supply cap
    function maxCollateralDeposit(
        IPoolDataProvider _poolDataProvider,
        IAToken _aToken,
        address _asset
    ) external view returns (uint256) {
        (, uint256 _supplyCap) = _poolDataProvider.getReserveCaps(_asset);
        if (_supplyCap == 0) return type(uint256).max;

        uint256 _scaledSupplyCap = _supplyCap * 10 ** ERC20(_asset).decimals();
        uint256 _currentSupply = _aToken.totalSupply() + ERC20(_asset).balanceOf(address(this));
        if (_scaledSupplyCap <= _currentSupply) return 0;

        return _scaledSupplyCap - _currentSupply;
    }

    /// @notice Returns the maximum amount of borrow token that can be borrowed
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _pool The AAVE pool
    /// @param _borrowToken The borrow token address
    /// @return The maximum borrow amount, capped by borrow cap and available liquidity
    function maxBorrowAmount(
        IPoolDataProvider _poolDataProvider,
        IPool _pool,
        address _borrowToken
    ) external view returns (uint256) {
        (uint256 _borrowCap,) = _poolDataProvider.getReserveCaps(_borrowToken);
        return Math.min(
            _borrowCap == 0 ? type(uint256).max : _borrowCap * 10 ** ERC20(_borrowToken).decimals(),
            _pool.getVirtualUnderlyingBalance(_borrowToken) // Available liquidity
        );
    }

    /// @notice Returns the liquidation collateral factor (LTV) for the asset, eMode-aware
    /// @param _pool The AAVE pool
    /// @param _poolDataProvider The AAVE pool data provider
    /// @param _asset The collateral asset address
    /// @return The liquidation collateral factor in WAD
    function getLiquidateCollateralFactor(
        IPool _pool,
        IPoolDataProvider _poolDataProvider,
        address _asset
    ) external view returns (uint256) {
        uint8 _categoryId = uint8(_pool.getUserEMode(address(this)));
        if (_categoryId != 0) {
            uint16 _id = _pool.getReserveData(_asset).id;
            uint128 _bm = _pool.getEModeCategoryCollateralBitmap(_categoryId);
            if (((_bm >> _id) & 1) != 0) {
                DataTypes.CollateralConfig memory _cfg = _pool.getEModeCategoryCollateralConfig(_categoryId);
                return uint256(_cfg.ltv) * 1e14;
            }
        }
        (, uint256 _ltv,,,,,,,,) = _poolDataProvider.getReserveConfigurationData(_asset);
        return _ltv * (WAD / MAX_BPS);
    }

    // ===============================================================
    // Write functions
    // ===============================================================

    /// @notice Supplies collateral to the AAVE pool
    /// @param _pool The AAVE pool
    /// @param _asset The asset to supply
    /// @param _amount The amount to supply
    function supply(
        IPool _pool,
        address _asset,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.supply(_asset, _amount, address(this), REFERRAL);
    }

    /// @notice Withdraws collateral from the AAVE pool
    /// @param _pool The AAVE pool
    /// @param _asset The asset to withdraw
    /// @param _amount The amount to withdraw
    function withdraw(
        IPool _pool,
        address _asset,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.withdraw(_asset, _amount, address(this));
    }

    /// @notice Borrows tokens from the AAVE pool
    /// @param _pool The AAVE pool
    /// @param _borrowToken The token to borrow
    /// @param _amount The amount to borrow
    function borrow(
        IPool _pool,
        address _borrowToken,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.borrow(_borrowToken, _amount, INTEREST_RATE_MODE, REFERRAL, address(this));
    }

    /// @notice Repays borrowed tokens to the AAVE pool
    /// @param _pool The AAVE pool
    /// @param _borrowToken The token to repay
    /// @param _amount The amount to repay
    function repay(
        IPool _pool,
        address _borrowToken,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.repay(_borrowToken, _amount, INTEREST_RATE_MODE, address(this));
    }

}
