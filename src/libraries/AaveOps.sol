// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IAToken} from "@aave-v3/interfaces/IAToken.sol";
import {IPoolDataProvider} from "@aave-v3/interfaces/IPoolDataProvider.sol";

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

    function isSupplyPaused(
        IPoolDataProvider _poolDataProvider,
        address _asset
    ) external view returns (bool) {
        (,,,,,,,, bool _isActive, bool _isFrozen) = _poolDataProvider.getReserveConfigurationData(_asset);
        return !_isActive || _isFrozen || _poolDataProvider.getPaused(_asset);
    }

    function isBorrowPaused(
        IPoolDataProvider _poolDataProvider,
        address _borrowToken
    ) external view returns (bool) {
        (,,,,,, bool _borrowingEnabled,, bool _isActive, bool _isFrozen) =
            _poolDataProvider.getReserveConfigurationData(_borrowToken);
        return !_borrowingEnabled || !_isActive || _isFrozen || _poolDataProvider.getPaused(_borrowToken);
    }

    function isLiquidatable(
        IPool _pool
    ) external view returns (bool) {
        (,,,,, uint256 _healthFactor) = _pool.getUserAccountData(address(this));
        return _healthFactor < WAD && _healthFactor > 0;
    }

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

    function getLiquidateCollateralFactor(
        IPoolDataProvider _poolDataProvider,
        address _asset
    ) external view returns (uint256) {
        (, uint256 _ltv,,,,,,,,) = _poolDataProvider.getReserveConfigurationData(_asset);
        return _ltv * (WAD / MAX_BPS);
    }

    // ===============================================================
    // Write functions
    // ===============================================================

    function supply(
        IPool _pool,
        address _asset,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.supply(_asset, _amount, address(this), REFERRAL);
    }

    function withdraw(
        IPool _pool,
        address _asset,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.withdraw(_asset, _amount, address(this));
    }

    function borrow(
        IPool _pool,
        address _borrowToken,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.borrow(_borrowToken, _amount, INTEREST_RATE_MODE, REFERRAL, address(this));
    }

    function repay(
        IPool _pool,
        address _borrowToken,
        uint256 _amount
    ) external {
        if (_amount > 0) _pool.repay(_borrowToken, _amount, INTEREST_RATE_MODE, address(this));
    }

}
