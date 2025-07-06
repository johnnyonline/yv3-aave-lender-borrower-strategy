// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAToken} from "@aave-v3/interfaces/IAToken.sol";
import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave-v3/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave-v3/interfaces/IPoolAddressesProvider.sol";
import {IVariableDebtToken} from "@aave-v3/interfaces/IVariableDebtToken.sol";
import {IRewardsController} from "@aave-v3/rewards/interfaces/IRewardsController.sol";
import {IPriceOracle} from "@aave-v3/interfaces/IPriceOracle.sol";

import {BaseLenderBorrower, ERC20, SafeERC20} from "./BaseLenderBorrower.sol";

contract AaveLenderBorrowerStrategy is BaseLenderBorrower {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    uint256 private constant INTEREST_RATE_MODE = 2; // interestRateMode 2 for Variable, 1 is deprecated on v3.2.0
    uint16 private constant REFERRAL = 0;

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool public immutable POOL;
    IPoolDataProvider private immutable PROTOCOL_DATA_PROVIDER;
    IRewardsController private immutable REWARDS_CONTROLLER;
    IAToken public immutable A_TOKEN;
    IVariableDebtToken public immutable DEBT_TOKEN;
    IPriceOracle public immutable PRICE_ORACLE;

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @notice Constructor
    /// @param _asset The strategy's asset
    /// @param _name The strategy's name
    /// @param _lenderVault The address of the lender vault
    constructor(
        address _asset,
        string memory _name,
        address _lenderVault,
        address _addressesProvider
    ) BaseLenderBorrower(_asset, _name, CONTROLLER_FACTORY.stablecoin(), _lenderVault) {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressesProvider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
        PROTOCOL_DATA_PROVIDER = IPoolDataProvider(ADDRESSES_PROVIDER.getPoolDataProvider());
        REWARDS_CONTROLLER = IRewardsController(ADDRESSES_PROVIDER.getAddress(keccak256("INCENTIVES_CONTROLLER")));
        PRICE_ORACLE = IPriceOracle(ADDRESSES_PROVIDER.getPriceOracle());

        (address _aToken, , address _debtToken) = PROTOCOL_DATA_PROVIDER.getReserveTokensAddresses(_asset);
        A_TOKEN = IAToken(_aToken);
        DEBT_TOKEN = IVariableDebtToken(_debtToken);

        (,,,,, bool _usageAsCollateralEnabled,,,,) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(_asset);
        require(_usageAsCollateralEnabled, "!usageAsCollateralEnabled");
        require(!_isBorrowPaused(), "borrowPaused");

        // //_setEMode(true); // use emode if it's available
        // // Set ltv targets
        // _autoConfigureLTVs();

        // // approve spend protocol spend
        // ERC20(address(_asset)).safeApprove(address(POOL), type(uint256).max);
        // ERC20(address(_aToken)).safeApprove(address(POOL), type(uint256).max);
    }

    // ===============================================================
    // Management functions
    // ===============================================================

    // ===============================================================
    // Write functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _supplyCollateral(
        uint256 _amount
    ) internal override {
        POOL.supply(address(asset), _amount, address(this), REFERRAL);
    }

    /// @inheritdoc BaseLenderBorrower
    function _withdrawCollateral(
        uint256 _amount
    ) internal override {
        POOL.withdraw(address(asset), _amount, address(this));
    }

    /// @inheritdoc BaseLenderBorrower
    function _borrow(
        uint256 _amount
    ) internal override {
        POOL.borrow(address(asset), _amount, INTEREST_RATE_MODE, REFERRAL, address(this));
    }

    /// @inheritdoc BaseLenderBorrower
    function _repay(
        uint256 _amount
    ) internal override {
        POOL.repay(address(asset), _amount, INTEREST_RATE_MODE, address(this));
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _getPrice(
        address _asset
    ) internal view override returns (uint256) {
        return PRICE_ORACLE.getAssetPrice(_asset);
    }

    /// @inheritdoc BaseLenderBorrower
    function _isSupplyPaused() internal pure override returns (bool) {
        (,,,,,,,, bool isActive, bool isFrozen) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(address(asset));
        return !isActive || isFrozen || PROTOCOL_DATA_PROVIDER.getPaused(address(asset));
    }

    /// @inheritdoc BaseLenderBorrower
    function _isBorrowPaused() internal pure override returns (bool) {
        (,,,,,, bool _borrowingEnabled,,,) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(address(asset));
        return _isSupplyPaused() || !_borrowingEnabled;
    }

    /// @inheritdoc BaseLenderBorrower
    function _isLiquidatable() internal view override returns (bool) {
        (,,, uint256 _currentLiquidationThreshold, uint256 ltv, uint256 _healthFactor) = PROTOCOL_DATA_PROVIDER.getUserAccountData(address(this));
        return 0; // @todo
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxCollateralDeposit() internal pure override returns (uint256) {
        (, uint256 _supplyCap) = PROTOCOL_DATA_PROVIDER.getReserveCaps(address(asset));
        if (_supplyCap == 0) return type(uint256).max;

        uint256 _scaledSupplyCap = _supplyCap * 10 ** asset.decimals();
        uint256 _supply = A_TOKEN.totalSupply() + asset.balanceOf(address(this));
        if (_scaledSupplyCap <= _supply) return 0;

        return _scaledSupplyCap - _supply;
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxBorrowAmount() internal view override returns (uint256) {
        (uint256 _borrowCap,) = PROTOCOL_DATA_PROVIDER.getReserveCaps(address(asset));
        return _borrowCap == 0 ? type(uint256).max : _borrowCap * 10 ** ERC20(borrowToken).decimals();
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetBorrowApr(
        uint256 /*_newAmount*/
    ) public view override returns (uint256) { // @todo -- here
        return forceLeverage ? 0 : AMM.rate() * SECONDS_IN_YEAR; // Since we're not duming, rate will not necessarily change
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetRewardApr(
        uint256 _newAmount
    ) public view override returns (uint256) {
        return VAULT_APR_ORACLE.getExpectedApr(address(lenderVault), int256(_newAmount));
    }

    /// @inheritdoc BaseLenderBorrower
    function getLiquidateCollateralFactor() public view override returns (uint256) {
        return (WAD - CONTROLLER.loan_discount()) - ((BANDS * WAD) / (2 * A));
    }

    /// @inheritdoc BaseLenderBorrower
    function balanceOfCollateral() public view override returns (uint256) {
        return CONTROLLER.user_state(address(this))[0];
    }

    /// @inheritdoc BaseLenderBorrower
    function balanceOfDebt() public view override returns (uint256) {
        return CONTROLLER.debt(address(this));
    }

    // ===============================================================
    // Harvest / Token conversions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _claimRewards() internal pure override {
        return;
    }

    /// @inheritdoc BaseLenderBorrower
    function _claimAndSellRewards() internal override {
        uint256 _loose = balanceOfBorrowToken();
        uint256 _have = balanceOfLentAssets() + _loose;
        uint256 _owe = balanceOfDebt();
        if (_owe >= _have) return;

        uint256 _toSell = _have - _owe;
        if (_toSell > _loose) _withdrawBorrowToken(_toSell - _loose);

        _loose = balanceOfBorrowToken();

        _sellBorrowToken(_toSell > _loose ? _loose : _toSell);
    }

    /// @inheritdoc BaseLenderBorrower
    function _sellBorrowToken(
        uint256 _amount
    ) internal virtual override {
        AMM.exchange(CRVUSD_INDEX, ASSET_INDEX, _amount, 0);
    }

    /// @inheritdoc BaseLenderBorrower
    function _buyBorrowToken() internal virtual override {
        uint256 _borrowTokenStillOwed = borrowTokenOwedBalance();
        uint256 _maxAssetBalance = _fromUsd(_toUsd(_borrowTokenStillOwed, borrowToken), address(asset));
        _buyBorrowToken(_maxAssetBalance);
    }

    /// @notice Buy borrow token
    /// @param _amount The amount of asset to sale
    function _buyBorrowToken(
        uint256 _amount
    ) internal {
        AMM.exchange(ASSET_INDEX, CRVUSD_INDEX, _amount, 0);
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(
        ERC20 _token
    ) external {
        require(msg.sender == GOV, "!gov");
        require(_token != asset, "!asset");
        _token.safeTransfer(GOV, _token.balanceOf(address(this)));
    }

    /// @notice Manually buy borrow token
    /// @dev Potentially can never reach `_buyBorrowToken()` in `_liquidatePosition()`
    ///      because of lender vault accounting (i.e. `balanceOfLentAssets() == 0` is never true)
    function buyBorrowToken(
        uint256 _amount
    ) external onlyEmergencyAuthorized {
        if (_amount == type(uint256).max) _amount = balanceOfAsset();
        _buyBorrowToken(_amount);
    }

}
